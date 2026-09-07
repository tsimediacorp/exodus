import { redirect } from 'next/navigation';
import { isSignedIn } from '@/lib/auth';
import { readConfig } from '@/lib/store';
import { Shell } from '../shell';
import { FlagsForm } from './form';

export const dynamic = 'force-dynamic';

export default async function FlagsPage() {
  if (!(await isSignedIn())) redirect('/login');
  const config = await readConfig();
  return (
    <Shell>
      <h1>Flags &amp; A/B</h1>
      <p className="lede">
        Defaults for everyone, and how testers are split. Per-tester overrides
        live under Testers.
      </p>
      <FlagsForm flags={config.flags} ab={config.ab} />
    </Shell>
  );
}
