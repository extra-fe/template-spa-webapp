import { ApiProperty } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsArray,
  IsDateString,
  IsInt,
  IsNotEmpty,
  IsNumber,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';

export class CreateEntryDto {
  @ApiProperty({ example: 1 })
  @IsInt()
  @Min(1)
  @Max(8)
  frameNumber: number;

  @ApiProperty({ example: 1 })
  @IsInt()
  @Min(1)
  horseNumber: number;

  @ApiProperty({ example: 'ホクトベガ' })
  @IsString()
  @IsNotEmpty()
  @MaxLength(50)
  horseName: string;

  @ApiProperty({ example: '牝' })
  @IsString()
  @MaxLength(4)
  sex: string;

  @ApiProperty({ example: '4' })
  @IsString()
  @MaxLength(8)
  age: string;

  @ApiProperty({ example: 55.0, required: false })
  @IsOptional()
  @IsNumber()
  @Min(0)
  weight?: number;

  @ApiProperty({ example: '加藤和宏' })
  @IsString()
  @MaxLength(50)
  jockey: string;

  @ApiProperty({ example: '中野隆良' })
  @IsString()
  @MaxLength(50)
  trainer: string;

  @ApiProperty({ example: '482(-4)', required: false })
  @IsOptional()
  @IsString()
  @MaxLength(20)
  bodyWeight?: string;

  @ApiProperty({ example: 9, required: false })
  @IsOptional()
  @IsInt()
  @Min(1)
  oddsRank?: number;

  @ApiProperty({ example: 30.4, required: false })
  @IsOptional()
  @IsNumber()
  @Min(0)
  odds?: number;

  @ApiProperty({ example: 1, required: false })
  @IsOptional()
  @IsInt()
  @Min(1)
  rank?: number;

  @ApiProperty({ example: '2:24.9', required: false })
  @IsOptional()
  @IsString()
  @MaxLength(20)
  time?: string;

  @ApiProperty({ example: '', required: false })
  @IsOptional()
  @IsString()
  @MaxLength(20)
  margin?: string;
}

export class CreateRaceDto {
  @ApiProperty({ example: '1993-11-14T00:00:00Z' })
  @IsDateString()
  date: Date;

  @ApiProperty({ example: 'エリザベス女王杯' })
  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  name: string;

  @ApiProperty({ example: '京都' })
  @IsString()
  @IsNotEmpty()
  @MaxLength(50)
  venue: string;

  @ApiProperty({ type: [CreateEntryDto] })
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => CreateEntryDto)
  entries: CreateEntryDto[];
}
