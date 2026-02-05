import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { ShadowsocksModule } from './shadowsocks/shadowsocks.module';

@Module({
  imports: [ShadowsocksModule],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
