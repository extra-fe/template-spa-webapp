# セキュリティ強化 (Web脆弱性診断 事前対応)

第三者Web脆弱性診断を見据えた一般的なハードニングを適用済みです。本ドキュメントでは **適用済み項目** と **テンプレートとして意図的に未適用とした項目** を整理しています。プロジェクトの要件に応じて未適用項目を取捨選択してください。

## 適用済み項目

| 領域 | 内容 |
|---|---|
| CloudFront | レスポンスヘッダポリシー (HSTS / CSP / X-Frame-Options / X-Content-Type-Options / Referrer-Policy / Permissions-Policy) / `/api/*` を `https-only` 化 |
| WAF | レートベースルール (`/api/*` で 5分2000req/IP, Block) / AnonymousIpList マネージドルール (`HostingProviderIPList` は Count 化) |
| ALB | `drop_invalid_header_fields = true` (HTTP リクエストスマグリング対策) |
| S3 | 全バケットに SSE-S3 (AES256) 既定暗号化を明示適用 |
| NestJS | Helmet / グローバル ValidationPipe (`whitelist` + `forbidNonWhitelisted` + `transform`) / グローバル例外フィルタ (本番でスタック非露出) |

## 意図的に未適用とした項目

テンプレートのシンプルさと診断要件のバランスから、以下は **未適用** としています。

### 1. アプリケーション層レート制限 (`@nestjs/throttler`)

- **未適用の理由**: WAF v2 のレートベースルール (`/api/*` で 2000req/5min/IP) で代替済み。`@nestjs/throttler` のデフォルトメモリストアは ECS マルチタスク構成では共有されず、Redis 等の外部ストア導入が必要になり構成が肥大化する。
- **適用を検討すべきケース**:
  - ログインや OTP 等の特定エンドポイントに細粒度なスロットリングを掛けたい
  - WAF を使わない環境にデプロイする (Azure App Service 等)
  - 認証済みユーザー単位 (JWT `sub`) でレート制限したい

### 2. CloudFront `/api/*` の HTTP メソッド絞り込み

- **未適用の理由**: CloudFront の `allowed_methods` は `["GET","HEAD"]` / `["GET","HEAD","OPTIONS"]` / 全7メソッドの3パターンしか選択できず、`POST` を使う本テンプレートでは全許可セット以外を選べない。NestJS は未定義メソッド (`PUT`/`PATCH`/`DELETE` 等) へ 404 を返すため実害なし。
- **適用を検討すべきケース**: 診断ツールが「unused HTTP methods allowed」を指摘した場合、WAF カスタムルールで `/api/*` 配下の未使用メソッドを Block する (実装するとアプリ側で新メソッド追加時に WAF ルール更新が必要)。

### 3. CloudFront カスタムドメイン + ACM (TLSv1.2 強制)

- **未適用の理由**: デフォルト証明書 (`*.cloudfront.net`) 利用時は `minimum_protocol_version` を `TLSv1.2_*` に上げても実質無視される (AWS の仕様)。カスタムドメインと ACM 証明書を導入して初めて TLSv1.2/1.3 強制が有効になる。
- **適用を検討すべきケース**: 本番運用でカスタムドメインを使う場合。同時に HSTS の `preload` 有効化と HSTS Preload List 申請も行うと診断スコアがさらに改善。

### 4. S3 SSE-KMS (顧客管理キー)

- **未適用の理由**: SSE-S3 (AES256) で診断要件は満たせる。SSE-KMS は KMS 使用料 + 各サービスへの KMS 権限付与が必要で、テンプレートの初期構成としては過剰。
- **適用を検討すべきケース**: 監査要件で「鍵の使用ログ取得」「鍵ローテーションの管理者制御」が必要な場合。

### 5. CloudFront 経由のインフラ情報露出 (Technology Fingerprinting)

- **未適用の理由**: CloudFront はレスポンスに `x-amz-cf-id`・`x-amz-cf-pop`・`x-cache: Miss from cloudfront`・`via: xxx.cloudfront.net (CloudFront)` を自動付与する。`x-amz-cf-*` は AWS 管理ヘッダのためユーザー側で削除できない。`x-cache`・`via` は CloudFront レスポンスヘッダポリシーの `remove_headers_config` で除去可能だが、ドメインが `*.cloudfront.net` である限り IP レンジ（公開情報）からも CloudFront 利用は自明であり、除去の実効性は低い。`x-powered-by: Express` は Helmet が除去済み。
- **診断上のリスク**: 「Technology Fingerprinting」として低〜中リスクで指摘されることがあるが、実害はほぼない。
- **適用を検討すべきケース**: カスタムドメインへ移行した上で `x-cache`・`via` を `remove_headers_config` で除去すると、露出を最小化できる。ただし Shodan 等でのインフラ特定は引き続き可能なため、セキュリティ上の本質的な改善は限定的。

## 診断実施時の運用上の注意

- **WAF レート制限と診断ツールの衝突**: 第三者診断ツールは大量リクエストを送るため `/api/*` のレートベースルール (2000req/5min/IP) に引っかかる可能性が高い。診断ベンダのソース IP 帯が判明したら、`aws_wafv2_ip_set` + 高優先度 (priority < 40) の allow ルールを一時追加する。
- **AnonymousIpList の HostingProviderIPList**: 上記の通り Count 化してあるため、クラウド由来の診断トラフィックはブロックされない (ログには記録される)。
- **WAF ログでの結果確認**: CSP 違反やレート制限ヒットは Athena (`waf_logs` テーブル) で集計可能。
