# Filling the image gaps — done, and the long-term plan

> **Rewritten after a bad round.** Most of what follows described 17 jurisdictions
> resolved from external sources. Every one of those was later opened and compared
> against the row it was filling, and **five were the wrong plate** — see the "Showing
> the wrong plate" section of `plate-history.md`. What survives is six sources, each with
> the contents of the picture written into its note. "Each URL tested" meant each URL
> returned 200, which is not a test of anything that matters here.

Three files back this up:

- `current-plate-sources.csv` — a source for each jurisdiction missing its present-day
  plate, and a `depicts_dates` column naming the exact row each image belongs to. **6
  resolved and verified by eye, 4 rejected on inspection, 2 preceding-design, 1 still
  unfound, 9 superseded by the parser fix.**
- `commons-candidates.csv` — 73 Commons files, all free-licensed, that the Wikipedia
  articles do not link. Raw triage input.
- `plate-validity-cutoffs.csv` — the street-legal cutoffs, 29 of 65 jurisdictions.

## Done

**7 from the article itself.** The parser now honours Wikipedia's two ways of saying "same
design as above" — a `rowspan`-ed Design cell, and a description opening "As above, but
with…" — and borrows the picture from the row that owns it, saying so on the card. AK, AR,
CA, MO, NC, NV and UT needed no external source at all. This is the best class of fix
available: the encyclopedia is stating the designs are the same, so it is evidence rather
than a guess.

**3 from Keegan, kept after inspection.** ID, IN and (for Alabama) the state agency copy.
Each was opened and read against its row's description — potato base with a screened
serial and full white border, covered bridge with corner markings, sunrise beach with
`www.alabama.travel`. Five other Keegan/agency images were rejected as the *previous*
design: CA, KS, MO, SC, WY.

**2 from Wikimedia Commons.** Files that exist on Commons but are not linked into the
article tables, which is why the scrape never saw them: KY and NC, both free-licensed.
Both are bound to one row each — Kentucky's other current row is the base before it, and
North Carolina's July 2019 row is a different design from the `FIRST IN FREEDOM` plate in
the picture. An aspect-ratio check was previously used as a proxy for "is this a plate";
it is not one, and it passed a 4160×1920 photo of the back of a Ford Expedition.

**1 from an official PDF.** Nebraska publishes `2023_Series_Plates.pdf`; the standard
plate is the first embedded image, 440×220. Extract with:

```
pdfimages -png -f 1 -l 1 2023_Series_Plates.pdf out
```

That also matters beyond Nebraska: it is a free-licence-irrelevant *government
publication* of the design, and it is the same class of source that could replace the
eight fair-use Nebraska images in the dataset.

## Still open: 5 jurisdictions

Arkansas came off this list — its April 2021 row shares a Design cell with March 2006, so
the article's own photograph covers it. Four *joined* it, because the images that had been
covering them were the wrong plate.

| | why it stays open |
| --- | --- |
| **AZ** | the only free candidate is a photo of a whole vehicle with the plate a few percent of the frame |
| **KS** | agency site is JS-rendered and serves no plate image; Commons has stickers and a motorcycle plate only |
| **SC** | January 2026 base; brand new, and the article gives it no design description either |
| **WY** | WYDOT still publishes the 2017 sample; nothing free for the June 2024 flag plate |
| **YT** | current design dates from 1990 and still nothing free; enthusiast sites have it, but those photos are the photographers' own copyright |

Nunavut and Puerto Rico show the **preceding** design, labelled as such on the card, on the
judgement that a rollout months old means the old plate is what is actually on the road.
That is written into `current-plate-sources.csv` per jurisdiction rather than inferred, so
it cannot quietly spread to a jurisdiction where it is not true.

The pattern is structural rather than bad luck: a design is missing when it is **brand
new** (SC, WY, NU), the jurisdiction is **small and under-photographed** (NU, YT), or the
agency **does not publish its standard plate** (AZ, KS, PR) — the same fourteen-agency
blind spot the Keegan analysis found in the first place.

Most exist on collector sites. None of them can be taken from there, for the reason
already established: those photographers own their photographs outright, unlike the
Commons contributors who released theirs.

**The rule that came out of this round:** an image is not a source until someone has
looked at it beside the row's description. Keegan's snapshot is July 2023 and state
agencies leave superseded samples up for years, so "the agency publishes it" and "it is
the current plate" are independent facts. `depicts_dates` in the sources file is what
holds the two together.

## The 36 missing validity cutoffs

Wikipedia is exhausted. I mined all 36 remaining articles for reissue and recall
language: only four mention one with a year, and all four are about a single series
rather than a general rule. The next source is state DMV plate-replacement policy — about
32 lookups, and the only route that yields a *stated* cutoff rather than an inference.

Worth noting this is optional. A spotter never needs to know that a 1974 Vermont plate is
illegal, because they will never see one. Showing only the present plate for those 36 is
already correct behaviour.

## Long term

### 1. User submissions, keyed to the gaps

The dataset already knows every gap: jurisdiction, date range, and Wikipedia's own prose
description of the design, even where no photograph exists. So a submission screen has its
caption written before anyone uploads anything — *"Nunavut, August 2025 – present:
embossed blue serial on polar bear-shaped white plate with yellow…"*

Filter `street_legal = current` and no image to get the queue. It is currently **27 rows
across 5 jurisdictions** for present-day plates, and 1,208 rows across all eras.

### 2. Push accepted photos back to Commons under CC0

This is the step that compounds, and it is worth doing even though it gives work away.

Uploading a user's photo to Commons under CC0 fixes the gap for the app *and* removes the
licensing question at its root: a CC0 photograph taken by a contributor carries no
attribution burden and no dependence on anyone else's judgement about the plate design.
It also means the next person scraping Wikipedia — including a future run of this
scraper — inherits the fix.

Requires an explicit opt-in from the submitting user, since CC0 is irrevocable.

### 3. Re-run the scrape periodically

Every tool here is idempotent and cached. `wiki_plates.py` re-reads `.wiki-cache/`, so a
re-run costs API calls only for articles that changed. Designs get added to Wikipedia
continuously — several jurisdictions in this dataset have a "– present" row dated 2026 —
so an annual re-run keeps the current-design set honest.

### 4. Prefer free images where a choice exists

The rule the AZ/KY/UT cases established: when the same design is available both from a
state agency and from Commons, take the Commons copy. Same picture, explicit licence.
Wire this preference into whatever ingests `current-plate-sources.csv` rather than taking
the first URL that works.
