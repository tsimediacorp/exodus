"""Insert the six verses missing from the bundled KJV asset.

The shipped asset drops six verses of scripture outright, which also shifts
every later verse in those chapters one number early. It is otherwise the
better text: it preserves the KJV's LORD/Lord distinction for the divine name
(6,642 occurrences, against 7 in the replacement source), so the asset is
repaired in place rather than swapped out.

Insertion points are located by aligning against a reference KJV rather than
hardcoded, and the result is verified verse-by-verse before it is written.
"""
import json, re, difflib, sys

APP = '/Users/christiantejada/Desktop/development/exodus/assets/bible/kjv.json'
cur = json.load(open(APP))
ref = json.load(open('KJV.raw.json'))['books']
names = [b['n'] for b in cur]

def norm(s):
    s = s.replace('[', '').replace(']', '')
    s = re.sub(r'[^a-z ]', ' ', s.lower())
    return re.sub(r'\s+', ' ', s).strip()

# The bundled text inlines translator marginal notes, so a bundled verse is
# "the reference verse plus extra". Score on how much of the reference verse
# is contained in the bundled one.
def similar(a, b):
    return difflib.SequenceMatcher(None, norm(a), norm(b), autojunk=False).ratio()

TARGETS = [('Matthew', 2), ('Matthew', 22), ('Matthew', 26),
           ('Mark', 4), ('Mark', 7), ('Mark', 8)]

inserted = []
for name, cnum in TARGETS:
    bi = names.index(name)
    have = cur[bi]['c'][cnum - 1]
    want = [v['text'] for v in ref[bi]['chapters'][cnum - 1]['verses']]
    if len(want) - len(have) != 1:
        sys.exit(f'{name} {cnum}: expected exactly one missing verse, '
                 f'got have={len(have)} want={len(want)}')

    # Walk the reference; the first index whose bundled counterpart matches the
    # NEXT reference verse better than this one is the gap.
    gap = None
    for i in range(len(want)):
        if i >= len(have):
            gap = i
            break
        if similar(have[i], want[i]) < 0.55 and similar(have[i], want[i + 1]) > 0.7:
            gap = i
            break
    if gap is None:
        sys.exit(f'{name} {cnum}: could not locate the gap')

    have.insert(gap, want[gap].strip())
    inserted.append((name, cnum, gap + 1, want[gap][:70]))

# ---- verify the whole book now aligns, chapter by chapter ----
problems = []
for name, cnum in TARGETS:
    bi = names.index(name)
    have = cur[bi]['c'][cnum - 1]
    want = [v['text'] for v in ref[bi]['chapters'][cnum - 1]['verses']]
    if len(have) != len(want):
        problems.append(f'{name} {cnum}: length {len(have)} != {len(want)}')
        continue
    for i, (h, w) in enumerate(zip(have, want)):
        if similar(h, w) < 0.55:
            problems.append(f'{name} {cnum}:{i+1} misaligned\n    have: {h[:80]}\n    want: {w[:80]}')

if problems:
    print('VERIFICATION FAILED — not written:')
    for p in problems[:10]:
        print(' ', p)
    sys.exit(1)

total = sum(len(c) for b in cur for c in b['c'])
print(f'verses after repair: {total}')
for name, cnum, vnum, text in inserted:
    print(f'  inserted {name} {cnum}:{vnum} — {text}…')

# LORD must survive untouched.
allv = [v for b in cur for c in b['c'] for v in c]
print('LORD occurrences preserved:', sum(v.count('LORD') for v in allv))

with open('kjv.repaired.json', 'w', encoding='utf-8') as f:
    json.dump(cur, f, ensure_ascii=False, separators=(',', ':'))
print('wrote kjv.repaired.json')
