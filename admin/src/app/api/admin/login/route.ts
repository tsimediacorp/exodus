import { NextRequest, NextResponse } from 'next/server';
import { checkPassword, cookieMaxAge, cookieName, isConfigured, mintToken } from '@/lib/auth';

export async function POST(request: NextRequest) {
  if (!isConfigured()) {
    return NextResponse.json(
      { error: 'ADMIN_PASSWORD and ADMIN_SECRET are not set on this deployment.' },
      { status: 503 },
    );
  }
  const { password } = (await request.json().catch(() => ({}))) as { password?: string };
  if (!password || !checkPassword(password)) {
    // One deliberate second. This is a single shared password on a public URL;
    // without a delay it is worth guessing at.
    await new Promise((resolve) => setTimeout(resolve, 1000));
    return NextResponse.json({ error: 'Wrong password.' }, { status: 401 });
  }
  const response = NextResponse.json({ ok: true });
  response.cookies.set(cookieName, mintToken(), {
    httpOnly: true,
    sameSite: 'lax',
    secure: process.env.NODE_ENV === 'production',
    path: '/',
    maxAge: cookieMaxAge,
  });
  return response;
}
