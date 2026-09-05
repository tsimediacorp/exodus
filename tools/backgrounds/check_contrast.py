#!/usr/bin/env python3
"""Is the verse still readable over every card background?

Run this after adding artwork to assets/backgrounds/:

    python3 tools/backgrounds/check_contrast.py

A photograph is far less predictable than something we painted, and the
failure is silent -- the card renders, it just cannot be read. This simulates
the real card (BoxFit.cover into the card box, then the scrim) and reports the
worst tile inside the region the text actually occupies.

The scrim values are READ FROM lib/widgets/scripture_background.dart rather
than copied, so this cannot quietly disagree with what ships.

Needs Pillow:  python3 -m pip install pillow
"""
import glob
import os
import re
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow is not installed: python3 -m pip install pillow")

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DART = os.path.join(ROOT, "lib", "widgets", "scripture_background.dart")
FOLDER = os.path.join(ROOT, "assets", "backgrounds")

# Card geometry in logical pixels, read off scripture_hero_card.dart. The verse
# is in an Expanded, so it runs to roughly four fifths of the width -- this is
# the whole reason the right end of the scrim matters.
CARD_W, CARD_H = 340, 215
TEXT = (18, 40, 268, 185)
TILE = 22

VERSE = (0xF3, 0xEF, 0xE6)
BRASS = (0xC9, 0xA9, 0x61)   # eyebrow and citation: smaller, more fragile
SCRIM = (0x06, 0x0A, 0x14)

VERSE_MIN = 4.5              # body text
BRASS_MIN = 3.0              # bold, letterspaced, but small


def scrim_from_dart():
    """The alphas and stops that actually ship."""
    with open(DART) as handle:
        source = handle.read()

    def numbers(name):
        match = re.search(rf"{name}\s*=\s*\[([^\]]*)\]", source)
        if not match:
            sys.exit(f"could not find {name} in {DART}")
        return [float(n) for n in re.findall(r"[\d.]+", match.group(1))]

    alphas, stops = numbers("scrimAlphas"), numbers("scrimStops")
    if len(alphas) != len(stops):
        sys.exit("scrimAlphas and scrimStops disagree in length")
    return list(zip(stops, alphas))


def scrim_alpha(t, stops):
    for i in range(len(stops) - 1):
        (p0, a0), (p1, a1) = stops[i], stops[i + 1]
        if p0 <= t <= p1:
            f = 0 if p1 == p0 else (t - p0) / (p1 - p0)
            return a0 + (a1 - a0) * f
    return stops[-1][1]


def relative_luminance(rgb):
    def channel(c):
        c /= 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = (channel(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(fg, bg):
    l1, l2 = relative_luminance(fg), relative_luminance(bg)
    hi, lo = max(l1, l2), min(l1, l2)
    return (hi + 0.05) / (lo + 0.05)


def cover(img, w, h):
    """What BoxFit.cover does."""
    scale = max(w / img.width, h / img.height)
    img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    left, top = (img.width - w) // 2, (img.height - h) // 2
    return img.crop((left, top, left + w, top + h))


def worst_tile(path, stops):
    img = cover(Image.open(path).convert("RGB"), CARD_W, CARD_H)
    px = img.load()
    x0, y0, x1, y1 = TEXT
    worst = (99.0, 99.0, None)
    for ty in range(y0, y1 - TILE + 1, 6):
        for tx in range(x0, x1 - TILE + 1, 6):
            r = g = b = n = 0
            for y in range(ty, ty + TILE, 3):
                for x in range(tx, tx + TILE, 3):
                    pr, pg, pb = px[x, y]
                    r, g, b, n = r + pr, g + pg, b + pb, n + 1
            a = scrim_alpha(tx / CARD_W, stops)
            out = tuple(
                (c / n) * (1 - a) + s * a
                for c, s in ((r, SCRIM[0]), (g, SCRIM[1]), (b, SCRIM[2]))
            )
            verse, brass = contrast(VERSE, out), contrast(BRASS, out)
            if verse < worst[0]:
                worst = (verse, brass, (tx, ty))
    return worst


def main():
    stops = scrim_from_dart()
    paths = sorted(glob.glob(os.path.join(FOLDER, "*.jpg")) +
                   glob.glob(os.path.join(FOLDER, "*.jpeg")) +
                   glob.glob(os.path.join(FOLDER, "*.png")) +
                   glob.glob(os.path.join(FOLDER, "*.webp")))
    if not paths:
        print("No backgrounds yet — the painted landscape is used, nothing to check.")
        return 0

    print(f"scrim {['%.2f' % a for _, a in stops]} at {[s for s, _ in stops]}\n")
    print(f"{'image':24}{'verse':>10}{'brass':>10}   worst tile")
    print("-" * 62)
    failed = []
    for path in paths:
        verse, brass, at = worst_tile(path, stops)
        bad = verse < VERSE_MIN or brass < BRASS_MIN
        if bad:
            failed.append(os.path.basename(path))
        print(f"{os.path.basename(path):24}{verse:>8.2f}:1{brass:>8.2f}:1   {at}"
              f"{'   <-- TOO BRIGHT' if bad else ''}")
    print("-" * 62)
    if failed:
        print(f"\n{len(failed)} unreadable: {', '.join(failed)}")
        print("Darken the image, or replace it. Do NOT lighten the scrim to suit "
              "one photo — that weakens every other card.")
        return 1
    print(f"\nAll {len(paths)} clear {VERSE_MIN}:1 for the verse and "
          f"{BRASS_MIN}:1 for the citation.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
