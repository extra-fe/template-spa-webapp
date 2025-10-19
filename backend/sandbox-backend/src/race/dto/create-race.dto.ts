import { ApiProperty } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsArray,
  IsDateString,
  IsNotEmpty,
  IsNumber,
  IsOptional,
  IsString,
  ValidateNested,
} from 'class-validator';

export class CreateEntryDto {
  @ApiProperty({ example: 1 })
  frameNumber: number;

  @ApiProperty({ example: 1 })
  horseNumber: number;

  @ApiProperty({ example: 'ホクトベガ' })
  horseName: string;

  @ApiProperty({ example: '牝' })
  sex: string;

  @ApiProperty({ example: '4' })
  age: string;

  @ApiProperty({ example: 55.0, required: false })
  weight?: number;

  @ApiProperty({ example: '加藤和宏' })
  jockey: string;

  @ApiProperty({ example: '中野隆良' })
  trainer: string;

  @ApiProperty({ example: '482(-4)', required: false })
  bodyWeight?: string;

  @ApiProperty({ example: 9, required: false })
  oddsRank?: number;

  @ApiProperty({ example: 30.4, required: false })
  odds?: number;

  @ApiProperty({ example: 1, required: false })
  rank?: number;

  @ApiProperty({ example: '2:24.9', required: false })
  time?: string;

  @ApiProperty({ example: '', required: false })
  margin?: string;
}

export class CreateRaceDto {
  @ApiProperty({ example: '1993-11-14T00:00:00Z' })
  @IsDateString()
  date: Date;

  @ApiProperty({ example: 'エリザベス女王杯' })
  @IsString()
  name: string;

  @ApiProperty({ example: '京都' })
  @IsString()
  venue: string;

  @ApiProperty({ type: [CreateEntryDto] })
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => CreateEntryDto)
  entries: CreateEntryDto[];
}
