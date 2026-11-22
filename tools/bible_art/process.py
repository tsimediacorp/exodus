#!/usr/bin/env python3
"""Turn the raw art into what ships in the app.

    tools/bible_art/.venv/bin/python tools/bible_art/process.py

For every plate:
  1. Find the paper: the colour of the brightest broad tone in the image.
  2. Lift that paper to white, channel by channel. On the page the plate is
     drawn with a multiply blend, so white becomes the page's own paper and
     the art sits in the sheet instead of on a card laid over it.
  3. Fade the edges to white. This also removes what the generator sometimes
     adds at the edges (stained borders, a book's gutter, a ruled frame).
  4. Save as WebP.

Vignettes are trimmed to the motif, so they can be set small.

Writes assets/bible_art/{plates,vignettes}/*.webp and assets/bible_art/
manifest.json (book index, chapter, verse, title per plate; vignette ids).
"""
import json, os, sys
from PIL import Image, ImageChops, ImageDraw, ImageFilter
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
RAW = os.path.join(HERE, 'raw')
OUT = os.path.join(ROOT, 'assets', 'bible_art')
sys.path.insert(0, HERE)
from plates import PLATES, MAPS, VIGNETTES  # noqa: E402

PLATE_H = 1080      # pixels tall; a plate is about 500pt on the page
VIGNETTE_W = 420
QUALITY = 74

# Per-plate fixes for what the generator drew past the art.
BLANK_BOTTOM = {'dan-03': 0.17}   # a printed caption under the scene
# Drawn as a page in a book, or on a stained sheet: cut in past the edge.
CROP = {i: 0.08 for i in ('1ki-19', 'dan-07', 'jer-01', 'joh-13', 'jos-10',
                          'rev-19', 'act-12', 'gen-15', 'exo-02', 'rev-21',
                          'luk-19', 'jer-29', 'hab-03', 'isa-43')}


def paper_colour(a):
    """The paper: median colour of the brightest 25% of pixels."""
    lum = a[..., :3].mean(axis=2)
    cut = np.percentile(lum, 75)
    return np.median(a[lum >= cut][:, :3], axis=0)


def whiten(img):
    a = np.asarray(img.convert('RGB')).astype(np.float32)
    paper = np.clip(paper_colour(a), 120, 255)
    a = np.clip(a * (255.0 / paper), 0, 255)
    # Paper is never perfectly even. Anything within a few percent of white
    # is paper: ease it the rest of the way, so no faint card shows.
    lum = a.mean(axis=2, keepdims=True)
    t = np.clip((lum - 222) / (250 - 222), 0, 1)
    t = t * t * (3 - 2 * t)
    a = a + (255 - a) * t
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def fade_edges(img, inset=0.05, feather=0.09):
    """White beyond a rounded rectangle, softly."""
    w, h = img.size
    m = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(m)
    ix, iy = int(w * (inset + feather / 2)), int(h * (inset + feather / 2))
    d.rounded_rectangle([ix, iy, w - ix, h - iy], radius=int(w * 0.08), fill=255)
    m = m.filter(ImageFilter.GaussianBlur(w * feather / 2.2))
    white = Image.new('RGB', (w, h), (255, 255, 255))
    return Image.composite(img, white, m)


def process_plate(pid):
    src = os.path.join(RAW, f'{pid}.png')
    img = Image.open(src)
    if pid in CROP:
        w, h = img.size
        c = CROP[pid]
        img = img.crop((int(w * c), int(h * c * 0.6), int(w * (1 - c)), int(h * (1 - c * 0.6))))
    img = whiten(img)
    if pid in BLANK_BOTTOM:
        w, h = img.size
        ImageDraw.Draw(img).rectangle(
            [0, int(h * (1 - BLANK_BOTTOM[pid])), w, h], fill=(255, 255, 255))
    img = fade_edges(img)
    w, h = img.size
    img = img.resize((round(w * PLATE_H / h), PLATE_H), Image.LANCZOS)
    out = os.path.join(OUT, 'plates', f'{pid}.webp')
    img.save(out, 'WEBP', quality=QUALITY, method=6)
    return os.path.getsize(out)


def process_vignette(vid):
    img = Image.open(os.path.join(RAW, f'{vid}.png'))
    w, h = img.size
    img = whiten(img.crop((int(w * .1), int(h * .1), int(w * .9), int(h * .9))))
    img = fade_edges(img, inset=0.12, feather=0.08)
    # Trim to the motif: whatever is meaningfully darker than the paper.
    a = np.asarray(img).astype(np.int16)
    ink = (255 - a.min(axis=2)) > 40
    ys, xs = np.where(ink)
    if len(xs):
        pad = int(img.width * 0.03)
        box = (max(0, xs.min() - pad), max(0, ys.min() - pad),
               min(img.width, xs.max() + pad), min(img.height, ys.max() + pad))
        img = img.crop(box)
    if img.width > VIGNETTE_W:
        img = img.resize((VIGNETTE_W, round(img.height * VIGNETTE_W / img.width)),
                         Image.LANCZOS)
    out = os.path.join(OUT, 'vignettes', f'{vid}.webp')
    img.save(out, 'WEBP', quality=QUALITY + 6, method=6)
    return os.path.getsize(out)


def main():
    os.makedirs(os.path.join(OUT, 'plates'), exist_ok=True)
    os.makedirs(os.path.join(OUT, 'vignettes'), exist_ok=True)
    books = [b['n'] for b in json.load(open(os.path.join(ROOT, 'assets', 'bible', 'kjv.json')))]
    plates, total = [], 0
    for pid, book, ch, v, title, _ in PLATES + MAPS:
        if not os.path.exists(os.path.join(RAW, f'{pid}.png')):
            print('missing', pid)
            continue
        total += process_plate(pid)
        plates.append({'id': pid, 'book': books.index(book), 'chapter': ch,
                       'verse': v, 'title': title, 'map': pid.startswith('map-')})
    vignettes = []
    for vid, _ in VIGNETTES:
        if os.path.exists(os.path.join(RAW, f'{vid}.png')):
            total += process_vignette(vid)
            vignettes.append(vid)
    plates.sort(key=lambda p: (p['book'], p['chapter'], p['verse']))
    with open(os.path.join(OUT, 'manifest.json'), 'w') as f:
        json.dump({'plates': plates, 'vignettes': vignettes}, f, indent=1)
    print(f'{len(plates)} plates, {len(vignettes)} vignettes, {total / 1e6:.1f} MB')


if __name__ == '__main__':
    main()
