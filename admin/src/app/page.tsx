import { redirect } from 'next/navigation';
import { isConfigured, isSignedIn } from '@/lib/auth';
import { isDurable, readConfig } from '@/lib/store';
import { Shell } from './shell';

export const dynamic = 'force-dynamic';

export default async function OverviewPage() {
  if (!isConfigured()) {
    return (
      <div className="login">
        <div className="brand">EXODUS</div>
        <div className="brand-sub">ADMIN</div>
        <div className="note warn">
          <strong>Not configured.</strong> Set <code>ADMIN_PASSWORD</code> and{' '}
          <code>ADMIN_SECRET</code> in the Vercel project&rsquo;s environment
          variables, then redeploy.
        </div>
      </div>
    );
  }
  if (!(await isSignedIn())) redirect('/login');

  const config = await readConfig();
  const testers = Object.keys(config.overrides).length;

  return (
    <Shell>
      <h1>Overview</h1>
      <p className="lede">
        What the app asks this panel on every launch, and what it is being told.
      </p>

      {!isDurable && (
        <div className="note warn">
          <strong>Settings will not stick.</strong> No Redis is connected, so
          config lives in a temp file that Vercel throws away between
          invocations. Add the Upstash integration in the Vercel dashboard
          (Storage &rarr; Upstash Redis) and redeploy; it sets{' '}
          <code>KV_REST_API_URL</code> and <code>KV_REST_API_TOKEN</code> for
          you. Until then treat everything here as scratch.
        </div>
      )}

      <div className="card">
        <h2>Force update</h2>
        <p className="muted" style={{ marginTop: 4 }}>
          Builds below the minimum are blocked at launch.
        </p>
        <table>
          <thead>
            <tr><th>Platform</th><th>Minimum</th><th>Latest</th><th>State</th></tr>
          </thead>
          <tbody>
            {(['android', 'ios'] as const).map((platform) => {
              const release = config.releases[platform];
              return (
                <tr key={platform}>
                  <td style={{ textTransform: 'capitalize' }}>{platform}</td>
                  <td><code>{release.minBuild || '—'}</code></td>
                  <td><code>{release.latestBuild || '—'}</code></td>
                  <td>
                    {release.minBuild > 0
                      ? <span className="pill warn">Gate on</span>
                      : <span className="pill off">No gate</span>}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <div className="card">
        <h2>Flags</h2>
        <table>
          <thead><tr><th>Flag</th><th>Default</th></tr></thead>
          <tbody>
            {Object.entries(config.flags).map(([key, on]) => (
              <tr key={key}>
                <td><code>{key}</code></td>
                <td>{on ? <span className="pill ok">On</span> : <span className="pill off">Off</span>}</td>
              </tr>
            ))}
          </tbody>
        </table>
        <p className="muted" style={{ marginTop: 14 }}>
          A/B split: <strong>{config.ab.bPercent}%</strong> of testers in group B
          {' '}(salt <code>{config.ab.salt}</code>). {testers} tester
          {testers === 1 ? '' : 's'} pinned or overridden.
        </p>
      </div>

      <div className="card">
        <h2>The endpoint the app calls</h2>
        <p className="muted" style={{ marginTop: 4 }}>
          Public and unauthenticated, because a build old enough to be blocked
          may be old enough to have a broken sign-in.
        </p>
        <p style={{ marginTop: 10 }}>
          <code>GET /api/v1/config?platform=android&amp;build=45&amp;userId=…</code>
        </p>
        <p className="muted">
          Last written {new Date(config.updatedAt).getTime() === 0
            ? 'never' : new Date(config.updatedAt).toLocaleString()}.
        </p>
      </div>
    </Shell>
  );
}
