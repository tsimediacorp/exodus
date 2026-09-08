import { NextRequest, NextResponse } from 'next/server';
import { writeSnapshot, type Snapshot } from '@/lib/snapshots';
import { readOutbox } from '@/lib/outbox';

export const dynamic = 'force-dynamic';
export const maxDuration = 30;

/**
 * A device handing over its local state, and collecting anything waiting.
 *
 * BETA SCAFFOLDING, AND THE MOST SENSITIVE THING HERE. Counsel conversations
 * and memory are a couple's most private material and normally never leave the
 * phone. They are here so the beta can be debugged, they are keyed to a device
 * rather than a person, and the whole store disappears when this panel does.
 *
 * Confessions are deliberately NOT synced. That tab was built and described to
 * users as never leaving the device; its debugging value is low and the cost
 * of breaking that promise is the feature itself.
 *
 * The response carries the outbox so a check-in is one round trip rather than
 * two - the app is doing this on launch, on a connection that may be poor.
 */
export async function POST(request: NextRequest) {
  const body = (await request.json().catch(() => null)) as Partial<Snapshot> | null;
  const deviceId = body?.deviceId?.trim();
  if (!deviceId) {
    return NextResponse.json({ error: 'deviceId is required.' }, { status: 400 });
  }

  await writeSnapshot({
    deviceId,
    userId: body?.userId?.trim() ?? '',
    build: Number(body?.build ?? 0) || 0,
    platform: body?.platform === 'ios' ? 'ios' : 'android',
    receivedAt: new Date().toISOString(),
    memory: Array.isArray(body?.memory) ? body!.memory! : [],
    conversations: Array.isArray(body?.conversations) ? body!.conversations! : [],
    truncated: body?.truncated,
  });

  return NextResponse.json({ ok: true, commands: await readOutbox(deviceId) });
}
