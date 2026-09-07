import { NextRequest, NextResponse } from 'next/server';
import { isSignedIn } from '@/lib/auth';
import { updateConfig } from '@/lib/store';
import type { UserOverride } from '@/lib/config';

export async function POST(request: NextRequest) {
  if (!(await isSignedIn())) {
    return NextResponse.json({ error: 'Not signed in.' }, { status: 401 });
  }
  const body = (await request.json().catch(() => ({}))) as {
    userId?: string;
    override?: UserOverride | null;
  };
  const userId = (body.userId ?? '').trim();
  if (!userId) {
    return NextResponse.json({ error: 'A user id is required.' }, { status: 400 });
  }

  const config = await updateConfig((current) => {
    const overrides = { ...current.overrides };
    if (body.override === null) {
      delete overrides[userId];
    } else {
      overrides[userId] = { ...overrides[userId], ...(body.override ?? {}) };
    }
    return { ...current, overrides };
  });
  return NextResponse.json({ ok: true, config });
}
