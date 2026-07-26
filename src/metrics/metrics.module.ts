import { Module } from '@nestjs/common';
import {
  makeGaugeProvider,
  PrometheusModule,
} from '@willsoto/nestjs-prometheus';
import { XrayModule } from '../xray/xray.module';
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
import { MetricsService } from './metrics.service';

@Module({
  imports: [XrayModule, PrometheusModule],
  providers: [
    MetricsService,
    makeGaugeProvider({
      name: XRAY_INBOUND_USERS,
      help: 'Number of users currently registered on xray inbounds',
    }),
    makeGaugeProvider({
      name: XRAY_INBOUND_UPLINK_BYTES,
      help: 'Cumulative uplink traffic per xray inbound in bytes',
      labelNames: ['inbound'],
    }),
    makeGaugeProvider({
      name: XRAY_INBOUND_DOWNLINK_BYTES,
      help: 'Cumulative downlink traffic per xray inbound in bytes',
      labelNames: ['inbound'],
    }),
    makeGaugeProvider({
      name: XRAY_SYS_GOROUTINES,
      help: 'Number of goroutines in the xray process',
    }),
    makeGaugeProvider({
      name: XRAY_SYS_ALLOC_BYTES,
      help: 'Bytes allocated and still in use by xray',
    }),
    makeGaugeProvider({
      name: XRAY_SYS_SYS_BYTES,
      help: 'Total bytes of memory obtained from the OS by xray',
    }),
    makeGaugeProvider({
      name: XRAY_SYS_UPTIME_SECONDS,
      help: 'Xray process uptime in seconds',
    }),
    makeGaugeProvider({
      name: XRAY_STATS_SCRAPE_SUCCESS,
      help: '1 if the last xray stats scrape succeeded, otherwise 0',
    }),
  ],
})
export class MetricsModule {}
