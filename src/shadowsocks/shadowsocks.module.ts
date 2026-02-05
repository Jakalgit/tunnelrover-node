import { Module } from '@nestjs/common';
import { ShadowsocksService } from './services/shadowsocks.service';
import { ShadowsocksController } from './controllers/shadowsocks.controller';

@Module({
  providers: [ShadowsocksService],
  controllers: [ShadowsocksController]
})
export class ShadowsocksModule {}
