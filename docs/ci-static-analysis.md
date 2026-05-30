# 静的解析 (Lint / 型チェック) の CI ゲート

TypeScript (backend / frontend) の ESLint と型チェックを **PR 時点で自動検出する CI ゲート**を用意しています。これまでローカルの `yarn lint` 任せだった lint / 型エラー / 規約逸脱を、`main` への PR でブロックします。

## 対象ワークフロー

| 対象 | ワークフロー | ジョブ |
|---|---|---|
| backend (`backend/sandbox-backend`) | [.github/workflows/ci-backend.yaml](../.github/workflows/ci-backend.yaml) | **Backend Lint & Type check** (`yarn lint:ci` + `yarn typecheck`) |
| frontend (`frontend/sandbox-frontend`) | [.github/workflows/ci-frontend.yaml](../.github/workflows/ci-frontend.yaml) | **Frontend Lint & Type check** (`yarn lint:ci` + `yarn typecheck`) |

## 設計上のポイント

- **非破壊・厳格**: CI 用の `lint:ci` は `--fix` を付けず `--max-warnings 0` で実行し、warning も失敗扱いにします (ローカル整形用の `lint` は従来どおり `--fix` 付き)。型チェックは backend `tsc --noEmit` / frontend `tsc -b --noEmit`。
- **Trivy と並列実行**し、失敗時は既存パターンで Slack 通知します。
- backend は `no-floating-promises` / `no-unsafe-argument` を **error に昇格**済み (`no-explicit-any` のみ off)。
- 改行コードはリポジトリ root の [.gitattributes](../.gitattributes) (`* text=auto eol=lf`) で LF に正規化し、Windows の `core.autocrlf=true` 環境でも Prettier の CRLF 差分が CI で誤検出されないようにしています。
- パスフィルタはワークフローではなく**ジョブレベル** (`changes` ジョブ + `if`) で行うため、backend/frontend を含まない PR (docs / iac 等) でも各ジョブは **skipped (= 必須チェックでは成功扱い)** として報告されます。これにより `Backend/Frontend Lint & Type check` を Required status checks にしても、対象外 PR が「Expected で永久 pending」になりマージ不能になる問題を回避しています。

## PR 必須化 (Branch protection)

PR 必須化するには Branch protection の Required status checks に `Backend Lint & Type check` / `Frontend Lint & Type check` を追加します (管理者権限が必要)。

運用の詳細は [Backend仕様書](./backend-spec.md) / [Frontend仕様書](./frontend-spec.md) の「静的解析 / CI ゲート」節を参照してください。
