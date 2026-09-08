import { kvGet, kvSet } from './kv';

export interface Device {
  token: string;
  deviceId: string;
  userId: string;
  platform: 'android' | 'ios';
  build: number;
  firstSeen: string;
  lastSeen: string;
}

const KEY = 'exodus:admin:devices';

export async function readDevices(): Promise<Record<string, Device>> {
  return (await kvGet<Record<string, Device>>(KEY)) ?? {};
}

/**
 * Register or refresh one device.
 *
 * Keyed by deviceId rather than token, because a token rotates while the
 * install does not. Keying by token would grow a new row every rotation and
 * leave dead tokens in the list that look like real testers.
 */
export async function upsertDevice(
  input: Omit<Device, 'firstSeen' | 'lastSeen'>,
): Promise<void> {
  const devices = await readDevices();
  const existing = devices[input.deviceId];
  const now = new Date().toISOString();
  devices[input.deviceId] = {
    ...input,
    firstSeen: existing?.firstSeen ?? now,
    lastSeen: now,
  };
  await kvSet(KEY, devices);
}

export async function removeDevice(deviceId: string): Promise<void> {
  const devices = await readDevices();
  delete devices[deviceId];
  await kvSet(KEY, devices);
}
