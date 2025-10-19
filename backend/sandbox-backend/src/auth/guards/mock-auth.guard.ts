import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';

@Injectable()
export class MockAuthGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest();

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
