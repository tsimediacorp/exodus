'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import type { Snapshot, SyncedConversation } from '@/lib/snapshots';

export function DeviceBrowser({
  snapshots,
  canPush,
}: {
  snapshots: Snapshot[];
  canPush: boolean;
}) {
  const [openDevice, setOpenDevice] = useState<string | null>(
    snapshots[0]?.deviceId ?? null,
  );
  const snapshot = snapshots.find((s) => s.deviceId === openDevice);

  return (
    <>
      <div className="card">
        <h2>Devices</h2>
        <table>
          <thead>
            <tr><th>Device</th><th>User</th><th>Chats</th><th>Memory</th><th>Synced</th></tr>
          </thead>
          <tbody>
            {snapshots.map((s) => (
              <tr
                key={s.deviceId}
                onClick={() => setOpenDevice(s.deviceId)}
                style={{
                  cursor: 'pointer',
                  background: s.deviceId === openDevice ? 'rgba(201,169,97,0.07)' : undefined,
                }}
              >
                <td>{s.platform} <code>{s.deviceId}</code></td>
                <td className="muted">{s.userId || '—'}</td>
                <td>{s.conversations.length}</td>
                <td>{s.memory.length}</td>
                <td className="muted">{new Date(s.receivedAt).toLocaleString()}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {snapshot && <DeviceDetail key={snapshot.deviceId} snapshot={snapshot} canPush={canPush} />}
    </>
  );
}

function DeviceDetail({ snapshot, canPush }: { snapshot: Snapshot; canPush: boolean }) {
  const router = useRouter();
  const [openChat, setOpenChat] = useState<string | null>(null);
  const [memory, setMemory] = useState(snapshot.memory.map((m) => m.text).join('\n'));
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState('');

  async function queue(body: Record<string, unknown>, done: string) {
    setBusy(true);
    setStatus('');
    const response = await fetch('/api/admin/outbox', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ deviceId: snapshot.deviceId, ...body }),
    });
    const json = await response.json().catch(() => ({}));
    setBusy(false);
    setStatus(response.ok
      ? `${done}${json.pushed ? ' and pushed' : ' (applies next time the app opens)'}`
      : json.error ?? 'Failed.');
    router.refresh();
  }

  async function forget() {
    await fetch(`/api/admin/snapshots?deviceId=${encodeURIComponent(snapshot.deviceId)}`,
      { method: 'DELETE' });
    router.refresh();
  }

  const chat = snapshot.conversations.find((c) => c.id === openChat);

  return (
    <>
      {snapshot.truncated && (
        <div className="note">
          <strong>Partial.</strong> {snapshot.truncated}
        </div>
      )}

      <div className="card stack">
        <div className="row" style={{ justifyContent: 'space-between' }}>
          <h2>Memory</h2>
          <button className="danger" onClick={forget}>Delete this device&rsquo;s copy</button>
        </div>
        <p className="muted" style={{ margin: 0 }}>
          One fact per line. Saving replaces everything EXODUS remembers about
          this couple.
        </p>
        <textarea
          value={memory}
          onChange={(e) => setMemory(e.target.value)}
          style={{ minHeight: 160, fontFamily: 'ui-monospace, Menlo, monospace', fontSize: 13 }}
        />
        <div className="row">
          <button
            disabled={busy}
            onClick={() =>
              queue(
                {
                  type: 'memorySet',
                  items: memory.split('\n').map((l) => l.trim()).filter(Boolean),
                },
                'Memory queued',
              )
            }
          >
            Replace memory on device
          </button>
          {status && <span className="muted">{status}</span>}
        </div>
      </div>

      <div className="card">
        <h2>Conversations</h2>
        {snapshot.conversations.length === 0 ? (
          <p className="muted">None on this device.</p>
        ) : (
          <table>
            <thead><tr><th>Title</th><th>Messages</th><th>Updated</th></tr></thead>
            <tbody>
              {snapshot.conversations.map((c) => (
                <tr key={c.id} onClick={() => setOpenChat(c.id === openChat ? null : c.id)}
                  style={{ cursor: 'pointer' }}>
                  <td>{c.title || 'Untitled'}</td>
                  <td>{c.messages.length}</td>
                  <td className="muted">{new Date(c.updatedAt).toLocaleString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {chat && <Thread chat={chat} busy={busy} canPush={canPush} onSend={queue} />}
    </>
  );
}

function Thread({
  chat,
  busy,
  canPush,
  onSend,
}: {
  chat: SyncedConversation;
  busy: boolean;
  canPush: boolean;
  onSend: (body: Record<string, unknown>, done: string) => Promise<void>;
}) {
  const [text, setText] = useState('');
  const [notify, setNotify] = useState(true);

  return (
    <div className="card stack">
      <h2>{chat.title || 'Untitled'}</h2>
      <div style={{ maxHeight: 420, overflowY: 'auto' }}>
        {chat.messages.map((message, i) => (
          <div
            key={i}
            style={{
              borderLeft: `2px solid ${message.role === 'user' ? 'var(--steel)' : 'var(--brass)'}`,
              paddingLeft: 12,
              margin: '14px 0',
            }}
          >
            <div className="muted" style={{ fontSize: 11, letterSpacing: 1, textTransform: 'uppercase' }}>
              {message.role === 'user' ? 'Them' : 'EXODUS'}
              {' · '}
              {new Date(message.at).toLocaleString()}
            </div>
            <div style={{ whiteSpace: 'pre-wrap', marginTop: 4, fontSize: 14 }}>
              {message.content}
            </div>
          </div>
        ))}
      </div>

      <div className="field">
        <label htmlFor="say">Send as EXODUS into this thread</label>
        <textarea id="say" value={text} onChange={(e) => setText(e.target.value)} />
      </div>
      <div className="row">
        <label style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
          <input type="checkbox" checked={notify} disabled={!canPush}
            onChange={(e) => setNotify(e.target.checked)} />
          Push a notification too{!canPush && ' (needs FIREBASE_SERVICE_ACCOUNT)'}
        </label>
        <button
          disabled={busy || !text.trim()}
          onClick={() =>
            onSend(
              {
                type: 'message',
                conversationId: chat.id,
                text: text.trim(),
                notify: notify && canPush
                  ? { title: 'EXODUS', body: text.trim().slice(0, 120) }
                  : null,
              },
              'Message queued',
            )
          }
        >
          Send
        </button>
      </div>
    </div>
  );
}
