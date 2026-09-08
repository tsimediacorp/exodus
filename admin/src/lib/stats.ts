import { kvGet, kvSet } from './kv';
import type { DayStats } from './stats-shape';

export * from './stats-shape';

const INDEX = 'exodus:admin:stats:days';
const key = (day: string) => `exodus:admin:stats:${day}`;

export function today(): string {
  return new Date().toISOString().slice(0, 10);
}

export async function readDays(): Promise<string[]> {
  return (await kvGet<string[]>(INDEX)) ?? [];
}

export async function readDay(day: string): Promise<DayStats> {
  return (
    (await kvGet<DayStats>(key(day))) ?? {
      day,
      totals: {},
      byGroup: { A: {}, B: {} },
      devices: [],
      devicesByGroup: { A: [], B: [] },
    }
  );
}

/** The last [count] days, newest first. */
export async function readRecent(count = 14): Promise<DayStats[]> {
  const days = (await readDays()).sort().reverse().slice(0, count);
  return Promise.all(days.map(readDay));
}

/**
 * Fold one device's counts into today's rollup.
 *
 * Rollups rather than an event log. A raw stream would be more flexible, but
 * it grows without bound in a store that charges by size, and every question a
 * closed beta actually asks - how many, how often, A versus B - is answerable
 * from counters.
 */
export async function record(input: {
  deviceId: string;
  group: 'A' | 'B';
  counts: Record<string, number>;
}): Promise<void> {
  const day = today();
  const stats = await readDay(day);
  const group = input.group === 'B' ? 'B' : 'A';

  for (const [event, count] of Object.entries(input.counts)) {
    const n = Number(count);
    if (!Number.isFinite(n) || n <= 0) continue;
    // Unknown names are still counted. A build newer than the panel should
    // not have its numbers silently dropped.
    stats.totals[event] = (stats.totals[event] ?? 0) + n;
    stats.byGroup[group][event] = (stats.byGroup[group][event] ?? 0) + n;
  }

  if (input.deviceId && !stats.devices.includes(input.deviceId)) {
    stats.devices.push(input.deviceId);
  }
  if (input.deviceId && !stats.devicesByGroup[group].includes(input.deviceId)) {
    stats.devicesByGroup[group].push(input.deviceId);
  }

  await kvSet(key(day), stats);
  const days = await readDays();
  if (!days.includes(day)) await kvSet(INDEX, [...days, day]);
}
