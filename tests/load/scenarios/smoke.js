// 疎通確認 (smoke test): 認証不要の 2 エンドポイントを 1 VU で 30 秒間叩く。
//   - GET /health                 … API コンテナ単体のヘルス
//   - GET /api/guest/connect-test … CloudFront/WAF/ALB を経由した到達確認
// 本格的なシナリオを回す前にこれで env と URL を検証する。
//
// 実行: k6 run tests/load/scenarios/smoke.js

import http from 'k6/http';
import { check, sleep } from 'k6';
import { baseUrl } from '../lib/config.js';

export const options = {
  vus: 1,
  duration: '30s',
  thresholds: {
    http_req_failed: ['rate==0'],
    http_req_duration: ['p(95)<300'],
  },
};

export default function () {
  const healthRes = http.get(`${baseUrl}/health`, {
    tags: { name: 'GET /health' },
  });
  check(healthRes, {
    'health status 200': (r) => r.status === 200,
    'health body.status == ok': (r) => r.json('status') === 'ok',
  });

  const connectRes = http.get(`${baseUrl}/api/guest/connect-test`, {
    tags: { name: 'GET /api/guest/connect-test' },
  });
  check(connectRes, {
    'connect-test status 200': (r) => r.status === 200,
    'connect-test body has message': (r) => !!r.json('message'),
  });

  sleep(1);
}
