# Competitor review audit — PlateSpot deep read

## Method

```bash
for p in 1..10; do curl "https://itunes.apple.com/us/rss/customerreviews/page=$p/id=1396893331/sortby=mostrecent/json"; done
```

PlateSpot (Villegas Ventures LLC, id `1396893331`) — **16,856 ratings, 4.69 store average.**
Swept `us`/`ca`/`gb`/`au` × 4 sort orders × 10 pages. Deduped by review id → **228 unique reviews**
(us 219, ca 9, gb/au 0). Raw corpus: `platespot_reviews.json`.

Two things learned about the feed itself, both of which matter for reading the numbers:

- **`sortby` is ignored.** All four sort orders returned byte-identical content. This is *good* — the
  corpus is a clean recency sample, not skewed toward critics the way a `mostcritical` pull would be.
- **Depth is exhausted, not capped.** US pages 7+ come back empty, so 228 is everything Apple exposes.

**The one bias that remains, and it is large:** the feed returns only reviews *with written text*.
Mean rating among these 228 writers is **3.13**, against a store average of 4.69 over all 16,856
ratings. People who type are disproportionately annoyed. Treat 3.13 as "sentiment among writers,"
never as "sentiment among users." Every percentage below is a share of writers.

## Headline: ads

**119 of 228 (52%)** mention ads. 76 of those are ≤2 stars. This is not a background grumble, it is
the single dominant fact about the app's reception. Recurring specifics:

- Frequency is "every other plate" / "every two or three claimed plates" — named repeatedly.
- Some ads **freeze the app**: *"I have to shut my phone off and back on to get the ads off the screen."*
- Ads fire on the core interaction — claiming a plate — which is exactly the moment the app should
  feel rewarding. One reviewer was mid-transfer of their existing list from Notes: *"at least 30
  popped up."*
- Several state they would happily pay to remove them and still rate low out of irritation.

For a paid or ad-free app this is the widest open door in the category. It is also a warning about
where *not* to put a rewarded-video placement if Plates ever monetizes: not on the claim tap.

## Feature requests, ranked by number of distinct reviews

Counted against the 40 reviews (18%) containing request language. Every request below is quoted or
paraphrased from at least one review; counts are distinct reviewers.

| # | Request | Reviews | Plates status |
|---|---|---|---|
| 1 | **Persistent collection + trip history + trip-to-trip comparison** | **8** | ✅ Book + History |
| 2 | Multiple / current plate designs per state | 6 | ❌ deferred |
| 3 | Facts: more of them, state symbols, trivia; two accuracy complaints | 5 | ✅ partly |
| 4 | Native American / tribal nation plates | 4 | ❌ deferred |
| 5 | Selectable region sets, filter to unfound only | 4 | ⚠️ region enum exists, no UI |
| 6 | US map that fills in as you collect | 3 | ✅ Map tab |
| 7 | Missing Saskatchewan *(their data bug)* | 5 | ✅ n/a |
| 8 | US territories added | 1 | ✅ PR present |
| 9 | Multiplayer / team play | 1 | ❌ gated on car test |
| 10 | Family Sharing for the ad-free unlock | 1 | — |
| 11 | Rewards / badges to hold kids' attention | 1 | ⚠️ Badges tab became Book |
| 12 | Foreign & collector plates (UK, German, red Colorado) | 1 | ❌ |
| 13 | Share to Messages, not just social | 1 | ❌ |

### #1 in their own words

The top cluster is unambiguous, and it is precisely what the Book + History tabs do:

- *"a dedicated total spot thing for just lifetime instead of a trip"* — plus, in the same review, a
  grey US map that colors in. One reviewer asked for both features Plates just shipped.
- *"I would've liked to compare my two recent road trips since I know I saw plates on one trip I
  didn't see on the other!"*
- *"I'd love to have a trip counter so you can compare how many and which plates you got on
  different trips."*
- *"save each 'game' with a date and a place to take notes or at least name the trip … beat a
  previous high score while reminiscing about previous trips."*
- *"Would be helpful if one could add plates to a saved trip instead of having to start a whole new
  collection."* — titled **"Love the app- don't like the 'trip' feature."**
- *"save or export or somehow keep track of different trips. We like to compare one trip to the next
  … there is no functionality to do that."*
- *"Just wish there was a way to save progress. Had to wipe my phone and had to start the game over
  after 42 states."*

That last one is worth dwelling on: their model loses everything with the device. Plates derives the
book from every sighting ever, so a trip wipe cannot empty it — but **the same reviewer's complaint
applies to Plates today, because there is no cloud backup.** Local SwiftData dies with the phone.

## Gaps this audit opens

Ordered by (reviews × cheapness), not by my preference:

1. **Filter to unfound / selectable sets — 4 reviews, small.** `PlateRegion` already has 4 cases
   including `.territory`; this is a segmented control over an existing enum, not new modelling.
   Note the requests point *both* ways — two reviewers want territories out of their hunt, one wants
   them in — which is the argument for a filter rather than a fixed list.
2. **Multiple / current plate designs — 6 reviews, large.** Second-biggest ask and the one with the
   copyright problem already analysed. Note the complaint is often *staleness*, not variety:
   *"I live in Ohio and the license plate shown is no longer issued."* Refreshing current art is
   cheaper than a historical gallery and answers more of the reviews.
3. **Tribal plates — 4 reviews.** Also the subject of the app's angriest fact complaint: Oklahoma's
   facts *"no mention of natives … but can talk about the pioneer movement."* Worth getting right in
   `PlateFacts` regardless of whether tribal plates ship.
4. **Cloud backup.** Nobody asked PlateSpot for it by name, but the "wiped my phone, lost 42 states"
   review is the failure mode, and it gets worse the better the Book works. A lifetime collection
   with no backup is a liability the trip-scoped competitor doesn't have.
5. **Fact accuracy is a real review risk.** Two of 228 reviews are corrections (Ontario's motto is
   not "The Heartland Province"), one at 1 star. Plates ships ~6 agent-written facts per region and
   has never been fact-checked.

## What this does not say

- Nothing about download volume or revenue; ratings are not installs.
- 228 writers out of 16,856 raters is a 1.4% sample, self-selected for irritation.
- No Android/Google Play data.
- Requests are what people *say* they want. The 8-review top cluster validates the Book, but 8
  reviewers is 8 reviewers — it is directional, not a market size.
