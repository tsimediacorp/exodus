'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { KNOWN_FLAGS, type Flags, type UserOverride } from '@/lib/config';

export function Testers({
  overrides,
  defaults,
}: {
  overrides: Record<string, UserOverride>;
  defaults: Flags;
}) {
  const router = useRouter();
  const [userId, setUserId] = useState('');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);

  async function post(body: unknown) {
    setBusy(true);
    await fetch('/api/admin/overrides', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    setBusy(false);
    router.refresh();
  }

  async function add(event: React.FormEvent) {
    event.preventDefault();
    if (!userId.trim()) return;
    await post({ userId: userId.trim(), override: { note: note.trim() } });
    setUserId('');
    setNote('');
  }

  const entries = Object.entries(overrides);

  return (
    <>
      <form className="card row" onSubmit={add}>
        <div className="field" style={{ flex: 1 }}>
          <label htmlFor="uid">User id</label>
          <input id="uid" type="text" value={userId} onChange={(e) => setUserId(e.target.value)} />
        </div>
        <div className="field" style={{ flex: 1 }}>
          <label htmlFor="note">Who is this</label>
          <input
            id="note"
            type="text"
            placeholder="Chris, Pixel 8"
            value={note}
            onChange={(e) => setNote(e.target.value)}
          />
        </div>
        <button type="submit" disabled={busy || !userId.trim()}>Add</button>
      </form>

      {entries.length === 0 ? (
        <p className="muted">No testers pinned yet. Everyone gets the defaults.</p>
      ) : (
        entries.map(([id, override]) => (
          <div className="card stack" key={id}>
            <div className="row" style={{ justifyContent: 'space-between' }}>
              <div>
                <strong>{override.note || 'Unnamed tester'}</strong>
                <div><code>{id}</code></div>
              </div>
              <button className="danger" disabled={busy}
                onClick={() => post({ userId: id, override: null })}>
                Remove
              </button>
            </div>

            <div className="row">
              <div className="field">
                <label>Group</label>
                <select
                  value={override.group ?? ''}
                  onChange={(e) =>
                    post({
                      userId: id,
                      override: { group: e.target.value === '' ? undefined : e.target.value },
                    })
                  }
                >
                  <option value="">By hash</option>
                  <option value="A">Pin to A</option>
                  <option value="B">Pin to B</option>
                </select>
              </div>
            </div>

            <div>
              <label>Flags for this tester only</label>
              {KNOWN_FLAGS.map((flag) => {
                const value = override.flags?.[flag.key];
                const effective = value ?? defaults[flag.key] ?? false;
                return (
                  <div className="row" key={flag.key}
                    style={{ justifyContent: 'space-between', marginTop: 10 }}>
                    <div>
                      <code>{flag.key}</code>{' '}
                      {value === undefined && <span className="muted">(default)</span>}
                    </div>
                    <div className="row">
                      <button
                        className={effective ? '' : 'ghost'}
                        disabled={busy}
                        onClick={() =>
                          post({
                            userId: id,
                            override: { flags: { ...override.flags, [flag.key]: !effective } },
                          })
                        }
                      >
                        {effective ? 'On' : 'Off'}
                      </button>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        ))
      )}
    </>
  );
}
