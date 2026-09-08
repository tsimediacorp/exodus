'use client';

import { usePathname, useRouter } from 'next/navigation';
import Link from 'next/link';

const NAV = [
  { href: '/', label: 'Overview' },
  { href: '/releases', label: 'Force update' },
  { href: '/push', label: 'Push' },
  { href: '/chats', label: 'Chats & memory' },
  { href: '/analytics', label: 'Analytics' },
  { href: '/flags', label: 'Flags & A/B' },
  { href: '/users', label: 'Testers' },
];

export function Shell({ children }: { children: React.ReactNode }) {
  const path = usePathname();
  const router = useRouter();

  async function signOut() {
    await fetch('/api/admin/logout', { method: 'POST' });
    router.replace('/login');
    router.refresh();
  }

  return (
    <div className="shell">
      <aside className="side">
        <div className="brand">EXODUS</div>
        <div className="brand-sub">ADMIN</div>
        <nav className="nav">
          {NAV.map((item) => (
            <Link key={item.href} href={item.href} className={path === item.href ? 'on' : ''}>
              {item.label}
            </Link>
          ))}
        </nav>
        <div style={{ marginTop: 28 }}>
          <button className="ghost" onClick={signOut} style={{ width: '100%' }}>
            Sign out
          </button>
        </div>
      </aside>
      <main className="main">{children}</main>
    </div>
  );
}
