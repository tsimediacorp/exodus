import { redirect } from 'next/navigation';
import { isSignedIn } from '@/lib/auth';
import { readAllSnapshots } from '@/lib/snapshots';
import { isConfigured } from '@/lib/fcm';
import { Shell } from '../shell';
import { DeviceBrowser } from './browser';

export const dynamic = 'force-dynamic';

export default async function ChatsPage() {
  if (!(await isSignedIn())) redirect('/login');
  const snapshots = await readAllSnapshots();

  return (
    <Shell>
      <h1>Chats &amp; memory</h1>
      <p className="lede">
        What each device has locally. Synced on launch and when a conversation
        ends.
      </p>

      <div className="note warn">
        <strong>Beta only.</strong> These are the couple&rsquo;s Counsel
        conversations and everything EXODUS remembers about them, which
        normally never leave the phone. Delete a device&rsquo;s copy when you
        are done with it, and take this whole panel down at launch.
        Confessions are never synced.
      </div>

      {snapshots.length === 0 ? (
        <p className="muted">
          Nothing yet. A device appears after it opens a build with sync in it.
        </p>
      ) : (
        <DeviceBrowser snapshots={snapshots} canPush={isConfigured()} />
      )}
    </Shell>
  );
}
