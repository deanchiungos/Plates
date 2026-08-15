# Onboarding

Walking a new player through what the app does, without making them read about it.

**Confirmed design decisions.** One welcome card, not a deck. Coach marks are
balloons that point at the thing they describe, in the app's own design language —
not TipKit, not the centered popup. Both decided in conversation; neither is open.

**The one-sentence architecture:** a first launch that *plays* within a minute,
followed by one-shot coach marks that fire the first time each feature could
actually matter, backed by a reference page in More for everything skipped.

---

## 0. What already exists, and must not be trampled

A third of an onboarding is already built, each piece arriving at the right
moment. The plan's first job is to sequence these, not replace them:

- **"Who's playing?"** — `DevicePlayer.hasProfile` gates it and `IdentityPrompt`
  does the asking: the editor on a genuinely new install, a pick-your-face list on
  a restored one. This *is* the identity step. It fires from `GameScreen` once a
  trip or book exists, once per launch, and the welcome flow gives it a place in
  line rather than a second door.
- **The trip-or-book fork** — the Game tab's empty state ("Nothing to fill yet")
  offers *Start a trip* / *Start a book* with one line on the difference. This is
  the second step of onboarding, already designed. It stays where it is; the
  welcome card lands on it.
- **The location ask** — `TrackingHintCard` already asks for the permission in
  words, on the Game screen, before ever spending the one-shot system prompt. Do
  not move this into the welcome flow. A permission request during onboarding is
  the classic way to get a reflexive "no" that can never be re-asked; the card's
  entire design is that the ask happens when the map and rarity make its value
  visible.
- **The first find** — confetti, the rarity card, the tile flipping to its state
  art. This is the best explanation of the core loop the app will ever render,
  and it is triggered by doing the thing, not by reading about it.
- **Empty states everywhere** — Trips, Trail, Books all explain themselves when
  empty. Coach marks must never repeat what the empty state under them already
  says.

The corollary: **the welcome flow is for people with nothing, and only them.** It
is gated on `!DevicePlayer.hasProfile` alone, which means every existing install —
including every TestFlight tester — never sees it. That one condition is the
entire migration story, and it costs nothing.

> **This gate used to read `!DevicePlayer.hasProfile && trips.isEmpty &&
> books.isEmpty`, and it could never once have been true.** `PlatesStore.seedIfNeeded`
> handed every first launch a trip called "Summer Roadtrip" and a book called "My
> Plate Book", so `trips.isEmpty` was false before the first frame drew. The same
> seed also made the fork above unreachable — nobody had ever seen the empty state
> this plan calls step two, because there was always something to fill. Both are
> fixed: the seed creates nothing, and the fork is now what a new install actually
> opens on. Anything below that assumes an empty first launch is assuming
> correctly, and only since that change.

---

## 1. Principles

1. **Teach in the car, not in the lobby.** The app is opened at the moment a
   drive starts, often by a kid in the back seat. Time-to-first-plate is the
   number this whole plan is judged on. Target: under 60 seconds from first
   launch to first tap, including typing a trip name.
2. **A feature is explained at the first moment it could matter, once, and never
   again.** No tip fires on a schedule, on launch count, or "after 3 days".
   Every trigger below is a fact about the player's actual state.
3. **Nothing is gated.** Every step of the welcome is skippable; every coach mark
   is dismissible by tapping it *or by doing the thing it describes*. A tutorial
   you cannot leave is an obstacle the moment you have understood it — same
   reasoning as the find card's tap-to-dismiss.
4. **The app's own voice.** Directions to the player, tab names not code names,
   no self-justification, no exclamation marks. Every string is a single
   `LocalizedStringKey` literal so the catalog harvests it (the popup lesson).
5. **One mark on screen, ever.** Two balloons at once is a fairground. A global
   arbiter enforces it.

---

## 2. Layer 1 — the welcome (first launch only)

Three beats. Two already exist.

### 2.1 The card

One full-screen view on the paper ground, in the app's own type. Content, top to
bottom:

- A drawn plate tile (reuse `PlateTile` with a handsome state — Arizona or
  Colorado, something with art), slightly oversized, at a small tilt like a plate
  tossed on a table. No animation on v1; a one-time settle-into-place spring is a
  polish item (§9).
- Title, condensed face: **"PLATES"** — the wordmark treatment from the More
  footer, bigger.
- Two sentences, Overpass, and no more than two:
  > "Spot license plates on the road. Tap them here, and try to collect all 50
  > states."
- Primary button: **"Play"** (route blue, the app's capsule style).
- Quiet text button underneath: **"Skip"**.

Both buttons go to the same place — the sequenced flow below — except Skip marks
every Layer-1 step seen and drops the player on the Game tab's empty state
directly. Skip exists so the card is a choice, but the honest expectation is that
"Play" *is* the skip button: the whole flow is three tappable screens.

What the card deliberately does not contain: feature bullets, page dots, a
gradient, an illustration commissioned for onboarding, or the word "welcome".

### 2.2 Who's playing

The existing `IdentityPrompt` sheet (`saveLabel: "Continue"`), presented from
`RootView` as the card dismisses rather than on `GameScreen`'s own trigger.

> **Built without the stand-down this section originally specified.** The plan said
> `GameScreen.introduceThisPhoneOnce` should refuse to fire once `Coach.seen(.welcome)`,
> so the two paths could not collide. They cannot collide anyway: the Game screen's
> ask waits for a trip or a book to exist, and the welcome runs before there is
> either. Worse, the stand-down would have opened a hole — somebody who taps Skip is
> never asked their name by the card, and a permanent stand-down would mean never
> being asked at all. Leaving the Game screen's trigger alone makes Skip mean "not
> now" instead of "never".

Name, face, colour — all optional, all defaulted, one tap through for the
impatient. This sheet is also the party's identity, which is why it earns its
place in line: it is the one piece of setup another person will ever see.

Note that `IdentityPrompt` has two faces and the welcome only ever meets one of
them. A restored install — which shows the pick-your-face list instead — is by
definition not a first run, has `trips` and `books` arriving from iCloud, and must
never be given the welcome card on top of that. The `!hasProfile` gate does not
distinguish the two, so the welcome's own condition needs the extra clause:
**skip the card when the store already has players.** That is the one place the
migration gate is not simply `!hasProfile`.

### 2.3 The fork

Land on the Game tab, which shows the existing empty state. One change to it,
welcome-flow only: the description line gains a second sentence of framing.

> "A trip is one drive with a route and a finish. A book you just keep adding
> to. **Pick one to start collecting — you can have both later.**"

The bolded sentence is added only while `!Coach.seen(.fork)`; after the first
container exists the empty state reads as it does today. Filling in the trip
editor (or book editor) **is** the tutorial for it — no marks inside either
sheet, ever. They are forms; forms explain themselves or they are bad forms.

### 2.4 The first-tap line

On the first visit to a grid that has a collection and zero sightings, one coach
mark (the component from Layer 2, so nothing special-cased) anchored to the
grid's first tile:

> "See one of these on the road? Tap it."

Dismissed by tapping it, or — the good path — by logging the first plate, at
which point the celebration takes over and the loop is closed. This is the only
coach mark that fires during the welcome sequence.

---

## 3. Layer 2 — coach marks

### 3.1 The component: `CoachMark`

A balloon that points. Design spec:

- **Shape.** A rounded rectangle (`cornerRadius: 12`, matching fields) with a
  small notch (a 10pt triangle, same fill) on whichever edge faces the anchor.
  Fill is `Theme.route`; text is white, `.plates(size: 13.5, weight: .medium)`,
  max width ~260pt, padding 12/10. One optional bold lead-in span. A subtle
  shadow (`Theme.ink.opacity(0.18)`, radius 10) lifts it off the paper —
  the one place the app allows a real shadow, because the balloon genuinely
  floats above the page.
- **No scrim, no dimming, no blocking.** The mark never intercepts a tap that
  is not on the mark itself. Someone who ignores it and plays anyway is using
  the app correctly; the mark dismisses itself when its condition is met (§3.3).
- **Placement.** Anchor preferences: the target view registers itself with
  `.coachAnchor(_ key:)` (an `anchorPreference` wrapper), and a `CoachLayer`
  hosted at each screen's root reads the anchor and lays the balloon above or
  below the target, whichever half of the screen has room, notch pointing at
  the anchor's midpoint. The layer lives per-screen rather than at RootView,
  because a balloon must scroll with its target — marks anchored inside
  ScrollViews (the grid tile, a trip row) are the common case, and a
  root-level overlay would float detached the moment the list moved.
- **Motion.** Appears with the popup's scale-plus-opacity transition; a slow
  ±3pt vertical float while idle is a polish item, off by default (motion is
  noise in a moving car, and `accessibilityReduceMotion` would have to gate it
  anyway).
- **Entry timing.** A mark appears 0.6s after its trigger condition first
  becomes true on a visible screen — long enough for the screen to settle,
  matching every existing DEBUG delay. A mark whose screen disappears before it
  fires simply does not fire; the trigger re-evaluates next visit. Nothing is
  queued.
- **Dismissal.** Three ways, all equivalent: tap the balloon; perform the action
  it describes (each mark's condition, §3.3); or leave the screen. All three
  call `Coach.markSeen(key)` — including leaving the screen. **A mark shows at
  most once, even if ignored.** A balloon that reappears on every visit until
  acknowledged is nagging, and the reference page exists precisely so an
  ignored tip is not lost forever. This also makes the state machine trivial:
  shown means seen.
- **Accessibility.** The balloon posts a VoiceOver announcement
  (`AccessibilityNotification.Announcement`) with its text when it appears, and
  is itself an accessibility element (button, label = text, hint = "Dismisses
  this tip"). Dynamic Type scales the text; at accessibility sizes the balloon
  widens to the screen minus margins rather than growing taller than its
  target. Reduce Motion drops the scale transition for a fade.
- **Localization.** `LocalizedStringKey` throughout, single literals.

### 3.2 The ledger: `Coach`

`ios/Plates/Domain/Coach.swift`. The shape mirrors `DevicePlayer`:

```swift
enum Coach {
    enum Tip: String, CaseIterable {
        case welcome        // the card itself was shown (or skipped)
        case fork           // the framed empty state was seen
        case firstTap       // "See one of these on the road? Tap it."
        case swipeTrip      // swipe left to pin / mark done
        case uncheck        // long-press in unlimited
        case doneTrip       // the record + fold, after first finish
        case trailScope     // the Trail shows one drive; the name switches it
        case spotterChip    // the colored corner is who called it
        case listLength     // mark old trips done once the list is long
    }

    static func seen(_ tip: Tip) -> Bool
    static func markSeen(_ tip: Tip)
    static func reset()          // "Replay the tips" and the DEBUG arg
}
```

`UserDefaults`, key per case (`coach.swipeTrip`), deliberately **not** synced
through iCloud — tips are about what *this hand* has been shown, same reasoning
as `DevicePlayer`'s note about KVS. `reset()` clears every key except `welcome`:
replaying tips should not re-run the welcome over a full app (and the welcome's
own gate would refuse anyway, but the ledger should agree with it).

One global `@Observable` arbiter, `CoachPresenter`, owns "which mark is up right
now" so two screens cannot both present. It exposes
`request(_ tip:) -> Bool` (false if something else is showing or the tip is
seen) and `dismiss(_ tip:)`. Injected via environment next to `PopupHost`. A
mark also stands down while `popup.item != nil` — a balloon under a popup scrim
is furniture.

### 3.3 The marks

Each entry: trigger (a fact about state, checked in that screen's
`onAppear`/`onChange`), anchor, copy (draft — final pass at build time under the
copy rules), and the action that counts as "done".

| key | trigger | anchored to | copy | done-when |
|---|---|---|---|---|
| `firstTap` | grid visible, collection exists, `platesFound == 0` | first unfound tile | **"See one of these on the road?** Tap it." | first sighting logged |
| `swipeTrip` | Trips list visible, ≥1 swipeable row, and (unlike the rest) only from the *second* session — on day one the list is one trip and there is nothing to organise | first trip row | "Swipe left to pin this trip, or mark it done." | any SwipeRow opened |
| `uncheck` | grid visible, collection is unlimited mode, any plate `count ≥ 1` | a counted tile | "Every tap counts again here. **Hold a plate** to take one back." | uncheck popup opened |
| `doneTrip` | Trips list visible, a trip was finished in this session (set by `finish(_:)`) | the Finished section header | "Finished trips file themselves here. Open one to see its story, or add its plates to a book." | finished trip's record opened |
| `trailScope` | Trail visible with pins, ≥2 possible scopes | the scope bar | "This is one drive. Tap here to see another, or everything ever." | scope picker opened |
| `spotterChip` | grid visible and a sighting by a *different* player exists on the current collection (a party landed, or a shared book synced) | that plate's tile | "The colored corner is who called it." | tapped/expired only — there is no action |
| `listLength` | Trips list visible, `trips.running.count ≥ 8` | the Finished/Archived area | "Getting long? Mark old trips done — they file themselves away." | any trip finished or archived |

Cut from the table on purpose: a mark for the **switcher** (the header's SWITCH
control labels itself), the **filter** (behind a labelled button), **voice
mode / party / lookup / widget / Siri** (reachable features with their own
screens that explain themselves on arrival — they are Layer 3's job), and
anything inside an editor sheet.

`doneTrip`'s trigger is deliberately "finished *this session*" rather than "a
finished trip exists" — the mark is a follow-through on an action just taken,
not archaeology about state from last month.

> **Three things this table did not anticipate, all found while building it.**
>
> 1. **`swipeTrip` had a rival already on screen.** The trips list carried a
>    permanent caption reading "Tap a trip to play it. Swipe one left to pin it
>    or mark it done." — the mark's own words, in muted 12.5pt, three inches
>    below the row the balloon points at. §0's rule ("never repeat what the
>    thing under it already says") decides it: the caption is now the tap half
>    only, and the swipe gesture is taught by the mark and documented on the
>    "How to play" page. That page is therefore no longer optional polish; it is
>    where this copy went.
> 2. **A list wants its balloon above, not below.** Placing below is right for a
>    grid and wrong for a list, where the space below a row is the next row — the
>    `doneTrip` balloon landed squarely on the trip that had just been filed,
>    hiding its own evidence. `coachAnchor(prefersAbove:)` carries the
>    preference; the layer still overrides it when there is no room above.
> 3. **"Second session" needs a counter.** `Coach.launchCount`, bumped once in
>    `PlatesApp.init`. It is the only piece of coach state that is not a fact
>    about the collection, and it exists for `swipeTrip` alone.

---

## 4. Layer 3 — "How to play" in More

One scrolling page, pushed from a new row in the More tab's "App" group
(`MoreRow(title: "How to play")`), above Settings. Structure — each section a
titled card in the `MoreSection`/`SettingsGroup` visual family, two to four
sentences each, present tense, no screenshots (they rot):

1. **The game.** Tap plates as you spot them. One point a state in classic;
   rarity points on a route. The grid, the found state, repeats in unlimited.
2. **Trips and books.** One drive with a finish, versus the book you fill
   forever. Where each is made, switching between them, what marking a trip
   done does (files it under Finished, stops it collecting, reopen any time).
3. **Adding a trip to a book.** The fold, in three sentences: open a finished
   trip, Add to book, stack or fill the gaps. The one rule worth stating:
   nothing is ever counted twice in your all-time record.
4. **Rarity.** Where the tiers come from, that plates from far away are worth
   more, that a plate keeps the value you claimed it at.
5. **The Map and the Trail.** Which question each answers ("which states" vs
   "where was I").
6. **Playing together.** The party in one paragraph; shared books in another.
7. **Hands free.** The Siri phrases, verbatim, and voice mode — this content
   already exists on the Settings voice card; it moves here and Settings keeps
   only the toggle-adjacent line.
8. **The widget and the lookup.** One paragraph each.
9. **Replay the tips** — a quiet row at the bottom calling `Coach.reset()`,
   with a one-line footnote: "Tips appear once, as things come up. This brings
   them back."

The page is also where any future explainer-footer in the app should point
instead of growing longer in place.

> **Built, with one section merged and one thing removed rather than slimmed.**
> §4's items 1 and 4 both wanted to explain scoring, so the three modes are
> stated once under "The game" and rarity keeps only what is about *rarity* —
> where the tiers come from, and that a plate keeps the value you claimed it at.
>
> Settings' voice card was not slimmed; it is gone. §4 asked for "only the
> toggle-adjacent line" and there is no toggle — the auto-listen switch was
> removed months ago, so the card was pure explanation sitting on a page whose
> stated rule is controls and state only. The Siri phrases moved here verbatim.
> No pointer row was added back to Settings either: "How to play" is the row
> directly above it in the same menu, and a cross-reference between two adjacent
> rows is furniture. "Replay the tour" made the same move for the same reason,
> and is now the page's last card.
>
> Body copy on this page is full ink, not the muted grey the same size uses
> elsewhere. Everywhere else 13.5pt is a subtitle under a heading; here it is
> the entire content, and nine cards of grey reads as a disclaimer.
>
> **On "no screenshots", which stands — but now means something narrower.** Each
> of the eight explaining sections carries a small drawing, because nine cards
> of unbroken prose is a page nobody scrolls and nothing to navigate by. None of
> them is a *capture*: they are built from the app's live vocabulary — real
> `PlateTile`s with real artwork, the actual tab-bar symbols, `RarityTier`'s own
> five colours, the real player palette. That is the whole point of the rule.
> A screenshot rots silently when a control moves; a picture assembled from the
> components themselves restyles when they do. Every one is
> `accessibilityHidden` and every section reads correctly without it.

---

## 5. Files

| file | contents |
|---|---|
| `ios/Plates/Domain/Coach.swift` | `Coach` ledger, `Tip` enum, `CoachPresenter` |
| `ios/Plates/Design/CoachMark.swift` | balloon view, notch shape, `coachAnchor` preference + `CoachLayer` |
| `ios/Plates/Screens/WelcomeCard.swift` | the one card |
| `ios/Plates/Screens/HowToPlayScreen.swift` | Layer 3 |
| `RootView.swift` | welcome gating + presentation, `CoachPresenter` into environment |
| `GameScreen.swift` | `firstTap`, `uncheck`, `spotterChip` triggers; stand down `noticeTheChangeOnce` after welcome; fork framing line |
| `TripsScreen.swift` | `swipeTrip`, `doneTrip`, `listLength` triggers |
| `Trail.swift` | `trailScope` trigger |
| `MoreScreen.swift` | How to play row |
| `SettingsScreen.swift` | voice card slimmed, pointer to How to play |

No model changes. No new dependencies. Nothing in the widget or intents.

---

## 6. DEBUG hooks

Same pattern as everything else — every state reachable without a hand on the
device:

- `-welcome` — force the card regardless of gating (composes with `-demoData`).
- `-coach swipeTrip` — force one mark on its screen, ledger ignored.
- `-coachReset` — wipe the ledger at launch.
- `-howToPlay` — open the reference page directly (it is two taps deep).
- `-forgetMe` — *already built.* Drops this device's claim on a player without
  touching the store, which is the only way to reach the identity step twice.
  Alone it re-runs a first launch; with `-demoData` it is a restored install to
  the letter, and it is how the pick-your-face list is reachable at all.

All compiled out of Release, all listed in the existing launch-args comment
blocks where they land.

---

## 7. Test and screenshot matrix

Headless, via the args above, on the usual simulator:

1. Card: default, Dynamic Type XXL, Reduce Motion (transition swap).
2. Sequence: card → Who's playing → framed empty state, and Skip's short-cut.
3. Each of the seven marks, screenshotted on its screen (`-coach X`), including
   one inside a scrolled list to prove the anchor tracks.
4. Arbiter: two eligible marks on one screen (`-coach firstTap` while uncheck
   conditions hold) → exactly one balloon.
5. Popup collision: mark up, popup opens → balloon stands down.
6. Gating: `-demoData` (an existing install) never shows the card; fresh
   container shows it once; second launch shows nothing.
7. Existing-user simulation: profile set + trips present + empty ledger → no
   welcome, marks still fire per their triggers (this is the actual migration
   case every current user hits).
7b. Restored install (`-demoData -forgetMe`): the pick-your-face list, **no
   welcome card over it**, and no second player created by tapping through. The
   failure this guards is the worst one in the app — your whole collection
   arriving as a stranger under Settings → Other people.
8. VoiceOver spot check by hand: announcement fires, balloon focusable — the
   one item that needs a human ear.

---

## 8. Build order

1. **`Coach` + `CoachPresenter` + `CoachMark`/`CoachLayer`** — everything
   stands on these. Prove the anchor-in-ScrollView case first; it is the only
   technically risky piece of the plan.
2. **`firstTap` mark** — smallest full slice through ledger → arbiter →
   balloon → done-condition.
3. **Welcome card + sequencing + fork framing** — the Layer-1 spine.
4. **`swipeTrip`, `uncheck`, `doneTrip`** — the three features that motivated
   onboarding in the first place.
5. **How to play page** + Settings voice-card slimming.
6. **Remaining marks** (`trailScope`, `spotterChip`, `listLength`) — polish
   tier, shippable without them.

Each step builds and screenshots before the next; 1–4 are the release bar,
5–6 can trail.

**Status.** All six steps are built and verified on the simulator.

> **Step 6 turned up two things the plan had no way to predict.**
>
> **A balloon can point off the page.** The anchor doc claims a scrolled-away
> target makes its balloon fade, and in a *lazy* container that is true — the
> view stops existing and takes its anchor with it. The trips list is a plain
> `ForEach` in a `ScrollView`, so every row is realised at all times, and the
> ninth one reports a rect a few hundred points below the page. `doneTrip`
> promptly clamped itself to the bottom edge and aimed at the tab bar.
> `CoachLayer` now declines to draw a mark whose target is not on screen; it
> keeps its turn and appears the moment its subject is scrolled to, which is
> the only moment it means anything.
>
> **`listLength` cannot point at its own subject.** The plan aimed it at the
> Finished header, then this build aimed it at the oldest running row. Both are
> the right *subject* and both are unreachable: in a list long enough to fire
> the trigger the oldest row is below the fold, and somebody with nine running
> trips and nothing finished has no Finished header at all — which is exactly
> who the tip is for. It hangs off the head of the list instead, and the copy
> names the list in its first clause ("That's a lot of trips going at once")
> so the arrow is read as pointing at the stack rather than at one trip. It is
> the only mark here about a screen rather than about a control.

---

## 9. Explicitly out of scope (so it stays out)

- Any animated tour, video, or Lottie. The app draws its own everything.
- Interactive fake data ("try tapping this sample plate") — the first real
  plate is minutes away; teaching on fakes cheapens it.
- Notification-driven re-engagement ("finish setting up!"). The reminders
  system nudges quiet *trips*; onboarding never pings.
- Per-feature "what's new" changelogs on update. Different problem.
- The welcome card settle-in animation and balloon idle float — noted as
  polish, cut from v1.
- A11y beyond §3.1's spec (e.g., a guided VoiceOver tour) — the app's existing
  labels are the tour.

## 10. Risks, named

- **Anchor preferences across ScrollView + LazyVGrid.** A lazily-recycled tile
  can drop its anchor when scrolled far off-screen. Mitigation: `firstTap` and
  `uncheck` anchor to the first *visible* eligible tile at fire time and do not
  chase it; if its anchor vanishes (scrolled away), the balloon fades rather
  than jumps. Step 1 of the build order exists to burn this risk down first.
- **Balloon over the tab bar / under the nav bar** on small screens at big
  type: `CoachLayer` clamps to safe-area insets and flips sides before
  clipping.
- **Copy drift.** Every string in this plan is a draft; the build-time pass
  applies the copy rules (user-directed, tab names, single-literal keys) and
  whatever reads wrong in a real screenshot gets rewritten there, not defended
  here.
