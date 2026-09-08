# Admin panel: state of play

Last updated 2026-09-07, after builds 46-49.

https://exodus-admin-seven.vercel.app

## What it does

| Feature | State |
|---|---|
| Force update by minimum build | Done, build 46 |
| A/B groups | Done, build 46 |
| Feature flags, global and per tester | Done, build 46 |
| Remote toggle of memory editing | Done, build 46 |
| Manual push to devices | Done, build 47 |
| See chats for debugging | Done, build 48 |
| Edit user memories remotely | Done, build 48 |
| Message from EXODUS into a chat, with push | Done, build 48 |
| Analytics, including A/B comparison | Done, build 49 |
| Subscription management | Deferred, deliberately. See below |

## Setup still outstanding

All three are Vercel dashboard tasks and none of the panel works properly
without them.

| | |
|---|---|
| `ADMIN_PASSWORD` | Sign-in is impossible without it |
| `FIREBASE_SERVICE_ACCOUNT` | Push sends nothing. Firebase console -> Project settings -> Service accounts -> Generate new private key, paste the whole JSON |
| Upstash Redis | Storage tab. Without it nothing persists: not the update gate, not the device list, not the analytics |

iOS push additionally needs an APNs key from the Apple developer account.
Android works today.

## Why subscriptions are not here

There is no billing, paywall, or entitlement code anywhere in `lib/`. A
subscription page would have nothing to manage.

Building it means choosing first:

1. **The stack.** RevenueCat, or raw StoreKit 2 plus Play Billing. RevenueCat
   costs a percentage and saves weeks; raw is free and is genuinely fiddly on
   two platforms.
2. **Tiers and price.** What is free, what is paid, whether there is a trial.
3. **What happens at the boundary** — does an expired subscriber lose their
   history, or just new counsel?

Those are product decisions, and making them during a closed beta means making
them without the usage data the beta exists to produce. They are also
expensive to reverse once real subscribers exist. Deferred on that basis,
2026-09-07, with Chris's agreement.

## The privacy position

Worth writing down, because it changes at launch and someone has to remember.

**During the beta**, Counsel conversations and memory sync to the panel with no
opt-in. Chris's call, made 2026-09-07 on the basis that testers are known
people and the whole thing comes out before launch.

**Confessions never sync**, and are not measured even as a count. That tab was
built and described to users as never leaving the device. `debug_sync_test.dart`
asserts the snapshot contains no confessions; `analytics_test.dart` asserts no
event name can mention them.

**Analytics carries counts only.** No message text, no verse, no name. There is
no field on the endpoint for content.

## Removing all of it at launch

Everything is behind one compile-time switch. A build made without
`--dart-define=EXODUS_ADMIN_URL` sends nothing anywhere: no snapshot, no
events, no push registration, and no update gate. Tests assert this.

Then delete, in this order:

1. `lib/services/debug_sync.dart` and its test
2. `lib/services/analytics.dart`, its test, and the `Analytics.instance.track`
   calls (nine of them)
3. The `admin/` directory and the Vercel project
4. `lib/services/remote_config.dart` and `update_required_screen.dart`, if the
   force-update gate is not wanted in production. It is the one piece here
   worth keeping.
5. `lib/services/push_service.dart` only if remote push is not wanted at all.
   It is also worth keeping.

`CommunityPost.composite` is stored on every generated post so the seeded
community stories can be found and cleared in the same pass.
