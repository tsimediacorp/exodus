# EXODUS

> God's design. Unfiltered.

A Flutter app delivering scripture-first, no-fluff biblical counsel for young
couples, powered by an uncensored LLM (GLM-4.6 by default, swappable to
Venice or direct Zhipu).

---

## First-time setup

```bash
cd exodus
flutter pub get
```

`ios/` and `android/` are both checked in. Drop your OpenRouter key into `.env`
and run:

```bash
flutter run
```

## Android builds

The Android toolchain needs a JDK, and the Homebrew `openjdk@17` install is
keg-only so it never lands on `PATH`. Without this, `flutter doctor` reports
"Could not determine java version" and every Gradle build fails:

```bash
flutter config --jdk-dir="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
```

Then, for a sideloadable build — `--split-per-abi` matters, since the universal
APK carries all three ABIs and is roughly triple the size:

```bash
flutter build apk --release --split-per-abi
```

`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` is the one for any
current phone. Release builds are signed with the **debug** keystore, which is
fine for sideloading but will not do for the Play Store — that needs a real
keystore in `android/key.properties` (gitignored), a `signingConfigs` block in
`android/app/build.gradle.kts`, and `flutter build appbundle` instead.

Three things in the Gradle config are workarounds for stale plugins rather than
choices, and are commented as such where they live: `compileSdk` is forced to 36
for every subproject because flutter_webrtc pins 31; `proguard-rules.pro`
silences R8 warnings about Tink's compile-only annotations; and
`flutter_timezone` had to go from 1.0.8 to 5.x because 1.0.8 referenced the
long-removed v1 Android embedding.

## The master prompt — the most important file

**`lib/config/master_prompt.dart`** is the baseline for how EXODUS sounds.
Six labeled sections:

| Section      | What it controls                                       |
|--------------|--------------------------------------------------------|
| `identity`   | Who EXODUS is — its name, role, persona                |
| `doctrine`   | Theological convictions (canon, marriage, sex, sin)    |
| `audience`   | Who it's talking to (young couples, what they bring)   |
| `style`      | Voice rules — directness, citation, length             |
| `guardrails` | Safety lanes (abuse, off-topic, theological disputes)  |
| `signature`  | The "EXODUS feel" — naming roots, calling sin, prayer  |

Two ways to tune:

1. **Edit the file** (the `default*` strings) → bake new defaults into the build.
   Save, hot-reload (`r`), next message uses the new prompt.
2. **In-app Settings screen** (gear icon top-right) → override any section at
   runtime without recompiling. Overrides are stored in `shared_preferences`.
   "Reset to defaults" wipes overrides and falls back to the file.

You also control from Settings:
- `temperature` (slider, 0.0–1.5)
- `maxTokens` (number field)
- `activeProvider` — switch between `openrouter`, `glm`, `venice`

`models` map (in master_prompt.dart) lets you swap model IDs without touching
service code.

## API keys

`lib/config/api_keys.dart` is gitignored. Paste your key there.
OpenRouter is the default because one key gives you GLM-4.6, Venice-uncensored,
and dozens of other models.

## Features

- **Streaming responses** — tokens render as they arrive (SSE)
- **Conversation persistence** — the chat survives app restarts
- **New chat** — top-right icon, clears the current thread
- **Settings screen** — provider/temperature/prompt overrides at runtime
- **Provider-agnostic** — one service class, three backends

## Structure

```
lib/
├── main.dart                  ← initializes storage, then runs the app
├── config/
│   ├── master_prompt.dart     ← edit defaults; settings screen overrides at runtime
│   └── api_keys.dart          ← gitignored
├── theme/
│   └── exodus_theme.dart
├── widgets/
│   ├── exodus_shield.dart     ← logo as CustomPainter, no asset needed
│   └── message_bubble.dart
├── screens/
│   ├── splash_screen.dart
│   ├── chat_screen.dart       ← streaming + persistence wired in
│   └── settings_screen.dart   ← edit prompt/provider/temperature live
├── models/
│   └── chat_message.dart      ← JSON-serializable, mutable content for streaming
└── services/
    ├── ai_service.dart        ← askStream() for SSE, ask() for one-shot
    └── storage_service.dart   ← shared_preferences wrapper
```

## Design language

- **Obsidian** `#0A0E1A` — background, the "night watch" base
- **Midnight / Slate / Steel** — layered surfaces and borders
- **Covenant Blue** `#3B6FE3` — primary action, user message, divine promise
- **Brass** `#C9A961` — shield border, cross, accent (warmth amid the dark)
- **Crimson** `#B94545` — danger, sin, alerts

The shield is drawn programmatically (heater shape, brass border, gold cross,
soft blue halo) — scales to any size, no PNG to maintain.

## Roadmap

- Multiple conversation threads with a sidebar
- Daily verse + couple-of-the-day prompt
- Multi-user couple mode — both spouses contribute to one thread
- Sermon/devotional library that EXODUS can cite
- Voice mode for car/morning use
