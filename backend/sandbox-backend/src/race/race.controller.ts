import { Controller, Get, Param, ParseIntPipe } from '@nestjs/common';
import { RaceService } from './race.service';

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
}
