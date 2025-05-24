# 正誤表

| No  | title                                     | section           |
| --- | ----------------------------------------- | ----------------- |
| 1   | Auth0 API呼び出し用のパーミッション不足 | 1.2.10 IdP(Auth0) |
| 2   | CloudFront VPCオリジン取得用のfilter条件不足 | 2.2.5 CloudFront VPCオリジン |

# 正誤表内容
## No1 Auth0 API呼び出し用のパーミッション不足

### 修正点
- Auth0のMachine to Machine Application作成手順に***Auth0 Management API を選択*** が不足している
- アプリケーション作成時に指定するパーミッションが不足している

### 誤
- アプリケーション名は任意(ここでは、Terraform Provider Auth0 auth)
- permissionsは以下を選択
    - read:clients
    - update:clients
    - delete:clients
    - create:clients

### 正
- アプリケーション名は任意(ここでは、Terraform Provider Auth0 auth)
- ***Auth0 Management API を選択***
- permissionsは以下を選択
    - read:clients
    - update:clients
    - delete:clients
    - create:clients
    - ***read:resource_servers***
    - ***update:resource_servers***
    - ***delete:resource_servers***
    - ***create:resource_servers***

### 誤のままだとこうなります
terraform apply でエラーになります。
`create:resource_servers` のpermissionがないためです。

![terraform applyでエラー](./images/errata-01.png)
```
│ Error: 403 Forbidden: Insufficient scope, expected any of: create:resource_servers
│
│   with auth0_resource_server.audience,
│   on auth0.tf line 26, in resource "auth0_resource_server" "audience":
│   26: resource "auth0_resource_server" "audience" {
```

## No2 CloudFront VPCオリジン取得用のfilter条件不足

### 修正点
- CloudFront VPCオリジン取得用のfilter条件に、VPCを追加

### 誤
security-group.tfへの追記内容
```
data "aws_security_group" "cloudfront_vpc_origin" {
  filter {
    name   = "group-name"
    values = ["CloudFront-VPCOrigins-Service-SG"]
  }
  depends_on = [aws_cloudfront_vpc_origin.alb]
}
```

### 正
```
data "aws_security_group" "cloudfront_vpc_origin" {
  filter {
    name   = "group-name"
    values = ["CloudFront-VPCOrigins-Service-SG"]
  }
  filter {
    name   = "vpc-id"
    values = [aws_vpc.vpc.id]
  }
  depends_on = [aws_cloudfront_vpc_origin.alb]
}
```


### 誤のままだとこうなります
- 別VPC用のCloudFront VPCオリジンを作った時に、セキュリティグループ CloudFront-VPCOrigins-Service-SG が1件に特定できずにエラーになる