import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { XrayService } from '../services/xray.service';
import { AuthGuard } from '../../auth/guards/auth.guard';
import { UpdateUsersDto } from '../dto/update-users.dto';

@Controller('xray')
export class XrayController {
  constructor(private readonly xrayService: XrayService) {}

  @UseGuards(AuthGuard)
  @Post()
  addUser(@Body() dto: UpdateUsersDto) {
    return this.xrayService.addUser(dto);
  }

  @UseGuards(AuthGuard)
  @Delete()
  removeUser(@Body() dto: UpdateUsersDto) {
    return this.xrayService.removeUser(dto);
  }

  @UseGuards(AuthGuard)
  @Get('/list/:tag')
  getUsers(@Param('tag') tag: string) {
    return this.xrayService.getInboundUsers(tag);
  }

  @UseGuards(AuthGuard)
  @Get('/count/:tag')
  getInboundUsersCount(@Param('tag') tag: string) {
    return this.xrayService.getInboundUsersCount(tag);
  }
}
