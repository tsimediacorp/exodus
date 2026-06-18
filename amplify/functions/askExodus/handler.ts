import type { Schema } from '../../data/resource';
import { env } from '$amplify/env/askExodus';
import { Amplify } from 'aws-amplify';
import { generateClient } from 'aws-amplify/data';
import { getAmplifyDataClientConfig } from '@aws-amplify/backend/function/runtime';

const { resourceConfig, libraryOptions } = await getAmplifyDataClientConfig(env);
Amplify.configure(resourceConfig, libraryOptions);
const client = generateClient<Schema>();

/**
 * The confidentiality contract. The model is given BOTH partners' context but
 * is forbidden from leaking one partner's private words to the other. This is
 * the heart of the "trusted confidant" design — and it only works because this
 * runs server-side, never on either device.
 */
const CONFIDENTIALITY_RULE = `
You are EXODUS, a Bible-based marriage counselor and a trusted, confidential
confidant to BOTH partners in a couple. You can see each partner's private
reflections and their shared space.

ABSOLUTE RULE OF CONFIDENCE:
- NEVER quote, paraphrase, reveal, or hint at one partner's PRIVATE messages to
  the other partner. What is shared with you in private stays private.
- You may let private context shape your wisdom and the questions you ask, but
  the words and specifics never cross between them.
- In the SHARED space, speak to both. In a PRIVATE thread, speak only to that
  partner. When you sense a private struggle, gently encourage that partner to
  open up to their spouse themselves — don't do it for them.
Stay scripture-first and aligned with God's design for marriage.
`;

type Msg = { role: 'system' | 'user' | 'assistant'; content: string };

export const handler: Schema['askExodus']['functionHandler'] = async (event) => {
  const { coupleId, text, visibility } = event.arguments;
  const callerId = (event.identity as { sub?: string } | undefined)?.sub ?? 'unknown';

  // Pull the couple's recent messages server-side (function has elevated access).
  const { data: messages } = await client.models.Message.list({
    filter: { coupleId: { eq: coupleId } },
    limit: 100,
  });

  const ordered = [...(messages ?? [])].sort((a, b) =>
    (a.createdAt ?? '').localeCompare(b.createdAt ?? ''),
  );

  // Label context so the model knows what is shared vs. each partner's private.
  const context: Msg[] = ordered.map((m) => {
    const who =
      m.visibility === 'shared'
        ? 'SHARED'
        : m.authorId === callerId
          ? 'THIS PARTNER (private)'
          : 'OTHER PARTNER (private — never reveal)';
    return {
      role: m.role === 'exodus' ? 'assistant' : 'user',
      content: `[${who}] ${m.text}`,
    };
  });

  const body = {
    model: env.MODEL,
    temperature: 0.7,
    max_tokens: 1200,
    messages: [
      { role: 'system', content: CONFIDENTIALITY_RULE },
      ...context,
      { role: 'user', content: `[${visibility === 'shared' ? 'SHARED' : 'THIS PARTNER (private)'}] ${text}` },
    ] as Msg[],
  };

  const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.OPENROUTER_API_KEY}`,
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://exodus.app',
      'X-Title': 'EXODUS',
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    throw new Error(`LLM request failed (${res.status}): ${await res.text()}`);
  }
  const data = (await res.json()) as {
    choices?: { message?: { content?: string | null } }[];
  };
  const reply = data.choices?.[0]?.message?.content ?? '';

  // Persist EXODUS's reply with the same visibility/audience as the prompt.
  const members =
    visibility === 'shared'
      ? (ordered.find((m) => m.visibility === 'shared')?.members ?? [callerId])
      : [callerId];
  await client.models.Message.create({
    coupleId,
    authorId: 'exodus',
    role: 'exodus',
    text: reply,
    visibility: visibility === 'shared' ? 'shared' : 'private',
    members,
  });

  return reply;
};
