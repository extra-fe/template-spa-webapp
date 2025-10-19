// src/auth/conditional-auth.guard.ts
import { Injectable, CanActivate, ExecutionContext } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { MockAuthGuard } from './mock-auth.guard';
import { Observable } from 'rxjs';

@Injectable()
export class ConditionalAuthGuard implements CanActivate {
  private readonly useMock = process.env.AUTH_ENABLED === 'false';

canActivate(context: ExecutionContext): boolean | Promise<boolean> | Observable<boolean> {
    if (this.useMock) {
      // モック認証（テスト・ローカル用）
      return new MockAuthGuard().canActivate(context);
    }
    // 本番認証（JWT）
    const JwtAuthGuard = AuthGuard('jwt');
    return new JwtAuthGuard().canActivate(context);
  }
}
