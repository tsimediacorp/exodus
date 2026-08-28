"""Rebuild assets/bible/kjv.json from a clean KJV, keeping the divine name.

The asset that shipped had three problems: six verses were missing outright,
about a fifth of its verses had translator marginal notes appended to the
scripture text ("...from the waters. firmament: Heb. expansion"), and four
verses were split in a way no printed KJV uses.

The clean reference text has none of those, but renders the divine name as
"Lord" everywhere — losing the KJV's LORD/Lord distinction (YHWH vs Adonai),
which is not an acceptable trade in a King James Bible.

So: text comes from the reference, and the CASING of Lord/God is transplanted
from the old asset by word-level alignment. Alignment (rather than counting
occurrences per verse) is what makes this safe across the marginal notes,
which are insertions, and the four mis-split verses, which shift verse
boundaries — difflib absorbs both.
"""
import json, re, difflib, sys

APP = '/Users/christiantejada/Desktop/development/exodus/assets/bible/kjv.json'
old = json.load(open(APP))
ref = json.load(open('KJV.raw.json'))['books']
canon  = [b['n'] for b in old]
abbrev = [b['a'] for b in old]

WORD = re.compile(r"[A-Za-z]+")
DIVINE = {'lord', 'god'}

def tokens(text):
    return [(m.group(0), m.start(), m.end()) for m in WORD.finditer(text)]

transplanted = 0
skipped = 0
result = []

for bi, book in enumerate(ref):
    out_chapters = []
    for ci, chapter in enumerate(book['chapters']):
        rverses = [v['text'] for v in chapter['verses']]
        overses = old[bi]['c'][ci] if ci < len(old[bi]['c']) else []

        # Align the whole chapter as one token stream, so a verse boundary that
        # moved (or a note that was inserted) does not throw the rest off.
        rtok, rmap = [], []          # rmap: (verse index, token index in verse)
        for vi, text in enumerate(rverses):
            for ti, (w, _s, _e) in enumerate(tokens(text)):
                rtok.append(w.lower()); rmap.append((vi, ti))
        otok = [w.lower() for text in overses for (w, _s, _e) in tokens(text)]
        ocase = [w for text in overses for (w, _s, _e) in tokens(text)]

        # reference token index -> old token index, for tokens that align
        pairing = {}
        for block in difflib.SequenceMatcher(None, rtok, otok, autojunk=False)\
                            .get_matching_blocks():
            for k in range(block.size):
                pairing[block.a + k] = block.b + k

        # decide the casing of every Lord/God in the reference
        decisions = {}               # (verse index, token index) -> replacement
        for k, w in enumerate(rtok):
            if w not in DIVINE:
                continue
            j = pairing.get(k)
            if j is None:
                skipped += 1
                continue
            source = ocase[j]
            if source.lower() != w:  # alignment landed on a different word
                skipped += 1
                continue
            if source.isupper():     # LORD / GOD
                decisions[rmap[k]] = source
                transplanted += 1

        # splice the decided casings back into the verse strings
        out_verses = []
        for vi, text in enumerate(rverses):
            toks = tokens(text)
            pieces, cursor = [], 0
            for ti, (w, s, e) in enumerate(toks):
                repl = decisions.get((vi, ti))
                if repl is None:
                    continue
                pieces.append(text[cursor:s]); pieces.append(repl); cursor = e
            pieces.append(text[cursor:])
            v = ''.join(pieces)
            # The source hyphenates proper nouns with an en dash; a hyphen is
            # what a printed KJV uses and what anyone searching would type.
            v = v.replace('–', '-')
            out_verses.append(re.sub(r'\s+', ' ', v).strip())
        out_chapters.append(out_verses)

    result.append({'n': canon[bi], 'a': abbrev[bi], 'c': out_chapters})

allv = [v for b in result for c in b['c'] for v in c]
print(f'verses: {len(allv)}')
print(f'casings transplanted: {transplanted}   unalignable (left as-is): {skipped}')
print(f'LORD: {sum(v.count("LORD") for v in allv)}   GOD: {sum(v.count("GOD") for v in allv)}')

with open('kjv.rebuilt.json', 'w', encoding='utf-8') as f:
    json.dump(result, f, ensure_ascii=False, separators=(',', ':'))
print('wrote kjv.rebuilt.json')
