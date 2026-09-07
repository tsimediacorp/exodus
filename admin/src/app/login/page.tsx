'use client';

import { useRouter } from 'next/navigation';
import { useState } from 'react';

export default function LoginPage() {
  const router = useRouter();
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError('');
    const response = await fetch('/api/admin/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ password }),
    });
    setBusy(false);
    if (response.ok) {
      router.replace('/');
      router.refresh();
      return;
    }
    const body = await response.json().catch(() => ({}));
    setError(body.error ?? 'Could not sign in.');
  }

  return (
    <div className="login">
      <div className="brand">EXODUS</div>
      <div className="brand-sub">ADMIN</div>
      <form className="card stack" onSubmit={submit}>
        <div className="field">
          <label htmlFor="pw">Password</label>
          <input
            id="pw"
            type="password"
            value={password}
            autoFocus
            onChange={(e) => setPassword(e.target.value)}
          />
        </div>
        {error && <div className="note warn"><strong>{error}</strong></div>}
        <button type="submit" disabled={busy || !password}>
          {busy ? 'Checking…' : 'Sign in'}
        </button>
      </form>
    </div>
  );
}
