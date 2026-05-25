# Front Door の SKU 選択について (Azure)

本テンプレートでは **Front Door Standard SKU** を採用しています (`sku_name = "Standard_AzureFrontDoor"`)。 Premium との主な違いと、 Standard を選んだ理由を整理します。

## Standard と Premium の主な違い

| 項目 | Standard | Premium |
|---|---|---|
| グローバル LB / CDN / カスタムドメイン / TLS | ✅ | ✅ |
| Front Door Rules Engine (ヘッダ書き換え等) | ✅ | ✅ |
| **WAF (Microsoft_DefaultRuleSet / Microsoft_BotManagerRuleSet)** | ❌ | ✅ |
| **Private Link to Origin** (App Service / Container Apps 等を private にして直接非公開化) | ❌ | ✅ |
| エンドポイント数上限 | 10 | 25 |
| 月額基本料金 (Japan East 目安) | **約 $35** | **約 $330** |

## 本テンプレが Standard を採用している理由

1. **コスト**: dev/sandbox 用途で月 $300+ の固定費は過剰 (約10倍差)
2. **WAF 不要**: AWS 側で配置している `aws_wafv2_web_acl` 相当は Standard では作れない。 dev では DRS マネージドルールが必須となる脅威モデルでない判断
3. **Private Link 不可の代替策あり**: Container Apps ingress を public のまま、 アプリ層で `X-Azure-FDID` ヘッダ検証することで「Front Door 経由のみ許可」を実現可能 (本テンプレ未実装、 ハードニング項目として残置)
4. **upgrade パスがある**: 本番化時に Premium へ変更すれば WAF / Private Link が即利用可能

## Premium に upgrade すべきタイミング

- **本番リリース時**: WAF (DRS + Bot Manager) で公開層を守りたい
- **クローズドな業務システム化**: Container Apps ingress を private にして公開接点を Front Door に集約したい

## upgrade 時の作業

1. `iac/azure/frontdoor-standard.tf` の `sku_name` を `"Premium_AzureFrontDoor"` に変更
2. `azurerm_cdn_frontdoor_firewall_policy` と `azurerm_cdn_frontdoor_security_policy` を追加 (AWS WAF v2 の 3 種マネージドルール相当をマッピング)
3. (任意) Container Apps 環境を `internal_load_balancer_enabled = true` に変更し、 Front Door から Private Link で接続
