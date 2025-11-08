import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class RaceService {
  constructor(private readonly prisma: PrismaService) {}

  async findAll() {
    return this.prisma.race.findMany({
      include: { entries: true },
    });
  }

  async findOne(id: number) {
    return this.prisma.race.findUnique({
      where: { id },
      include: { entries: true },
    });
  }
}
