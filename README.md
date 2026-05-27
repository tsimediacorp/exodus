# EXODUS

> God's design. Unfiltered.

A Flutter app delivering scripture-first, no-fluff biblical counsel for young
couples, powered by an uncensored LLM (GLM-4.6 by default, swappable to
Venice or direct Zhipu).

---

## First-time setup

```bash
cd exodus
# Generate the iOS scaffold (only iOS in this round; add more later)
flutter create . --project-name exodus --org com.dreamviz --platforms=ios
flutter pub get
```

Then drop your OpenRouter key into `lib/config/api_keys.dart` and run:

```bash
flutter run
```

To target other platforms later: `flutter create --platforms=android,web,macos .`

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
