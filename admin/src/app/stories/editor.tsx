'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import type { Story, StoryReply } from '@/lib/stories';

const BLANK: Partial<Story> = {
  author: '',
  authorContext: '',
  tag: 'Marriage',
  title: '',
  body: '',
  replies: [],
  published: true,
};

export function StoryEditor({ stories }: { stories: Story[] }) {
  const router = useRouter();
  const [draft, setDraft] = useState<Partial<Story> | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  async function save() {
    if (!draft) return;
    setBusy(true);
    setError('');
    const response = await fetch('/api/admin/stories', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(draft),
    });
    setBusy(false);
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      setError(body.error ?? 'Could not save.');
      return;
    }
    setDraft(null);
    router.refresh();
  }

  async function remove(id: string) {
    setBusy(true);
    await fetch(`/api/admin/stories?id=${encodeURIComponent(id)}`, { method: 'DELETE' });
    setBusy(false);
    router.refresh();
  }

  const set = <K extends keyof Story>(key: K, value: Story[K]) =>
    setDraft((current) => ({ ...(current ?? BLANK), [key]: value }));

  const replies: StoryReply[] = draft?.replies ?? [];

  return (
    <>
      {draft === null ? (
        <div className="row" style={{ marginBottom: 16 }}>
          <button onClick={() => setDraft({ ...BLANK })}>Write a story</button>
        </div>
      ) : (
        <div className="card stack">
          <h2>{draft.id ? 'Edit story' : 'New story'}</h2>

          <div className="row">
            <div className="field" style={{ flex: 2 }}>
              <label htmlFor="author">Name</label>
              <input id="author" type="text" placeholder="Marcus T."
                value={draft.author ?? ''} onChange={(e) => set('author', e.target.value)} />
            </div>
            <div className="field" style={{ flex: 2 }}>
              <label htmlFor="ctx">Context</label>
              <input id="ctx" type="text" placeholder="married 9 years"
                value={draft.authorContext ?? ''}
                onChange={(e) => set('authorContext', e.target.value)} />
            </div>
            <div className="field">
              <label htmlFor="tag">Tag</label>
              <input id="tag" type="text" placeholder="Rebellion"
                value={draft.tag ?? ''} onChange={(e) => set('tag', e.target.value)} />
            </div>
          </div>

          <div className="field">
            <label htmlFor="title">Title, in their voice</label>
            <input id="title" type="text" style={{ width: '100%' }}
              value={draft.title ?? ''} onChange={(e) => set('title', e.target.value)} />
          </div>

          <div className="field">
            <label htmlFor="body">
              The story. Blank line between paragraphs. No em dashes: nobody
              types them and one gives the whole thing away.
            </label>
            <textarea id="body" style={{ minHeight: 190 }}
              value={draft.body ?? ''} onChange={(e) => set('body', e.target.value)} />
          </div>

          <div>
            <label>Replies</label>
            {replies.map((reply, i) => (
              <div className="row" key={i} style={{ marginTop: 10, alignItems: 'flex-start' }}>
                <div className="field" style={{ flex: 1 }}>
                  <input type="text" placeholder="Name" value={reply.author}
                    onChange={(e) => set('replies', replies.map((r, j) =>
                      j === i ? { ...r, author: e.target.value } : r))} />
                  <label style={{ display: 'flex', gap: 6, alignItems: 'center', marginTop: 6 }}>
                    <input type="checkbox" checked={reply.fromAuthor}
                      onChange={(e) => set('replies', replies.map((r, j) =>
                        j === i ? { ...r, fromAuthor: e.target.checked } : r))} />
                    Original poster
                  </label>
                </div>
                <div className="field" style={{ flex: 3 }}>
                  <textarea value={reply.body} style={{ minHeight: 70 }}
                    onChange={(e) => set('replies', replies.map((r, j) =>
                      j === i ? { ...r, body: e.target.value } : r))} />
                </div>
                <button className="ghost"
                  onClick={() => set('replies', replies.filter((_, j) => j !== i))}>
                  Remove
                </button>
              </div>
            ))}
            <div className="row" style={{ marginTop: 12 }}>
              <button className="ghost" onClick={() =>
                set('replies', [...replies, { author: '', body: '', fromAuthor: false }])}>
                Add a reply
              </button>
              {replies.length < 2 && (
                <span className="muted">
                  Two or more, and at least one from the original poster. A story
                  with nobody answering is a testimonial, not a community.
                </span>
              )}
            </div>
          </div>

          <div className="row">
            <label style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
              <input type="checkbox" checked={draft.published ?? true}
                onChange={(e) => set('published', e.target.checked)} />
              Published. Off keeps it here and off every device.
            </label>
          </div>

          {error && <div className="note warn"><strong>{error}</strong></div>}

          <div className="row">
            <button onClick={save} disabled={busy}>{busy ? 'Saving…' : 'Save'}</button>
            <button className="ghost" onClick={() => setDraft(null)}>Cancel</button>
          </div>
        </div>
      )}

      {stories.length === 0 ? (
        <p className="muted">
          Nothing written yet. Devices show only what EXODUS generates on the
          phone.
        </p>
      ) : (
        stories.map((story) => (
          <div className="card" key={story.id}>
            <div className="row" style={{ justifyContent: 'space-between' }}>
              <div>
                <strong>{story.title}</strong>{' '}
                {story.published
                  ? <span className="pill ok">Live</span>
                  : <span className="pill off">Draft</span>}
                <div className="muted">
                  {story.author}
                  {story.authorContext ? ` · ${story.authorContext}` : ''}
                  {' · '}{story.tag}
                  {' · '}{story.replies.length} repl{story.replies.length === 1 ? 'y' : 'ies'}
                </div>
              </div>
              <div className="row">
                <button className="ghost" onClick={() => setDraft(story)}>Edit</button>
                <button className="danger" disabled={busy}
                  onClick={() => remove(story.id)}>Delete</button>
              </div>
            </div>
            <p className="muted" style={{ marginTop: 10, whiteSpace: 'pre-wrap' }}>
              {story.body.slice(0, 220)}{story.body.length > 220 ? '…' : ''}
            </p>
          </div>
        ))
      )}
    </>
  );
}
