import { AdminConfig, normalize } from './config';
import { kvGet, kvSet, isDurable } from './kv';

const KEY = 'exodus:admin:config';

export { isDurable };

/**
 * Config storage, over the shared key-value layer.
 *
 * Kept as its own module because everything else about the config - the
 * defaults, the normalising - belongs next to the reads and writes rather
 * than scattered through the routes.
 */
export async function readConfig(): Promise<AdminConfig> {
  return normalize(await kvGet<unknown>(KEY));
}

export async function writeConfig(config: AdminConfig): Promise<void> {
  await kvSet(KEY, { ...config, updatedAt: new Date().toISOString() });
}

/** Read, change, write. The panel's writes are small and infrequent. */
export async function updateConfig(
  change: (current: AdminConfig) => AdminConfig,
): Promise<AdminConfig> {
  const next = change(await readConfig());
  await writeConfig(next);
  return next;
}
