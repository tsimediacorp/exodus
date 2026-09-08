import { NextRequest, NextResponse } from 'next/server';
import { isSignedIn } from '@/lib/auth';
import { removeDevice } from '@/lib/devices';

/**
 * Drop a device from the registry.
 *
 * FCM only reports a token as dead when the app was properly uninstalled. A
 * token that is merely wrong comes back as INVALID_ARGUMENT and stays in the
 * list forever, looking like a tester who never receives anything - so this
 * has to be removable by hand.
 */
export async function DELETE(request: NextRequest) {
  if (!(await isSignedIn())) {
    return NextResponse.json({ error: 'Not signed in.' }, { status: 401 });
  }
  const deviceId = request.nextUrl.searchParams.get('deviceId')?.trim();
  if (!deviceId) {
    return NextResponse.json({ error: 'deviceId is required.' }, { status: 400 });
  }
  await removeDevice(deviceId);
  return NextResponse.json({ ok: true });
}
