import { kvGet, kvSet } from './kv';

export interface StoryReply {
  author: string;
  body: string;
  fromAuthor: boolean;
}

export interface Story {
  id: string;
  author: string;
  authorContext: string;
  tag: string;
  title: string;
  body: string;
  replies: StoryReply[];
  /** Sorts the feed. Set it back-dated to slot a story in among older ones. */
  publishedAt: string;
  /** Off keeps a draft out of every device without deleting it. */
  published: boolean;
  updatedAt: string;
}

const KEY = 'exodus:admin:stories';

export async function readStories(): Promise<Story[]> {
  const stories = (await kvGet<Story[]>(KEY)) ?? [];
  return stories.sort((a, b) => b.publishedAt.localeCompare(a.publishedAt));
}

export async function writeStories(stories: Story[]): Promise<void> {
  await kvSet(KEY, stories);
}

export async function upsertStory(input: Partial<Story> & { id?: string }): Promise<Story> {
  const stories = await readStories();
  const now = new Date().toISOString();
  const existing = input.id ? stories.find((s) => s.id === input.id) : undefined;

  const story: Story = {
    id: existing?.id ?? `curated-${Date.now().toString(36)}`,
    author: (input.author ?? existing?.author ?? '').trim(),
    authorContext: (input.authorContext ?? existing?.authorContext ?? '').trim(),
    tag: (input.tag ?? existing?.tag ?? 'Marriage').trim(),
    title: (input.title ?? existing?.title ?? '').trim(),
    body: (input.body ?? existing?.body ?? '').trim(),
    replies: (input.replies ?? existing?.replies ?? []).map((r) => ({
      author: (r.author ?? '').trim(),
      body: (r.body ?? '').trim(),
      fromAuthor: Boolean(r.fromAuthor),
    })),
    publishedAt: input.publishedAt ?? existing?.publishedAt ?? now,
    published: input.published ?? existing?.published ?? true,
    updatedAt: now,
  };

  await writeStories([...stories.filter((s) => s.id !== story.id), story]);
  return story;
}

export async function deleteStory(id: string): Promise<void> {
  await writeStories((await readStories()).filter((s) => s.id !== id));
}

/**
 * Everything a device should show, in the shape the app already parses.
 *
 * Drafts are filtered here rather than on the device: an unpublished story
 * should never leave the panel at all, not merely be hidden once it arrives.
 */
export async function publishedForDevices(): Promise<unknown[]> {
  return (await readStories())
    .filter((s) => s.published && s.title && s.body)
    .map((s) => ({
      id: s.id,
      author: s.author,
      authorContext: s.authorContext,
      tag: s.tag,
      title: s.title,
      body: s.body,
      publishedAt: s.publishedAt,
      replies: s.replies.filter((r) => r.author && r.body),
    }));
}
