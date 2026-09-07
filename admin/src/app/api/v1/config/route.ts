import { NextRequest, NextResponse } from 'next/server';
import { readConfig } from '@/lib/store';
import { groupFor } from '@/lib/ab';
import { evaluate } from '@/lib/version';
import type { Platform } from '@/lib/config';

export const dynamic = 'force-dynamic';

/**
 * What the app asks for on launch.
 *
 * Public and unauthenticated on purpose: it must answer before the user has
 * signed in, because a build old enough to be blocked may be old enough to
 * have a broken sign-in. Nothing here is sensitive - it is version numbers and
 * feature switches - and the user id is only ever used to pick a bucket.
 *
 * GET /api/v1/config?platform=android&build=45&userId=<cognito sub>
 */
export async function GET(request: NextRequest) {
  const params = request.nextUrl.searchParams;
  const platform: Platform = params.get('platform') === 'ios' ? 'ios' : 'android';
  const build = Number(params.get('build') ?? 0);
  const userId = params.get('userId') ?? '';

  const config = await readConfig();
  const release = config.releases[platform];
  const override = userId ? config.overrides[userId] : undefined;

  const gate = evaluate(build, release.minBuild, release.latestBuild);
  const group = override?.group ?? groupFor(userId, config.ab.salt, config.ab.bPercent);

  return NextResponse.json(
    {
      ...gate,
      minBuild: release.minBuild,
      latestBuild: release.latestBuild,
      updateUrl: release.updateUrl,
      message: release.message,
      group,
      flags: { ...config.flags, ...(override?.flags ?? {}) },
      serverTime: new Date().toISOString(),
    },
    {
      headers: {
        // Short cache: a force-update needs to reach devices in minutes, but
        // this endpoint should not be hit on every rebuild of a screen.
        'Cache-Control': 'public, max-age=0, s-maxage=60, stale-while-revalidate=300',
      },
    },
  );
}
