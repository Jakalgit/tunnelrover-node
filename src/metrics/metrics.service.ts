import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { InjectMetric } from '@willsoto/nestjs-prometheus';
import { Gauge } from 'prom-client';
import { XrayService } from '../xray/services/xray.service';
import {
  XRAY_INBOUND_DOWNLINK_BYTES,
  XRAY_INBOUND_UPLINK_BYTES,
  XRAY_INBOUND_USERS,
  XRAY_STATS_SCRAPE_SUCCESS,
  XRAY_SYS_ALLOC_BYTES,
  XRAY_SYS_GOROUTINES,
  XRAY_SYS_SYS_BYTES,
  XRAY_SYS_UPTIME_SECONDS,
} from './metrics.constants';

@Injectable()
export class MetricsService implements OnModuleInit {
  private readonly logger = new Logger(MetricsService.name);

  constructor(
    private readonly xrayService: XrayService,
    @InjectMetric(XRAY_INBOUND_USERS)
    private readonly inboundUsers: Gauge<string>,
    @InjectMetric(XRAY_INBOUND_UPLINK_BYTES)
    private readonly inboundUplink: Gauge<string>,
    @InjectMetric(XRAY_INBOUND_DOWNLINK_BYTES)
    private readonly inboundDownlink: Gauge<string>,
    @InjectMetric(XRAY_SYS_GOROUTINES)
    private readonly sysGoroutines: Gauge<string>,
    @InjectMetric(XRAY_SYS_ALLOC_BYTES)
    private readonly sysAlloc: Gauge<string>,
    @InjectMetric(XRAY_SYS_SYS_BYTES)
    private readonly sysSys: Gauge<string>,
    @InjectMetric(XRAY_SYS_UPTIME_SECONDS)
    private readonly sysUptime: Gauge<string>,
    @InjectMetric(XRAY_STATS_SCRAPE_SUCCESS)
    private readonly scrapeSuccess: Gauge<string>,
  ) {}

  async onModuleInit() {
    await this.collectXrayMetrics();
  }

  @Cron(CronExpression.EVERY_30_SECONDS)
  async collectXrayMetrics() {
    try {
      const [usersCount, sysStats] = await Promise.all([
        this.xrayService.getInboundUsersCount(),
        this.xrayService.getSysStats(),
      ]);

      if (usersCount.isOk) {
        this.inboundUsers.set(usersCount.data);
      }

      if (sysStats.isOk && sysStats.data) {
        this.sysGoroutines.set(sysStats.data.numGoroutine);
        this.sysAlloc.set(sysStats.data.alloc);
        this.sysSys.set(sysStats.data.sys);
        this.sysUptime.set(sysStats.data.uptime);
      }

      for (const tag of this.xrayService.inboundTags) {
        const inboundStats = await this.xrayService.getInboundStats(tag);
        if (!inboundStats.isOk || !inboundStats.data) {
          continue;
        }

        this.inboundUplink.set({ inbound: tag }, inboundStats.data.uplink);
        this.inboundDownlink.set({ inbound: tag }, inboundStats.data.downlink);
      }

      this.scrapeSuccess.set(1);
    } catch (error) {
      this.scrapeSuccess.set(0);
      this.logger.warn(
        `Failed to collect xray metrics: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }
  }
}
