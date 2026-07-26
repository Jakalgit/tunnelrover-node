import { Module } from '@nestjs/common';
import * as path from 'path';
import { ConfigModule } from '@nestjs/config';
import { ScheduleModule } from '@nestjs/schedule';
import { PrometheusModule } from '@willsoto/nestjs-prometheus';
import { AuthModule } from './auth/auth.module';
import { MetricsModule } from './metrics/metrics.module';
import { XrayModule } from './xray/xray.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      envFilePath: [path.join(__dirname, '../.env')],
      isGlobal: true,
    }),
    ScheduleModule.forRoot(),
    PrometheusModule.register({
      path: '/metrics',
      defaultMetrics: {
        enabled: true,
      },
    }),
    AuthModule,
    XrayModule,
    MetricsModule,
  ],
})
export class AppModule {}
