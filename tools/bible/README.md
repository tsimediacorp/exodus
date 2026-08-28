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
for t in ASV BSB YLT; do
  curl -L -o "$t.raw.json" \
    "https://raw.githubusercontent.com/scrollmapper/bible_databases/master/formats/json/$t.json"
done
python3 convert.py     # writes asv.json, bsb.json, ylt.json
```

`convert.py` takes book identity from the app's own canon BY POSITION rather
than from the source file, because the source names books "I Samuel" and
"Revelation of John". It also strips square brackets, which the source leaves
unmatched around "[Selah"; the KJV asset already strips its `{}` translator
markers the same way.

## The KJV repair

The KJV asset originally shipped was missing six verses outright — Matthew
2:16, 22:1, 26:38 and Mark 4:40, 7:11, 8:8 — which also shifted every later
verse in those chapters one number early, silently. `repair_kjv.py` inserts
them, locating each gap by alignment against a reference KJV rather than by
hardcoded index, and verifying the whole chapter re-aligns before writing.

It repairs in place rather than swapping in the reference text wholesale
because the bundled asset is otherwise the better one: it preserves the KJV's
`LORD`/`Lord` distinction for the divine name (6,642 occurrences, against 7 in
the replacement source).

## Known, deliberate differences

- **Versification.** The KJV splits four verses the critical text merges
  (1 Samuel 20:42, 1 Kings 22:53, 3 John 14, Revelation 12:18), so it counts
  31,106 where ASV/BSB/YLT count 31,102. No text differs; only the numbering.
- **Omitted verses.** ASV and BSB follow the critical text and carry sixteen
  verses as empty strings (Matthew 17:21, Mark 9:44, Acts 8:37 and the rest).
  The numbering is kept so every other verse lands where a reader expects; the
  reader renders them as "Not included in the ASV." rather than a blank line.
