import { Controller, Get, Logger, Req, UseGuards } from '@nestjs/common';
import { AppService } from './app.service';
import { ApiBearerAuth } from '@nestjs/swagger';
import { ConditionalAuthGuard } from './auth/guards/conditional-auth.guard';

@Controller()
export class AppController {
  constructor(private readonly appService: AppService) {}

  @Get()
  getHello(): string {
    Logger.debug("hoge");
    Logger.error("fuga");

    return this.appService.getHello();
  }

  @Get('api/guest/connect-test')
  connectTest() {
    Logger.debug("connect-test-debug");
    return { message: 'GET api/guest/connect-test ok4', time: new Date().toISOString()};
  }

  @ApiBearerAuth('access-token') // ← .addBearerAuth() で指定した name を使う
  @Get('api/protected')
  @UseGuards(ConditionalAuthGuard)
  getProtectedResource(@Req() req) {
    Logger.debug('GET api/protected ok');
    Logger.debug(`JWT payload: ${JSON.stringify(req.user)}`);
    return { message: 'GET api/protected', time: new Date().toISOString() };
  }  
}
