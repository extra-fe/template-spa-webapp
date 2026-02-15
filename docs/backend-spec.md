# Backend 仕様書

## 1. 概要

競馬レース管理APIサーバー。NestJSフレームワークで構築し、Auth0によるJWT認証、PostgreSQLデータベース、OpenTelemetryによるオブザーバビリティを備える。

| 項目 | 値 |
|---|---|
| アプリケーション名 | sandbox-backend |
| フレームワーク | NestJS 11 |
| 言語 | TypeScript 5.9.x |
| ランタイム | Node.js 22 |
| ORM | Prisma 6.19.0 |
| データベース | PostgreSQL |
| パッケージマネージャ | Yarn |
| ソースパス | `backend/sandbox-backend/` |

## 2. 技術スタック

### コアライブラリ

| ライブラリ | バージョン | 用途 |
|---|---|---|
| @nestjs/core | ^11 | NestJSコアフレームワーク |
| @nestjs/platform-express | ^11 | Express HTTPアダプタ |
| @nestjs/config | ^4.0.2 | 環境変数・設定管理 |
| @nestjs/swagger | ^11.2.1 | OpenAPI/Swagger生成 |
| @prisma/client | ^6.19.0 | Prisma ORMクライアント |

### 認証ライブラリ

| ライブラリ | バージョン | 用途 |
|---|---|---|
| @nestjs/passport | ^11.0.5 | Passport認証統合 |
| @nestjs/jwt | ^11.0.1 | JWT処理 |
| passport-jwt | ^4.0.1 | JWT Passportストラテジー |
| jwks-rsa | ^3.2.0 | Auth0 JWKS鍵取得 |

### オブザーバビリティ

| ライブラリ | バージョン | 用途 |
|---|---|---|
| @opentelemetry/sdk-node | 0.208.0 | OpenTelemetry Node SDK |
| @opentelemetry/auto-instrumentations-node | 0.67.0 | 自動計装 |
| @opentelemetry/exporter-trace-otlp-http | 0.208.0 | OTLP トレースエクスポーター |
| @opentelemetry/instrumentation-nestjs-core | 0.55.0 | NestJS計装 |
| @prisma/instrumentation | 6.19.0 | Prisma計装 |

### バリデーション

| ライブラリ | 用途 |
|---|---|
| class-validator | DTOバリデーション |
| class-transformer | リクエストボディの型変換 |

## 3. ディレクトリ構成

```
backend/sandbox-backend/
├── prisma/
│   ├── schema.prisma        # データベーススキーマ定義
│   └── seed.ts              # シードデータ
├── src/
│   ├── auth/
│   │   ├── auth.module.ts       # 認証モジュール
│   │   ├── strategies/
│   │   │   └── jwt.strategy.ts  # JWT認証ストラテジー
│   │   └── guards/
│   │       ├── jwt-auth.guard.ts           # JWT認証ガード
│   │       ├── mock-auth.guard.ts          # モック認証ガード（開発用）
│   │       └── conditional-auth.guard.ts   # 条件付き認証ガード
│   ├── health/
│   │   └── health.controller.ts  # ヘルスチェック
│   ├── otel/
│   │   └── instrumentation.ts    # OpenTelemetry設定
│   ├── prisma/
│   │   ├── prisma.module.ts      # Prismaモジュール
│   │   └── prisma.service.ts     # Prismaサービス
│   ├── race/
│   │   ├── race.module.ts        # レースモジュール
│   │   ├── race.controller.ts    # レースコントローラー
│   │   ├── race.service.ts       # レースサービス
│   │   └── dto/
│   │       └── create-race.dto.ts  # レース作成DTO
│   ├── app.module.ts         # ルートモジュール
│   ├── app.controller.ts     # ルートコントローラー
│   ├── app.service.ts        # ルートサービス
│   └── main.ts               # エントリーポイント
├── test/                     # E2Eテスト
├── Dockerfile                # マルチステージDockerビルド
├── package.json
├── nest-cli.json
└── tsconfig.json
```

## 4. モジュール構成

```
AppModule（ルート）
├── ConfigModule（環境変数管理）
├── AuthModule（認証）
│   └── JwtStrategy
├── PrismaModule（データベース）
│   └── PrismaService（グローバル）
├── HealthModule（ヘルスチェック）
│   └── HealthController
└── RaceModule（レース管理）
    ├── RaceController
    └── RaceService
```

## 5. API エンドポイント

### 5.1 レース管理API

| メソッド | パス | 認証 | 説明 |
|---|---|---|---|
| GET | `/api/races` | 条件付き | レース一覧取得（出走馬情報含む） |
| GET | `/api/races/:id` | 条件付き | レース詳細取得（出走馬情報含む） |
| POST | `/api/races` | 条件付き | レース新規作成（出走馬含む） |

### 5.2 テスト・ユーティリティAPI

| メソッド | パス | 認証 | 説明 |
|---|---|---|---|
| GET | `/api/protected` | 条件付き | 認証テスト用エンドポイント |
| GET | `/api/guest/connect-test` | 不要 | 接続テスト用エンドポイント |
| GET | `/health` | 不要 | ヘルスチェック |

### 5.3 レスポンス形式

**GET /api/races**
```json
[
  {
    "id": 1,
    "date": "1993-11-14T00:00:00.000Z",
    "name": "エリザベス女王杯",
    "venue": "京都",
    "entries": [
      {
        "id": 1,
        "raceId": 1,
        "frameNumber": 1,
        "horseNumber": 1,
        "horseName": "ホクトベガ",
        "sex": "牝",
        "age": "4",
        "weight": 55.0,
        "jockey": "加藤和宏",
        "trainer": "中野隆良",
        "bodyWeight": "482(-4)",
        "oddsRank": 9,
        "odds": 30.4,
        "rank": 1,
        "time": "2:24.9",
        "margin": ""
      }
    ]
  }
]
```

**GET /health**
```json
{ "status": "ok" }
```

**GET /api/guest/connect-test**
```json
{ "message": "GET api/guest/connect-test ok4", "time": "2025-01-01T00:00:00.000Z" }
```

### 5.4 リクエストボディ（POST /api/races）

**CreateRaceDto:**

| フィールド | 型 | 必須 | バリデーション | 説明 |
|---|---|---|---|---|
| date | Date (ISO8601) | Yes | `@IsDateString()` | レース開催日 |
| name | string | Yes | `@IsString()` | レース名 |
| venue | string | Yes | `@IsString()` | 競馬場名 |
| entries | CreateEntryDto[] | Yes | `@IsArray()`, `@ValidateNested` | 出走馬リスト |

**CreateEntryDto:**

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| frameNumber | number | Yes | 枠番 |
| horseNumber | number | Yes | 馬番 |
| horseName | string | Yes | 馬名 |
| sex | string | Yes | 性別（例: 牡, 牝） |
| age | string | Yes | 馬齢 |
| weight | number | No | 斤量 (kg) |
| jockey | string | Yes | 騎手名 |
| trainer | string | Yes | 調教師名 |
| bodyWeight | string | No | 馬体重（例: 482(-4)） |
| oddsRank | number | No | 単勝人気順 |
| odds | number | No | 単勝オッズ |
| rank | number | No | 着順 |
| time | string | No | タイム（例: 2:24.9） |
| margin | string | No | 着差 |

## 6. データベース

### 6.1 ERダイアグラム

```
races (Race)                    entries (Entry)
+----------+-----------+        +-------------+-----------+
| id       | Int (PK)  |───┐    | id          | Int (PK)  |
| date     | DateTime  |   │    | raceId      | Int (FK)  |
| name     | String    |   └───>| frameNumber | Int       |
| venue    | String    |        | horseNumber | Int       |
+----------+-----------+        | horseName   | String    |
                                | sex         | String    |
                                | age         | String    |
                                | weight      | Float?    |
                                | jockey      | String    |
                                | trainer     | String    |
                                | bodyWeight  | String?   |
                                | oddsRank    | Int?      |
                                | odds        | Float?    |
                                | rank        | Int?      |
                                | time        | String?   |
                                | margin      | String?   |
                                +-------------+-----------+
```

### 6.2 リレーション

- **Race → Entry**: 1対多（`onDelete: Cascade`）
- レースを削除すると、関連する出走馬レコードも自動削除

### 6.3 テーブルマッピング

| Prismaモデル | テーブル名 |
|---|---|
| Race | `races` |
| Entry | `entries` |

## 7. 認証

### 7.1 JWT認証（Auth0）

| 設定 | 値 |
|---|---|
| 方式 | Bearer Token (Authorization ヘッダー) |
| アルゴリズム | RS256 |
| 鍵取得 | JWKS (`https://{AUTH0_DOMAIN}/.well-known/jwks.json`) |
| 発行者 | `https://{AUTH0_DOMAIN}/` |
| オーディエンス | `AUTH0_AUDIENCE` 環境変数 |

### 7.2 条件付き認証ガード (ConditionalAuthGuard)

`AUTH_ENABLED` 環境変数で認証モードを切り替え:

| AUTH_ENABLED | 動作 | 用途 |
|---|---|---|
| `true` (デフォルト) | JWT認証（Auth0で検証） | 本番環境 |
| `false` | モック認証（常に通過） | ローカル開発 |

## 8. CORS設定

| 設定 | 値 |
|---|---|
| origin | `CORS_ORIGIN` 環境変数（カンマ区切り） |
| methods | `CORS_METHODS` 環境変数（カンマ区切り） |
| credentials | `true` |

`CORS_ORIGIN` と `CORS_METHODS` の両方が設定されている場合のみCORSが有効化される。

## 9. Swagger / OpenAPI

- **本番環境以外** (`NODE_ENV !== 'production'`) で有効
- エンドポイント: `/api` (Swagger UI)
- Bearer認証スキーム設定済み（`access-token`）

## 10. オブザーバビリティ (OpenTelemetry)

### 設定

| 項目 | 値 |
|---|---|
| サービス名 | `OTEL_SERVICE_NAME` (デフォルト: `sandbox-backend`) |
| エクスポーター | OTLP HTTP (Jaeger互換) |
| エンドポイント | `OTEL_EXPORTER_OTLP_ENDPOINT` (デフォルト: `http://localhost:4318/v1/traces`) |

### 計装対象

| 計装 | 対象 |
|---|---|
| Node.js自動計装 | HTTP, Express等（fsは無効化） |
| NestJS計装 | コントローラー、ガード等 |
| Prisma計装 | データベースクエリ |

### 起動方法

```bash
# OpenTelemetry有効で起動
yarn start:otel
```

### グレースフルシャットダウン

`SIGTERM` / `SIGINT` シグナルでSDKをシャットダウンし、未送信のトレースをフラッシュ。

## 11. 環境変数

| 変数名 | 必須 | デフォルト | 説明 |
|---|---|---|---|
| `PORT` | No | `3000` | サーバーリッスンポート |
| `DATABASE_URL` | Yes | - | PostgreSQL接続文字列 |
| `LOG_LEVEL` | No | `error` | ログレベル |
| `CORS_ORIGIN` | No | - | 許可オリジン（カンマ区切り） |
| `CORS_METHODS` | No | - | 許可メソッド（カンマ区切り） |
| `AUTH0_DOMAIN` | Yes | - | Auth0テナントドメイン |
| `AUTH0_AUDIENCE` | Yes | - | Auth0 APIオーディエンス |
| `AUTH_ENABLED` | No | `true` | 認証の有効/無効 |
| `NODE_ENV` | No | - | 実行環境（`production` でSwagger無効） |
| `PRISMA_LOG_LEVEL` | No | - | Prisma ORMのログレベル |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | No | `http://localhost:4318/v1/traces` | OTLPエンドポイント |
| `OTEL_SERVICE_NAME` | No | `sandbox-backend` | OTelサービス名 |

## 12. Docker

### マルチステージビルド

**ステージ1: builder**
- ベースイメージ: `node:22-bookworm-slim`
- Yarnで依存関係インストール（レジストリフォールバック・リトライ設定あり）
- Prismaクライアント生成
- NestJSビルド

**ステージ2: runtime**
- ベースイメージ: `node:22-bookworm-slim`
- 本番依存のみコピー
- 非rootユーザー (`appuser`) で実行
- 公開ポート: `3000`
- エントリーポイント: `node dist/main`

### ビルドコマンド

```bash
docker build -t sandbox-backend .
docker run -p 3000:3000 --env-file .env sandbox-backend
```

## 13. 開発コマンド

| コマンド | 説明 |
|---|---|
| `yarn start:dev` | 開発サーバー起動（ホットリロード） |
| `yarn start:debug` | デバッグモードで起動 |
| `yarn start:prod` | 本番モードで起動 |
| `yarn start:otel` | OpenTelemetry有効で起動 |
| `yarn build` | プロダクションビルド |
| `yarn test` | ユニットテスト実行 |
| `yarn test:e2e` | E2Eテスト実行 |
| `yarn test:cov` | カバレッジ計測 |
| `yarn lint` | ESLint実行（自動修正） |
| `yarn format` | Prettier実行 |

## 14. テスト

| 項目 | 値 |
|---|---|
| テストフレームワーク | Jest 29.7.0 |
| テストランナー | ts-jest |
| テスト環境 | node |
| テストファイルパターン | `*.spec.ts` |
| E2E設定 | `test/jest-e2e.json` |
