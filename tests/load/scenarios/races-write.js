// 書き込み負荷シナリオ: POST /api/races を繰り返す。
// race.name に "LOADTEST-<runId>-<VU>-<iter>" を入れ、テスト後にプレフィックスで一括削除できるようにする。
//
// 書き込みは読み取りより負荷が高く DB に痕跡が残るので、stages は read より控えめに設定。
//
// 実行: k6 run tests/load/scenarios/races-write.js

import http from 'k6/http';
import { check, sleep } from 'k6';
import {
  baseUrl,
  defaultThresholds,
  authHeaders,
} from '../lib/config.js';
import { getRopgToken } from '../lib/auth.js';
import { buildRacePayload } from '../lib/data.js';

export const options = {
  stages: [
    { duration: '30s', target: 5 },
    { duration: '2m', target: 5 },
    { duration: '30s', target: 20 },
    { duration: '2m', target: 20 },
    { duration: '30s', target: 0 },
  ],
  thresholds: {
    ...defaultThresholds,
    // 書き込みは少し緩めに
    http_req_duration: ['p(95)<1000'],
  },
};

export function setup() {
  return { token: getRopgToken() };
}

export default function (data) {
  const params = authHeaders(data.token);
  const payload = JSON.stringify(buildRacePayload(__VU, __ITER));

  const res = http.post(`${baseUrl}/api/races`, payload, {
    ...params,
    tags: { name: 'POST /api/races' },
  });
  check(res, {
    'status 201 or 200': (r) => r.status === 201 || r.status === 200,
    'response has id': (r) => !!r.json('id'),
  });

  sleep(1);
}
