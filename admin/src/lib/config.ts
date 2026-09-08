/** The shape of everything the panel controls, and its defaults. */

export type Platform = 'android' | 'ios';

export interface Release {
  /** Builds below this cannot be used at all until the user updates. */
  minBuild: number;
  /** The newest build out there. Drives a soft "update available" nudge. */
  latestBuild: number;
  updateUrl: string;
  /** Shown on the blocking screen. Say what they gain, not "update required". */
  message: string;
}

export type Flags = Record<string, boolean>;

export interface UserOverride {
  /** Pin a tester to a group instead of letting the hash decide. */
  group?: 'A' | 'B';
  /** Flags for this tester only. Merged over the defaults. */
  flags?: Flags;
  /** Who this is, so the list is readable a week later. */
  note?: string;
}

export interface AdminConfig {
  releases: Record<Platform, Release>;
  /** Defaults for everyone. */
  flags: Flags;
  ab: {
    /** Change this to reshuffle every assignment. */
    salt: string;
    /** Percentage landing in group B. 0 = everyone in A. */
    bPercent: number;
  };
  /** Keyed by the app's user id (Cognito sub). */
  overrides: Record<string, UserOverride>;
  updatedAt: string;
}

/**
 * Flags the app actually reads. Listed here so the panel can render real
 * toggles rather than asking whoever is using it to remember the key names.
 *
 * These exist for the closed beta and come out at launch, which is why each
 * one says what it gates rather than being a bare key.
 */
export const KNOWN_FLAGS: { key: string; label: string; blurb: string }[] = [
  {
    key: 'memoryEditing',
    label: 'Memory editing',
    blurb:
      'Lets the user see and edit what EXODUS remembers about them. The A/B '
      + 'question is whether editing it makes counsel feel more trustworthy '
      + 'or just more fiddly.',
  },
  {
    key: 'community',
    label: 'Community feed',
    blurb: 'The stories above the daily verse on the home screen.',
  },
  {
    key: 'communityCuratedOnly',
    label: 'Only show curated stories',
    blurb:
      'Devices show only what is on the Stories page and stop generating '
      + 'their own. What you want for a demo, where the feed has to be '
      + 'exactly what you expect.',
  },
  {
    key: 'coaching',
    label: 'Live coaching',
    blurb: 'Spoken sessions over WebRTC. Expensive per minute; worth gating.',
  },
];

export const DEFAULT_CONFIG: AdminConfig = {
  releases: {
    android: {
      minBuild: 0,
      latestBuild: 0,
      updateUrl: '',
      message: 'A new build is ready with fixes you asked for.',
    },
    ios: {
      minBuild: 0,
      latestBuild: 0,
      updateUrl: '',
      message: 'A new build is ready with fixes you asked for.',
    },
  },
  flags: {
    memoryEditing: true,
    community: true,
    coaching: true,
    communityCuratedOnly: false,
  },
  ab: { salt: 'exodus', bPercent: 0 },
  overrides: {},
  updatedAt: new Date(0).toISOString(),
};

/**
 * Merge a stored blob over the defaults.
 *
 * Deliberately forgiving: a config written by an older version of the panel,
 * or hand-edited in Redis, must still boot. A panel that 500s because one key
 * is missing is a panel that cannot be used to fix anything.
 */
export function normalize(raw: unknown): AdminConfig {
  const input = (raw ?? {}) as Partial<AdminConfig>;
  const release = (p: Platform): Release => ({
    ...DEFAULT_CONFIG.releases[p],
    ...(input.releases?.[p] ?? {}),
    minBuild: Number(input.releases?.[p]?.minBuild ?? 0) || 0,
    latestBuild: Number(input.releases?.[p]?.latestBuild ?? 0) || 0,
  });
  return {
    releases: { android: release('android'), ios: release('ios') },
    flags: { ...DEFAULT_CONFIG.flags, ...(input.flags ?? {}) },
    ab: {
      salt: input.ab?.salt ?? DEFAULT_CONFIG.ab.salt,
      bPercent: clampPercent(input.ab?.bPercent),
    },
    overrides: input.overrides ?? {},
    updatedAt: input.updatedAt ?? DEFAULT_CONFIG.updatedAt,
  };
}

function clampPercent(value: unknown): number {
  const n = Number(value);
  if (!Number.isFinite(n)) return 0;
  return Math.min(100, Math.max(0, Math.round(n)));
}
