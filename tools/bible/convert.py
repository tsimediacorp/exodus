"""Convert scrollmapper's per-translation JSON into the app's asset shape.

App shape (matching assets/bible/kjv.json exactly):
    [{"n": "Genesis", "a": "gn", "c": [["verse 1", "verse 2", ...], ...]}, ...]

Book identity comes from the app's OWN canon by position, not from the source
file: the source names books "I Samuel" / "Revelation of John", and bookIndex
is an index into the app's list, so a rename would silently misfile a book.
Order was verified identical for all three sources before this ran.
"""
import json, re, sys

APP_KJV = '/Users/christiantejada/Desktop/development/exodus/assets/bible/kjv.json'
kjv = json.load(open(APP_KJV))
canon  = [b['n'] for b in kjv]
abbrev = [b['a'] for b in kjv]

def clean(text: str) -> str:
    # Square brackets mark editorial insertions (mostly "[Selah") and are left
    # unmatched by the source. The KJV asset already strips its {} markers and
    # keeps the words; do the same here so the two read alike.
    text = text.replace('[', '').replace(']', '')
    return re.sub(r'\s+', ' ', text).strip()

def convert(src: str, out: str) -> None:
    d = json.load(open(src))
    books = d['books']
    assert len(books) == 66, f'{src}: expected 66 books, got {len(books)}'
    result = []
    for i, b in enumerate(books):
        chapters = []
        for ch in b['chapters']:
            verses = [clean(v['text']) for v in ch['verses']]
            chapters.append(verses)
        result.append({'n': canon[i], 'a': abbrev[i], 'c': chapters})
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(result, f, ensure_ascii=False, separators=(',', ':'))
    print(f'{out}: {sum(len(c) for b in result for c in b["c"])} verses')

for t, out in [('ASV', 'asv.json'), ('BSB', 'bsb.json'), ('YLT', 'ylt.json')]:
    convert(f'{t}.raw.json', out)
