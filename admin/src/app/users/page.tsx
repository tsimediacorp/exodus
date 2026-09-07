import { redirect } from 'next/navigation';
import { isSignedIn } from '@/lib/auth';
import { readConfig } from '@/lib/store';
import { Shell } from '../shell';
import { Testers } from './testers';

export const dynamic = 'force-dynamic';

export default async function UsersPage() {
  if (!(await isSignedIn())) redirect('/login');
  const config = await readConfig();
  return (
    <Shell>
      <h1>Testers</h1>
      <p className="lede">
        Per-tester overrides, keyed by the user id the app reports.
      </p>
      <div className="note">
        <strong>Where to find a user id.</strong> The app shows it under
        Settings, and it is the Cognito <code>sub</code> in the AWS console
        (Cognito &rarr; User pools &rarr; Users). Anyone not listed here gets
        the defaults and a hashed group.
      </div>
      <Testers overrides={config.overrides} defaults={config.flags} />
    </Shell>
  );
}
