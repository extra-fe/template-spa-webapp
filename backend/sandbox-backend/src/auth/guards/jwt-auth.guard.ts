import { Injectable, ExecutionContext } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Request } from 'express';

@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {
  canActivate(context: ExecutionContext) {
    const request = context.switchToHttp().getRequest<Request>();

    // OPTIONS メソッドはスルー（プリフライト用）
    if (request.method === 'OPTIONS') {
      return true;
    }
    return super.canActivate(context);
  }
}
