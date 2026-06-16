import { Body, Controller, HttpCode, Post } from '@nestjs/common';
import { RedisService } from '../../redis/redis.service';

type HysteriaAuthRequest = {
  addr?: string;
  auth?: string;
  tx?: number;
};

@Controller('internal/hysteria')
export class HysteriaAuthController {
  constructor(private readonly redisService: RedisService) {}

  @Post('auth')
  @HttpCode(200)
  async auth(@Body() body: HysteriaAuthRequest) {
    const userId = body.auth?.trim();

    if (!userId) {
      return { ok: false, id: '' };
    }

    const ok = await this.redisService.isUserAllowed(userId);

    return {
      ok,
      id: userId,
    };
  }
}
