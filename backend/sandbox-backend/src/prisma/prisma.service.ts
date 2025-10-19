import { OnModuleInit } from '@nestjs/common';
import { PrismaClient } from '@prisma/client'
import { Injectable } from '@nestjs/common/decorators';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit {
  constructor() {
    super({
      log: process.env.PRISMA_LOG_LEVEL?.split(',') as any,
    });
  }

  async onModuleInit() {
    await this.$connect();
  }
}
