import { promises as fs } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { AdminConfig, normalize } from './config';

const KEY = 'exodus:admin:config';

const KV_URL = process.env.KV_REST_API_URL ?? process.env.UPSTASH_REDIS_REST_URL ?? '';
const KV_TOKEN =
  process.env.KV_REST_API_TOKEN ?? process.env.UPSTASH_REDIS_REST_TOKEN ?? '';

/** Whether settings will actually survive. The UI says so plainly when not. */
export const isDurable = Boolean(KV_URL && KV_TOKEN);

/**
 * Config storage.
 *
 * Upstash over plain fetch rather than an SDK: it is two REST calls, and a
 * dependency here would be one more thing to keep current on a panel that
 * should need almost no maintenance.
 *
 * With no Redis configured it falls back to a temp file so the panel runs
 * locally and on a fresh deploy without any provisioning. That file does NOT
 * survive on Vercel - every serverless invocation may get a different
 * container - which is why isDurable is surfaced in the UI instead of being
 * left for someone to discover when a setting silently reverts.
 */
export async function readConfig(): Promise<AdminConfig> {
  if (isDurable) {
    const raw = await kv<string | null>(['GET', KEY]);
    return normalize(raw ? safeParse(raw) : {});
  }
  try {
    return normalize(JSON.parse(await fs.readFile(filePath(), 'utf8')));
  } catch {
    return normalize({});
  }
}

export async function writeConfig(config: AdminConfig): Promise<void> {
  const stamped: AdminConfig = { ...config, updatedAt: new Date().toISOString() };
  const body = JSON.stringify(stamped);
  if (isDurable) {
    await kv(['SET', KEY, body]);
    return;
  }
  await fs.writeFile(filePath(), body, 'utf8');
}

/** Read, change, write. The panel's writes are small and infrequent. */
export async function updateConfig(
  change: (current: AdminConfig) => AdminConfig,
): Promise<AdminConfig> {
  const next = change(await readConfig());
  await writeConfig(next);
  return next;
}

function filePath(): string {
  return path.join(os.tmpdir(), 'exodus-admin-config.json');
}

function safeParse(raw: string): unknown {
  try {
    return JSON.parse(raw);
  } catch {
    return {};
  }
}

async function kv<T = unknown>(command: string[]): Promise<T> {
  const response = await fetch(KV_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${KV_TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(command),
    cache: 'no-store',
  });
  if (!response.ok) {
    throw new Error(`Redis ${command[0]} failed: ${response.status}`);
  }
  const json = (await response.json()) as { result: T };
  return json.result;
}
