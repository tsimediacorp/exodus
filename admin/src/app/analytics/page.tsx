import { redirect } from 'next/navigation';
import { isSignedIn } from '@/lib/auth';
import { readConfig } from '@/lib/store';
import { combine, EVENT_LABELS, perDevice, readRecent } from '@/lib/stats';
import { Shell } from '../shell';

export const dynamic = 'force-dynamic';

export default async function AnalyticsPage() {
  if (!(await isSignedIn())) redirect('/login');
  const days = await readRecent(14);
  const totals = combine(days);
  const config = await readConfig();

  const names = Array.from(
    new Set([...Object.keys(EVENT_LABELS), ...Object.keys(totals.totals)]),
  );
  const aCount = totals.devicesByGroup.A.length;
  const bCount = totals.devicesByGroup.B.length;

  return (
    <Shell>
      <h1>Analytics</h1>
      <p className="lede">
        Counts only, from the last 14 days. No message text, no verse, no name
        ever reaches this page.
      </p>

      {days.length === 0 ? (
        <p className="muted">
          Nothing reported yet. Devices send counts when the app opens.
        </p>
      ) : (
        <>
          <div className="card">
            <h2>A/B</h2>
            <p className="muted" style={{ marginTop: 4 }}>
              Per active device, because comparing raw totals when the groups
              are different sizes says more about the split than about the
              feature. {config.ab.bPercent}% of testers are assigned to B.
            </p>
            {bCount === 0 && (
              <div className="note" style={{ marginTop: 12 }}>
                <strong>No group B yet.</strong> Everyone is in A, so there is
                nothing to compare. Set a percentage under Flags &amp; A/B, or
                pin a tester to B under Testers.
              </div>
            )}
            <table style={{ marginTop: 14 }}>
              <thead>
                <tr>
                  <th>Event</th>
                  <th>A ({aCount} device{aCount === 1 ? '' : 's'})</th>
                  <th>B ({bCount} device{bCount === 1 ? '' : 's'})</th>
                  <th>Difference</th>
                </tr>
              </thead>
              <tbody>
                {names.map((name) => {
                  const a = totals.byGroup.A[name] ?? 0;
                  const b = totals.byGroup.B[name] ?? 0;
                  const aAvg = aCount ? a / aCount : 0;
                  const bAvg = bCount ? b / bCount : 0;
                  const comparable = aCount > 0 && bCount > 0;
                  const delta = comparable && aAvg > 0
                    ? Math.round(((bAvg - aAvg) / aAvg) * 100)
                    : null;
                  return (
                    <tr key={name}>
                      <td>{EVENT_LABELS[name] ?? name}</td>
                      <td>{perDevice(a, aCount)} <span className="muted">({a})</span></td>
                      <td>{perDevice(b, bCount)} <span className="muted">({b})</span></td>
                      <td>
                        {delta === null ? (
                          <span className="muted">—</span>
                        ) : (
                          <span className={delta === 0 ? 'muted' : ''}>
                            {delta > 0 ? '+' : ''}{delta}%
                          </span>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
            <div className="note" style={{ marginTop: 16 }}>
              With a handful of testers these differences are noise, not
              findings. A dozen devices per group over a couple of weeks is
              where a number starts meaning something.
            </div>
          </div>

          <div className="card">
            <h2>By day</h2>
            <table>
              <thead>
                <tr>
                  <th>Day</th><th>Active devices</th>
                  <th>Opens</th><th>Counsel messages</th>
                </tr>
              </thead>
              <tbody>
                {days.map((day) => (
                  <tr key={day.day}>
                    <td>{day.day}</td>
                    <td>{day.devices.length}</td>
                    <td>{day.totals.app_open ?? 0}</td>
                    <td>{day.totals.counsel_message ?? 0}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}

      <div className="card">
        <h2>What is not measured</h2>
        <p className="muted" style={{ marginTop: 4 }}>
          The confessional is not instrumented at all, not even a count. Even
          knowing how often it is used is metadata about a feature the app
          promises is private, and no product question here is worth that.
        </p>
      </div>
    </Shell>
  );
}
