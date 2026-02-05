import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as dgram from 'node:dgram';

@Injectable()
export class ShadowsocksService {
  private readonly host: string;
  private readonly port: number;

  constructor(private readonly configService: ConfigService) {
    this.host = configService.get<string>('CONTAINER_HOST');
    this.port = Number(configService.get<string>('CONTAINER_PORT') || 6100);
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
