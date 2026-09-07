import { redirect } from 'next/navigation';
import { isSignedIn } from '@/lib/auth';
import { readConfig } from '@/lib/store';
import { Shell } from '../shell';
import { ReleaseForm } from './form';

export const dynamic = 'force-dynamic';

export default async function ReleasesPage() {
  if (!(await isSignedIn())) redirect('/login');
  const config = await readConfig();

  return (
    <Shell>
      <h1>Force update</h1>
      <p className="lede">
        Anything below the minimum build is stopped at launch and cannot be used
        until it updates.
      </p>

      <div className="note">
        <strong>Build numbers, not versions.</strong> The app ships{' '}
        <code>0.1.0+45</code>; the gate compares the <code>45</code>. It is the
        only part that reliably goes up, and comparing it is an integer test
        rather than a parsing exercise. A build of <code>0</code> means no gate.
      </div>

      <ReleaseForm platform="android" release={config.releases.android} />
      <ReleaseForm platform="ios" release={config.releases.ios} />
    </Shell>
  );
}
