# Frontend 仕様書

## 1. 概要

競馬レース管理SPAアプリケーションのフロントエンド。Auth0による認証機能を備え、レース情報のCRUD操作を提供する。

| 項目 | 値 |
|---|---|
| アプリケーション名 | sandbox-frontend |
| フレームワーク | React 19.2.0 |
| 言語 | TypeScript 5.9.x |
| ビルドツール | Vite 6.4.1 |
| パッケージマネージャ | Yarn |
| ソースパス | `frontend/sandbox-frontend/` |

## 2. 技術スタック

### 依存ライブラリ

| ライブラリ | バージョン | 用途 |
|---|---|---|
| react | ^19.2.0 | UIライブラリ |
| react-dom | ^19.2.0 | DOM レンダリング |
| react-router-dom | ^7.9.5 | クライアントサイドルーティング |
| @auth0/auth0-react | ^2.8.0 | Auth0認証SDK |
| axios | ^1.13.2 | HTTPクライアント |

### 開発ツール

| ツール | 用途 |
|---|---|
| @vitejs/plugin-react | Vite用Reactプラグイン |
| typescript-eslint | TypeScript用ESLint |
| eslint-plugin-react-hooks | React Hooks Lintルール |
| eslint-plugin-react-refresh | React Refresh Lintルール |

## 3. ディレクトリ構成

```
frontend/sandbox-frontend/
├── public/                  # 静的ファイル
├── src/
│   ├── components/          # 共通コンポーネント
│   │   └── ProtectedRoute.tsx   # 認証ガードコンポーネント
│   ├── hooks/               # カスタムフック
│   │   └── useApiCaller.ts      # API呼び出しフック
│   ├── pages/               # ページコンポーネント
│   │   ├── Login.tsx            # ログインページ
│   │   └── RaceApp.tsx          # レース管理ページ
│   ├── App.tsx              # トップページ（ホーム）
│   ├── App.css              # アプリケーションスタイル
│   ├── index.css            # グローバルスタイル
│   └── main.tsx             # エントリーポイント
├── .env                     # 環境変数テンプレート
├── package.json
├── tsconfig.json
├── tsconfig.app.json
├── tsconfig.node.json
├── vite.config.ts
└── eslint.config.js
```

## 4. ルーティング

| パス | コンポーネント | 認証 | 説明 |
|---|---|---|---|
| `/` | `App` | 不要 | ホームページ。ログイン/ログアウトボタン、API接続テスト |
| `/login` | `Login` | 不要 | ログインページ |
| `/races` | `RaceApp` | **必須** | レース管理ページ（ProtectedRouteで保護） |

### 認証ガード (ProtectedRoute)

- `useAuth0` フックで認証状態を確認
- 未認証の場合、`loginWithRedirect()` でAuth0ログインページにリダイレクト
- ローディング中は `Loading...` を表示

## 5. 認証

### Auth0 設定

| 設定項目 | 値の取得元 |
|---|---|
| domain | `VITE_AUTH0_DOMAIN` |
| clientId | `VITE_AUTH0_CLIENT_ID` |
| audience | `VITE_AUTH0_AUDIENCE` |
| redirect_uri | `window.location.origin` |

### 認証フロー

1. ユーザーがログインボタンをクリック
2. Auth0のユニバーサルログインページにリダイレクト
3. 認証成功後、`redirect_uri` に戻る
4. `getAccessTokenSilently()` でアクセストークンを取得
5. API呼び出し時に `Authorization: Bearer <token>` ヘッダーを付与

## 6. API通信

### useApiCaller カスタムフック

API呼び出しを一元管理するカスタムフック。

```typescript
callApi<T>(
  path: string,               // APIパス（例: '/api/races'）
  requiresAuth: boolean = true, // 認証要否（デフォルト: true）
  method: string = 'GET',     // HTTPメソッド
  body?: unknown              // リクエストボディ
): Promise<T>
```

**動作仕様:**
- ベースURL: `VITE_API_BASE_URL` 環境変数から取得
- 認証が必要な場合、Auth0からトークンを取得し `Authorization` ヘッダーに付与
- `Content-Type: application/json` を全リクエストに設定
- `withCredentials: true` でクッキーを送信
- エラー時は `API call failed with status {statusCode}` メッセージでthrow

## 7. 画面仕様

### 7.1 ホーム画面 (`/`)

| 要素 | 機能 |
|---|---|
| Login/Logoutボタン | 認証状態に応じて表示を切り替え |
| ユーザー名表示 | 認証済み: ユーザー名、未認証: `unauthorized`、読込中: `LoadingNow` |
| Call Guest APIボタン | `/api/guest/connect-test` を認証なしで呼び出し |
| Call Protected APIボタン | `/api/protected` を認証ありで呼び出し |
| APIレスポンス表示 | JSON形式で整形表示 |

### 7.2 レース管理画面 (`/races`)

**レース一覧テーブル:**

| カラム | フィールド |
|---|---|
| ID | `race.id` |
| Name | `race.name` |
| Date | `race.date`（YYYY-MM-DD形式で表示） |
| Venue | `race.venue` |
| Action | Viewボタン |

**レース詳細パネル:**
- レース名と日付をヘッダーに表示
- 競馬場（Venue）を表示
- 出走馬一覧テーブル: No.(馬番), Horse Name, Jockey, Trainer, Weight

**レース新規作成フォーム:**

| フィールド | 入力タイプ | バリデーション |
|---|---|---|
| Date | `date` | 必須（未入力時にalert表示） |
| Race name | `text` | - |
| Venue | `text` | - |

- 日付はJST（+09:00）のISO8601形式に変換して送信

## 8. 環境変数

| 変数名 | 説明 | 例 |
|---|---|---|
| `VITE_AUTH0_DOMAIN` | Auth0テナントドメイン | `your-tenant.auth0.com` |
| `VITE_AUTH0_CLIENT_ID` | Auth0アプリケーションのClient ID | `xxxxxxxxxxxxxxxxxxxx` |
| `VITE_AUTH0_AUDIENCE` | Auth0 APIオーディエンス | `https://your-api.example.com` |
| `VITE_API_BASE_URL` | バックエンドAPIのベースURL | `https://your-cdn.example.com` |

## 9. ビルド・開発コマンド

| コマンド | 説明 |
|---|---|
| `yarn dev` | 開発サーバー起動（Vite） |
| `yarn build` | TypeScriptコンパイル + プロダクションビルド |
| `yarn preview` | ビルド結果のプレビュー |
| `yarn lint` | ESLint実行 |

## 10. デプロイ

### AWS
- `yarn build` で生成される `dist/` ディレクトリをS3バケットにアップロード
- CloudFrontのキャッシュを無効化
- CodePipeline（CodeBuild）で自動化

### Azure
- `yarn build` で生成される `dist/` ディレクトリをAzure Blob Storage (`$web` コンテナ) にアップロード
- Front Doorのキャッシュをパージ
- GitHub Actions で手動トリガー（`workflow_dispatch`）

### SPA ルーティング対応
- AWS: CloudFrontカスタムエラーレスポンス（403 → 200 `/index.html`）
- Azure: Storage Account の静的Webサイトホスティングでエラードキュメントに `index.html` を指定
