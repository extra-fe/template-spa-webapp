import { PrismaClient } from '../generated/prisma'

const prisma = new PrismaClient();

async function main() {
  const race = await prisma.race.create({
    data: {
      date: new Date('1994-06-05'),
      name: '第44回安田記念',
      venue: '東京',
      entries: {
        create: [
          {
            frameNumber: 3,
            horseNumber: 5,
            horseName: 'ノースフライト',
            sex: '牝',
            age: '5',
            weight: 55.0,
            jockey: '角田晃一',
            trainer: '加藤敬二',
            bodyWeight: '470',
            oddsRank: 5,
            odds: 7.0,
            rank: 1,
            time: '1:33.2',
            margin: '',
          },
          {
            frameNumber: 1,
            horseNumber: 2,
            horseName: 'トーワダーリン',
            sex: '牝',
            age: '5',
            weight: 55.0,
            jockey: '田中勝春',
            trainer: '佐山優',
            bodyWeight: '424',
            oddsRank: 10,
            odds: 68.2,
            rank: 2,
            time: '1:33.6',
            margin: '2 1/2',
          },
          {
            frameNumber: 2,
            horseNumber: 4,
            horseName: 'ドルフィンストリート',
            sex: '牡',
            age: '5',
            weight: 57.0,
            jockey: 'サンマルタン',
            trainer: 'ハモンド',
            bodyWeight: '504',
            oddsRank: 4,
            odds: 7.0,
            rank: 3,
            time: '1:33.7',
            margin: '3/4',
          },
          {
            frameNumber: 6,
            horseNumber: 12,
            horseName: 'サクラバクシンオー',
            sex: '牡',
            age: '6',
            weight: 57.0,
            jockey: '小島太',
            trainer: '境勝太郎',
            bodyWeight: '498',
            oddsRank: 3,
            odds: 6.9,
            rank: 4,
            time: '1:33.7',
            margin: 'ハナ',
          },
          {
            frameNumber: 7,
            horseNumber: 13,
            horseName: 'スキーパラダイス',
            sex: '牝',
            age: '5',
            weight: 55.0,
            jockey: '武豊',
            trainer: 'ファーブル',
            bodyWeight: '448',
            oddsRank: 1,
            odds: 2.6,
            rank: 5,
            time: '1:33.7',
            margin: 'ハナ',
          },
        ],
      },
    },
  });

  console.log(`🌱 Seeded race: ${race.name}`);
}

main()
  .catch((e) => {
    console.error('❌ Error seeding:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
