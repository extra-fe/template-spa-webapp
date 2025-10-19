# syntax=docker/dockerfile:1.7

########## Build Stage ##########
FROM node:22-bookworm-slim AS builder

WORKDIR /usr/src/app

# まず依存のみコピーして確定
COPY package.json yarn.lock ./

# レジストリ固定 + キャッシュ + リトライ + 固定ロック
ENV YARN_REGISTRY=https://registry.npmjs.org
RUN --mount=type=cache,target=/root/.cache/yarn bash -ceu '\
  yarn config set registry "$YARN_REGISTRY" >/dev/null ; \
  for i in 1 2 3; do \
    echo "==> yarn install (try ${i}/3)"; \
    yarn install --frozen-lockfile --non-interactive --network-timeout 600000 && exit 0; \
    echo "yarn install failed; retrying..."; sleep $((i*5)); \
  done; exit 1 \
'

# アプリ本体
COPY . .

# Prisma クライアント生成（エンジン同梱）
RUN npx prisma generate

# ビルド（Nest/TS）
RUN yarn build


########## Runtime Stage ##########
FROM node:22-bookworm-slim

# OpenSSL と CA を追加（サイズ削減のため後片付け）
RUN apt-get update -y \
 && apt-get install -y --no-install-recommends openssl libssl3 ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# 非特権ユーザー
RUN useradd -ms /bin/bash appuser
WORKDIR /usr/src/app

# 実行に必要なものだけインストール（prod 依存のみ）
COPY package.json yarn.lock ./
ENV YARN_REGISTRY=https://registry.npmjs.org NODE_ENV=production
RUN --mount=type=cache,target=/root/.cache/yarn bash -ceu '\
  yarn config set registry "$YARN_REGISTRY" >/dev/null ; \
  yarn install --production --frozen-lockfile --non-interactive --network-timeout 600000 \
'

# ビルド成果物と Prisma 配布物をコピー
COPY --from=builder /usr/src/app/dist ./dist
# Prisma はクライアント本体と .prisma（エンジン）両方必要
COPY --from=builder /usr/src/app/node_modules/@prisma ./node_modules/@prisma
COPY --from=builder /usr/src/app/node_modules/.prisma ./node_modules/.prisma

# 権限
RUN chown -R appuser:appuser /usr/src/app
USER appuser

EXPOSE 3000
CMD ["node", "dist/src/main"]
