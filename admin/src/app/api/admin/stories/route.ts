import { NextRequest, NextResponse } from 'next/server';
import { isSignedIn } from '@/lib/auth';
import { deleteStory, upsertStory, type Story } from '@/lib/stories';

export async function POST(request: NextRequest) {
  if (!(await isSignedIn())) {
    return NextResponse.json({ error: 'Not signed in.' }, { status: 401 });
  }
  const body = (await request.json().catch(() => ({}))) as Partial<Story>;
  if (!(body.title ?? '').trim() || !(body.body ?? '').trim()) {
    return NextResponse.json(
      { error: 'A title and a story are required.' },
      { status: 400 },
    );
  }
  return NextResponse.json({ ok: true, story: await upsertStory(body) });
}

export async function DELETE(request: NextRequest) {
  if (!(await isSignedIn())) {
    return NextResponse.json({ error: 'Not signed in.' }, { status: 401 });
  }
  const id = request.nextUrl.searchParams.get('id')?.trim();
  if (!id) return NextResponse.json({ error: 'id is required.' }, { status: 400 });
  await deleteStory(id);
  return NextResponse.json({ ok: true });
}
