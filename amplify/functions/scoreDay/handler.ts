import type { Schema } from '../../data/resource';
import { env } from '$amplify/env/scoreDay';
import { Amplify } from 'aws-amplify';
import { generateClient } from 'aws-amplify/data';
import { getAmplifyDataClientConfig } from '@aws-amplify/backend/function/runtime';

const { resourceConfig, libraryOptions } = await getAmplifyDataClientConfig(env);
Amplify.configure(resourceConfig, libraryOptions);
const client = generateClient<Schema>();

/**
 * Returns JSON: {"score": 0-100, "recap": "..."} once both partners have
 * answered the day's question. Returns "" if fewer than two answers exist yet.
 */
export const handler: Schema['scoreDay']['functionHandler'] = async (event) => {
  const { coupleId, roundId, day, prompt } = event.arguments;

  const { data: answers } = await client.models.QuizAnswer.list({
    filter: { roundId: { eq: roundId } },
    limit: 10,
  });
  // One answer per author.
  const byAuthor = new Map<string, string>();
  for (const a of answers ?? []) {
    if (a.authorId && a.answer) byAuthor.set(a.authorId, a.answer);
  }
  if (byAuthor.size < 2) return '';

  const [a1, a2] = [...byAuthor.values()];
  const sys = `You are EXODUS, a warm Christian marriage coach scoring how aligned a couple is on a daily question. Be encouraging and honest. Return ONLY JSON: {"score": <integer 0-100>, "recap": "<2-3 warm sentences on where they align and one thing to talk about>"}.`;
  const user = `Question: "${prompt}"\nPartner A answered: "${a1}"\nPartner B answered: "${a2}"\nScore their alignment 0-100 and give the recap.`;

  const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.OPENROUTER_API_KEY}`,
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://exodus.app',
      'X-Title': 'EXODUS',
    },
    body: JSON.stringify({
      model: env.MODEL,
      temperature: 0.5,
      max_tokens: 1500,
      messages: [
        { role: 'system', content: sys },
        { role: 'user', content: user },
      ],
    }),
  });
  if (!res.ok) throw new Error(`scoreDay LLM failed (${res.status})`);
  const data = (await res.json()) as {
    choices?: { message?: { content?: string | null } }[];
  };
  const raw = data.choices?.[0]?.message?.content ?? '';
  let score = 50;
  let recap = '';
  const s = raw.indexOf('{');
  const e = raw.lastIndexOf('}');
  if (s >= 0 && e > s) {
    try {
      const j = JSON.parse(raw.slice(s, e + 1));
      score = Math.max(0, Math.min(100, Number(j.score) || 50));
      recap = String(j.recap ?? '');
    } catch {
      /* keep defaults */
    }
  }

  const { data: couple } = await client.models.Couple.get({ id: coupleId });
  const members = couple?.members?.filter((m): m is string => !!m) ?? [];

  // Upsert today's alignment (id = roundId keeps one per couple/day).
  const existing = await client.models.DailyAlignment.get({ id: roundId });
  if (existing.data) {
    await client.models.DailyAlignment.update({ id: roundId, score, recap });
  } else {
    await client.models.DailyAlignment.create({
      id: roundId,
      coupleId,
      day,
      score,
      recap,
      members,
    });
  }

  return JSON.stringify({ score, recap });
};
