# Device-to-Device Multiplayer — The Party Plan

How Plates becomes a party game: one person hosts a trip, everyone in the car
joins from their own phone, and every sighting anyone logs appears on every
screen. The party **replaces** the current shared-device multiplayer — the
hand-added player roster and the "who spotted it?" popup are retired in the
same release (§2a). This document is the complete plan — what to build, in
what order, and exactly why it cannot break anything that already works.

Everything in here was verified against the code as of 2026-08-04 (branch
`main`, on top of commit `f27967e` plus the uncommitted working tree). File and
line references are to that state.

---

## 0. The headline: zero schema changes

The original sketch assumed `Sighting` would need new fields (an author-device
tag, a logical clock), which would mean a CloudKit production schema deploy —
the additive-and-permanent, only-fails-in-TestFlight step that
`PlatesStore.swift` warns about at length. **Careful reading shows none of that
is necessary.** The whole feature ships with:

- **No new `@Model` types.** The schema stays `[Trip, Book, Player, Sighting]`.
- **No new properties on any model.** Every field the wire protocol needs
  already exists.
- **No CloudKit Console visit.** Nothing to deploy, nothing that can produce
  CKError 2 in front of testers.

Why each presumed field turned out to be unnecessary:

| Presumed field | Why it isn't needed |
|---|---|
| `Sighting.authorDeviceID` (anti-echo) | Echo only happens if received data re-enters the broadcast path. Live broadcasts fire from `PlateLogger.record` (the single write path for taps, Siri, and voice — `PlateLogger.swift:23`). Received sightings are applied through a separate merge function that never calls `PlateLogger`, so nothing received is ever re-broadcast. Full snapshots intentionally contain everything and are idempotent, so they don't care about authorship either. |
| `Sighting.lamport` (concurrency ordering) | All scores and attributions are *derived* from the sighting set (`Scoring.swift` header: "the only way to change a count is to add or remove a Sighting"). Once two devices hold the same set, they compute the same answers. Determinism needs only a tie-break on equal `spottedAt` values — a pure code change (§4.1), not a stored clock. |
| `Player.isRemote` (roster tagging) | Peers become ordinary `Player` rows. The model already means "people in the car" (`Models.swift:27`); the party just adds them automatically instead of by hand. |
| Removing `Player` from the schema (since its management UI is retired) | Never do this. The model stays: every existing sighting's attribution, every old trip's standings, and the CloudKit record type (which is permanent in production anyway) depend on it. What gets retired is the *UI for hand-managing* players (§2a), not the data. |

Consequences: every phase below is additive Swift code plus two Info.plist
keys. The one place the plan touches existing behavior is a tie-break refinement
in `Scoring.swift` that is a no-op except on exact timestamp collisions.

---

## 1. Why this codebase is unusually ready

1. **`Sighting` is the only fact.** Every count, score, standing, tier, map
   fill, and trail pin derives from `sightings` (`Scoring.swift`, `PlateIndex`).
   Syncing sightings *is* syncing the game. There are no counters to reconcile
   and no caches to invalidate.
2. **Sightings are conflict-free by construction.** `Sighting.id` is a UUID
   minted at creation (`Models.swift:410`), so two phones can never collide.
   Applying the same sighting twice is detectable by id. Un-tapping deletes
   rows; re-spotting mints new ids. That is a two-phase set — add-once,
   remove-once — the simplest CRDT there is. Tombstones for removals are the
   only bookkeeping.
3. **`rarityWhenSpotted` is frozen onto the sighting** (`Models.swift:432`,
   banked in `PlateLogger.swift:36`). Rarity travels as data. If it were
   recomputed per device it would diverge instantly (different GPS fixes);
   because it's banked, peers agree by definition.
4. **There is exactly one write path.** Grid tap, Siri intent, and voice mode
   all go through `PlateLogger.record` — the file's own comment explains it was
   built to end drift between three copies. That is the single hook point for
   "broadcast what I just logged."
5. **Removal paths are few and known.** Three, total:
   - `GameScreen.swift:732` `clear(_:in:)` — un-tap deletes all sightings of a code
   - `VoiceModeScreen.swift:349` — voice undo deletes the newest sighting
   - `TripsScreen.swift:303` — trip delete cascades (party must already be over; §7)
6. **The transport question answers itself.** This is a car game. The party is
   people within arm's reach, road trips go through dead zones, and the moments
   the game is most alive are exactly the moments there is no signal. That
   rules out anything server-shaped and rules in **MultipeerConnectivity**:
   no account, no network, no CloudKit sharing (which SwiftData doesn't support
   anyway — CKShare requires custom zones and a drop to Core Data or raw
   CloudKit). Local-first also means the existing per-account iCloud backup is
   untouched: it keeps doing exactly what it does today, and as a bonus every
   party member ends the trip with their own durable copy.

---

## 2. Party semantics (the product decisions, made explicit)

- **A party is a Trip.** The trip's UUID is the party id. Books stay
  single-player — they are lifetime personal collections with no journey, and
  sharing one is a different product. The party UI simply doesn't offer books.
- **Host creates, others join.** The host opens (or creates) a trip and starts
  a party. Joiners discover it over local networking, confirm a 4-character
  code the host's screen displays, and receive a full snapshot.
- **One device, one player.** Every device has exactly one identity — its
  *device player* (§2a) — and every sighting it logs is attributed to that
  player, from the grid, Siri, and voice alike. The old "who spotted it?"
  popup is gone: in a party the phone *is* the person, so there is nobody to
  ask.
- **Anyone can un-tap a plate**, matching today's single-device rule where
  `clear` removes every sighting of the code regardless of spotter. The
  removal broadcasts as a tombstone.
- **Trip settings are host-owned during a party.** `scoringMode` and
  `includesTrucks` change what every score means; a mid-party flip would
  silently rewrite everyone's game. Non-hosts see them read-only while
  connected; host changes broadcast.
- **The party ends; the data stays.** Ending the party (or the trip) just stops
  the radio. Every device keeps its full local copy of the trip, its
  sightings, and the roster — which then rides each person's own iCloud backup.
- **Concurrent same-plate taps need no arbiter.** If two people tap Ohio in the
  same second, both sightings exist. The trip total counts the distinct code
  once; per-player standings each credit their own sighting — which is exactly
  what `score(for:)` already computes (`Scoring.swift:108`). `claimedRarity`
  (first-by-`spottedAt`) and the spotter chip (last-by-`spottedAt`) resolve
  deterministically once the sets merge (§4.1). Clock skew between phones can
  decide a genuine photo-finish "wrong" by a second or two; consistent
  everywhere beats fair-to-the-millisecond, and no one in the back seat is
  timing it.

### What is shared vs. what stays local on `Trip`

`Trip` mixes party-wide facts with this-phone-only state. The snapshot and
`tripUpdate` messages carry **only** the shared columns; merge code must never
write the local ones:

| Shared (in the wire snapshot) | Local (never sent, never overwritten) |
|---|---|
| `id`, `name`, `startedAt`, `endedAt` | `currentLat`, `currentLon`, `locatedAt` (this phone's fix — feeds live rarity) |
| `origin`, `destination` + their coordinates | `pinnedAt` (a preference about *your* lists) |
| `scoringModeRaw`, `includesTrucks` | `archivedAt` (ditto) |

### Roster

- On join, each device sends its device player (id, name, colorIndex,
  joinedAt). Everyone merges everyone: peers become ordinary `Player` rows,
  fetched-by-id-before-insert so re-joins don't duplicate.
- **Color collisions** (two "Me, color 0" players) are resolved
  deterministically: order all party players by `(joinedAt, id)`, and any
  player whose `colorIndex` is already taken by an earlier one moves to the
  lowest free index. Every device runs the same rule on the same data, so all
  screens agree without a negotiation message. Only *remote* rows are moved —
  your own device player's color choice is never overridden on your own
  screen's behalf; if two people insist on the same color, the later joiner's
  row shifts everywhere, including on their device.
- Because hand-adding players no longer exists (§2a), the duplicate-identity
  problem the roster used to face — the host adds "Mia" by hand, then Mia
  joins from her own phone as a second row — **cannot arise for new trips**.
  Legacy rows from the retired feature are the one place it lingers; §2a
  covers them.

### 2a. Sunsetting shared-device multiplayer

Today "multiplayer" means several `Player` rows on one phone: a management
screen behind the More tab, a "who spotted it?" popup on every tap when
`players.count > 1`, and a speaker picker in voice mode. Running that model
*alongside* the party would be incoherent — a tap would have to ask "who
spotted it?" about people who each have their own phone in hand — so the party
replaces it outright, in the same release. What that means, precisely:

**The device player.** Each install designates exactly one `Player` row as
"me": its UUID goes in `UserDefaults` under `devicePlayerID`. Resolution on
first launch after the update: the row the id points at if valid, else the
earliest-`joinedAt` player (the seeded "Me" for almost every install), else a
freshly seeded one. `seedIfNeeded` (`PlatesStore.swift:113`) is unchanged —
the "Me" it already creates simply becomes the device player. Note
`UserDefaults`, deliberately not `NSUbiquitousKeyValueStore`: an iPhone and
iPad on one iCloud account share their `Player` rows via CloudKit and will
independently resolve to the same "Me" row, which is correct — they are the
same human.

**Settings grows a "Playing as" card** — name and color, editing the device
player. It reuses `PlayerEditor` (`PlayersScreen.swift:196`), which survives
the retirement precisely because it edits one player; only the roster
management around it goes. A card that sets something passes the
Settings-is-for-controls rule (`SettingsScreen.swift` header).

**What is deleted** (all in the release that ships Phase 2):

- `GameScreen.tap` (`GameScreen.swift:664`): the `players.count > 1` branch
  and `askWhoSpotted` (line 678) — a tap always records as the device player.
- The `addingPlayer` sheet and the "Playing with others? Add players" hint
  (`GameScreen.swift:48`, `:311`, `:394`) — the hint becomes "Playing with
  others? Start a party", opening `PartyScreen`.
- The `-popup who` debug case (`GameScreen.swift:262`, `:300`) — the popup it
  demonstrates no longer exists.
- `VoiceModeScreen`'s speaker picker and its spoken "who is logging?" question
  (`VoiceModeScreen.swift:56`, `:183`, `:280`) — voice always logs as the
  device player, and the `players:` parameter goes with it.
- `PlayersScreen` minus `PlayerEditor`: the roster list, add-player button,
  and remove-player flow. The More tab's "Players" row
  (`MoreScreen.swift:25`) becomes the "Party" row.

**What survives untouched, because it renders data rather than the feature:**

- `PlayerStrip` standings (`GameScreen.swift:389`) — shown whenever the trip's
  sightings involve more than one player, which now means a party trip or a
  legacy trip. Same for spotter chips (`GameScreen.swift:588`) and
  `standings(among:)`.
- Every existing trip's attributions, scores, and per-player history. Legacy
  `Player` rows are never migrated, merged, or deleted — they just stop being
  editable as a roster.

**Two honest costs, both accepted for v1:**

1. **Phoneless passengers lose their standings entry.** Today one phone can
   score four kids in the back seat; after the sunset, people without a device
   in the party share the host's score. This is a real regression for that
   use case, traded for coherence. The escape hatch, if it's ever missed, is
   a "guest riders" list on the party screen — host-attached players with the
   old who-popup scoped to guests only. Explicitly out of scope now.
2. **Installs mid-trip with multiple players change behavior on update:** the
   who-popup vanishes and everything logs as "Me". A one-time popup on first
   launch when >1 players exist ("Multiplayer is now a party — everyone plays
   from their own phone") says so instead of letting them discover it.

---

## 3. Architecture

```
                    ┌──────────────────────────────┐
   PlateLogger ─────▶                              │
   (all logging)    │   PartySession (@Observable) │────▶ MCSession ⇄ peers
   clear()/undo ────▶   • roster & connection state│
                    │   • outbox: encode & send    │
                    └──────────────┬───────────────┘
                                   │ received envelopes
                                   ▼
                    ┌──────────────────────────────┐
                    │   PartyMerge (pure functions)│──── writes ModelContext
                    │   idempotent apply(...)      │     (never PlateLogger)
                    └──────────────────────────────┘
                                   ▲
                    PartyTombstones (sidecar JSON, keyed by trip UUID)
```

New files (all under `Plates/`, which is a folder-synced group — **no
`project.pbxproj` edits needed**, the same property that let this whole app
grow without touching the project file):

| File | Contents |
|---|---|
| `Plates/Domain/Party/PartyWire.swift` | Versioned `Codable` envelope + payload structs. Pure data, no imports beyond Foundation. |
| `Plates/Domain/Party/PartyMerge.swift` | Idempotent apply functions: snapshot, sighting, removal, roster, trip update. The only file that writes received data into SwiftData. |
| `Plates/Domain/Party/PartyTombstones.swift` | Removed-sighting UUIDs per trip, persisted as JSON in Application Support (deliberately *not* a `@Model` — that would reopen the CloudKit schema). |
| `Plates/Domain/Party/PartySession.swift` | `MCSession` + advertiser + browser lifecycle, join-code check, snapshot-on-connect, outbox. `@MainActor @Observable`, with a static `shared` optional — `nil` means "no party", and every hook is a one-line optional call. |
| `Plates/Screens/PartyScreen.swift` | Host/join sheet: start party (shows code), nearby-party list, connected-member list, leave/end. Built from `SettingsGroup`/`PopupPicker` idioms the app already has. |

### The wire protocol (`PartyWire.swift`)

```swift
struct PartyEnvelope: Codable {
    static let version = 1
    var v: Int = PartyEnvelope.version
    var payload: Payload

    enum Payload: Codable {
        case hello(HelloSnapshot)      // full state: trip + roster + sightings + tombstones
        case sighting(SightingEvent)   // one new sighting, live
        case remove([UUID])            // tombstones for un-tap / voice undo
        case roster([PlayerEvent])     // players added on some device
        case tripUpdate(TripPatch)     // host-only: name/route/mode/trucks/ended
        case bye                       // clean leave / party ended
    }
}

struct SightingEvent: Codable {   // mirrors the model exactly — all fields exist today
    var id: UUID
    var plateCode: String
    var spottedAt: Date
    var tripID: UUID
    var playerID: UUID?
    var rarityWhenSpotted: Int?
    var spottedLat: Double?
    var spottedLon: Double?
}
```

A mismatched `v` on hello politely refuses the join ("Someone needs to update
Plates") instead of half-working. Sixty sightings is ~12 KB of JSON; there is
no delta protocol and there must not be one — **snapshot-on-every-connect makes
first join, rejoin after a locked phone, and recovery from a dropped session
the same code path**, and that one property is worth infinitely more than the
kilobytes.

### Merge rules (`PartyMerge.swift`)

All idempotent; applying any message (or the whole snapshot) twice is a no-op.
SwiftData + CloudKit forbids `@Attribute(.unique)`, so uniqueness is enforced
here, by fetch-before-insert on the `id` field:

- **Sighting**: skip if id exists locally **or** is tombstoned. Otherwise
  insert, look up `trip`/`player` relationships by UUID (player may lawfully be
  nil — unowned sightings are already legal, `Models.swift:417`).
- **Removal**: add ids to tombstones, delete matching local rows.
- **Player**: fetch by id → update name/color, or insert. Then run the color
  de-collision rule (§2).
- **Trip** (snapshot/patch): fetch by id → update *shared columns only*, or
  create. A joiner who played this trip in a previous session merges instead
  of duplicating — rejoin falls out for free.
- One `context.save()` per envelope, after the batch.

### Hooks into existing code — the complete list

Until the sunset lands, the footprint on existing files is three one-liners
plus one localized refinement (the sunset's own deletions are enumerated in
§2a and land with Phase 2):

1. `PlateLogger.record` (`PlateLogger.swift:41`, after `context.save()`):
   `PartySession.shared?.broadcast(sighting)` — guarded to fire only when the
   sighting's trip is the party trip.
2. `GameScreen.clear` (`GameScreen.swift:732`): collect the deleted ids,
   `PartySession.shared?.broadcastRemoval(ids)`.
3. `VoiceModeScreen` undo (`VoiceModeScreen.swift:349`): same, one id.
4. **Determinism tie-breaks in `Scoring.swift`** (§4.1).

Sightings arriving mid-celebration change nothing: the grid derives from the
store, SwiftUI re-renders on the context change, and peer finds deliberately do
**not** trigger local confetti — v1 shows a small toast ("Mia found MONTANA —
epic") because two phones erupting for one plate is noise, and the find banner
is the *spotter's* reward. (`FindBanner` and tier haptics stay exactly as they
are; the toast is new, small, and optional to build.)

---

## 4. Phases

### Phase 0 — Determinism + wire + merge (no networking, no UI, no risk)

The foundation, fully testable without a second device:

1. **Tie-breaks** (§4.1 below) in `Scoring.swift`.
2. `PartyWire.swift` — envelope + payloads + version.
3. `PartyMerge.swift` + `PartyTombstones.swift`.
4. **Prove it in a harness**: build snapshot from a `DemoData` trip → apply
   into a fresh in-memory `ModelContainer` → assert identical
   `score(for:)`, `standings`, `claimedRarity`, spotter for every code →
   **apply the same snapshot again → assert nothing changed** → apply a
   removal → assert the plate is gone and stays gone through a re-snapshot.
   (No test target exists yet; a DEBUG-only launch flag in the
   `-openTrail`/`-noCloud` style — `-partyMergeCheck`, asserting and printing
   PASS/FAIL to the console — fits how this app already verifies itself.
   Adding a real XCTest target is better if you're willing to touch the
   project file; the flag needs nothing.)

#### 4.1 The tie-break change, precisely

Three derivations currently order equal-`spottedAt` sightings arbitrarily —
harmless on one device, divergent across two:

- `PlateIndex.init` (`Scoring.swift:37`): `if s.spottedAt >= e.latestAt` makes
  the *array-order-last* equal sighting win, and relationship array order is
  not guaranteed to match across devices. Compare `(spottedAt, id.uuidString)`
  tuples instead.
- `claimedRarity(of:)` (`Scoring.swift:149`): `.min { $0.spottedAt < $1.spottedAt }`
  → min by the same tuple.
- `spotter(of:)` (`Scoring.swift:72`): `.max { $0.spottedAt < $1.spottedAt }`
  → max by the same tuple.

Identical results everywhere except exact timestamp collisions, where the
result was undefined before. **This is the only behavior change to existing
code in the entire plan.**

### Phase 1 — Transport + party UI

1. `PartySession.swift`: service type `plates-party` (12 chars — within the
   15-char limit), `MCSession` with `encryptionPreference: .required`,
   advertiser carrying `{trip name, host name}` in `discoveryInfo`, join code
   checked in the invitation context. On `.connected`: host sends `hello`.
2. **Info.plist** (`ios/Info.plist` — the hand-maintained one that exists
   precisely for keys the `INFOPLIST_KEY_*` build settings can't express):

   ```xml
   <key>NSLocalNetworkUsageDescription</key>
   <string>Plates uses the local network to find the other phones in your car and share sightings during a party.</string>
   <key>NSBonjourServices</key>
   <array>
       <string>_plates-party._tcp</string>
       <string>_plates-party._udp</string>
   </array>
   ```

   Both `_tcp` and `_udp` — MultipeerConnectivity uses both, and missing the
   udp entry is the classic silent-discovery-failure. iOS shows the
   local-network permission prompt on first advertise/browse.
3. `PartyScreen.swift` + entry point: a "Party" row where trip actions already
   live. Custom browse UI (not `MCBrowserViewController` — it would look like a
   different app).
4. Wire the three broadcast hooks (§3).

### Phase 2 — Roster, rules & the sunset

Roster merge + color de-collision; host-locked trip editing while connected
(disable the editor's mode/trucks controls for non-hosts; host edits →
`tripUpdate`); the peer-find toast.

Plus the whole of §2a, in this order so the app never lacks a multiplayer
story mid-phase:

1. Device-player resolution (`devicePlayerID` + fallback chain) and the
   Settings "Playing as" card — additive, shippable alone.
2. Route all logging through the device player: `GameScreen.tap`, voice mode,
   Siri (`PlatesStore.currentTarget` callers already pass a player through
   `PlateLogger`; they switch to the device player).
3. Delete the retired UI: who-popup, add-player sheet and hint, speaker
   picker, `PlayersScreen` roster (keeping `PlayerEditor`), `-popup who`.
4. Swap the More tab's "Players" row for "Party" and add the one-time
   migration popup for installs with >1 players.

The retirement must not ship *before* the party (that removes multiplayer with
no replacement) nor linger *after* it (two competing models, and the
who-popup would interrogate people holding their own phones). Same release,
one story.

### Phase 3 — Edges

- **Reconnect**: MC sessions die when a phone locks or backgrounds. The
  session keeps advertising/browsing while the party is open and re-snapshots
  on every reconnect — already the design, just needs the retry loop.
- **Host leaves**: `bye` → members keep playing locally and may re-host the
  same trip (same UUID → everyone re-merges; nothing lost). True host handoff
  is a non-goal for v1.
- **Guard rails**: deleting a trip (`TripsScreen.swift:286`) or marking it
  done while its party is live → end the party first, with the same
  confirm-dialog pattern the screen already uses.
- **Same-account devices**: one person's iPhone and iPad share an iCloud
  account, so CloudKit may deliver a sighting that MC also delivered. The
  merge already handles it — same UUID, second arrival is a no-op. (CloudKit
  dedupes nothing itself; the fetch-before-insert rule is what makes this safe.)

---

## 5. Verification plan

- **Phase 0**: the `-partyMergeCheck` harness above; run on one simulator.
- **Phase 1+**: two simulators (`xcrun simctl` can boot a second device
  alongside the iPhone 17 fixture). MC discovery between two simulators on one
  Mac generally works but is known to be flaky; the reliable rig is
  simulator + a real device, or two devices. Test explicitly: join → snapshot
  arrives → tap on A appears on B → un-tap on B removes on A → lock B, tap on
  A twice, unlock B → both arrive via re-snapshot → kill and relaunch B →
  trip intact, rejoin merges cleanly, standings identical on both (this is
  the tie-break payoff — compare *every* number, not just the totals).
- **Permission prompt**: first party start must show the local-network prompt;
  denial must degrade to a clear "Plates needs local network access —
  Settings" row, in the pattern `SettingsScreen.openSettings` already uses.

---

## 6. Risk register — why nothing breaks

| Risk | Standing |
|---|---|
| CloudKit production schema | **Eliminated.** No model or field changes; nothing to deploy; CKError 2 impossible from this work. |
| Existing single-player behavior | Three added one-line hooks, all no-ops when `PartySession.shared == nil` (always, until the user starts a party). Plus the tie-break, which only changes undefined-order cases. With one player — the overwhelmingly common install — the sunset changes nothing either: `tap` already skips the who-popup and records as the only player, which is exactly what the device-player path does. |
| Legacy multi-player installs | Historical data fully preserved and rendered (standings, chips, scores). Behavior change on update — no more who-popup — is announced by the one-time migration popup (§2a), not silently discovered. |
| Phoneless passengers | Genuine v1 regression, accepted deliberately; "guest riders" documented as the future escape hatch (§2a). |
| iCloud backup | Untouched — same container, same `.automatic` config, same fallback. Peer data becomes part of your local store and therefore your backup; that is the design (your copy of the trip), noted as a privacy point below. |
| Data loss | Additive only. Merge never deletes except explicit tombstones from an explicit user un-tap. Trip/book/player deletion flows unchanged. |
| MC 8-peer ceiling | Fine — 7 joiners + host is more than a car. (The player cap was already removed; the *party* is capped by physics, not code.) |
| Peer availability | Snapshot-on-connect means any device can drop and return with zero special-case code. |
| Privacy | Shared: player first names, color indices, sightings (with coordinates when location is on — worth one line in the join UI: "your sighting locations are shared with the party"). Never shared: `currentLat/Lon` live fixes, pins, archives, books. Traffic is peer-to-peer and encrypted (`.required`); no server ever sees it. |
| Version skew | Envelope `v` check refuses cleanly at hello. |

## 7. Non-goals (v1)

Remote/apart play (would require CloudKit sharing — a Core Data or raw-CloudKit
rewrite of the persistence layer), book sharing, host handoff, spectator mode,
cross-account player identity, "guest riders" for phoneless passengers (§2a),
and any server. None are foreclosed by this design: the wire format is
versioned, and a future remote transport would carry the same envelopes over a
different pipe.

---

## 8. Order of work, restated as a checklist

**Phase 0 is complete and verified** (see §9).

- [x] `Scoring.swift` tie-breaks (`PlateIndex`, `claimedRarity`, `spotter`)
- [x] `PartyWire.swift`
- [x] `PartyTombstones.swift`
- [x] `PartyMerge.swift`
- [x] `-partyMergeCheck` harness — must pass before any networking exists
- [ ] `PartySession.swift`
- [ ] Info.plist: `NSLocalNetworkUsageDescription`, `NSBonjourServices` (tcp + udp)
- [ ] `PartyScreen.swift` + entry point
- [ ] Three broadcast hooks (`PlateLogger`, `GameScreen.clear`, voice undo)
- [ ] Two-simulator smoke test of the Phase-1 loop
- [ ] Roster merge + color rule + host-locked editing + peer-find toast
- [ ] Device player: `devicePlayerID` resolution + Settings "Playing as" card
- [ ] Route grid / voice / Siri logging through the device player
- [ ] Delete: who-popup, add-player sheet + hint, speaker picker,
      `PlayersScreen` roster (keep `PlayerEditor`), `-popup who`
- [ ] More tab: "Players" row → "Party" row; one-time migration popup
- [ ] Legacy check: a store with 3 hand-added players and old trips still
      renders standings, chips, and scores identically after the update
- [ ] Reconnect loop, guard rails on trip delete/finish, `bye` handling
- [ ] Device test in an actual car

---

## 9. Phase 0 as built

Shipped as four new files under `Plates/Domain/Party/` plus the tie-break, with
no schema change and no project-file edit, exactly as planned.

| File | What it holds |
|---|---|
| `PartyWire.swift` | `PartyEnvelope` (versioned) + `PartySnapshot`, `SightingEvent`, `RemovalEvent`, `PlayerEvent`, `TripEvent`. No SwiftData import. |
| `PartyTombstones.swift` | Per-trip withdrawn ids, JSON in Application Support. `init(url: nil)` gives a memory-only instance for the harness. |
| `PartyMerge.swift` | Snapshot building + idempotent apply. Fetch-before-insert on `id`; one `save()` per envelope. |
| `PartyMergeCheck.swift` | The `-partyMergeCheck` harness. DEBUG-only. |

Two decisions worth recording because they are load-bearing and invisible:

- **`dateEncodingStrategy = .deferredToDate`, explicitly set.** `spottedAt` is
  half of `SightingOrder`, so a strategy that rounds — `.iso8601` drops
  sub-second precision — would hand sender and receiver *different* timestamps
  for the same sighting and desync their answers while looking perfectly
  reasonable in a debugger. The harness asserts bit-exactness against a
  deliberately awkward instant.
- **Tombstones are applied before sightings** when a snapshot lands, so a
  withdrawn plate is never inserted at all rather than inserted and deleted a
  line later.

### What the harness checks

Five cases, all against in-memory stores: the full round trip (every derived
number, not just totals), double-apply idempotence, removals surviving a stale
re-snapshot, tie determinism under reversed insert order, and exact date
round-tripping plus refusal of a newer protocol version. The fixture is
deliberately nastier than `DemoData` — same-instant collisions on two plates
(one deciding `spotter`, one deciding `claimedRarity` and therefore the score),
an unowned sighting, a repeat, and plates with and without coordinates.

**The harness was mutation-tested rather than trusted.** Reverting the
`PlateIndex` tie-break to date-only produced `spotter=Theo` on the source and
`spotter=Mia` on the peer — precisely the two-phones-disagree bug, caught.
Removing the idempotence guard produced doubled counts on the second apply,
also caught. Both were then reverted and the real code re-verified as PASS. A
green harness that cannot go red proves nothing; this one goes red for both
failures it exists to prevent.

Run it with:

```bash
xcrun simctl launch --console-pty <UDID> com.eggeppel.plates -partyMergeCheck -noCloud
```
