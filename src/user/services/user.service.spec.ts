import { Test, TestingModule } from '@nestjs/testing';
import { UserService } from './user.service';
import { RedisService } from '../../redis/redis.service';
import { HysteriaKickService } from '../../hysteria/services/hysteria-kick.service';

describe('UserService', () => {
  let service: UserService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        UserService,
        {
          provide: RedisService,
          useValue: {
            addUsers: jest.fn(),
            removeUsers: jest.fn(),
            listUsers: jest.fn().mockResolvedValue([]),
            countUsers: jest.fn().mockResolvedValue(0),
          },
        },
        {
          provide: HysteriaKickService,
          useValue: {
            kickUsers: jest.fn(),
          },
        },
      ],
    }).compile();

    service = module.get<UserService>(UserService);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });
});
