import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateRaceDto } from './dto/create-race.dto';

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

  async create(createRaceDto: CreateRaceDto) {
    const { entries, ...raceData } = createRaceDto;
    return this.prisma.race.create({
      data: {
        ...raceData,
        entries: {
          create: entries,
        },
      },
      include: { entries: true },
    });
  }
}
