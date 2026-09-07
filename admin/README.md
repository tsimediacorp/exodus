# EXODUS admin

Closed-beta control panel. Force update, feature flags, A/B groups.

Everything here is scaffolding for the beta and comes out at launch.

## Deploy

1. In Vercel, import this repo and set **Root Directory** to `admin`.
2. Set environment variables:

   | Variable | |
   |---|---|
   | `ADMIN_PASSWORD` | The password for the panel |
   | `ADMIN_SECRET` | Any long random string. `openssl rand -hex 32` |

3. Add **Storage → Upstash Redis** in the Vercel dashboard. It sets
   `KV_REST_API_URL` and `KV_REST_API_TOKEN` automatically. **Without this,
   settings do not persist** — the panel says so on the overview page.

4. Point the app at it:

   ```bash
   flutter build apk --release --dart-define=EXODUS_ADMIN_URL=https://your-panel.vercel.app
   ```

   No URL means no remote config: no gate, and every flag at its built-in
   default. That is deliberate, so a build can be made that answers to nobody.

## The contract

```
GET /api/v1/config?platform=android&build=45&userId=<cognito sub>
```

```json
{
  "updateRequired": false,
  "updateAvailable": true,
  "minBuild": 40, "latestBuild": 46,
  "updateUrl": "https://…", "message": "…",
  "group": "A",
  "flags": { "memoryEditing": true }
}
```

Public and unauthenticated on purpose: a build old enough to be blocked may be
old enough to have a broken sign-in, so the gate has to answer before auth.
Nothing here is sensitive, and the user id only ever picks a bucket.

## Build numbers, not versions

The gate compares the `+45` in `0.1.0+45`. It is the only part that reliably
increases. `lib/config/build_info.dart` holds the app's copy, and
`test/build_info_test.dart` fails if it ever drifts from `pubspec.yaml` — a
stale constant would make shipped builds report an old number and lock users
out of an app they had already updated.

## Adding a flag

1. Add it to `KNOWN_FLAGS` in `src/lib/config.ts` so the panel renders a real
   toggle with an explanation.
2. Add its **shipping** default to `_defaults` in
   `lib/services/remote_config.dart`. That default is what runs when the panel
   is unreachable, so it must be the behaviour you would ship, not the
   experiment.
3. Read it with `RemoteConfig.instance.flag('yourFlag')`.

## What this panel does not do yet

See `docs/admin-roadmap.md` in the repo root. Push, chat viewing and remote
memory editing all need app-side work that does not exist yet; the short
version is that the app has no remote push and keeps chats and memory on the
device only.

## Local

```bash
cd admin && npm install && npm run dev   # http://localhost:3000
npm test                                  # the gate and A/B logic
```
