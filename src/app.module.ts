import { Module } from '@nestjs/common';
import { ShadowsocksModule } from './shadowsocks/shadowsocks.module';
import * as path from 'path';
import { ConfigModule } from '@nestjs/config';
import { AuthModule } from './auth/auth.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      envFilePath: [path.join(__dirname, '../.env')],
      isGlobal: true,
    }),
    ShadowsocksModule,
    AuthModule,
  ],
})
export class AppModule {}
