import { Controller, Get, Query } from '@nestjs/common';
import { ShadowsocksService } from '../services/shadowsocks.service';

@Controller('shadowsocks')
export class ShadowsocksController {
  constructor(private readonly shadowsocksService: ShadowsocksService) {}

  @Get('add')
  async addUser(
    @Query('port') port: number,
    @Query('password') password: string,
  ) {
    const command = `add: {"server_port":${port},"password":"${password}"}`;
    await this.shadowsocksService.sendCommand(command);
    console.log('add ok');
    return { ok: true, port };
  }

  @Get('remove')
  async removeUser(@Query('port') port: number) {
    const command = `remove: {"server_port":${port}}`;
    await this.shadowsocksService.sendCommand(command);
    console.log('remove ok');
    return { ok: true, port };
  }

  @Get('list')
  async listUsers() {
    const command = `list`;
    await this.shadowsocksService.sendCommand(command);
    console.log('list ok');
    return { ok: true, list: [] };
  }
}
