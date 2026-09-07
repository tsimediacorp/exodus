# Admin panel: what works, and what each remaining feature actually costs

Written 2026-09-07, after auditing what is server-side and what is not.

## The finding

Three of the seven requested features cannot be built from the panel alone,
because the data or the delivery mechanism does not exist in the app yet.

| Feature | State |
|---|---|
| Force update by minimum version | **Done** (build 46) |
| A/B groups | **Done** |
| Remote toggle of memory editing | **Done** |
| Manual push to users | Blocked: no remote push exists |
| EXODUS message into a chat, with push | Blocked: chats are on-device |
| See chats for debugging | Blocked: chats are on-device |
| Edit user memories remotely | Blocked: memory is on-device |
| User management | Partial: users exist in Cognito |
| Analytics | Nothing to read yet |
| Subscription management | No billing exists anywhere in the app |

## Why push is blocked

`flutter_local_notifications` schedules notifications **on the device**. There
is no `firebase_messaging`, no device token, and no server able to reach a
phone. Every notification the app has ever sent was scheduled locally by the
app itself.

To send one from the panel:

1. Add `firebase_messaging` to the app. The Firebase project already exists
   (`exodus-tsi`, used for App Distribution), so this is configuration, not a
   new vendor.
2. Register the FCM token against the signed-in user. A `DeviceToken` model on
   the existing Amplify schema is the natural home.
3. A send endpoint in the panel, holding a service-account key, that posts to
   FCM for the selected users.

APNs also needs an Apple push key for iOS, which is a Chris task in the Apple
developer console.

Roughly: a day of app work, half a day of panel work. It unblocks both push
features, because "message from EXODUS with a push" is the same delivery path
carrying a message payload.

## Why chats and memory are blocked

They never leave the phone. Counsel conversations, memory, community posts,
devotionals, study, letters and check-ins are all in `SharedPreferences`. Only
Together-mode messages, prayers and quiz data are in Amplify, and those are
protected by `ownersDefinedIn('members')` so not even an admin can read them
without elevated access.

**This is a decision, not a task.** Reading chats and editing memory from a web
panel means shipping a couple's most private material to a server. For a closed
beta with testers who know and agree, that is a legitimate trade. It is worth
being deliberate about:

- **Make it opt-in per user**, driven by a flag this panel already supports.
  A tester turns on "debug sync" and knows what it means.
- **Confessions must stay out.** That feature was built and described to users
  as never leaving the device — it is the entire premise of the tab. Debugging
  value is low and the cost of breaking that promise is the feature itself.
- **Set a deletion date.** Synced beta data should not outlive the beta.

Once decided, the shape is a `DebugSnapshot` model on Amplify holding the
conversation and memory JSON for opted-in users, written by the app on a timer,
read by the panel through an IAM role. Injecting a message back is the same
model in reverse: an outbox the app drains on launch and on push.

## Analytics and subscriptions

Nothing to build a panel against yet. There is no analytics SDK wired up
(`amplify_analytics_pinpoint` arrives as a transitive dependency but nothing
calls it), and no billing, paywall or entitlement code anywhere in `lib/`.
Both are real projects rather than panel pages, and neither is on the critical
path for a closed beta.

## Order I would do them in

1. **Push** — highest value for a closed beta, no privacy decision needed, and
   it unblocks two of the requests at once.
2. **Debug sync**, opt-in, once the privacy call is made.
3. **Analytics**, when there is a question you want a number to answer.
4. **Subscriptions**, when there is something to sell.
