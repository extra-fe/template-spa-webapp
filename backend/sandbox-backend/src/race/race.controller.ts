import { RaceService } from './race.service';
import { Body, Controller, Get, Param, ParseIntPipe, Post,UseGuards  } from '@nestjs/common';
import { CreateRaceDto } from './dto/create-race.dto';
import { ConditionalAuthGuard } from 'src/auth/guards/conditional-auth.guard';

@Controller('api/races')
export class RaceController {
  constructor(private readonly raceService: RaceService) {}

  @UseGuards(ConditionalAuthGuard)
  @Get()
  findAll() {
    return this.raceService.findAll();
  }

  @UseGuards(ConditionalAuthGuard)
  @Get(':id')
  findOne(@Param('id', ParseIntPipe) id: number) {
    return this.raceService.findOne(id);
  }

  @UseGuards(ConditionalAuthGuard)
  @Post()
  create(@Body() createRaceDto: CreateRaceDto) {
    return this.raceService.create(createRaceDto);
  }
}
