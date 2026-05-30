import { CanActivate, ExecutionContext } from '@nestjs/common';
import { Injectable } from '@nestjs/common/decorators';
import { AuthenticatedRequest } from '../types';

@Injectable()
export class MockAuthGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();

    // モックユーザーを注入
    request.user = {
      sub: 'mock-user-id-123',
      email: 'mock@example.com',
      name: 'Mock User',
      roles: ['admin'], // 必要に応じてカスタマイズ
    };

    return true; // 認証通過
  }
}
