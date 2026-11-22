#!/usr/bin/env python3
"""Generate the Bible's plates, maps and vignettes through OpenRouter.

    python3 tools/bible_art/generate.py [--only id,id] [--cap 60] [--jobs 6]

Writes raw PNGs to tools/bible_art/raw/<id>.png and appends every call's
cost to raw/ledger.jsonl. An id whose PNG exists is skipped, so the run can
be stopped and resumed, and a rejected image is redone by deleting it.
Stops starting new work once the ledger passes --cap dollars.
"""
import argparse, base64, json, os, sys, threading, time, urllib.request
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
RAW = os.path.join(HERE, 'raw')
LEDGER = os.path.join(RAW, 'ledger.jsonl')
sys.path.insert(0, HERE)
from plates import PLATES, MAPS, VIGNETTES  # noqa: E402

MODEL = 'google/gemini-3-pro-image'

PLATE_STYLE = (
    "Style: a hand-drawn illustration plate for a fine illustrated Bible. Confident "
    "sepia-brown pen-and-ink linework with fine cross-hatching, washed with soft, muted "
    "watercolour (ochre, sage green, dusty teal, faded vermilion, warm umber), on warm "
    "aged cream parchment paper whose texture shows through. Storybook engraving meets "
    "watercolour field sketch. Reverent, luminous, timeless, painterly. The edges fade "
    "softly into the bare paper (vignetted, no hard rectangle) so it sits on a printed "
    "page. Absolutely no text, letters, words, numbers, captions, labels, signatures, "
    "frames or borders. Figures are small, dignified and seen at a distance; no "
    "close-up faces. Not photorealistic, not 3D, not anime, not glossy.")

MAP_STYLE = (
    "Style: an antique hand-drawn pictorial map plate for a fine illustrated Bible, "
    "filling the image as a flat sheet seen straight on (not a photograph of a book: no "
    "page edges, binding or shadows). Sepia pen-and-ink linework with hatching for "
    "mountains, soft muted watercolour washes (pale teal seas, ochre deserts, sage "
    "hills), on warm cream parchment. Tiny pictorial towns, tents, palms and ships. "
    "This is a BLANK, UNLABELLED map: no place names, no text, no letters, no words, no numbers, no legend, no title, no cartouche, no border frame. Places are shown only by tiny pictures. Not photorealistic.")

VIGNETTE_STYLE = (
    "Style: a small printer's vignette ornament for a fine illustrated Bible: one "
    "simple motif, centred, drawn in sepia pen-and-ink with delicate hatching and a "
    "light touch of muted watercolour, on plain warm cream paper with lots of empty "
    "paper around it. Elegant and restrained. No text, no letters, no border, no "
    "frame. Not photorealistic.")

lock = threading.Lock()


def spent():
    if not os.path.exists(LEDGER):
        return 0.0
    with open(LEDGER) as f:
        return sum(json.loads(l).get('cost') or 0 for l in f if l.strip())


def key():
    for line in open(os.path.join(ROOT, '.env')):
        if line.startswith('OPENROUTER_API_KEY='):
            return line.split('=', 1)[1].strip().strip('"')
    raise SystemExit('No OPENROUTER_API_KEY in .env')


def jobs():
    for pid, book, ch, v, title, scene in PLATES:
        yield pid, '2:3', f"Scene: {book} {ch}:{v}, {title}. {scene} {PLATE_STYLE}"
    for pid, book, ch, v, title, scene in MAPS:
        yield pid, '2:3', f"Subject: {scene} {MAP_STYLE}"
    for vid, motif in VIGNETTES:
        yield vid, '4:3', f"Subject: {motif}. {VIGNETTE_STYLE}"


def call(api_key, prompt, aspect):
    body = json.dumps({
        'model': MODEL,
        'messages': [{'role': 'user', 'content': prompt}],
        'modalities': ['image', 'text'],
        'image_config': {'aspect_ratio': aspect},
    }).encode()
    req = urllib.request.Request(
        'https://openrouter.ai/api/v1/chat/completions', data=body,
        headers={'Authorization': f'Bearer {api_key}',
                 'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=240) as r:
        return json.load(r)


def run(job, api_key, cap):
    pid, aspect, prompt = job
    out = os.path.join(RAW, f'{pid}.png')
    if os.path.exists(out):
        return f'{pid} skip'
    for attempt in range(3):
        with lock:
            if spent() >= cap:
                return f'{pid} CAP'
        try:
            res = call(api_key, prompt, aspect)
        except Exception as e:  # network, 5xx, timeout
            time.sleep(5 * (attempt + 1))
            last = repr(e)
            continue
        cost = (res.get('usage') or {}).get('cost') or 0
        with lock, open(LEDGER, 'a') as f:
            f.write(json.dumps({'id': pid, 'cost': cost, 't': time.time()}) + '\n')
        try:
            url = res['choices'][0]['message']['images'][0]['image_url']['url']
            data = base64.b64decode(url.split(',', 1)[1])
        except Exception:
            last = json.dumps(res.get('error') or res)[:200]
            continue
        with open(out, 'wb') as f:
            f.write(data)
        return f'{pid} ok ${cost:.3f}'
    return f'{pid} FAIL {last}'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', default='')
    ap.add_argument('--cap', type=float, default=60.0)
    ap.add_argument('--jobs', type=int, default=6)
    a = ap.parse_args()
    os.makedirs(RAW, exist_ok=True)
    only = set(filter(None, a.only.split(',')))
    todo = [j for j in jobs() if not only or j[0] in only]
    api_key = key()
    with ThreadPoolExecutor(a.jobs) as ex:
        for line in ex.map(lambda j: run(j, api_key, a.cap), todo):
            print(line, flush=True)
    print(f'TOTAL SPENT ${spent():.2f}', flush=True)


if __name__ == '__main__':
    main()
