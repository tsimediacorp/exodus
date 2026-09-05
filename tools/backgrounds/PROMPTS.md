# Scripture card backgrounds — generation prompts

Drop finished images into `assets/backgrounds/`. The app reads that folder at
runtime, so **no code change is needed** — add a file, rebuild, done. Remove
them all and the card falls back to the painted landscape.

---

## The constraints (these matter more than the scenery)

The card is wide and short, with the verse set over the **left half**. Any
image that ignores this is unusable no matter how good it looks.

| | |
|---|---|
| **Aspect** | 16:9 (or wider). Cropped with `BoxFit.cover`, centre-anchored. |
| **Size** | 1600×900 is plenty. The card renders ~1050×520 at 3× density. |
| **Format** | JPEG, quality ~80. Aim for **under 250 KB each**. |
| **Naming** | Anything. `dawn-ridges.jpg`, `01.jpg` — the app sorts and picks deterministically. |
| **How many** | 8–14 is a good set. Each verse gets a stable one, so more = less repetition. |

**Three rules every prompt below already encodes:**

1. **Dark on the left, light on the right.** The left third is where the verse
   sits. The app also lays a dark scrim over that side, but a bright left edge
   still fights the text.
2. **No people, no text, no lettering, no watermark.** A face pulls focus from
   scripture, and any text in the image will collide with the real text.
3. **Deep shadows, low sun, unsaturated.** These sit inside an app built on
   near-black and brass. A vivid blue sky or green field reads as a stock photo
   dropped into someone else's design.

---

## Base prompt

Paste this in front of any scene below:

> Cinematic landscape photograph, wide panoramic composition. Deep shadow
> across the entire left third of the frame, light source low on the right
> horizon. Muted desaturated palette of deep navy, charcoal and warm gold.
> Heavy atmospheric haze, soft volumetric light, film grain, shot on 35mm.
> Reverent, still, vast. No people, no animals, no buildings, no text, no
> letters, no watermark, no logo. Nothing in the lower left quadrant that
> draws the eye.

Then add one scene:

---

## Scenes

1. **Dawn ridges** — layered mountain ridgelines receding into mist, sun
   cresting the furthest ridge on the right, valleys still in blue shadow.
2. **Cloud sea** — a high peak above an ocean of cloud at first light, gold
   rimming the cloud tops on the right.
3. **Desert dusk** — vast sand dunes, long raking shadows, a copper sun just
   above the dune line on the right.
4. **Sea cliffs** — dark basalt cliffs meeting a pale calm sea, low sun
   throwing a narrow gold path across the water on the right.
5. **Storm breaking** — heavy dark cloud pulling apart, a single shaft of warm
   light falling on distant hills at the right.
6. **Olive grove** — ancient gnarled olive trees on a terraced hillside, warm
   low sunlight raking through from the right, deep shade at the left.
7. **Wheat at golden hour** — a still field of ripe wheat, sun low and hazy on
   the right horizon, foreground in shadow.
8. **Still water** — a glassy mountain lake at dawn, peaks reflected, warm
   light only on the far right shoulder of the range.
9. **Forest light** — shafts of misty light through tall dark pines, brightest
   at the right, forest floor unlit.
10. **Snow peaks** — distant snow-covered summits under a cold pale sky, first
    warm light catching only the rightmost peak.
11. **Canyon** — deep red rock canyon walls in shadow, a band of warm light on
    the upper right rim.
12. **Night sky** — a dark hill ridge under a deep star field, faint warm glow
    on the right horizon before dawn. *(Use one or two of these at most — a
    night scene is a change of key, not a default.)*

---

## After generating

- Check each at phone size with the left half covered by your thumb. If the
  remaining right half still reads as a whole image, the crop is safe.
- Downsample and compress before committing:

```bash
sips -Z 1600 assets/backgrounds/*.jpg
```

- Anything over ~250 KB is worth another pass; the whole set rides in every
  download.

---

## If you'd rather keep the painted ones

They stay as the fallback either way — `lib/widgets/ridge_backdrop.dart`,
seeded per verse, four times of day. Deleting everything from
`assets/backgrounds/` reverts to them with no other change.
