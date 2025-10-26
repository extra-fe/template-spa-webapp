// src/otel/instrumentation.ts
import 'dotenv/config';
import { NodeSDK } from '@opentelemetry/sdk-node';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { NestInstrumentation } from '@opentelemetry/instrumentation-nestjs-core';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { PrismaInstrumentation } from '@prisma/instrumentation';

// ログレベルを環境変数で設定（警告を抑制）
process.env.OTEL_LOG_LEVEL = process.env.OTEL_LOG_LEVEL || 'NONE';

// OTLPエクスポーターの設定（Jaeger用）
const traceExporter = new OTLPTraceExporter({
  url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://localhost:4318/v1/traces',
});

// 計装の設定
const instrumentations = [
  getNodeAutoInstrumentations({
    // 不要な計装を無効化してオーバーヘッドを削減
    '@opentelemetry/instrumentation-fs': {
      enabled: false,
    },
  }),
  new NestInstrumentation(),
  new PrismaInstrumentation(),
];

// NodeSDKの初期化
const sdk = new NodeSDK({
  traceExporter,
  instrumentations,
  serviceName: process.env.OTEL_SERVICE_NAME || 'sandbox-backend',
  autoDetectResources: false,
});

// SDKの起動
sdk.start();
console.log('[OTel] SDK started with OTLP exporter');
console.log('[OTel] Service name:', process.env.OTEL_SERVICE_NAME || 'sandbox-backend');
console.log('[OTel] OTLP endpoint:', process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://localhost:4318/v1/traces');

// グレースフルシャットダウン
const shutdown = async () => {
  try {
    await sdk.shutdown();
    console.log('[OTel] SDK shutdown successfully');
    process.exit(0);
  } catch (error) {
    console.error('[OTel] Error shutting down SDK:', error);
    process.exit(1);
  }
};

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
