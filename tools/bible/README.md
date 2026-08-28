# Bible assets

How `assets/bible/*.json` were produced, so they can be regenerated or audited.

## Format

```json
[{"n": "Genesis", "a": "gn", "c": [["verse 1", "verse 2", ...], ...]}, ...]
```

`n` is the book name, `a` its abbreviation, `c` chapters of verse strings.
Book ORDER is load-bearing: `BibleRef.bookIndex` indexes straight into this
list, so a reordered asset silently sends every scripture link in the app to
the wrong book. `test/bible_translation_assets_test.dart` checks this on every
registered translation.

## Source

All texts come from [scrollmapper/bible_databases](https://github.com/scrollmapper/bible_databases)
(`formats/json/<ABBREV>.json`), MIT-licensed as a database. That licence covers
the database, NOT the underlying translations — those are cleared separately:

| Asset      | Translation                | Status                                    |
|------------|----------------------------|-------------------------------------------|
| `kjv.json` | King James Version         | Public domain (1611/1769)                 |
| `bsb.json` | Berean Standard Bible      | Public domain since 2023-04-30 ([licence](https://berean.bible/licensing.htm)) |
| `asv.json` | American Standard Version  | Public domain (1901)                      |
| `ylt.json` | Young's Literal Translation| Public domain (1898)                      |

NIV, ESV, NLT, NASB and CSB are under copyright and cannot be bundled without
a licence agreement with their publishers.

## Regenerating

```bash
cd tools/bible
for t in ASV BSB YLT KJV; do
  curl -L -o "$t.raw.json" \
    "https://raw.githubusercontent.com/scrollmapper/bible_databases/master/formats/json/$t.json"
done
python3 convert.py       # writes asv.json, bsb.json, ylt.json
python3 rebuild_kjv.py   # writes kjv.rebuilt.json — see "The KJV rebuild"
```

`convert.py` takes book identity from the app's own canon BY POSITION rather
than from the source file, because the source names books "I Samuel" and
"Revelation of John". It also strips square brackets, which the source leaves
unmatched around "[Selah"; the KJV asset already strips its `{}` translator
markers the same way.

## The KJV rebuild

The KJV asset originally shipped had three defects:

1. **Six verses were missing outright** — Matthew 2:16, 22:1, 26:38 and Mark
   4:40, 7:11, 8:8 — which also shifted every later verse in those chapters
   one number early. Matthew 2:23, the Nazarene prophecy, sat at 2:22.
2. **Translator marginal notes were appended to the scripture text** in 6,435
   verses, about a fifth of the Bible: `"...divide the waters from the waters.
   firmament: Heb. expansion"`. Readers saw the gloss as scripture.
3. **Four verses were split** in a way no printed KJV uses (1 Samuel 20:42,
   1 Kings 22:53, 3 John 14, Revelation 12:18), giving 31,106 verses instead
   of 31,102.

`rebuild_kjv.py` fixes all three by taking the text from the clean reference
KJV, which has none of them. The catch is that the reference renders the divine
name as "Lord" everywhere, losing the KJV's `LORD`/`Lord` distinction (YHWH vs
Adonai) — 6,642 occurrences in the old asset against 7 in the reference. Losing
YHWH from a King James Bible is a worse defect than the three being fixed.

So the casing is transplanted from the old asset by **word-level alignment**
per chapter, not by counting occurrences per verse. Alignment is what makes it
safe: the marginal notes are insertions and the mis-split verses move verse
boundaries, and `difflib` absorbs both. Notes sometimes mention the divine name
themselves (129 of them), which is exactly why a naive per-verse count would
have gone wrong.

The result is verified against the cases that would catch a bad transplant:

- **Psalm 110:1** — "The LORD said unto my Lord": both forms in one verse.
- **Genesis 15:2** — "Lord GOD".
- **Deuteronomy 6:4** — "The LORD our God is one LORD".

`test/bible_translation_assets_test.dart` pins all of these, plus the six
restored verses and standard versification.

Incidentally removed with the notes: 14 stray guillemets (`«»`), unbalanced
parentheses, and en dashes inside hyphenated proper nouns.

## Known, deliberate differences

- **Versification.** All four assets carry 31,102 verses on the same
  versification, so a reference resolves to the same passage in each.
- **Omitted verses.** ASV and BSB follow the critical text and carry sixteen
  verses as empty strings (Matthew 17:21, Mark 9:44, Acts 8:37 and the rest).
  The numbering is kept so every other verse lands where a reader expects; the
  reader renders them as "Not included in the ASV." rather than a blank line.
