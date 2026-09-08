import { NextRequest, NextResponse } from 'next/server';
import { isSignedIn } from '@/lib/auth';
import { readDevices, removeDevice } from '@/lib/devices';
import { isConfigured, sendTo } from '@/lib/fcm';

export const maxDuration = 30;

export async function POST(request: NextRequest) {
  if (!(await isSignedIn())) {
    return NextResponse.json({ error: 'Not signed in.' }, { status: 401 });
  }
  if (!isConfigured()) {
    return NextResponse.json(
      {
        error:
          'FIREBASE_SERVICE_ACCOUNT is not set. Firebase console -> Project '
          + 'settings -> Service accounts -> Generate new private key, then '
          + 'paste the whole JSON into that Vercel environment variable.',
      },
      { status: 503 },
    );
  }

  const body = (await request.json().catch(() => ({}))) as {
    title?: string;
    message?: string;
    payload?: string;
    deviceIds?: string[];
  };
  const title = (body.title ?? '').trim();
  const message = (body.message ?? '').trim();
  if (!title || !message) {
    return NextResponse.json({ error: 'A title and a message are required.' }, { status: 400 });
  }

  const devices = await readDevices();
  const targets = Object.values(devices).filter(
    (device) => !body.deviceIds?.length || body.deviceIds.includes(device.deviceId),
  );
  if (targets.length === 0) {
    return NextResponse.json({ error: 'No devices selected.' }, { status: 400 });
  }

  const results = await sendTo(targets.map((d) => d.token), {
    title,
    body: message,
    payload: body.payload?.trim() || undefined,
  });

  // A token FCM calls dead will never work again, and leaving it in the list
  // makes a real tester look like one who never receives anything.
  const byToken = new Map(targets.map((d) => [d.token, d]));
  for (const result of results) {
    if (result.gone) {
      const device = byToken.get(result.token);
      if (device) await removeDevice(device.deviceId);
    }
  }

  const sent = results.filter((r) => r.ok).length;
  return NextResponse.json({
    ok: true,
    sent,
    failed: results.length - sent,
    errors: results.filter((r) => !r.ok).map((r) => r.error).slice(0, 5),
  });
}
