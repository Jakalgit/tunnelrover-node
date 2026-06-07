import { Injectable } from '@nestjs/common';
import { RedisService } from '../../redis/redis.service';
import { HysteriaKickService } from '../../hysteria/services/hysteria-kick.service';

/** User management API (/user) — backed by Redis + Hysteria kick. */
@Injectable()
export class UserService {
  constructor(
    private readonly redisService: RedisService,
    private readonly hysteriaKickService: HysteriaKickService,
  ) {}

  async addUser(uuids: string[]) {
    const result: { uuid: string; isOk: boolean; message: string }[] = [];

    for (const uuid of uuids) {
      try {
        await this.redisService.addUsers([uuid]);
        result.push({ uuid, isOk: true, message: '' });
      } catch {
        result.push({ uuid, isOk: false, message: '' });
      }
    }

    return result;
  }

  async removeUser(uuids: string[]) {
    await this.redisService.removeUsers(uuids);
    await this.hysteriaKickService.kickUsers(uuids);
  }

  async getInboundUsers() {
    const users = await this.redisService.listUsers();

    return {
      isOk: true,
      data: {
        users: users.map((uuid) => ({ username: uuid })),
      },
    };
  }

  async getInboundUsersCount() {
    const count = await this.redisService.countUsers();

    return {
      isOk: true,
      data: count,
    };
  }
}
