import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { Logger, LogLevel } from '@nestjs/common/services';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  const logLevel = (process.env.LOG_LEVEL ?? 'error') as LogLevel;
  Logger.overrideLogger([logLevel]);

  if (process.env.CORS_ORIGIN && process.env.CORS_METHODS) {
    app.enableCors({
      origin: process.env.CORS_ORIGIN.split(','),
      methods: process.env.CORS_METHODS.split(','),
      credentials: true,
    });
  }

  if (process.env.NODE_ENV !== 'production') {
    const config = new DocumentBuilder()
      .setTitle('Hoge Title')
      .setDescription('Hoge API description')
      .setVersion('1.0')
      .addTag('hoge1')
      .addBearerAuth(
        {
          type: 'http',
          scheme: 'bearer',
          bearerFormat: 'JWT',
        },
        'access-token', 
      )
      .build();
    const documentFactory = () => SwaggerModule.createDocument(app, config);
    SwaggerModule.setup('api', app, documentFactory);
  }

  await app.listen(process.env.PORT ?? 3000);
}
bootstrap();
