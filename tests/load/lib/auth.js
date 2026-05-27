// Auth0 ROPG (Resource Owner Password Grant) でアクセストークンを取得する。
//
// 用途: k6 の setup() からテスト開始前に 1 回だけ呼び、全 VU で同じトークンを共有する。
// これにより Auth0 への負荷を最小化し、API 本体の計測に集中できる。
//
// 複数ユーザーを使い分けたい場合はこの関数を VU 数ぶんループして配列で返し、
// シナリオ側で __VU を使って `tokens[(__VU - 1) % tokens.length]` のように分配する。

import http from 'k6/http';
import { check, fail } from 'k6';

export function getRopgToken() {
  const domain = __ENV.AUTH0_DOMAIN;
  const audience = __ENV.AUTH0_AUDIENCE;
  const clientId = __ENV.AUTH0_CLIENT_ID;
  const clientSecret = __ENV.AUTH0_CLIENT_SECRET;
  const username = __ENV.AUTH0_USERNAME;
  const password = __ENV.AUTH0_PASSWORD;
  const scope = __ENV.AUTH0_SCOPE || '';

  for (const [k, v] of Object.entries({
    AUTH0_DOMAIN: domain,
    AUTH0_AUDIENCE: audience,
    AUTH0_CLIENT_ID: clientId,
    AUTH0_CLIENT_SECRET: clientSecret,
    AUTH0_USERNAME: username,
    AUTH0_PASSWORD: password,
  })) {
    if (!v) fail(`${k} is required for ROPG auth. See tests/load/.env.example`);
  }

  const url = `https://${domain}/oauth/token`;
  const payload = {
    grant_type: 'password',
    username,
    password,
    audience,
    scope,
    client_id: clientId,
    client_secret: clientSecret,
  };

  const res = http.post(url, payload, {
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    tags: { name: 'auth0_token' },
  });

  const ok = check(res, {
    'auth0 token status 200': (r) => r.status === 200,
    'auth0 token has access_token': (r) => !!r.json('access_token'),
  });
  if (!ok) {
    fail(`Auth0 ROPG failed: status=${res.status} body=${res.body}`);
  }

  return res.json('access_token');
}
