import { NextRequest, NextResponse } from 'next/server';
import { isSignedIn } from '@/lib/auth';
import { forgetSnapshot } from '@/lib/snapshots';

/** Delete one device's synced chats and memory from the panel. */
export async function DELETE(request: NextRequest) {
  if (!(await isSignedIn())) {
    return NextResponse.json({ error: 'Not signed in.' }, { status: 401 });
  }
  const deviceId = request.nextUrl.searchParams.get('deviceId')?.trim();
  if (!deviceId) {
    return NextResponse.json({ error: 'deviceId is required.' }, { status: 400 });
  }
  await forgetSnapshot(deviceId);
  return NextResponse.json({ ok: true });
}
