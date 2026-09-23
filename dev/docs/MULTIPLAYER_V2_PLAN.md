# Multiplayer Part II — Identity, Rules, and Shared Books

Follow-on to [MULTIPLAYER_PLAN.md](MULTIPLAYER_PLAN.md), whose Phases 0–3 are
built and verified. This plan covers what live testing surfaced plus the two
feature requests: proper player identity, party rules, the roster/standings
bug, party-trip badging, the avatar-stack treatment, and long-term shared
books over CloudKit.

Verified against the code as of 2026-08-05. Everything up to §5 needs **no
schema change**. §6 (shared books) is the one that finally forces the CloudKit
production deploy, and it is isolated so nothing else waits on it.

---

## 1. The bug first: ghost players scoring on every trip

**Report:** a fresh trip shows "Me, Dad, Mia, T…" all at 0 — players from an
old party (or the demo fixture) appear on games they were never part of.

**Root cause, precisely:** `GameScreen.swift:399`:

```swift
PlayerStrip(standings: collection.standings(among: players))
```

where `players` is `@Query(sort: \Player.joinedAt)` — **every `Player` row in
the store**. That was correct in the shared-device era, when the store's
players were by definition the people in the car. Phase 2's roster merge broke
the assumption: partying once inserts the other phones' players into your
store permanently (by design — history needs them), so every trip's strip now
shows everyone you have ever met, at 0. The same stale assumption gates the
strip (`players.count > 1`, line 398), the spotter chips (line 600), and the
same pattern sits in `VoiceModeScreen` via its `players` parameter.

**Fix — scope players to the collection.** One new derivation in
`Scoring.swift`:

```swift
/// The people actually on this collection: everyone with a sighting filed
/// under it, plus (while a party is live on it) the party's members, plus
/// always the device player. NOT the whole Player table — that is everyone
/// you have ever met, which is a contact list, not a scoreboard.
func participants(all players: [Player], including me: Player?) -> [Player]
```

- Strip and chips render `standings(among: participants)` and hide when
  `participants.count <= 1` — a solo new trip goes back to showing no strip.
- Members of a *live* party on this trip appear at 0 before their first find
  (correct: they are playing), but leave no trace on your *next* trip.
- Old trips keep their real standings — participants includes everyone with a
  sighting, whoever they were.
- `Player` rows are still never deleted. This is a display-scoping fix, not a
  data change.

Acceptance: partied store → create new solo trip → no strip, no chips, no
ghost scores. Old party trip → full standings intact.

---

## 2. Player identity — "everyone is Me"

**The multiplayer problem being reported:** every clean install's device
player is the seeded `"Me"` (`PlatesStore.swift:128`). A three-phone party is
Me, Me, and Me — indistinguishable in the member list (MCPeerID displayName),
the standings, and the spotter chips. Colour de-collision separates the dots
but not the names.

**Fix — a profile, not an account.** Each install already has the two things
an account would provide: a stable unique id (`Player.id`, a UUID minted at
seed) and an editable name/colour (Settings → "Playing as"). What is missing
is the moment that makes someone *set* it. Deliberately no server, no email,
no password — a car game does not need a login, and CloudKit identity comes
free later for shared books (§6).

1. **First-launch naming.** After seeding, the first open of the Game screen
   presents "Who's playing?" — name field + colour row (reusing
   `PlayerEditor`), pre-filled "Me", one Save button. Skippable (dismiss keeps
   "Me") but shown once, in the same one-shot pattern as the migration notice
   (`DevicePlayer.migrationNoticeKey`).
2. **The party is the enforcement point.** Hosting or joining while the device
   player is still named "Me" (i.e. never customised — track with a
   `profileSetKey` flag, not by string-matching the name) interposes the same
   sheet first. Nobody enters a party unnamed; existing installs get caught
   here too.
3. **`MCPeerID` carries the player name** (it already does, via `myName`) —
   after this every surface showing a peer shows a real name.
4. Duplicate names are allowed (two Sams in one car is reality); identity is
   the UUID, colour separates them visually.

---

## 3. Party trips wear it in the Trips tab

A trip that was a party should be tellable at a glance. The store cannot say
which those are (multiple spotters is also true of legacy shared-device
trips), so parties are recorded where the party machinery already keeps its
local facts:

**`PartyLedger`** — a sidecar JSON in Application Support, same shape and
placement as `PartyTombstones` (deliberately not a `@Model`; §6 is the only
thing allowed to touch the schema). Written by `PartySession` on host and on
first join:

```swift
struct PartyRecord: Codable {
    var tripID: UUID
    var role: String          // "host" | "guest"
    var startedAt: Date
    var rules: PartyRules     // §4 — the ledger is also where rules persist
}
```

**In `TripRow`:** the row already has a marker vocabulary — route-blue spine
for playing, `car.fill`, `pin.fill`. A party trip adds a `person.2.fill`
glyph in a distinct tint (`Theme.paint` is taken by the pin; pick from the
player palette, e.g. the green) plus an `AvatarStack` (§5) of the
participants' initials at the row's trailing edge. Archived/finished party
trips keep the badge — "the trip we all did" is exactly what you want to find
again later. `TripEditor`'s header line says "Played as a party".

Cost of the sidecar approach, stated: the badge is per-device (not in iCloud
backup, lost on reinstall). Acceptable for a badge; §6's deploy is the moment
to promote it to a stored field if that ever rankles.

---

## 4. Party rules

Two rules, decided by the host, shown in a **Rules card on the host's Party
screen** (toggles, host-only), enforced identically on every phone.

```swift
struct PartyRules: Codable, Equatable {
    /// You can only take back your own plates. Default ON.
    var protectsClaims: Bool = true
    /// Tapping a plate somebody else already found claims it for you too,
    /// instead of doing nothing. Default OFF.
    var sharedClaims: Bool = false
}
```

### 4a. Protected claims — "you can't uncheck someone's found plate"

Today `GameScreen.clear()` deletes **every** sighting of the code, whoever
logged it, and the voice undo deletes the newest regardless of owner. In a
party that means one bored kid can strip the board.

With `protectsClaims` on (the default):

- `clear()` deletes only sightings whose `player` is the device player
  (unowned sightings count as yours — they came from this phone's Siri era).
  If none of the plate's sightings are yours, the tap does nothing but a
  denial haptic and a one-line toast: "Mia spotted that one."
- Voice undo walks back the newest sighting **of this device's**, not the
  newest overall.
- The tombstone/removal path is unchanged — it only ever carries what the UI
  allowed.
- Enforcement is at the action sites, not in `PartyMerge`. The merge stays
  dumb on purpose: the threat model is a sibling, not an attacker, and the
  merge staying a pure function of its input is what the Phase-0 harness
  proves. (Shared books get real enforcement for free from CloudKit ownership
  — §6.)

Off = today's behaviour: anyone can clear a plate, broadcast as removals.

Outside a party the rule is moot: solo, every sighting is yours.

### 4b. Shared claims — "multiple people can claim the same state"

Today, in classic/weighted, tapping a found plate *toggles it off*
(`tap()` → `hasSeen` → `clear`). With `sharedClaims` on:

- Tapping a plate that others found but **you** have not → logs your own
  sighting through `PlateLogger` (banked rarity from *your* car position, as
  ever). Both of you now score it — and here is the load-bearing fact:
  **`score(for:)` already handles this correctly.** Per-player scores count
  distinct codes among that player's own sightings, and the trip total counts
  the distinct code once (`Scoring.swift:144–168`). No scoring change at all;
  the rule only changes what a tap does.
- Tapping a plate you already claimed → protected-claims logic (take back
  yours, or nothing).
- Unlimited mode ignores the toggle — every tap already adds.
- The find card fires for *your* first claim of the plate (it is your find),
  but confetti is scaled down when the plate was already on the board — the
  banner moment belongs to the first spotter.

### 4c. Rules on the wire — envelope v2

Guests must enforce the same rules, so rules travel:

- `PartyEnvelope.currentVersion = 2`. `TripEvent` gains `rules: PartyRules?`
  (optional, so the struct decodes v1 payloads in tests) and the hello/
  tripUpdate paths carry it. Host toggling a rule mid-party → `tripUpdate` →
  every phone applies it live.
- Persisted per trip in the `PartyLedger`, so rules survive an app restart on
  every phone, not just the host's.
- v1↔v2: the version check already refuses cleanly with "someone needs to
  update Plates". The app is unreleased, so there is no v1 population to
  migrate — bump and move on, and note that *after* release, additions must
  become optional fields instead of version bumps wherever possible.

---

## 5. AvatarStack — the overlapping-circles treatment

One component, matching the screenshot: overlapping circles, ~30% overlap,
each with two-letter initials, capped with a "+N" overflow circle.

```swift
struct AvatarStack: View {
    let players: [Player]
    var max: Int = 4          // shows max-1 players + "+N" when over
    var size: CGFloat = 24
}
```

- Circle in the player's colour, two-letter initials (`Player.initials2`:
  first letters of the first two words of the name, else first two
  characters — "Aunt Deb" → AD, "Mia" → MI), `Theme.ink` text, and a 2pt
  ring in `Theme.surface` so overlapped edges read as separate circles on any
  background — the ring does the job the dark gap does in the screenshot.
- Overflow circle: neutral fill (`Theme.inkMuted` tint), "+N".
- Ordering: standings order where scores exist, join order otherwise, so the
  stack is stable rather than reshuffling per render.

Where it appears:

| Surface | Replaces |
|---|---|
| Party screen member list header | the plain iphone-glyph rows keep the detail list; the stack is the at-a-glance summary |
| `TripRow` for party trips (§3) | nothing — new |
| Plate tile under `sharedClaims`, when 2+ people claimed it | the single spotter chip (1 claimant keeps today's chip) |
| Trip editor header for party trips | nothing — new |

On the tile the stack renders at `size: 12` to match the current chip, capped
at 2 + overflow — a 5:3 tile cannot carry five circles.

---

## 6. Shared books — contribute to one book together, long-term

The different-in-kind feature: proximity radios cannot do "my friend adds
plates from another state on Tuesday". This is CloudKit sharing, and it is
the phase that finally spends the schema deploy the party avoided.

### What carries over unchanged (the Phase-0 dividend)

`PartyWire` imports neither SwiftData nor MultipeerConnectivity; `PartyMerge`
does not care where an envelope came from. Reused as-is: the envelope/payload
shapes, idempotent fetch-before-insert apply, tombstones, `SightingOrder`
determinism, and the `-partyMergeCheck` harness (which gains shared-book
cases). The transport swaps; the reasoning stays.

### Architecture decision, made now

**Raw CloudKit (`CKSyncEngine` + custom zone + `CKShare`) alongside SwiftData
— not a Core Data rewrite.** Rewriting persistence on `NSPersistentCloudKit-
Container` to get its sharing support would trade the whole working store for
one feature. Instead the shared book is its own small system: records in a
custom zone (`SharedBooks`), mirrored into SwiftData rows by the same merge
pattern the party uses. SwiftData's `.automatic` container keeps owning
private backup exactly as today.

- `SBBook` record (name, createdAt) and `SBSighting` records (the
  `SightingEvent` fields, `bookID` reference) in the owner's custom zone.
- `CKShare` on the book's record (zone-wide shares need the whole zone to be
  one book; per-record hierarchy is simpler to reason about) — invited via
  `UICloudSharingController` (Messages link), accepted via
  `CKShare.Metadata` in the scene delegate path.
- `CKSyncEngine` maintains push/pull; every remote change lands as events fed
  through a `SharedBookMerge` that is `PartyMerge`'s sibling: fetch by
  UUID-field, insert-or-skip, tombstones for removals (`CKRecord` deletion
  *is* the tombstone here — CloudKit does that bookkeeping for us).
- Participants' sightings carry their `playerID` + name + colour so the
  book's spotter chips and stacks work; `rarityWhenSpotted` banks each
  contributor's own local value — the same asymmetry that makes parties
  honest makes distributed contribution honest.

### The ownership model, stated so nobody is surprised

A party replicates — everyone leaves with their own copy. A shared book is
**one thing that lives in the owner's iCloud**. If the owner deletes it or
stops sharing, participants lose access (CloudKit's semantics, not ours). The
UI must say so: the share sheet's explanatory line, and a "Leave book"
(participant) vs "Stop sharing" (owner) distinction in the book editor.
Participants get an offered **"Keep a copy"** on leaving, which snapshots the
shared book into a local one — that is a plain `PartyMerge`-style copy and is
cheap to offer.

### Sub-phases

- **6a — Schema + zone.** Create zone, record types, and the *deploy to
  production* step (CloudKit Console → Deploy Schema Changes) — the CKError-2
  trap from `PlatesStore`'s warning, done once, before any UI exists.
  Nothing user-visible ships in 6a.
- **6b — Owner flow.** "Share this book" in the book editor →
  `UICloudSharingController`; local `Book` marked shared (ledger sidecar,
  again — `sharedBookIDs`); sightings logged to a shared book also written as
  `SBSighting` records.
- **6c — Participant flow.** Accept-share entry point, book appears in the
  Book tab with the owner's name under it, contributions flow both ways via
  `CKSyncEngine`; harness cases for double-apply, removal, and the
  two-writers-same-plate race (which `SightingOrder` already settles).
- **6d — Presence & polish.** AvatarStack of participants on the shared
  book's header; "Keep a copy" on leave; conflict copy for rename races
  (last-writer-wins is fine for a name).

Prerequisite: §2. Sharing with "Me" is the same bug the party had, and
CloudKit participants arrive with real Apple-account display names to
reconcile against.

### What shared books deliberately do NOT get in v1

Party rules (a lifetime book with `protectsClaims` off invites griefing that
a car does not — protection is simply always on: CloudKit already only lets
you delete your own records unless you own the zone), scoring modes (books
stay `.classic`, per `Models.swift`), and offline *invitation* (accepting a
share needs the network once; contributing after that queues offline via
`CKSyncEngine`).

---

## 7. Order of work

| Phase | Contents | Risk |
|---|---|---|
| **4** | §1 ghost-player fix, §2 identity/onboarding | None — display scoping + one sheet |
| **5** | §4 rules (+ wire v2), §3 trip badging, §5 AvatarStack | Low — enforcement sites are the three known write/remove paths |
| **6a–6d** | Shared books | The schema deploy, isolated in 6a |

4 and 5 are each shippable alone. 6 ships behind its sub-phases with 6a's
deploy done first and quietly.

- [x] 4: `participants` scoping in Scoring + strip/chips/voice call sites
- [x] 4: first-launch "Who's playing?" + party-entry naming gate
- [x] 4: two-simulator retest: new trip after party shows no ghosts; member
      list shows real names
- [x] 5: `PartyRules` + envelope v2 + ledger persistence + host Rules card
- [x] 5: protected claims at `clear()` / voice undo + denial toast
- [x] 5: shared claims in `tap()` + tile AvatarStack
- [x] 5: `PartyLedger` + TripRow badge + editor header line
- [x] 5: harness cases: shared-claim double-tap idempotence; protected-claim
      removal refused locally
- [x] 6a: record types, mapping and merge (built + harness-verified)
- [ ] 6a: **production schema deploy — needs the CloudKit Console (you)**
- [x] 6b: owner share flow (built, unverified)
- [x] 6c: participant accept + push/pull (built, unverified)
- [x] 6d: keep-a-copy is the default behaviour; shared badge + contributor stack on the book header

---

## 8. Phase 4 as built

One new derivation, one new preference, no schema change.

### The ghost players

`PlateCollection.participants(from:me:alsoPlaying:)` in `Scoring.swift`, and
three call sites moved onto it: the standings strip, its `> 1` gate, and the
spotter chips. `PartySession.roster(for:)` supplies the live-party half and
returns empty for every collection that is not the party's, which is what stops
a running party leaking into the trip beside it.

**Mutation-tested.** Reverting `participants` to return the whole player table
made the new harness case fail with exactly the screenshot: *"a brand new trip
lists nobody: got Dad, Mia, Nan, Theo"*. Restored, PASS. The case also pins the
two additive rules — this phone is always a participant, and so is anyone who
has joined the party but not yet called a plate.

Worth being straight about the evidence: the fix is proven at the data layer by
the harness, not by tapping through to a fresh trip on a partied device — that
needs taps I cannot make. The mutation reproduces the reported symptom exactly,
which is the strongest available substitute.

### Identity

- `DevicePlayer.profileSetKey` / `hasProfile` / `markProfileSet()`.
- Seeding sets the flag when players **already exist**, so an install that has
  been played for months is never asked to introduce itself. The `-demoData`
  path sets it too, or every screenshot run would open on the sheet.
- `PlayerEditor` gained `title`, `saveLabel` and `onSaved` (all defaulted, so
  existing call sites are untouched) and is reused verbatim as the profile
  sheet — "Who's playing?" / "Start".
- Two prompts: once on first launch of the Game screen, and as a gate in front
  of hosting or joining, which continues straight into the action it
  interrupted. Mutually exclusive with the migration notice, since an install
  with a roster to migrate already has names.

### Verified on two simulators

| Check | Result |
|---|---|
| Fresh install | "Who's playing?" appears, pre-filled "Me", colour row; no standings strip behind it |
| Distinct identities | Host `Ethan` (colour 0), guest `Mia` (colour 1) after de-collision |
| Member list | Host shows **Mia**, not "Me" |
| Attribution | Guest's Ohio credited to **Mia** on the host's store |
| Merge harness | PASS, including the new participants case |

### Debug flag added

`-asPlayer Mia` names the device player at launch. Two simulators both seed a
player called "Me", so without it a two-device party is two identical players
and the thing under test is invisible. DEBUG-only.

---

## 9. Phase 5 as built

Two new files (`PartyLedger`, `AvatarStack`), the wire at v2, and no schema
change.

### Rules

`PartyRules` lives in `PartyWire` because it travels; `TripEvent.rules` carries
it on both `hello` and `tripUpdate`, so a host toggling one mid-drive reaches
every phone live. Envelope bumped to **v2**: the field is optional and *would*
have decoded against v1 without complaint, which is exactly why a bump was
right — a v1 phone would have ignored the rules and happily stripped plates the
rest of the party had agreed were protected. A rule not everybody enforces is
not a rule.

Persistence is `PartyLedger`, a sidecar JSON beside `PartyTombstones` (still no
`@Model`, still no CloudKit deploy). It doubles as the record of *which trips
were parties*, which is what the Trips badge reads.

Rules are in force only while a session exists on that trip — keyed on the
session rather than on being connected, so a phone that drops out for a minute
does not briefly get permission to clear the board. Once the party ends the trip
on your phone is your copy and the ordinary rules resume.

- **Protected claims** (default on): `clear()` now takes a list of what may go,
  built by `removableSightings(of:by:protected:)`. Unowned sightings stay
  removable — they predate attribution or belonged to somebody since deleted, so
  protecting them would strand plates nobody alive could undo. Voice undo uses
  the same predicate, since "undo" said out loud is the easiest way in the app
  to take back somebody else's plate by accident.
- **Shared claims** (default off): a tap on a plate you have not personally
  claimed logs your own sighting instead of taking the plate off the board. **No
  scoring change was needed** — `score(for:)` already counts distinct codes per
  player and the trip total already counts the code once.
- Refusals surface as a one-line toast ("Mia spotted that one."), not a dialog.
  `PeerFindToast` generalised into `NoticeToast`, since a peer's find and a
  refusal are the same shape of message and neither earns the find card.

### AvatarStack

Overlapping circles, two-letter initials (`Player.initials2` — "Aunt Deb" → AD,
"Mia" → MI), ring drawn in the *background* colour so it reads as a gap rather
than a border, and a "+N" circle past the limit. Used on plate tiles with more
than one claimant (one claimant keeps exactly the chip it always had), and on
party rows in the Trips tab.

### Verified

| Check | Result |
|---|---|
| Rules card | Host-only, both toggles, protection on / shared off by default |
| Ledger written | `{"role":"guest","rules":{"sharedClaims":false,"protectsClaims":true}}` on the joining device |
| Trips badge | Party trip carries the green `person.2` glyph + ET/MI/TH stack; the guest's own trip carries neither |
| Tile stack | California claimed by two people renders MI/DA overlapping, legible at 13pt |
| Harness | PASS, including protected-claim permissions, unowned-plate removability, two claimants on one code, and rules surviving the wire |

### Not verified by tapping

The `tapFound` branch itself — shared-claim taps and refusal toasts — is proven
at the predicate layer by the harness, not by tapping a tile, which needs device
access I do not have. The predicates it composes (`hasClaimed`,
`removableSightings`, `claimants`) are each covered directly.

### Fixture change

`DemoData` now logs California twice, by two different players. Nothing else in
the fixture produced a plate with more than one claimant, so the tile stack had
no case to draw.

---

## 10. Phase 6a as built — and where I had to stop

Two new files under `Domain/Shared/`. **No schema change to SwiftData**, so the
app's own store is untouched; the CloudKit types below are new and are the thing
that eventually needs deploying.

| File | Contents |
|---|---|
| `SharedBookRecords.swift` | `CKRecord` ↔ model mapping, both directions, plus the zone/type/field names. Pure functions — no container, no account. |
| `SharedBookMerge.swift` | `PartyMerge`'s sibling: idempotent fetch-before-insert, contributor creation, deletions. |

### Design decisions worth keeping

- **Custom zone, and it has to be.** Records in the default zone cannot be
  shared at all. That single CloudKit fact is most of why shared books are a
  different mechanism from the party rather than a variation on it.
- **Sightings carry their contributor inline** (`playerID`, `playerName`,
  `playerColor`) instead of syncing a roster. There is no roster to sync: a
  CloudKit participant is an Apple account, not a row in your `Player` table,
  and the whole point of a shared book is somebody you may never sit in a car
  with. Three small fields per record buys working spotter chips and avatar
  stacks with no second sync channel.
- **Every sighting is `parent`ed to its book record.** That is what makes one
  `CKShare` on the book cover every plate in it; without it each sighting is an
  unshared island and the invitation hands over an empty book.
- **No tombstone sidecar.** CloudKit reports deletions as deleted record ids, so
  it does that bookkeeping for us. `PartyTombstones` exists only because a party
  snapshot re-sends everything it knows and has no other way to say "and not
  this one".
- **The field names are permanent.** A production CloudKit schema is additive
  and cannot be un-deployed; renaming anything after the first deploy means
  carrying both names forever.

### Verified

A full round trip through real `CKRecord`s built in memory: four sightings
(one deliberately unowned) out of one store and into another.

| Check | Result |
|---|---|
| Records built | 4, each parented to the book so one share covers them |
| Round trip | Name, plates, banked rarity, coordinates and contributor name all intact |
| Unowned stays unowned | No author invented for the orphan |
| Contributor created once | 1, from 4 sightings |
| Idempotence | Re-applying the whole batch adds nothing |
| Deletion | Applies, and the plate goes |

**Mutation-tested.** Removing the idempotence guard failed with *"re-applying
adds nothing: got 4, want 0"* — and, revealingly, also *"the deletion applied:
got 2, want 1"*, because the duplicate rows meant one withdrawal deleted two
plates. That second failure is exactly the silent corruption this layer exists
to prevent. Restored, PASS.

### Where I stopped, and why

**The simulator has no iCloud account.** `CKSyncEngine` cannot run, a `CKShare`
cannot be created, and an invitation cannot be accepted — accepting one needs a
*second, different* Apple ID on another device. None of that is testable in this
environment, and CloudKit code that has never once executed is precisely what
`PlatesStore`'s warning is about: it looks right, compiles, and fails in front
of testers.

So 6b–6d are **not** built. Writing an unexercised sync engine and share flow
and calling them done would be the least honest thing in this whole project.

### What has to happen next, in order

1. **You: deploy the schema.** CloudKit Console → container
   `iCloud.com.tagsmedia.tags` → Development → *Deploy Schema Changes*. The
   record types `SBBook` and `SBSighting` and the zone `SharedBooks` are created
   on demand in Development the first time the app writes one, so this is only
   possible *after* step 2 has run once on a real device. Read the diff before
   confirming: it is permanent.
2. **A real device with an iCloud account**, to write the first records and
   populate the Development schema.
3. **6b–6d**, testable from that point: owner share flow
   (`UICloudSharingController`), participant accept, `CKSyncEngine` wiring, then
   presence and "keep a copy".

A second Apple ID on a second physical device is the acceptance test for the
whole feature. There is no simulator substitute.

---

## 11. Avatars

A player can pick an emoji instead of initials. Twenty curated faces plus an
"initials" option, in `PlayerEditor` (so Settings → "Playing as" and the
first-run "Who's playing?" sheet both get it for free). Rendered by
`AvatarStack`, the plate-tile spotter chip, and the Settings card.

**This is the first SwiftData schema change in the project.** `Player.avatar` is
one optional `String` — the shape CloudKit requires — but it still needs a
production schema deploy before any build carrying it reaches TestFlight. It
can ride along with §6a's deploy; there is no reason to spend two.

It travels both transports: `PlayerEvent.avatar` on the party wire (an *optional*
field, so no version bump — a build that ignores it shows initials, which is a
real face rather than a broken one), and `playerAvatar` on `SBSighting` for
shared books, alongside the name and colour already carried there.

`Glyphs.canDraw` falls back to initials when a face cannot be drawn. That is a
genuine cross-device case rather than defensive noise: emoji arrive with OS
versions, so this season's pick would be an empty box on a sister's older
iPhone — in a party sitting right next to the phone that chose it.

### Not verified, and worth knowing why

**The iOS 26.3 simulator cannot render emoji at all** — every glyph is a box, at
8pt and at 20pt, on both simulators, while the font file is present and
correctly named in the runtime. The stored data is right (`🦊` is `F09FA68A` in
the store, confirmed by SQLite) and initials through the same `Text` draw
perfectly, so this is the runtime, not the app.

The `Glyphs` guard does not rescue it either: `CTFontGetGlyphsForCharacters`
reports the glyphs *exist*, so the fallback never triggers. The runtime has
glyph ids without bitmaps, and no API distinguishes that — emoji are bitmap
glyphs, so `CTFontCreatePathForGlyph` returns nil for working ones too.

So: the plumbing is verified end to end and the pixels are not. **One look on a
real device is the outstanding check** — the same trip a device already owes for
the peer-find toast, background reconnect, and all of §6.

`DemoData` gives Mia 🦊 and Theo 🚀 and leaves Dad on initials, so both paths
have a case. On this simulator that means screenshots show boxes where those two
appear; on a device it should show faces.

---

## 12. Phase 6b–6d as built

Four more files. All of it compiles; **none of it has ever talked to CloudKit.**

| File | Contents |
|---|---|
| `SharedBookSync.swift` | Zone creation, share creation, push, pull with change tokens, accept, stop-sharing. |
| `SharedBookLedger.swift` | Which books are shared and from whose zone, plus per-zone change tokens. Sidecar JSON. |
| `CloudShareSheet.swift` | `UICloudSharingController` wrapped for SwiftUI. |
| `PlatesAppDelegate` (in `PlatesApp.swift`) | The one callback SwiftUI has no equivalent for. |

### Decisions

- **`CKDatabase` operations, not `CKSyncEngine`.** The engine does more and owns
  its own scheduling and serialized state. This code had to be written before it
  could ever be run, so the thing worth optimising for was *being checkable by
  eye*: fetch with a token, apply, save, handle the few errors that really
  happen. A book is a few hundred small records; nothing here needs to be clever.
- **The share is saved with its root record in one operation.** CloudKit rejects
  a share whose root does not exist, and two steps leave a window where a crash
  orphans one of them.
- **Accepting needs a `UIApplicationDelegate`.** A share arrives from Messages as
  `userDidAcceptCloudKitShareWith`, not as a URL, so `onOpenURL` never sees it.
  That callback is the delegate's only reason to exist.
- **Pull on launch and on foreground, never poll.** A shared book is filled over
  weeks. Polling would spend battery shortening a wait nobody is sitting through.
- **Ending a share never deletes local plates.** Owner stops sharing or
  participant leaves; either way the rows stay and the book becomes an ordinary
  local one. Throwing away somebody's collection because a share ended would be
  losing data on a technicality — which also makes the planned "keep a copy"
  prompt unnecessary, since keeping it *is* the behaviour.
- **`changeTokenExpired` drops the token and refetches from scratch**, which is
  safe precisely because the merge is idempotent — the property Phase 0 proved.

### Verified

Only what can be: it builds, the merge harness still passes, and — the one that
actually mattered — **the app launches and plays normally with CloudKit enabled
and no iCloud account signed in**, which is every simulator and every signed-out
user. No crash, no error state, no change to the game.

### Not verified — everything that matters about it

No zone has been created, no share sent, no invitation accepted, no record
pushed or pulled. The simulator has no iCloud account and sharing needs two
Apple IDs on two devices. Read `SharedBookSync` as a first draft that compiles
and follows the documented shapes, not as working code.

---

## 13. What is actually left

### 1. One device session — unblocks almost everything

Four things are built, unverifiable on a simulator, and cheap to check once on
real hardware:

| Needs a device | Why |
|---|---|
| Emoji avatars | The iOS 26.3 simulator draws every emoji as a box (§11) |
| Peer-find toast | A party can only start from the Party screen, so the Game screen it draws on is never visible during a live find |
| Background reconnect | `simctl` cannot background an app without terminating it, so the lock-screen-and-return path is untested |
| Anything CloudKit | No iCloud account on any simulator |

### 2. The CloudKit production deploy — yours, and now covers two things

Order matters: **run on a device first**, which creates the record types in the
Development environment, *then* CloudKit Console → `iCloud.com.tagsmedia.tags`
→ Deploy Schema Changes. Read the diff; it is permanent and additive-only.

The deploy now carries **both** outstanding schema changes:

- `Player.avatar` (§11) — the first change to the SwiftData schema
- `SBBook` / `SBSighting` + the `SharedBooks` zone (§6a)

Doing them in one deploy is the whole reason `avatar` was allowed to be a schema
change at all.

### 3. Two Apple IDs on two devices — the shared-books acceptance test

Send an invitation, accept it, add a plate on each side, take one back. That is
the only test that exercises `SharedBookSync` at all.

### 4. Small things deliberately not built

- Participants' avatar stack on a shared book's header (the rest of 6d).
- Guest riders — phoneless passengers in a party, documented in §2a as the
  escape hatch if the regression is ever missed.
- Host handoff when the host leaves a party mid-drive.

### 5. Older, unrelated, still open

- Paste the Statistics Canada attribution into the App Store description (the
  exact wording is in `PlateRarity`'s Sources section).
- `ITSAppUsesNonExemptEncryption` has never been added to Info.plist; every
  TestFlight upload will ask until it is.

### Everything else is done and verified

Phases 0–5 are complete, harness-green, and mutation-tested at each step where a
silent failure was possible. Nothing in them needs a device or a deploy.

---

## 14. Pre-flight review of the sharing code

Read back before the first two-device test, on the reasoning that a failed test
costs a real session with two phones and two Apple IDs. Three bugs found by
inspection, all in `SharedBookSync`:

1. **`moreComing` was ignored.** CloudKit pages `recordZoneChanges`, and the
   flag means "ask again with the token I just gave you". Without the loop the
   first pull of a well-filled book returned one page and stopped — a
   participant would get a *partial* collection with nothing anywhere to say so.
   The worst kind of bug this feature could have, and invisible in any test
   smaller than a page. Now loops, and writes the token per page so an
   interrupted pull resumes instead of restarting.
2. **Stopping a share deleted the book record.** That takes the whole book out
   of CloudKit — every plate — so re-sharing would re-upload from scratch and a
   participant mid-sync would watch the book vanish rather than simply stop
   updating. Now deletes the `CKShare` and leaves the data.
3. **`makeShare` used the default save policy.** `.ifServerRecordUnchanged`
   refuses to write a record the server already has, which is exactly the
   share → stop → share-again path. Now `.changedKeys`.

Also added ten `[sharedbook]` log points behind `#if DEBUG` — zone ready, share
saved, each push, each withdrawal, each pull page with its counts, and every
failure. Every interesting CloudKit failure here is quiet, and "nothing
happened" is not a diagnosis.

### The test, in order

1. **Phone A:** Book tab → edit a book → **Share this book** → send to yourself
   or a second Apple ID via Messages.
2. **Phone B** (different Apple ID): open the link. It should launch Plates and
   the book should appear with A's plates already in it.
3. **Add a plate on B.** Foreground A — it should appear.
4. **Add a plate on A.** Foreground B — it should appear.
5. **Take one back on whichever device logged it.** It should disappear on the
   other.
6. **Stop sharing from A.** B keeps every plate it has; the book becomes an
   ordinary local one.

Watch Xcode's console filtered on `[sharedbook]`. Step 2 failing silently means
the accept path; steps 3–4 failing means push or pull; a partial book in step 2
would have been the paging bug.

---

## 15. Phase 6 finished — the last of 6d

The Book screen now says a book is shared and who is filling it: the header
label reads **SHARED BOOK** with the `person.2` glyph, and an `AvatarStack` of
contributors sits beside the settings button.

Contributors come from `book.participants(from:)` — the same scoping the
standings strip uses — rather than from `CKShare.participants`. That means the
header is right offline and needs no round trip to draw, and somebody counts as
a contributor exactly when one of their sightings has arrived, which is the
moment they are worth showing. Asking CloudKit would be slower, would fail
without a network, and would list people who have been invited but never added
anything.

Verified by planting a ledger entry (it is a sidecar JSON, so no debug code was
needed) and screenshotting: badge, label and the three-person stack all render,
and the harness still passes.

**Phase 6 is now complete as far as it can be without hardware.** Everything
outstanding is the two-device test in §14.
