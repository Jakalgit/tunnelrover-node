import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Redis from 'ioredis';

const USERS_KEY = 'hysteria:users';

@Injectable()
export class RedisService implements OnModuleDestroy {
  private readonly client: Redis;

  constructor(private readonly configService: ConfigService) {
    const host = this.configService.get<string>('REDIS_HOST', 'redis');
    const port = Number(this.configService.get<string>('REDIS_PORT', '6379'));

    this.client = new Redis({
      host,
      port,
      lazyConnect: true,
    });
  }

  async onModuleDestroy() {
    await this.client.quit();
  }

  async addUsers(uuids: string[]) {
    if (uuids.length === 0) {
      return;
    }

    await this.client.sadd(USERS_KEY, ...uuids);
  }

  async removeUsers(uuids: string[]) {
    if (uuids.length === 0) {
      return;
    }

    await this.client.srem(USERS_KEY, ...uuids);
  }

  async isUserAllowed(uuid: string) {
    const allowed = await this.client.sismember(USERS_KEY, uuid);
    return allowed === 1;
  }

  async listUsers() {
    return this.client.smembers(USERS_KEY);
  }

  async countUsers() {
    return this.client.scard(USERS_KEY);
  }
}
