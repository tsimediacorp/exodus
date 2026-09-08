import { redirect } from 'next/navigation';
import { isSignedIn } from '@/lib/auth';
import { readStories } from '@/lib/stories';
import { readConfig } from '@/lib/store';
import { Shell } from '../shell';
import { StoryEditor } from './editor';

export const dynamic = 'force-dynamic';

export default async function StoriesPage() {
  if (!(await isSignedIn())) redirect('/login');
  const stories = await readStories();
  const config = await readConfig();

  return (
    <Shell>
      <h1>Stories</h1>
      <p className="lede">
        Stories you write here go to every device, exactly as typed. They sit in
        the same feed as the ones EXODUS generates on the phone.
      </p>

      <div className="note">
        <strong>Edits and deletions take effect.</strong> Devices replace their
        whole curated set on each check-in, so changing a story here changes it
        everywhere, and deleting one removes it. Generated stories on the phone
        are left alone.
        {config.flags.communityCuratedOnly ? (
          <>
            {' '}Right now <code>communityCuratedOnly</code> is <strong>on</strong>,
            so devices show only what is on this page.
          </>
        ) : (
          <>
            {' '}Turn on <code>communityCuratedOnly</code> under Flags to make
            devices show only these, which is what you want for a demo.
          </>
        )}
      </div>

      <StoryEditor stories={stories} />
    </Shell>
  );
}
