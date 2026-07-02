import { defineFunction, secret } from '@aws-amplify/backend';

/**
 * Server-side counseling. Runs the cross-partner context assembly and the LLM
 * call so that:
 *   - one partner's PRIVATE messages never reach the other partner's device, and
 *   - the OpenRouter API key never ships in the client.
 *
 * Exposed as the `askExodus` custom mutation (see data/resource.ts).
 */
export const askExodus = defineFunction({
  name: 'askExodus',
  entry: './handler.ts',
  timeoutSeconds: 60,
  environment: {
    OPENROUTER_API_KEY: secret('OPENROUTER_API_KEY'),
    MODEL: 'z-ai/glm-4.6v',
  },
});
