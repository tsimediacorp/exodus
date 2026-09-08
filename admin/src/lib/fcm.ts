import { createSign } from 'node:crypto';

/**
 * Send a push through FCM's HTTP v1 API.
 *
 * Signs a JWT with the service account key and exchanges it for an access
 * token. Done by hand rather than with firebase-admin: that package pulls in a
 * large dependency tree and starts a background token refresher, neither of
 * which suits a serverless route that runs for 200ms and exits.
 *
 * FIREBASE_SERVICE_ACCOUNT holds the JSON from
 * Firebase console -> Project settings -> Service accounts -> Generate new
 * private key. It IS a credential: it can send push to every EXODUS install,
 * so it lives only in Vercel's encrypted env and never in the repo.
 */
interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

export interface SendResult {
  token: string;
  ok: boolean;
  error?: string;
  /** FCM says this token is dead and should be dropped from the registry. */
  gone?: boolean;
}

export function isConfigured(): boolean {
  return Boolean(process.env.FIREBASE_SERVICE_ACCOUNT);
}

function account(): ServiceAccount {
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT ?? '';
  if (!raw) throw new Error('FIREBASE_SERVICE_ACCOUNT is not set.');
  const parsed = JSON.parse(raw) as ServiceAccount;
  // Vercel's env editor turns real newlines into "\n" on paste, and a key with
  // literal backslash-n fails to sign with an error that names neither.
  parsed.private_key = parsed.private_key.replace(/\\n/g, '\n');
  return parsed;
}

let cached: { token: string; expires: number } | null = null;

async function accessToken(): Promise<string> {
  if (cached && cached.expires > Date.now() + 60_000) return cached.token;

  const sa = account();
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = base64url(
    JSON.stringify({
      iss: sa.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }),
  );
  const signer = createSign('RSA-SHA256');
  signer.update(`${header}.${claim}`);
  const signature = signer.sign(sa.private_key, 'base64url');

  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${header}.${claim}.${signature}`,
    }),
  });
  if (!response.ok) {
    throw new Error(`Google token exchange failed: ${await response.text()}`);
  }
  const json = (await response.json()) as { access_token: string; expires_in: number };
  cached = { token: json.access_token, expires: Date.now() + json.expires_in * 1000 };
  return json.access_token;
}

export async function sendTo(
  tokens: string[],
  message: { title: string; body: string; payload?: string },
): Promise<SendResult[]> {
  const sa = account();
  const bearer = await accessToken();
  const endpoint = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

  // One request per token. FCM's batch endpoint was retired, and a closed beta
  // is tens of devices, not thousands.
  return Promise.all(
    tokens.map(async (token): Promise<SendResult> => {
      try {
        const response = await fetch(endpoint, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${bearer}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            message: {
              token,
              notification: { title: message.title, body: message.body },
              data: message.payload ? { payload: message.payload } : {},
              android: { priority: 'HIGH' },
              apns: { payload: { aps: { sound: 'default' } } },
            },
          }),
        });
        if (response.ok) return { token, ok: true };
        const text = await response.text();
        return {
          token,
          ok: false,
          error: text.slice(0, 300),
          // An uninstalled app or a rotated token. Worth clearing out rather
          // than leaving in the list looking like a tester who never gets push.
          gone: response.status === 404 || text.includes('UNREGISTERED'),
        };
      } catch (error) {
        return { token, ok: false, error: String(error).slice(0, 300) };
      }
    }),
  );
}

function base64url(input: string): string {
  return Buffer.from(input).toString('base64url');
}
