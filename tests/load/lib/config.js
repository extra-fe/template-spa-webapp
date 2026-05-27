// 共通の k6 options。各シナリオで spread して使う。
// シナリオごとに stages / thresholds を上書き可能。

export const baseUrl = __ENV.BASE_URL;
if (!baseUrl) {
  throw new Error('BASE_URL is required. See tests/load/.env.example');
}

// 本番ガード: URL に "prod" を含む場合は ALLOW_PROD=true がなければ実行を拒否
if (/prod/i.test(baseUrl) && __ENV.ALLOW_PROD !== 'true') {
  throw new Error(
    `BASE_URL "${baseUrl}" は production と推測されます。意図的な場合は ALLOW_PROD=true を付けて再実行してください。`,
  );
}

// 既定のステージ: ramp-up → baseline → peak → ramp-down
export const defaultStages = [
  { duration: '30s', target: 10 },
  { duration: '2m', target: 10 },
  { duration: '30s', target: 50 },
  { duration: '3m', target: 50 },
  { duration: '30s', target: 0 },
];

// 既定のしきい値。失敗するとプロセスが exit 1 で終わるので CI 判定にも使える。
export const defaultThresholds = {
  http_req_failed: ['rate<0.01'],
  http_req_duration: ['p(95)<500'],
};

// 共通の HTTP リクエストオプション
export function authHeaders(token) {
  return {
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
  };
}
