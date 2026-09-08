/**
 * The shapes and the arithmetic, with nothing that touches storage.
 *
 * Split from stats.ts so the folding rules can be tested directly: an average
 * that silently compares two differently-sized groups is the kind of bug that
 * produces a confident wrong decision rather than an error.
 */

/** Every event name the app sends. Mirrors Events in analytics.dart. */
export const EVENT_LABELS: Record<string, string> = {
  app_open: 'App opened',
  counsel_message: 'Counsel messages sent',
  devotional_open: 'Devotional opened',
  study_open: 'Bible study opened',
  coaching_start: 'Coaching started',
  community_thread_open: 'Community thread opened',
  verse_open: 'Daily verse opened',
  memory_open: 'Memory opened',
  memory_edit: 'Memory edited',
};

export interface DayStats {
  day: string;
  /** Total per event, across everyone. */
  totals: Record<string, number>;
  /** The same, split by A/B group, which is the point of collecting any of it. */
  byGroup: { A: Record<string, number>; B: Record<string, number> };
  /** Devices that reported anything, so "active" means something. */
  devices: string[];
  devicesByGroup: { A: string[]; B: string[] };
}

/**
 * Per-device average, which is the only honest way to compare two groups that
 * are not the same size. Comparing raw totals when B has three testers and A
 * has nine says more about the split than about the feature.
 */
export function perDevice(count: number, devices: number): string {
  if (devices === 0) return '—';
  return (count / devices).toFixed(1);
}

/** Sum a set of days into one view. */
export function combine(days: DayStats[]): Omit<DayStats, 'day'> {
  const out = {
    totals: {} as Record<string, number>,
    byGroup: { A: {} as Record<string, number>, B: {} as Record<string, number> },
    devices: [] as string[],
    devicesByGroup: { A: [] as string[], B: [] as string[] },
  };
  for (const day of days) {
    for (const [event, n] of Object.entries(day.totals)) {
      out.totals[event] = (out.totals[event] ?? 0) + n;
    }
    for (const group of ['A', 'B'] as const) {
      for (const [event, n] of Object.entries(day.byGroup[group] ?? {})) {
        out.byGroup[group][event] = (out.byGroup[group][event] ?? 0) + n;
      }
      for (const id of day.devicesByGroup?.[group] ?? []) {
        if (!out.devicesByGroup[group].includes(id)) out.devicesByGroup[group].push(id);
      }
    }
    for (const id of day.devices) {
      if (!out.devices.includes(id)) out.devices.push(id);
    }
  }
  return out;
}

