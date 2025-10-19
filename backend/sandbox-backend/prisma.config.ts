// prisma.config.ts
import { defineConfig } from "prisma/config";
import "dotenv/config"; 

export default defineConfig({
  schema: "prisma/schema.prisma",
  migrations: {
    seed: "ts-node prisma/seed.ts",
  },
});
