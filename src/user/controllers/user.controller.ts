import { Body, Controller, Delete, Get, Post, UseGuards } from '@nestjs/common';
import { UserService } from '../services/user.service';
import { AuthGuard } from '../../auth/guards/auth.guard';

@Controller('user')
export class UserController {
  constructor(private readonly xrayService: UserService) {}

  @UseGuards(AuthGuard)
  @Post()
  addUser(@Body() body: { uuids: string[] }) {
    return this.xrayService.addUser(body.uuids);
  }

  @UseGuards(AuthGuard)
  @Delete()
  removeUser(@Body() body: { uuids: string[] }) {
    return this.xrayService.removeUser(body.uuids);
  }

  @UseGuards(AuthGuard)
  @Get('/list')
  getUsers() {
    return this.xrayService.getInboundUsers();
  }

  @UseGuards(AuthGuard)
  @Get('/count')
  getInboundUsersCount() {
    return this.xrayService.getInboundUsersCount();
  }
}
