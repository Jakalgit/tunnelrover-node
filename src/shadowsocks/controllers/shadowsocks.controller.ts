import { Body, Controller, Delete, Get, Post } from '@nestjs/common';
import { ShadowsocksService } from '../services/shadowsocks.service';
import { AddUsersDto } from '../dto/add-users.dto';
import { RemoveUsersDto } from '../dto/remove-users.dto';

@Controller('shadowsocks')
export class ShadowsocksController {
  constructor(private readonly shadowsocksService: ShadowsocksService) {}

  @Post('add')
  async addUser(@Body() dto: AddUsersDto) {
    await this.shadowsocksService.addUsers(dto);
    return { ok: true, ...dto };
  }

  @Delete('remove')
  async removeUser(@Body() dto: RemoveUsersDto) {
    await this.shadowsocksService.removeUsers(dto);
    return { ok: true, ...dto };
  }

  @Get('list')
  async listUsers() {
    const list = await this.shadowsocksService.getListUsers();
    return { ok: true, list };
  }
}
