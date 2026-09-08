import { kvGet, kvSet } from './kv';

export interface SyncedMessage {
  role: 'user' | 'exodus';
  content: string;
  at: string;
}

export interface SyncedConversation {
  id: string;
  title: string;
  updatedAt: string;
  messages: SyncedMessage[];
}

export interface SyncedMemory {
  id: string;
  text: string;
  source: string;
}

export interface Snapshot {
  deviceId: string;
  userId: string;
  build: number;
  platform: string;
  receivedAt: string;
  memory: SyncedMemory[];
  conversations: SyncedConversation[];
  /** What the device trimmed to stay under the size cap, if anything. */
  truncated?: string;
}

const INDEX = 'exodus:admin:snapshot:index';
const key = (deviceId: string) => `exodus:admin:snapshot:${deviceId}`;

export async function readIndex(): Promise<string[]> {
  return (await kvGet<string[]>(INDEX)) ?? [];
}

export async function readSnapshot(deviceId: string): Promise<Snapshot | null> {
  return kvGet<Snapshot>(key(deviceId));
}

export async function readAllSnapshots(): Promise<Snapshot[]> {
  const ids = await readIndex();
  const all = await Promise.all(ids.map((id) => readSnapshot(id)));
  return all
    .filter((s): s is Snapshot => s !== null)
    .sort((a, b) => b.receivedAt.localeCompare(a.receivedAt));
}

/**
 * Store one device's snapshot.
 *
 * One key per device rather than one big blob: a phone with a long history
 * would otherwise make every read of every other device expensive, and the
 * panel reads these on page load.
 */
export async function writeSnapshot(snapshot: Snapshot): Promise<void> {
  await kvSet(key(snapshot.deviceId), snapshot);
  const index = await readIndex();
  if (!index.includes(snapshot.deviceId)) {
    await kvSet(INDEX, [...index, snapshot.deviceId]);
  }
}

export async function forgetSnapshot(deviceId: string): Promise<void> {
  await kvSet(key(deviceId), null);
  await kvSet(INDEX, (await readIndex()).filter((id) => id !== deviceId));
}
