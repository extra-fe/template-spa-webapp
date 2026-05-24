import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { Logger, LogLevel, ValidationPipe } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import helmet from 'helmet';
import { GlobalExceptionFilter } from './common/filters/global-exception.filter';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  const logLevel = (process.env.LOG_LEVEL ?? 'error') as LogLevel;
  Logger.overrideLogger([logLevel]);

  // HTTP セキュリティヘッダ (helmet): CSP/X-Frame-Options/X-Content-Type-Options 等を一括付与
  // CloudFront 側のレスポンスヘッダポリシーと二重防御。HSTS は CloudFront と合わせて 1 年に揃える
  app.use(
    helmet({
      hsts: {
        maxAge: 31536000,
        includeSubDomains: true,
      },
    }),
  );

  // 入力バリデーション: DTO に定義されていないフィールドは拒否、型は自動変換
  // - whitelist: DTO 未定義プロパティを削ぐ
  // - forbidNonWhitelisted: 未定義プロパティがあれば 400 で拒否 (mass assignment 対策)
  // - transform: プレーンオブジェクトを DTO クラスインスタンスへ変換し型変換も適用
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
      transformOptions: { enableImplicitConversion: false },
    }),
  );

  // 例外フィルタ: 未捕捉例外のスタックトレースを本番ではクライアントへ返さない
  app.useGlobalFilters(new GlobalExceptionFilter());

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
