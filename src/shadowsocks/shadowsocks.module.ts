import { Module } from '@nestjs/common';
import { ShadowsocksService } from './services/shadowsocks.service';
import { ShadowsocksController } from './controllers/shadowsocks.controller';
import { AuthModule } from '../auth/auth.module';

@Module({
  imports: [AuthModule],
  providers: [ShadowsocksService],
  controllers: [ShadowsocksController],
})
export class ShadowsocksModule {}
