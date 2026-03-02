import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import { Observable } from 'rxjs';
import { ConfigService } from '@nestjs/config';

@Injectable()
export class AuthGuard implements CanActivate {
  constructor(private readonly configService: ConfigService) {}

  canActivate(
    context: ExecutionContext,
  ): boolean | Promise<boolean> | Observable<boolean> {
    const req = context.switchToHttp().getRequest();

    const mode = this.configService.get<string | undefined>('TEST_MODE');

    if (mode === '1') {
      return true;
    }

    try {
      const authHeader = req.headers['authorization'];
      const bearer = authHeader.split(' ')[0];
      const token = authHeader.split(' ')[1];

      if (bearer !== 'Bearer' || !token) {
        return false;
      }

      const nodeToken = this.configService.get<string>('NODE_TOKEN');

      if (token !== nodeToken) {
        return false;
      }
    } catch {
      return false;
    }

    return true;
  }
}
