# Scripture card backgrounds

Drop image files in here and the app uses them — no code change, nothing to
register. The asset manifest is read at runtime and any `.jpg`, `.jpeg`,
`.png` or `.webp` in this folder becomes a candidate.

An empty folder is fine: the card falls back to a painted landscape
(`lib/widgets/ridge_backdrop.dart`).

## Before committing new artwork

```bash
python3 tools/backgrounds/check_contrast.py
```

The verse runs to about four fifths of the card width, and every image in this
set puts its sun in the upper right — so a photograph that looks fine on its
own can still leave the end of each line sitting on lit sky. The checker
simulates the real card and reports the worst tile. If one fails, darken or
replace that image; do **not** lighten the scrim to suit it, because that
weakens every other card.

`tools/backgrounds/PROMPTS.md` has the generation prompts and the constraints
these images have to satisfy.
