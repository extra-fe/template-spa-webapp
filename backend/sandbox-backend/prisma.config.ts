import { defineConfig, env } from "prisma/config";

// 開発環境でのみ.envを読み込む
if (process.env.NODE_ENV !== "production") {
  const { config } = require("dotenv");
  config();
}

export default defineConfig({
  schema: "prisma/schema.prisma",
  migrations: {
    path: "prisma/migrations",
  },
  engine: "classic",
  datasource: {
    url: env("DATABASE_URL"),
  },
});
