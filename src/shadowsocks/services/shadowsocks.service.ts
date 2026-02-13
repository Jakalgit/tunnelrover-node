import { BadRequestException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as dgram from 'node:dgram';
import { AddUsersDto } from '../dto/add-users.dto';
import { RemoveUsersDto } from '../dto/remove-users.dto';

@Injectable()
export class ShadowsocksService {
  private readonly host: string;
  private readonly port: number;

  constructor(private readonly configService: ConfigService) {
    this.host = configService.get<string>('CONTAINER_HOST');
    this.port = Number(configService.get<string>('CONTAINER_PORT') || 6100);
  }

  async addUsers(dto: AddUsersDto) {
    const client = dgram.createSocket('udp4');

    try {
      await Promise.all(
        dto.credentials.map((el) => {
          const command = `add: {"server_port":${el.port},"password":"${el.password}"}`;

          return new Promise<void>((resolve, reject) => {
            client.send(Buffer.from(command), this.port, this.host, (err) =>
              err ? reject(err) : resolve(),
            );
          });
        }),
      );
    } catch {
      throw new BadRequestException('Error creating users');
    } finally {
      client.close();
    }
  }

  async removeUsers(dto: RemoveUsersDto) {
    const client = dgram.createSocket('udp4');

    try {
      await Promise.all(
        dto.ports.map((port) => {
          const command = `remove: {"server_port":${port}}`;

          return new Promise<void>((resolve, reject) => {
            client.send(Buffer.from(command), this.port, this.host, (err) =>
              err ? reject(err) : resolve(),
            );
          });
        }),
      );
    } catch {
      throw new BadRequestException('Error removing users');
    } finally {
      client.close();
    }
  }

  async getListUsers() {
    const listString = await new Promise<string>((resolve, reject) => {
      const client = dgram.createSocket('udp4');

      const timeout = setTimeout(() => {
        client.close();
        reject(new Error('UDP timeout'));
      }, 3000);

      client.on('message', (msg) => {
        clearTimeout(timeout);
        client.close();
        resolve(msg.toString('utf-8'));
      });

      client.on('error', (err) => {
        clearTimeout(timeout);
        client.close();
        reject(err);
      });

      client.send('list', this.port, this.host, (err) => {
        if (err) {
          clearTimeout(timeout);
          client.close();
          reject(err);
        }
      });
    });

    try {
      return JSON.parse(listString) as {
        server_port: number;
        password: string;
      }[];
    } catch {
      throw new BadRequestException('Error parsing list of users');
    }
  }

  async sendCommand(command: string): Promise<void> {
    return new Promise((resolve, reject) => {
      const client = dgram.createSocket('udp4');

      client.send(Buffer.from(command), this.port, this.host, (err) => {
        client.close();
        if (err) reject(err);
        else resolve();
      });
    });
  }
}
