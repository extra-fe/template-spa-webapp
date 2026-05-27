// POST /api/races 用のテストデータ生成。
//
// race.name は "LOADTEST-<実行ID>-<VU>-<iter>" 形式で、テスト後に
//   DELETE FROM "Race" WHERE name LIKE 'LOADTEST-%';
// で一括削除できるようにする。

// 実行ごとにユニークな ID (テスト終了後に「この run のレコードだけ消す」もできる)
export const runId = __ENV.RUN_ID || `${Date.now()}`;

export function buildRacePayload(vu, iter) {
  return {
    date: new Date().toISOString(),
    name: `LOADTEST-${runId}-${vu}-${iter}`,
    venue: '京都',
    entries: [
      buildEntry(1, 1, 'ホクトベガ'),
      buildEntry(2, 2, 'サクラチヨノオー'),
      buildEntry(3, 3, 'メジロマックイーン'),
    ],
  };
}

function buildEntry(frameNumber, horseNumber, horseName) {
  return {
    frameNumber,
    horseNumber,
    horseName,
    sex: '牡',
    age: '4',
    weight: 55.0,
    jockey: '加藤和宏',
    trainer: '中野隆良',
  };
}
