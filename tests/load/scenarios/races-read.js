// 読み取り負荷シナリオ: GET /api/races と GET /api/races/:id を交互に叩く。
//
// 流れ:
//   1. setup() で Auth0 ROPG トークンを 1 回取得 (全 VU 共有)
//   2. 各 iteration で /api/races を取得 → ランダムに 1 件選んで /api/races/:id
//   3. 一覧が空ならフォールバックで id=1 を叩く
//
// 実行: k6 run tests/load/scenarios/races-read.js

import http from 'k6/http';
import { check, sleep } from 'k6';
import {
  baseUrl,
  defaultStages,
  defaultThresholds,
  authHeaders,
} from '../lib/config.js';
import { getRopgToken } from '../lib/auth.js';

export const options = {
  stages: defaultStages,
  thresholds: defaultThresholds,
};

export function setup() {
  return { token: getRopgToken() };
}

export default function (data) {
  const params = authHeaders(data.token);

  const listRes = http.get(`${baseUrl}/api/races`, {
    ...params,
    tags: { name: 'GET /api/races' },
  });
  check(listRes, {
    'list status 200': (r) => r.status === 200,
    'list is array': (r) => Array.isArray(r.json()),
  });

  const races = listRes.status === 200 ? listRes.json() : [];
  const id =
    races.length > 0 ? races[Math.floor(Math.random() * races.length)].id : 1;

  const detailRes = http.get(`${baseUrl}/api/races/${id}`, {
    ...params,
    tags: { name: 'GET /api/races/:id' },
  });
  check(detailRes, {
    'detail status 200 or 404': (r) => r.status === 200 || r.status === 404,
  });

  sleep(1);
}
