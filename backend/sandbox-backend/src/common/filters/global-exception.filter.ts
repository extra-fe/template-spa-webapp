import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { Request, Response } from 'express';

// グローバル例外フィルタ: スタックトレースや内部実装詳細がクライアントへ漏れないようにする
// - HttpException (Validation/NotFound等) はそのままステータス・メッセージを返す
// - それ以外の未捕捉例外は本番では汎用 500 メッセージに丸めて返却 (詳細はサーバログのみ)
@Catch()
export class GlobalExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(GlobalExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();

    if (exception instanceof HttpException) {
      const status = exception.getStatus();
      const body = exception.getResponse();
      response.status(status).json(typeof body === 'string' ? { statusCode: status, message: body } : body);
      return;
    }

    // 想定外エラー: サーバログには詳細を残し、クライアントには汎用メッセージのみ返す
    const isProduction = process.env.NODE_ENV === 'production';
    const stack = exception instanceof Error ? exception.stack : String(exception);
    this.logger.error(`Unhandled exception on ${request.method} ${request.url}`, stack);

    const responseBody = isProduction
      ? { statusCode: HttpStatus.INTERNAL_SERVER_ERROR, message: 'Internal server error' }
      : {
          statusCode: HttpStatus.INTERNAL_SERVER_ERROR,
          message: exception instanceof Error ? exception.message : 'Internal server error',
          stack: exception instanceof Error ? exception.stack : undefined,
        };

    response.status(HttpStatus.INTERNAL_SERVER_ERROR).json(responseBody);
  }
}
