# template-spa-webapp
## MFAデバイスを使用してのトークン取得
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

## S3バケットを空にする
バケット名は実際のものに変更のこと。
```
aws s3 rm s3://sandbox-aws-dev-artifact-ngt8d --recursive
aws s3 rm s3://sandbox-aws-dev-web-ngt8d --recursive
```