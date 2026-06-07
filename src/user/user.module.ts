import { Module } from '@nestjs/common';
import { UserController } from './controllers/user.controller';
import { UserService } from './services/user.service';
import { HysteriaModule } from '../hysteria/hysteria.module';

@Module({
  imports: [HysteriaModule],
  controllers: [UserController],
  providers: [UserService],
})
export class UserModule {}
