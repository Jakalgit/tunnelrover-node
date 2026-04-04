import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { XtlsApi } from '@remnawave/xtls-sdk';
import { UpdateUsersDto } from '../dto/update-users.dto';

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

  async addUser(dto: UpdateUsersDto) {
    const promises: Promise<any>[] = dto.uuids.map((uuid) =>
      this.api.handler.addVlessUser({
        level: 0,
        uuid,
        tag: dto.tag,
        username: uuid,
        flow: 'xtls-rprx-vision',
      }),
    );

    return await Promise.all(promises);
  }

  async removeUser(dto: UpdateUsersDto) {
    const promises = dto.uuids.map((el) =>
      this.api.handler.removeUser(dto.tag, el),
    );
    return await Promise.all(promises);
  }

  getInboundUsers(tag: string) {
    return this.api.handler.getInboundUsers(tag);
  }

  getInboundUsersCount(tag: string) {
    return this.api.handler.getInboundUsersCount(tag);
  }
}
