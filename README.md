# ローカル環境を作ってAWSとAzureにデプロイ

技術書典18で出した本から参照しているコードを保存しているリポジトリです。

正誤表もこちらに記載しています。

# 正誤表
[こちら](./appendix/errata.md)をご確認ください。

## 明細
- 1.2.10 
    - IdP(Auth0)   Auth0のMachine to Machine Application作成

# コマンドなど
## AWS
### MFAデバイスを使用してのトークン取得
MFAデバイスを使用してのトークンを取得します。IAMユーザの多要素認証 (MFA)にある、識別子を控えます。
  
以下コマンドの[識別子]を控えた値に置き換えて、Powershellで実行します。

```
$mfa_device='[識別子]'

$Env:AWS_ACCESS_KEY_ID=''
$Env:AWS_SECRET_ACCESS_KEY=''
$Env:AWS_SESSION_TOKEN=''

$token=Read-Host
$cre=(aws sts get-session-token --serial-number $mfa_device --token-code $token) | ConvertFrom-Json

$Env:AWS_ACCESS_KEY_ID=$cre.Credentials.AccessKeyId
$Env:AWS_SECRET_ACCESS_KEY=$cre.Credentials.SecretAccessKey
$Env:AWS_SESSION_TOKEN=$cre.Credentials.SessionToken  
```

### S3バケットを空にする
バケット名は実際のものに変更のこと。
```
aws s3 rm s3://sandbox-aws-dev-artifact-6hqqm --recursive
aws s3 rm s3://sandbox-aws-dev-web-6hqqm --recursive
```

### ECRのリポジトリを空にする

```
# リポジトリ名を指定してください
$repositoryName = "dev/sandbox-aws-backend"

# リポジトリ内のイメージ一覧を取得
$imageList = aws ecr list-images --repository-name $repositoryName --query "imageIds[*]" --output json | ConvertFrom-Json

# イメージを1つずつ削除
foreach ($image in $imageList) {
    $imageDigest = $image.imageDigest
    $imageTag = $image.imageTag
    $imageId = @{}
    if ($imageDigest) {
        $imageId["imageDigest"] = $imageDigest
    }
    if ($imageTag) {
        $imageId["imageTag"] = $imageTag
    }
    aws ecr batch-delete-image --repository-name $repositoryName --image-ids (ConvertTo-Json @($imageId))
}
Write-Host "リポジトリ内のイメージが削除されました。"

```

## バックエンド
### ヘルスチェック用のコントローラ作成
```
nest g controller health
nest g module health
```

## API呼び出し
```
Invoke-WebRequest http://localhost:13000/ -Method GET
```

## Dockerコマンド
```
docker build -t hoge -f ./Dockerfile .    

docker stop $(docker ps -q --filter "ancestor=hoge:latest")
docker run -p 13000:3000 -e LOG_LEVEL=error hoge:latest
```

