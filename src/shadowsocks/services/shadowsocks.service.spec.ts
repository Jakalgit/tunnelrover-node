import { Test, TestingModule } from '@nestjs/testing';
import { ShadowsocksService } from './shadowsocks.service';

describe('ShadowsocksService', () => {
  let service: ShadowsocksService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [ShadowsocksService],
    }).compile();

    service = module.get<ShadowsocksService>(ShadowsocksService);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });
});
