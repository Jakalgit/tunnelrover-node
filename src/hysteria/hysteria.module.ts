import { Module } from '@nestjs/common';
import { HysteriaAuthController } from './controllers/hysteria-auth.controller';
import { HysteriaKickService } from './services/hysteria-kick.service';

@Module({
  controllers: [HysteriaAuthController],
  providers: [HysteriaKickService],
  exports: [HysteriaKickService],
})
export class HysteriaModule {}
