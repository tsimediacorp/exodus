'use client';

import { useState } from 'react';
import type { Device } from '@/lib/devices';

export function PushForm({ devices, canSend }: { devices: Device[]; canSend: boolean }) {
  const [title, setTitle] = useState('');
  const [message, setMessage] = useState('');
  const [payload, setPayload] = useState('');
  const [selected, setSelected] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<string>('');

  async function send() {
    setBusy(true);
    setResult('');
    const response = await fetch('/api/admin/push', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title, message, payload, deviceIds: selected }),
    });
    const body = await response.json().catch(() => ({}));
    setBusy(false);
    setResult(
      response.ok
        ? `Sent to ${body.sent} device${body.sent === 1 ? '' : 's'}` +
            (body.failed ? `, ${body.failed} failed: ${(body.errors ?? []).join('; ')}` : '.')
        : body.error ?? 'Send failed.',
    );
  }

  const toggle = (id: string) =>
    setSelected((current) =>
      current.includes(id) ? current.filter((x) => x !== id) : [...current, id],
    );

  return (
    <>
      <div className="card stack">
        <div className="field">
          <label htmlFor="t">Title</label>
          <input id="t" type="text" value={title} maxLength={60}
            onChange={(e) => setTitle(e.target.value)} style={{ width: '100%' }} />
        </div>
        <div className="field">
          <label htmlFor="m">Message</label>
          <textarea id="m" value={message} maxLength={240}
            onChange={(e) => setMessage(e.target.value)} />
        </div>
        <div className="field">
          <label htmlFor="p">
            Where a tap lands. Blank opens the app. <code>devotional</code>,{' '}
            <code>checkin:&lt;id&gt;</code>, or <code>chat:&lt;conversationId&gt;</code>.
          </label>
          <input id="p" type="text" value={payload} placeholder="devotional"
            onChange={(e) => setPayload(e.target.value)} style={{ width: '100%' }} />
        </div>
        <div className="row">
          <button onClick={send} disabled={busy || !canSend || !title || !message}>
            {busy ? 'Sending…' : selected.length
              ? `Send to ${selected.length} selected`
              : `Send to all ${devices.length}`}
          </button>
          {result && <span className="muted">{result}</span>}
        </div>
      </div>

      <div className="card">
        <h2>Devices</h2>
        {devices.length === 0 ? (
          <p className="muted">
            None registered yet. A device appears after it opens a build that
            has push wired in.
          </p>
        ) : (
          <table>
            <thead>
              <tr><th></th><th>Device</th><th>User</th><th>Build</th><th>Last seen</th></tr>
            </thead>
            <tbody>
              {devices.map((device) => (
                <tr key={device.deviceId}>
                  <td>
                    <input type="checkbox" checked={selected.includes(device.deviceId)}
                      onChange={() => toggle(device.deviceId)} />
                  </td>
                  <td>
                    {device.platform}
                    <div className="muted"><code>{device.deviceId}</code></div>
                  </td>
                  <td className="muted">{device.userId || '—'}</td>
                  <td><code>{device.build || '—'}</code></td>
                  <td className="muted">{new Date(device.lastSeen).toLocaleString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
        <p className="muted" style={{ marginTop: 12 }}>
          Nothing selected sends to everyone.
        </p>
      </div>
    </>
  );
}
