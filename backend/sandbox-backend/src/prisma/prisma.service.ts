import { Injectable, OnModuleInit } from '@nestjs/common';
import { Prisma, PrismaClient } from '@prisma/client';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit {
  constructor() {
    super({
      log: process.env.PRISMA_LOG_LEVEL?.split(',') as Prisma.LogLevel[],
    });
  }

  async onModuleInit() {
    await this.$connect();
  }
}
