import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { XtlsApi } from '@remnawave/xtls-sdk';

@Injectable()
export class XrayService {
  private api!: XtlsApi;

  constructor(private readonly configService: ConfigService) {
    const XRAY_HOST = configService.get<string>('XRAY_HOST');
    const XRAY_PORT = configService.get<string>('XRAY_PORT');
    this.api = new XtlsApi({
      connectionUrl: `${XRAY_HOST}:${XRAY_PORT}`,
    });
  }

  async addUser(uuids: string[]) {
    const promises = uuids.map((uuid) =>
      this.api.handler.addVlessUser({
        level: 0,
        uuid,
        tag: 'vless-ws',
        username: uuid,
        flow: '',
      }),
    );
    return await Promise.all(promises);
  }

  async removeUser(uuids: string[]) {
    const promises = uuids.map((el) =>
      this.api.handler.removeUser('vless-ws', el),
    );
    return await Promise.all(promises);
  }

  getInboundUsers() {
    return this.api.handler.getInboundUsers('vless-ws');
  }

  getInboundUsersCount() {
    return this.api.handler.getInboundUsersCount('vless-ws');
  }
}
