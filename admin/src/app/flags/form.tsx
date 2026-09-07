'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { KNOWN_FLAGS, type Flags } from '@/lib/config';

export function FlagsForm({ flags, ab }: { flags: Flags; ab: { salt: string; bPercent: number } }) {
  const router = useRouter();
  const [draftFlags, setDraftFlags] = useState<Flags>(flags);
  const [draftAb, setDraftAb] = useState(ab);
  const [busy, setBusy] = useState(false);
  const [saved, setSaved] = useState(false);

  async function save() {
    setBusy(true);
    setSaved(false);
    await fetch('/api/admin/flags', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ flags: draftFlags, ab: draftAb }),
    });
    setBusy(false);
    setSaved(true);
    router.refresh();
  }

  // Anything the app has ever been told about, even if it is not in the
  // known list - a flag added by hand should still be visible and editable.
  const keys = Array.from(new Set([...KNOWN_FLAGS.map((f) => f.key), ...Object.keys(draftFlags)]));

  return (
    <>
      <div className="card stack">
        <h2>Defaults</h2>
        {keys.map((key) => {
          const known = KNOWN_FLAGS.find((f) => f.key === key);
          const on = draftFlags[key] ?? false;
          return (
            <div key={key} style={{ borderTop: '1px solid var(--steel)', paddingTop: 14 }}>
              <div className="row" style={{ justifyContent: 'space-between' }}>
                <div>
                  <strong>{known?.label ?? key}</strong>{' '}
                  <code style={{ marginLeft: 6 }}>{key}</code>
                </div>
                <button
                  className={on ? '' : 'ghost'}
                  onClick={() => setDraftFlags((c) => ({ ...c, [key]: !on }))}
                >
                  {on ? 'On' : 'Off'}
                </button>
              </div>
              {known && <p className="muted" style={{ margin: '6px 0 0' }}>{known.blurb}</p>}
            </div>
          );
        })}
      </div>

      <div className="card stack">
        <h2>A/B split</h2>
        <p className="muted" style={{ margin: 0 }}>
          Assignment is a hash of the user id, so a tester keeps their group
          across relaunches and redeploys. An A/B result built on assignments
          that drift is not a result. Change the salt to deliberately reshuffle
          everyone.
        </p>
        <div className="row">
          <div className="field">
            <label htmlFor="bpct">Percent in group B</label>
            <input
              id="bpct"
              type="number"
              min={0}
              max={100}
              value={draftAb.bPercent}
              onChange={(e) => setDraftAb((c) => ({ ...c, bPercent: Number(e.target.value) }))}
            />
          </div>
          <div className="field">
            <label htmlFor="salt">Salt</label>
            <input
              id="salt"
              type="text"
              value={draftAb.salt}
              onChange={(e) => setDraftAb((c) => ({ ...c, salt: e.target.value }))}
            />
          </div>
        </div>
        <div className="note">
          Group B currently gets the same flags as A. To make a real experiment,
          pin specific testers to B under <strong>Testers</strong> and give them
          different flags there. Group is also sent to the app, so it can vary
          behaviour on its own.
        </div>
      </div>

      <div className="row">
        <button onClick={save} disabled={busy}>{busy ? 'Saving…' : 'Save'}</button>
        {saved && <span className="pill ok">Saved</span>}
      </div>
    </>
  );
}
