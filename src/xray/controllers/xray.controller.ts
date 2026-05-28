import { Body, Controller, Delete, Get, Post, UseGuards } from '@nestjs/common';
import { XrayService } from '../services/xray.service';
import { AuthGuard } from '../../auth/guards/auth.guard';

@Controller('xray')
export class XrayController {
  constructor(private readonly xrayService: XrayService) {}

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
