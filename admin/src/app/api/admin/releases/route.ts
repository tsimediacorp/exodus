import { NextRequest, NextResponse } from 'next/server';
import { isSignedIn } from '@/lib/auth';
import { updateConfig } from '@/lib/store';
import type { Platform, Release } from '@/lib/config';

export async function POST(request: NextRequest) {
  if (!(await isSignedIn())) {
    return NextResponse.json({ error: 'Not signed in.' }, { status: 401 });
  }
  const body = (await request.json().catch(() => ({}))) as {
    platform?: Platform;
    release?: Partial<Release>;
  };
  const platform: Platform = body.platform === 'ios' ? 'ios' : 'android';
  const patch = body.release ?? {};

  const config = await updateConfig((current) => ({
    ...current,
    releases: {
      ...current.releases,
      [platform]: {
        ...current.releases[platform],
        ...patch,
        minBuild: Math.max(0, Math.floor(Number(patch.minBuild ?? current.releases[platform].minBuild)) || 0),
        latestBuild: Math.max(0, Math.floor(Number(patch.latestBuild ?? current.releases[platform].latestBuild)) || 0),
      },
    },
  }));
  return NextResponse.json({ ok: true, config });
}
