# Bible art

The illustrated Bible's plates and ornaments: about 250 full-page plates for
the passages that carry a scene (maps among them), and small vignettes that
head every other chapter. All of it ships in the app under
`assets/bible_art/`, catalogued by `assets/bible_art/manifest.json`.

## Making it

1. **`plates.py`** is the list: each plate's id, book, chapter, the verse its
   caption quotes, the chapter's title, and what to draw. God the Father is
   never drawn as a figure; Jesus is drawn small and at a distance.
2. **`generate.py`** draws them through OpenRouter (`google/gemini-3-pro-image`,
   about $0.14 an image) using `OPENROUTER_API_KEY` from `.env`. That key is
   the app's own chat key too, so watch the balance: `--cap` stops the run
   at a spend, and `raw/ledger.jsonl` records every call. Raw PNGs land in
   `raw/` (not committed). An id whose PNG exists is skipped, so to redo one,
   move it out of `raw/` and run with `--only <id>`.

       python3 tools/bible_art/generate.py --only exo-14 --cap 60

3. Look at every image. Reject any with lettering, a page or book drawn
   around the art, or a figure that breaks the rules above.
4. **`process.py`** turns `raw/` into what ships: the paper is lifted to
   white (the app draws plates with a multiply blend, so white becomes the
   page's own paper), the edges fade out, vignettes are trimmed to the
   motif, and everything is saved as WebP with the manifest.

       python3 -m venv tools/bible_art/.venv
       tools/bible_art/.venv/bin/pip install pillow numpy
       tools/bible_art/.venv/bin/python tools/bible_art/process.py

   `CROP` and `BLANK_BOTTOM` in `process.py` fix plates the generator drew
   too much around.

## The house style

Sepia pen-and-ink with fine cross-hatching, washed in muted watercolour
(ochre, sage, dusty teal, faded vermilion), on cream paper. The full prompt
is in `generate.py`; the approved design is the "EXODUS Illustrated Bible"
canvas in Claude Design.
