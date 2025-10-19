import { RaceService } from './race.service';
import { Body, Controller, Get, Param, ParseIntPipe, Post } from '@nestjs/common';
import { CreateRaceDto } from './dto/create-race.dto';

@Controller('api/races')
export class RaceController {
  constructor(private readonly raceService: RaceService) {}

  @Get()
  findAll() {
    return this.raceService.findAll();
  }

  @Get(':id')
  findOne(@Param('id', ParseIntPipe) id: number) {
    return this.raceService.findOne(id);
  }
  @Post()
  create(@Body() createRaceDto: CreateRaceDto) {
    return this.raceService.create(createRaceDto);
  }
}
