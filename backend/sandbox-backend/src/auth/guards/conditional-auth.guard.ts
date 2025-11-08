// src/auth/conditional-auth.guard.ts

import { ExecutionContext, Injectable, CanActivate } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AuthGuard } from '@nestjs/passport';
import { MockAuthGuard } from './mock-auth.guard';

@Injectable()
export class ConditionalAuthGuard implements CanActivate {
  private useMock = process.env.AUTH_ENABLED === 'false';

  constructor(private reflector: Reflector) {}

  canActivate(context: ExecutionContext) {
    if (this.useMock) {
      const mock = new MockAuthGuard();
      return mock.canActivate(context);
    } else {
      const real = new (AuthGuard('jwt'))();
      return real.canActivate(context);
    }
  }
}
