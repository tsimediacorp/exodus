import { NextResponse } from 'next/server';
import { publishedForDevices } from '@/lib/stories';

export const dynamic = 'force-dynamic';

/**
 * The curated stories, for the app's community feed.
 *
 * Public like the rest of the v1 surface. These are written to be read by
 * every tester, so there is nothing here to protect.
 */
export async function GET() {
  return NextResponse.json(
    { stories: await publishedForDevices() },
    {
      headers: {
        'Cache-Control': 'public, max-age=0, s-maxage=60, stale-while-revalidate=300',
      },
    },
  );
}
