# ローカル開発 (Windows / PowerShell 一括起動)

リポジトリルートの `dev-up.ps1` で「PostgreSQL コンテナ起動 → Prisma generate/migrate → backend (`yarn start`) → frontend (`yarn dev`)」を一括実行できます。冪等なので何度実行しても安全です。

## 前提

- Docker Desktop（起動済み）
- PowerShell 7+ (`pwsh`) — `Start-Process pwsh` で別ウィンドウを開くため
- Node.js + `yarn` (Classic / v1.x) が `PATH` 上にある
  - Node のバージョンは backend `package.json` の `engines` で `^20.19.0 || ^22.13.0 || >=24.0.0` を要求していますが、スクリプトは `--ignore-engines` を付けるため Node 23 等でも動作します

## 実行

```powershell
.\dev-up.ps1
```

## スクリプトが行うこと

- `backend/.env` / `frontend/.env` が無ければ `.env.example` から作成（DB port=15432 / `AUTH_ENABLED=false` / `VITE_AUTH_ENABLED=false` に書き換え）
- Docker コンテナ `pg-local` (postgres:16) を `localhost:15432` で起動
- `node_modules` が無ければ `yarn install --ignore-engines`（Node 23 等の非対応バージョン対応）
- `prisma generate` → `prisma migrate deploy`
- backend (`yarn start`) と frontend (`yarn dev`) を **別の PowerShell ウィンドウ** で起動

## 停止

- backend / frontend: 各ウィンドウで `Ctrl+C`
- DB: `docker stop pg-local`

## 認証スキップ

backend は `.env` で `AUTH_ENABLED=false`、frontend は `.env` で `VITE_AUTH_ENABLED=false` を設定するとローカルで Auth0 認証をスキップできます（`dev-up.ps1` は `.env` 自動生成時にこれを設定します）。
