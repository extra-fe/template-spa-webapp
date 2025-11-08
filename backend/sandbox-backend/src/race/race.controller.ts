import { Body, Controller, Get, Param, ParseIntPipe, Post, UseGuards } from '@nestjs/common';
import { RaceService } from './race.service';
import { CreateRaceDto } from './dto/create-race.dto';
import { ConditionalAuthGuard } from 'src/auth/guards/conditional-auth.guard';

@Controller('api/races')
export class RaceController {
  constructor(private readonly raceService: RaceService) {}

  @Get()
  @UseGuards(ConditionalAuthGuard)
  findAll() {
    return this.raceService.findAll();
  }

  @Get(':id')
  @UseGuards(ConditionalAuthGuard)
  findOne(@Param('id', ParseIntPipe) id: number) {
    return this.raceService.findOne(id);
  }
  @Post()
  @UseGuards(ConditionalAuthGuard)
  create(@Body() createRaceDto: CreateRaceDto) {
    return this.raceService.create(createRaceDto);
  }
}
