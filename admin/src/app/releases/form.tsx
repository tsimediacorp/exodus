'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import type { Platform, Release } from '@/lib/config';

export function ReleaseForm({ platform, release }: { platform: Platform; release: Release }) {
  const router = useRouter();
  const [draft, setDraft] = useState(release);
  const [busy, setBusy] = useState(false);
  const [saved, setSaved] = useState(false);

  async function save() {
    setBusy(true);
    setSaved(false);
    await fetch('/api/admin/releases', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ platform, release: draft }),
    });
    setBusy(false);
    setSaved(true);
    router.refresh();
  }

  const set = <K extends keyof Release>(key: K, value: Release[K]) =>
    setDraft((current) => ({ ...current, [key]: value }));

  return (
    <div className="card stack">
      <h2 style={{ textTransform: 'capitalize' }}>{platform}</h2>
      <div className="row">
        <div className="field">
          <label htmlFor={`${platform}-min`}>Minimum build (blocks below)</label>
          <input
            id={`${platform}-min`}
            type="number"
            min={0}
            value={draft.minBuild}
            onChange={(e) => set('minBuild', Number(e.target.value))}
          />
        </div>
        <div className="field">
          <label htmlFor={`${platform}-latest`}>Latest build (soft nudge)</label>
          <input
            id={`${platform}-latest`}
            type="number"
            min={0}
            value={draft.latestBuild}
            onChange={(e) => set('latestBuild', Number(e.target.value))}
          />
        </div>
      </div>
      <div className="field">
        <label htmlFor={`${platform}-url`}>Where to send them</label>
        <input
          id={`${platform}-url`}
          type="text"
          value={draft.updateUrl}
          placeholder={
            platform === 'android'
              ? 'https://appdistribution.firebase.google.com/…'
              : 'https://testflight.apple.com/join/…'
          }
          onChange={(e) => set('updateUrl', e.target.value)}
          style={{ width: '100%' }}
        />
      </div>
      <div className="field">
        <label htmlFor={`${platform}-msg`}>
          What the blocking screen says. Tell them what they gain, not that they
          are required to do something.
        </label>
        <textarea
          id={`${platform}-msg`}
          value={draft.message}
          onChange={(e) => set('message', e.target.value)}
        />
      </div>
      <div className="row">
        <button onClick={save} disabled={busy}>
          {busy ? 'Saving…' : 'Save'}
        </button>
        {saved && <span className="pill ok">Saved</span>}
        {draft.minBuild > 0 && !draft.updateUrl && (
          <span className="pill warn">No update link: they will be stuck</span>
        )}
      </div>
    </div>
  );
}
