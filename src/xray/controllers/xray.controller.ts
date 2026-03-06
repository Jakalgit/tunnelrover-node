import { Body, Controller, Delete, Get, Post } from '@nestjs/common';
import { XrayService } from '../services/xray.service';

@Controller('xray')
export class XrayController {
  constructor(private readonly xrayService: XrayService) {}

  @Post()
  addUser(@Body() body: { uuids: string[] }) {
    return this.xrayService.addUser(body.uuids);
  }

  @Delete()
  removeUser(@Body() body: { uuids: string[] }) {
    return this.xrayService.removeUser(body.uuids);
  }

  @Get('/list')
  getUsers() {
    return this.xrayService.getInboundUsers();
  }

  @Get('/count')
  getInboundUsersCount() {
    return this.xrayService.getInboundUsersCount();
  }
}
