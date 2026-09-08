import { NextRequest, NextResponse } from 'next/server';
import { upsertDevice } from '@/lib/devices';

export const dynamic = 'force-dynamic';

/**
 * A device telling the panel where to reach it.
 *
 * Unauthenticated, like the config endpoint. The worst a stranger can do is
 * add a row that receives EXODUS beta notifications, and requiring a secret
 * here would mean shipping one inside the APK, where anyone can read it -
 * a lock with the key taped to it, at the cost of pretending otherwise.
 * It comes out at launch with the rest of the beta scaffolding.
 */
export async function POST(request: NextRequest) {
  const body = (await request.json().catch(() => null)) as {
    token?: string;
    deviceId?: string;
    userId?: string;
    platform?: string;
    build?: number;
  } | null;

  const token = body?.token?.trim();
  const deviceId = body?.deviceId?.trim();
  if (!token || !deviceId) {
    return NextResponse.json({ error: 'token and deviceId are required.' }, { status: 400 });
  }

  await upsertDevice({
    token,
    deviceId,
    userId: body?.userId?.trim() ?? '',
    platform: body?.platform === 'ios' ? 'ios' : 'android',
    build: Number(body?.build ?? 0) || 0,
  });
  return NextResponse.json({ ok: true });
}
