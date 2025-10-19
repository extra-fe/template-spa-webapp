import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { HealthModule } from './health/health.module';
import { ConfigModule } from '@nestjs/config';
import { AuthModule } from './auth/auth.module';
import { PrismaService } from './prisma/prisma.service';
import { PrismaModule } from './prisma/prisma.module';
import { RaceModule } from './race/race.module';

@Module({
  imports: [
    HealthModule,
    ConfigModule.forRoot({
      envFilePath:'.env'
    }),
    AuthModule,
    PrismaModule,
    RaceModule,
],
  controllers: [AppController],
  providers: [AppService, PrismaService],
})
export class AppModule {}
