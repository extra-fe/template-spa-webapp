-- CreateTable
CREATE TABLE "races" (
    "id" SERIAL NOT NULL,
    "date" TIMESTAMP(3) NOT NULL,
    "name" TEXT NOT NULL,
    "venue" TEXT NOT NULL,

    CONSTRAINT "races_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "entries" (
    "id" SERIAL NOT NULL,
    "raceId" INTEGER NOT NULL,
    "frameNumber" INTEGER NOT NULL,
    "horseNumber" INTEGER NOT NULL,
    "horseName" TEXT NOT NULL,
    "sex" TEXT NOT NULL,
    "age" TEXT NOT NULL,
    "weight" DOUBLE PRECISION,
    "jockey" TEXT NOT NULL,
    "trainer" TEXT NOT NULL,
    "bodyWeight" TEXT,
    "oddsRank" INTEGER,
    "odds" DOUBLE PRECISION,
    "rank" INTEGER,
    "time" TEXT,
    "margin" TEXT,

    CONSTRAINT "entries_pkey" PRIMARY KEY ("id")
);

-- AddForeignKey
ALTER TABLE "entries" ADD CONSTRAINT "entries_raceId_fkey" FOREIGN KEY ("raceId") REFERENCES "races"("id") ON DELETE CASCADE ON UPDATE CASCADE;
