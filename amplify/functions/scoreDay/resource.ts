import { defineFunction, secret } from '@aws-amplify/backend';

/**
 * Computes the couple's daily "alignment" score from both partners' quiz
 * answers and writes a DailyAlignment record. Server-side so the scoring
 * prompt + API key stay off the clients.
 */
export const scoreDay = defineFunction({
  name: 'scoreDay',
  entry: './handler.ts',
  timeoutSeconds: 45,
  environment: {
    OPENROUTER_API_KEY: secret('OPENROUTER_API_KEY'),
    MODEL: 'z-ai/glm-4.6v',
  },
});
