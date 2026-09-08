import { NextRequest, NextResponse } from 'next/server';
import { record } from '@/lib/stats';

export const dynamic = 'force-dynamic';

/**
 * Counts from a device.
 *
 * Names and numbers only. There is no field here for content, and that is
 * deliberate: anything needing the text of a message is on the Chats page,
 * which is a separate and visible thing rather than something that arrives
 * quietly with the metrics.
 */
export async function POST(request: NextRequest) {
  const body = (await request.json().catch(() => null)) as {
    deviceId?: string;
    group?: string;
    counts?: Record<string, number>;
  } | null;

  if (!body?.counts || typeof body.counts !== 'object') {
    return NextResponse.json({ error: 'counts is required.' }, { status: 400 });
  }

  await record({
    deviceId: (body.deviceId ?? '').trim(),
    group: body.group === 'B' ? 'B' : 'A',
    counts: body.counts,
  });
  return NextResponse.json({ ok: true });
}
