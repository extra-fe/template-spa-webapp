# tests/load — API 負荷テスト (k6)

NestJS API への HTTP 負荷テストを [k6](https://k6.io/) で実行する。
**AWS / Azure / GCP すべてのステージング環境で同じスクリプトが使える** (`BASE_URL` を差し替えるだけ)。

## ⚠️ 実行前の必須確認事項

- **本番環境では絶対に実行しない。** `lib/config.js` に URL に `prod` を含む場合のガードを入れているが、最終的な責任は実行者にある
- **対象環境の関係者に事前周知**する (CloudFront/WAF/ALB/Aurora/Auth0 すべてに痕跡が残る)
- **クラウドの利用料金**が発生する (Aurora ACU, Cloud Run リクエスト課金, データ転送量など)
- AWS の場合、**WAF のレート制限ルール**に引っかかる可能性がある。低 RPS から段階的に上げること

## 構成

```
tests/load/
├── README.md                # このファイル
├── .env.example             # env テンプレ (.env はコミット禁止)
├── lib/
│   ├── config.js            # stages / thresholds 共通定義 + 本番ガード
│   ├── auth.js              # Auth0 ROPG トークン取得 (setup() 用)
│   └── data.js              # POST /api/races のテストデータ生成
└── scenarios/
    ├── smoke.js             # /health + /api/guest/connect-test を 1 VU × 30s (環境疎通確認)
    ├── races-read.js        # GET /api/races + /api/races/:id
    ├── races-write.js       # POST /api/races
    └── mixed.js             # 70% read / 30% write の混在ワークロード (メイン)
```

## 前提セットアップ

### 1. Auth0 ロードテスト用アプリ & ユーザー (初回 1 回のみ)

ROPG (Resource Owner Password Grant) でトークンを取得するため、以下を Auth0 ダッシュボードで準備する。

1. **Application を作成**: Application Type = "Regular Web Application"
   - Settings → Advanced Settings → Grant Types → **"Password" を ON**
   - Settings から `Client ID` / `Client Secret` を控える
2. **Tenant Settings → General → "Default Directory"** にデータベース接続名を設定 (例: `Username-Password-Authentication`)
3. **テストユーザーを 1 名作成** (User Management → Users → Create User)
   - 接続: 上記の Database 接続
   - メールアドレスは `loadtest@example.com` のようにロードテスト専用と分かるものに

> **NOTE**: ROPG は非推奨のグラントタイプだが、負荷試験用途に限れば最も簡単。1 ユーザー 1 トークンで全 VU 共有するので、テスト中の Auth0 呼び出しは **1 回だけ**。

### 2. EC2 踏み台 (作業 VM) に k6 をインストール

Amazon Linux 2023 の場合:

```bash
sudo dnf install -y https://dl.k6.io/rpm/repo.rpm
sudo dnf install -y k6
k6 version
```

Ubuntu の場合:

```bash
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
  --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" \
  | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update
sudo apt-get install -y k6
```

### 3. リポジトリを clone して `.env` を作成

```bash
git clone <this-repo>
cd template-spa-webapp/tests/load
cp .env.example .env
vim .env   # BASE_URL と AUTH0_* を埋める
```

## 実行

### 環境変数の読み込み

```bash
# tests/load/ ディレクトリ直下で
set -a; source .env; set +a
```

### シナリオの実行

```bash
# まず疎通確認
k6 run scenarios/smoke.js

# 読み取りのみ
k6 run scenarios/races-read.js

# 書き込みのみ
k6 run scenarios/races-write.js

# 混在ワークロード (メイン)
k6 run scenarios/mixed.js
```

### クラウドの切り替え

`.env` の `BASE_URL` を差し替えるだけ。

| クラウド | BASE_URL の例 |
|---|---|
| AWS | `https://<dist>.cloudfront.net` |
| Azure | `https://<endpoint>.azurefd.net` |
| GCP | `https://<lb-domain-or-ip>` |

Auth0 テナントが 3 クラウドで共通なら `AUTH0_*` はそのままで OK。

### 結果の保存

```bash
# JSON サマリを残す
k6 run --summary-export=summary-$(date +%Y%m%d-%H%M%S).json scenarios/mixed.js

# リアルタイムで InfluxDB / CloudWatch / Datadog に投げる場合は k6 の output オプション参照
```

## チューニング

- **VU 数 / 持続時間**: `lib/config.js` の `defaultStages` を編集 (シナリオ側で上書き可)
- **しきい値 (p95, error rate)**: `lib/config.js` の `defaultThresholds` を編集
- **書き込み比率**: `scenarios/mixed.js` の `Math.random()` 閾値を変更

## クリーンアップ (重要)

POST `/api/races` で作成されたレコードは `name` が `LOADTEST-` で始まるので、テスト後にまとめて削除する。

### 踏み台 → Aurora / Flexible Server / Cloud SQL に psql 接続

接続方法は各クラウドの README を参照:
- AWS: `iac/aws/README.md` (踏み台 + SSM Session Manager + port forwarding)
- Azure: `iac/azure/README.md`
- GCP: `iac/gcp/README.md` (IAP TCP forwarding, ローカルポート 15432)

### 削除 SQL

```sql
-- entries は races の cascade で消える
DELETE FROM races WHERE name LIKE 'LOADTEST-%';

-- 念のため件数確認
SELECT COUNT(*) FROM races WHERE name LIKE 'LOADTEST-%';  -- → 0 になっているはず
```

特定の run だけ消したい場合 (k6 を `RUN_ID=20260101-001 k6 run ...` で起動した場合):

```sql
DELETE FROM races WHERE name LIKE 'LOADTEST-20260101-001-%';
```

## トラブルシュート

| 症状 | 原因 / 対処 |
|---|---|
| `BASE_URL is required` | `.env` が読み込まれていない。`set -a; source .env; set +a` を忘れていないか |
| `Auth0 ROPG failed: status=403` | Application で "Password" grant が無効。Auth0 ダッシュボードで有効化 |
| `Auth0 ROPG failed: status=403 ... access_denied` | Tenant の Default Directory 未設定、またはユーザー/パスワード不一致 |
| `Auth0 ROPG failed: status=400 ... invalid_grant` | ユーザーの接続が Default Directory と一致しない |
| 大量に `403` が返る | AWS WAF レート制限。`stages` の `target` を下げる |
| `502 Bad Gateway` 連発 | API/DB がサチュレート。Aurora ACU / Cloud Run min-instances を確認 |
| Auth0 自体に届かない | EC2 のセキュリティグループ outbound 443 が空いているか |
