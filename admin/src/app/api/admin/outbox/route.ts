import { NextRequest, NextResponse } from 'next/server';
import { isSignedIn } from '@/lib/auth';
import { queueCommand } from '@/lib/outbox';
import { readDevices } from '@/lib/devices';
import { isConfigured, sendTo } from '@/lib/fcm';
import { NotificationPayloads } from '@/lib/payloads';

export const maxDuration = 30;

/**
 * Queue a command for a device, and optionally wake it.
 *
 * The push is what makes a message from EXODUS feel like a message rather than
 * something the couple finds later: the app drains the outbox when it opens,
 * and the notification is what gets it opened.
 */
export async function POST(request: NextRequest) {
  if (!(await isSignedIn())) {
    return NextResponse.json({ error: 'Not signed in.' }, { status: 401 });
  }
  const body = (await request.json().catch(() => ({}))) as {
    deviceId?: string;
    type?: 'message' | 'memorySet';
    conversationId?: string;
    text?: string;
    items?: string[];
    notify?: { title: string; body: string } | null;
  };

  const deviceId = body.deviceId?.trim();
  if (!deviceId) {
    return NextResponse.json({ error: 'deviceId is required.' }, { status: 400 });
  }

  if (body.type === 'memorySet') {
    await queueCommand(deviceId, { type: 'memorySet', items: body.items ?? [] });
  } else {
    const text = (body.text ?? '').trim();
    const conversationId = (body.conversationId ?? '').trim();
    if (!text || !conversationId) {
      return NextResponse.json(
        { error: 'A conversation and some text are required.' },
        { status: 400 },
      );
    }
    await queueCommand(deviceId, { type: 'message', conversationId, text });
  }

  let pushed = 0;
  if (body.notify && isConfigured()) {
    const device = (await readDevices())[deviceId];
    if (device) {
      const results = await sendTo([device.token], {
        title: body.notify.title,
        body: body.notify.body,
        payload:
          body.type === 'memorySet'
            ? undefined
            : `${NotificationPayloads.chat}${(body.conversationId ?? '').trim()}`,
      });
      pushed = results.filter((r) => r.ok).length;
    }
  }

  return NextResponse.json({ ok: true, pushed });
}
