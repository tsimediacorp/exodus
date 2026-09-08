import { redirect } from 'next/navigation';
import { isSignedIn } from '@/lib/auth';
import { readDevices } from '@/lib/devices';
import { isConfigured } from '@/lib/fcm';
import { Shell } from '../shell';
import { PushForm } from './form';

export const dynamic = 'force-dynamic';

export default async function PushPage() {
  if (!(await isSignedIn())) redirect('/login');
  const devices = Object.values(await readDevices()).sort((a, b) =>
    b.lastSeen.localeCompare(a.lastSeen),
  );

  return (
    <Shell>
      <h1>Push</h1>
      <p className="lede">
        Send a notification to a device. Devices appear here once they have
        opened build 47 or later at least once.
      </p>

      {!isConfigured() && (
        <div className="note warn">
          <strong>Sending is not set up.</strong> In the Firebase console go to
          Project settings &rarr; Service accounts &rarr; Generate new private
          key, then paste the whole JSON file into a Vercel environment
          variable called <code>FIREBASE_SERVICE_ACCOUNT</code> and redeploy.
          That key can push to every EXODUS install, so it belongs only in
          Vercel&rsquo;s encrypted env, never in the repo.
        </div>
      )}

      <PushForm devices={devices} canSend={isConfigured()} />
    </Shell>
  );
}
