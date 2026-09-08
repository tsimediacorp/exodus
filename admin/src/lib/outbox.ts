import { kvGet, kvSet } from './kv';

/**
 * Something the panel wants a device to do next time it checks in.
 *
 * Commands rather than direct writes, because the device is the source of
 * truth for its own storage. The panel cannot reach into SharedPreferences; it
 * can only ask, and the app decides how to apply it.
 */
export type Command =
  | { id: string; type: 'message'; conversationId: string; text: string; createdAt: string }
  | { id: string; type: 'memorySet'; items: string[]; createdAt: string };

/**
 * A command before the queue stamps it.
 *
 * Written out as its own union rather than Omit<Command, ...>: Omit does not
 * distribute over a union, so it collapses to the shared fields and silently
 * rejects `conversationId` and `items`.
 */
export type NewCommand =
  | { type: 'message'; conversationId: string; text: string }
  | { type: 'memorySet'; items: string[] };

const key = (deviceId: string) => `exodus:admin:outbox:${deviceId}`;

export async function readOutbox(deviceId: string): Promise<Command[]> {
  return (await kvGet<Command[]>(key(deviceId))) ?? [];
}

export async function queueCommand(
  deviceId: string,
  command: NewCommand,
): Promise<Command> {
  const full = {
    ...command,
    id: `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`,
    createdAt: new Date().toISOString(),
  } as Command;
  await kvSet(key(deviceId), [...(await readOutbox(deviceId)), full]);
  return full;
}

/**
 * Drop the commands a device says it applied.
 *
 * Acknowledged by id rather than cleared wholesale: a command queued between
 * the device reading the list and acking it would otherwise be thrown away
 * unapplied, and nothing would ever show that it had been.
 */
export async function acknowledge(deviceId: string, ids: string[]): Promise<void> {
  const remaining = (await readOutbox(deviceId)).filter((c) => !ids.includes(c.id));
  await kvSet(key(deviceId), remaining);
}
