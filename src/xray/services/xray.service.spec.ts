import { Test, TestingModule } from '@nestjs/testing';
import { XrayService } from './xray.service';

describe('XrayService', () => {
  let service: XrayService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [XrayService],
    }).compile();

    service = module.get<XrayService>(XrayService);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });
});
