import { buildApp } from './app.js';
import { loadBotPolicy } from './training/load-policy.js';
import { openAIClient } from './language-model.js';

const app = buildApp({
  logger: true,
  ...(process.env.OPENAI_API_KEY
    ? {
        languageModel: openAIClient(
          process.env.OPENAI_API_KEY,
          process.env.BOT_LLM_MODEL,
        ),
      }
    : {}),
  ...(process.env.BOT_POLICY_FILE
    ? {
        botPolicy: loadBotPolicy(
          process.env.BOT_POLICY_FILE,
          process.env.BOT_POLICY_USE_LEARNER === '1',
        ),
      }
    : {}),
  ...(process.env.DATABASE_URL
    ? { databaseUrl: process.env.DATABASE_URL }
    : {}),
  ...(process.env.BOT_MATCH_DIR === ':memory:'
    ? {}
    : { saveDirectory: process.env.BOT_MATCH_DIR ?? 'data/matches' }),
});
const port = Number(process.env.PORT ?? 4000);
if (!Number.isInteger(port) || port < 1 || port > 65535)
  throw new Error('PORT must be between 1 and 65535.');

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.once(signal, () => {
    void app.close();
  });
}

try {
  await app.listen({ port, host: process.env.HOST ?? '127.0.0.1' });
} catch (error) {
  app.log.error(error);
  await app.close();
  process.exitCode = 1;
}
