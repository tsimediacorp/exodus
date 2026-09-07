import { NextRequest, NextResponse } from 'next/server';
import { isSignedIn } from '@/lib/auth';
import { updateConfig } from '@/lib/store';

export async function POST(request: NextRequest) {
  if (!(await isSignedIn())) {
    return NextResponse.json({ error: 'Not signed in.' }, { status: 401 });
  }
  const body = (await request.json().catch(() => ({}))) as {
    flags?: Record<string, boolean>;
    ab?: { salt?: string; bPercent?: number };
  };

  const config = await updateConfig((current) => ({
    ...current,
    flags: { ...current.flags, ...(body.flags ?? {}) },
    ab: {
      salt: body.ab?.salt ?? current.ab.salt,
      bPercent:
        body.ab?.bPercent === undefined
          ? current.ab.bPercent
          : Math.min(100, Math.max(0, Math.round(Number(body.ab.bPercent) || 0))),
    },
  }));
  return NextResponse.json({ ok: true, config });
}
