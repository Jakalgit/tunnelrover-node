import { Test, TestingModule } from '@nestjs/testing';
import { ShadowsocksController } from './shadowsocks.controller';

describe('ShadowsocksController', () => {
  let controller: ShadowsocksController;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [ShadowsocksController],
    }).compile();

    controller = module.get<ShadowsocksController>(ShadowsocksController);
  });

  it('should be defined', () => {
    expect(controller).toBeDefined();
  });
});
