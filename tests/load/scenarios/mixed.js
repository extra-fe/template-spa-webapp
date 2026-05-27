// 混在ワークロード: 読み取り 70% / 書き込み 30% の実運用に近いシナリオ。
// メインの負荷テスト用。CI で動かす場合もこれを基準にする。
//
// 実行: k6 run tests/load/scenarios/mixed.js

import http from 'k6/http';
import { check, sleep } from 'k6';
import {
  baseUrl,
  defaultStages,
  defaultThresholds,
  authHeaders,
} from '../lib/config.js';
import { getRopgToken } from '../lib/auth.js';
import { buildRacePayload } from '../lib/data.js';

export const options = {
  stages: defaultStages,
  thresholds: {
    ...defaultThresholds,
    'http_req_duration{name:GET /api/races}': ['p(95)<500'],
    'http_req_duration{name:GET /api/races/:id}': ['p(95)<500'],
    'http_req_duration{name:POST /api/races}': ['p(95)<1000'],
  },
};

export function setup() {
  return { token: getRopgToken() };
}

export default function (data) {
  const params = authHeaders(data.token);
  const roll = Math.random();

  if (roll < 0.5) {
    // 50% — 一覧取得
    const res = http.get(`${baseUrl}/api/races`, {
      ...params,
      tags: { name: 'GET /api/races' },
    });
    check(res, { 'list 200': (r) => r.status === 200 });
  } else if (roll < 0.7) {
    // 20% — 詳細取得 (id=1 を叩く。シードデータがあれば 200)
    const res = http.get(`${baseUrl}/api/races/1`, {
      ...params,
      tags: { name: 'GET /api/races/:id' },
    });
    check(res, {
      'detail 200 or 404': (r) => r.status === 200 || r.status === 404,
    });
  } else {
    // 30% — 書き込み
    const payload = JSON.stringify(buildRacePayload(__VU, __ITER));
    const res = http.post(`${baseUrl}/api/races`, payload, {
      ...params,
      tags: { name: 'POST /api/races' },
    });
    check(res, {
      'write 201 or 200': (r) => r.status === 201 || r.status === 200,
    });
  }

  sleep(1);
}
