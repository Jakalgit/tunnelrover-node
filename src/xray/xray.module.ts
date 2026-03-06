import { Module } from '@nestjs/common';
import { XrayController } from './controllers/xray.controller';
import { XrayService } from './services/xray.service';

@Module({
  controllers: [XrayController],
  providers: [XrayService],
})
export class XrayModule {}
