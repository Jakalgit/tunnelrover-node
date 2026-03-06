import { Test, TestingModule } from '@nestjs/testing';
import { XrayController } from './xray.controller';

describe('XrayController', () => {
  let controller: XrayController;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [XrayController],
    }).compile();

    controller = module.get<XrayController>(XrayController);
  });

  it('should be defined', () => {
    expect(controller).toBeDefined();
  });
});
