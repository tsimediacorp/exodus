import { NextRequest, NextResponse } from 'next/server';
import { acknowledge, readOutbox } from '@/lib/outbox';

export const dynamic = 'force-dynamic';

/** What is waiting for this device. Used after a push wakes the app. */
export async function GET(request: NextRequest) {
  const deviceId = request.nextUrl.searchParams.get('deviceId')?.trim();
  if (!deviceId) {
    return NextResponse.json({ error: 'deviceId is required.' }, { status: 400 });
  }
  return NextResponse.json({ commands: await readOutbox(deviceId) });
}

/** The device reporting what it applied. */
export async function POST(request: NextRequest) {
  const body = (await request.json().catch(() => ({}))) as {
    deviceId?: string;
    applied?: string[];
  };
  const deviceId = body.deviceId?.trim();
  if (!deviceId) {
    return NextResponse.json({ error: 'deviceId is required.' }, { status: 400 });
  }
  await acknowledge(deviceId, body.applied ?? []);
  return NextResponse.json({ ok: true });
}
