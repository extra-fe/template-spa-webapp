# DB マイグレーション (Prisma)

3 クラウドとも DB スキーマは Prisma で管理しています (`backend/sandbox-backend/prisma/`)。 ローカル開発で migration を生成 → コミット → 本番 DB へ適用 する流れです。

## 1. 新規 migration を作る (DB スキーマ変更時)

ローカル PostgreSQL (Docker) に対して開発します。 `dev-up.ps1` で起動済みであれば DB は立ち上がっています。

```powershell
cd backend/sandbox-backend

# schema.prisma を編集 (テーブル追加 / カラム追加など)
# その後 migration ファイルを生成 + ローカル DB に適用
yarn prisma migrate dev --name add_xxx

# 生成された migration を確認 (prisma/migrations/<timestamp>_add_xxx/migration.sql)
# Prisma Client もこのコマンドで自動再生成される
```

`migration.sql` と `schema.prisma` の変更を commit & push → PR。

> 既存 migration を作り直したい場合は `yarn prisma migrate reset` で DB を再構築。 本番では使わない。

## 2. 既存スキーマの確認 / 軽い変更

```powershell
# 現在の DB と schema の差分を確認 (migration を作らずに)
yarn prisma migrate diff `
  --from-schema-datamodel prisma/schema.prisma `
  --to-schema-datasource prisma/schema.prisma

# Prisma Client のみ再生成 (schema には変更なし)
yarn prisma generate
```

## 3. 本番 DB への migration 適用

各クラウドの DB は Private に配置されているため、 踏み台経由でポートフォワードしてから `prisma migrate deploy` を実行します。 ポートフォワード手順は [運用・調査コマンド: DB接続 (踏み台経由)](./operations.md#db接続-踏み台経由) を参照。

```powershell
# Bastion 経由で localhost:15432 → 各クラウドの DB へポートフォワード済みの状態で実行

# DATABASE_URL を 各クラウドの Secret から取得し host:port を localhost:15432 に置換
$Env:DATABASE_URL = "postgresql://<user>:<pass>@localhost:15432/<dbname>?sslmode=require"

cd backend/sandbox-backend
yarn prisma migrate deploy
```

> `migrate deploy` は `migrate dev` と違い、 未適用の migration を順に適用するだけで対話的なリセット動作はしない。 本番運用ではこちらを使う。

## 4. Prisma で表現できない DDL を実行する場合

Prisma の migration では表現できない / Prisma が自動生成しないものは、 raw SQL を migration ファイルに手書きするか、 psql で直接実行します。 例:

- **PostgreSQL 拡張** (`CREATE EXTENSION pgcrypto;` 等)
- **トリガー / ストアド** (`CREATE TRIGGER` / `CREATE FUNCTION`)
- **行レベルセキュリティ** (`ENABLE ROW LEVEL SECURITY` / `CREATE POLICY`)
- **複合インデックス・部分インデックス・GIN/GIST**
- **CHECK 制約・複雑な UNIQUE 制約**
- **データバックフィル** (スキーマ変更と同時に既存データを書き換える)
- **ロール / 権限** (`CREATE ROLE`, `GRANT`)
- **VIEW / MATERIALIZED VIEW**

### A. Prisma migration ファイルに DDL を手書き (推奨)

履歴管理されるため、 本番含めて再現性が担保される。

```powershell
cd backend/sandbox-backend

# --create-only で migration ファイルだけ生成 (DB に適用しない)
yarn prisma migrate dev --create-only --name add_pgcrypto_extension

# 生成された prisma/migrations/<timestamp>_add_pgcrypto_extension/migration.sql を編集
# 末尾に raw SQL を追記
#   CREATE EXTENSION IF NOT EXISTS pgcrypto;
#   CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_race_held_on ON "Race" USING btree (held_on);

# 編集後に適用 (ローカル DB)
yarn prisma migrate dev
```

> `db pull` で schema.prisma を実 DB に合わせて更新すると、 Prisma が認識可能な範囲 (テーブル/カラム/インデックス等) は反映される。 認識外の DDL (RLS / トリガー等) は migration.sql の手書きが正となる。

### B. psql で直接 DDL を実行 (ホットフィックス / 検証用)

緊急対応や、 Prisma 管理外で恒久的に持つもの (例: 監視用 VIEW を別 schema に作る) は psql で直接実行。

```powershell
# 踏み台経由で localhost:15432 にポートフォワード済みの状態

# ファイル経由で実行 (推奨: 履歴が残せる)
psql "$Env:DATABASE_URL" -f .\ddl\add_pgcrypto.sql

# ワンライナーで実行
psql "$Env:DATABASE_URL" -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"

# トランザクション内で実行 (失敗時に ROLLBACK)
psql "$Env:DATABASE_URL" -1 -f .\ddl\add_rls.sql
```

> psql 直実行は **Prisma の migration 履歴 (`_prisma_migrations`) に残らない**ため、 次の `migrate dev` 時に差分として検出される可能性がある。 恒久対応は A. の migration 手書きに含めること。

### C. 本番 DDL を反映する際の運用フロー

```
1. ローカル DB で A or B で DDL を試す
2. A. なら migration.sql を確定して commit & push & PR
3. 本番 (各クラウド DB) に踏み台経由で接続
4. yarn prisma migrate deploy で適用
   または psql -f で raw SQL を実行
5. _prisma_migrations / pg_extension / pg_indexes 等で適用結果を確認
```

### D. 重い DDL (CREATE INDEX / ALTER COLUMN 等) の注意

- `CREATE INDEX` は `CONCURRENTLY` 付きでオンライン作成 (トランザクション外で実行)
- `ALTER COLUMN` で型変更する場合、 テーブルサイズに比例して時間がかかる
- 大きな DDL は **メンテナンスウィンドウ** に実施 (cloud 別 maintenance_window 設定参照)

## 5. 適用後の動作確認

```powershell
# Migration 履歴の確認 (_prisma_migrations テーブル)
psql "$Env:DATABASE_URL" -c "SELECT migration_name, started_at, finished_at FROM _prisma_migrations ORDER BY started_at DESC LIMIT 5;"

# テーブル一覧
psql "$Env:DATABASE_URL" -c "\dt"

# 行数チェック (例)
psql "$Env:DATABASE_URL" -c "SELECT count(*) FROM \"Race\";"

# 拡張機能の確認 (DDL で CREATE EXTENSION した場合)
psql "$Env:DATABASE_URL" -c "SELECT extname, extversion FROM pg_extension ORDER BY extname;"

# インデックス確認 (DDL で CREATE INDEX した場合)
psql "$Env:DATABASE_URL" -c "SELECT schemaname, tablename, indexname FROM pg_indexes WHERE schemaname = 'public' ORDER BY tablename, indexname;"
```

ヘルスチェック・API スモークテストも実施:

```powershell
curl https://<your-domain>/api/guest/connect-test
curl https://<your-domain>/api/races   # 必要に応じて Bearer token 付き
```
