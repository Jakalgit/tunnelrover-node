import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { XtlsApi } from '@remnawave/xtls-sdk';

@Injectable()
export class XrayService {
  private api!: XtlsApi;
  private readonly TAGS = ['vless-tcp', 'vless-ws'];

  constructor(private readonly configService: ConfigService) {
    const XRAY_HOST = configService.get<string>('XRAY_HOST');
    const XRAY_PORT = configService.get<string>('XRAY_PORT');
    this.api = new XtlsApi({
      connectionUrl: `${XRAY_HOST}:${XRAY_PORT}`,
    });
  }

  async addUser(uuids: string[]) {
    const result: { uuid: string; isOk: boolean }[] = [];

    for (const u of uuids) {
      let isOk = true;
      for (const tag of this.TAGS) {
        try {
          const response = await this.api.handler.addVlessUser({
            level: 0,
            uuid: u,
            tag,
            username: u,
            flow: tag === 'vless-tcp' ? 'xtls-rprx-vision' : '',
          });

          if (!response.isOk) {
            isOk = false;
          }
        } catch (error) {
          isOk = false;
          throw error;
        }
      }

      result.push({
        uuid: u,
        isOk,
      });

      if (!isOk) {
        await this.removeUser([u]);
      }
    }

    return result;
  }

  async removeUser(uuids: string[]) {
    const promises = uuids
      .map((el) => {
        return this.TAGS.map((tag) => this.api.handler.removeUser(tag, el));
      })
      .flat();
    await Promise.all(promises);
  }

  async getInboundUsers() {
    const users: Set<string> = new Set();
    for (const tag of this.TAGS) {
      const response = await this.api.handler.getInboundUsers(tag);
      if (response.isOk) {
        response.data.users.forEach((user) => {
          users.add(user.username);
        });
      }
    }

    return {
      uuids: [...users],
    };
  }

  async getInboundUsersCount() {
    let maxUsers = 1000000000;

    for (const tag of this.TAGS) {
      const response = await this.api.handler.getInboundUsersCount(tag);

      if (response.isOk) {
        if (maxUsers === 1000000000) {
          maxUsers = 0;
        }
        maxUsers = Math.max(maxUsers, response.data);
      }
    }

    return maxUsers;
  }
}
