import { promises as fs } from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const URL_ = process.env.KV_REST_API_URL ?? process.env.UPSTASH_REDIS_REST_URL ?? '';
const TOKEN = process.env.KV_REST_API_TOKEN ?? process.env.UPSTASH_REDIS_REST_TOKEN ?? '';

/** Whether anything written here actually survives. */
export const isDurable = Boolean(URL_ && TOKEN);

/**
 * The smallest key-value layer that serves every beta feature.
 *
 * Upstash over plain fetch rather than an SDK: it is two REST calls, and the
 * panel should need almost no maintenance. Without Redis it falls back to a
 * temp file so everything runs locally and on a fresh deploy with no
 * provisioning - that file does not survive on Vercel, which is why isDurable
 * is shown in the UI rather than left to be discovered.
 */
export async function kvGet<T>(key: string): Promise<T | null> {
  if (isDurable) {
    const raw = await command<string | null>(['GET', key]);
    return raw ? (safeParse(raw) as T) : null;
  }
  try {
    return JSON.parse(await fs.readFile(filePath(key), 'utf8')) as T;
  } catch {
    return null;
  }
}

export async function kvSet(key: string, value: unknown): Promise<void> {
  const body = JSON.stringify(value);
  if (isDurable) {
    await command(['SET', key, body]);
    return;
  }
  await fs.writeFile(filePath(key), body, 'utf8');
}

function filePath(key: string): string {
  return path.join(os.tmpdir(), `${key.replace(/[^a-z0-9]/gi, '_')}.json`);
}

function safeParse(raw: string): unknown {
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

async function command<T = unknown>(parts: string[]): Promise<T> {
  const response = await fetch(URL_, {
    method: 'POST',
    headers: { Authorization: `Bearer ${TOKEN}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(parts),
    cache: 'no-store',
  });
  if (!response.ok) throw new Error(`Redis ${parts[0]} failed: ${response.status}`);
  const json = (await response.json()) as { result: T };
  return json.result;
}
