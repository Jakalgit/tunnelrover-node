import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

@Injectable()
export class HysteriaKickService {
  private readonly logger = new Logger(HysteriaKickService.name);

  constructor(private readonly configService: ConfigService) {}

  async kickUsers(uuids: string[]) {
    if (uuids.length === 0) {
      return;
    }

    const host = this.configService.get<string>('HYSTERIA_HOST', 'hysteria');
    const port = this.configService.get<string>('HYSTERIA_TRAFFIC_PORT', '9999');
    const secret = this.configService.get<string>('HYSTERIA_TRAFFIC_SECRET');

    if (!secret) {
      this.logger.warn('HYSTERIA_TRAFFIC_SECRET is not set, skip kick');
      return;
    }

    const url = `http://${host}:${port}/kick`;

    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: {
          Authorization: secret,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(uuids),
      });

      if (!response.ok) {
        this.logger.warn(`Hysteria kick failed: HTTP ${response.status}`);
      }
    } catch (error) {
      this.logger.warn({ error }, 'Hysteria kick request failed');
    }
  }
}
