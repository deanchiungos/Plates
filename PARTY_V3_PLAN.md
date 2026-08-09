# Party fixes, round three

The TestFlight party feedback, items 5–11 from the triage. Numbering kept so the
conversation and the plan agree. Items 1–4 (join failure reporting, join-in-flight
UI, device-player identity, guest-cannot-host) are already committed on
`party-and-shared-books`.

**Confirmed design decision:** everyone keeps a full copy of the trip after the
party. Host-only saving is rejected — the copy is what makes the party survive dead
zones, and it was re-confirmed after the tester suggested view-only guests. The
fixes below make the copy *feel* finished instead of haunted; none of them delete
another person's contribution from a trip you both drove.

---

## 0. The bug found while planning: guest finds never reach other guests live

Not in the feedback triage by name, but it is almost certainly the reported
"third player to join was missing the data", and it gates item 9's test.

**Topology fact.** Each guest invites the host into the guest's own `MCSession`,
and the host accepts each invitation with its one session. So the host's
`connectedPeers` is every guest, but each guest's `connectedPeers` is exactly one
peer: the host. `broadcast(_:)` sends to `session.connectedPeers` — for a guest,
that is the host and nobody else.

**Consequence.** When guest B taps Ohio:
- the host gets the live `.sighting` event and merges it — fine;
- guest C gets nothing until something triggers a full snapshot re-greet
  (reconnect, app foregrounding, or the roster growing). On a quiet drive that can
  be *never*, until C locks and unlocks their phone.

Two devices cannot show this bug — every pairing includes the host. Three can,
which is why it survived every test so far.

**Fix: the host relays.** In `PartySession.received(_:from:)`, after a successful
merge, the host forwards `.sighting` and `.remove` envelopes to every connected
peer except the sender:

```swift
if role == .host, outcome affected something,
   payload is .sighting or .remove {
    send(payload, to: session.connectedPeers.filter { $0 != peer })
}
```

Guarded the same three ways the roster relay already is:
- only the host relays (guests have nobody to relay to anyway — one peer);
- only on a merge that changed something, so a duplicate arriving twice is
  dropped, not forwarded (`sightingsAdded > 0` / `sightingsRemoved > 0`);
- the merge is idempotent and removals are tombstoned, so even a redundant relay
  changes nothing on arrival.

No envelope changes, no version bump: the relayed message is byte-identical to
one the guest could have received directly, so old builds handle it.

`announce` (the "Mia got Montana" line) already runs on the receiving side, so a
relayed find gets announced on C's phone exactly as if C had heard B directly.

**Files:** `PartySession.swift` only.

---

## 5. Ending or leaving a party offers to finish the trip

The complaint "I still see multiple players on my Game tab even though the party
has ended" is (assuming the tester means the party trip — awaiting confirmation)
the trip continuing to *look live* after the car emptied. The other players'
plates are real history and stay. What should change is the trip's tense.

**Mechanism already exists.** `TripsScreen.finish(_:)` sets `endedAt` and
`archivedAt`, clears the selection so the Game tab moves on, and ends any party on
the trip. The party screen just never offers it.

**Change.** When the host taps **End party**, and when a guest taps **Leave
party** or receives the host's goodbye (`saidGoodbye`), present a popup:

- Host: "End the party?" → **End and finish the trip** (finish + leave) /
  **Just end the party** (leave only; the trip stays playable solo) / Cancel.
- Guest, with sightings of their own on the trip: same two choices, guest verbs.
- Guest, having spotted nothing: see item 7 — the discard offer replaces the
  finish offer.
- Host goodbye received (`saidGoodbye`): no popup mid-notification — the existing
  "The host ended the party" trouble card gains a **Finish my copy** button next
  to Done, so it is one tap but never automatic.

Finishing a *shared copy* must not call `endPartyIfOn` twice or broadcast
anything: `leave()` runs first, then the finish is purely local. The host
finishing *does* go through the existing `TripsScreen.finish` path so the goodbye
still precedes the teardown.

**Plumbing note.** `PartyScreen` has no `@Environment(PopupHost.self)` today —
add it; the host object is installed at the root, same as every screen that
already uses it.

**Files:** `PartyScreen.swift`, small extraction of the finish logic out of
`TripsScreen` into a shared helper (it is currently `private`), `PartySession`
untouched.

## 6. An ended trip's strip reads as a result, not a live standings

`PlayerStrip` (in `TripHeader.swift`) draws the same running-score strip whether
the trip is mid-drive or eight months done. Once `trip.endedAt != nil`, retitle
the strip **Final** (or crown the leader) and stop implying play is ongoing. Pure
presentation: same participants, same scores, no data change. Applies to every
finished trip, party or not — a finished solo trip has the same tense problem,
just nobody complained yet.

**Files:** `TripHeader.swift`, the call site in `GameScreen.swift` (it needs to
pass the trip's ended state through).

## 7. Leaving with nothing spotted offers to discard the copy

Joined, watched, spotted nothing, left: the copy is clutter, not history. On
guest leave (and on the host-goodbye card), if the device player has **zero
sightings on the party trip**, the popup offers **Discard this trip** instead of
the finish option.

Discard = `context.delete(trip)` — the `.cascade` rule deletes its sightings
(which are other people's finds, but this is *my copy* of them; their phones keep
their own) — plus `PartyLedger.forget(trip:)` and `PartyTombstones` cleanup, and
clearing `TripSelection` if it pointed there.

Never offered when the player has even one sighting on the trip, and never
automatic. The offer text says plainly that everyone else keeps their copy.

**Files:** `PartyScreen.swift`, `PartyLedger.swift` (forget already exists),
maybe a small `PartyTombstones.forget`.

## 8. The party code stops regenerating

`freshCode()` runs on every `host()`, so a host whose app restarts mid-drive
advertises the same trip under a new code, and every guest's typed code goes
stale — they reconnect fine (the code is re-sent from memory) but anyone joining
*fresh* after the restart gets refused with the code still written on the
whiteboard.

**Change.** Add `code: String?` to `PartyLedger.Record` (optional — old files
must stay decodable, the pattern `hostName` already set). `PartySession.host`
consults the ledger before minting: same trip → same code, forever. `-partyCode`
still overrides in DEBUG. A new trip gets a new code; re-hosting Trip 8 next
weekend reuses Trip 8's code, which is a feature — regulars stop retyping.

**Files:** `PartyLedger.swift`, `PartySession.swift` (`freshCode` becomes
`code(for: tripID)`).

## 9. Three-device party, actually tested

Machinery exists but has only ever run pairwise. Boot the third simulator
(iPhone 17 Pro Max, `4FE35AED-CC70-4E85-A101-7446ECEB039E`), install, and run:

1. A hosts (`-hostParty -partyCode ABCD -asPlayer Anna`), B and C join
   (`-joinParty -partyCode ABCD`, `-asPlayer Dean` / `-asPlayer Mia`).
2. **Roster:** all three stores contain exactly Anna, Dean, Mia. (Item 0's
   relay-of-roster already exists; this verifies it three-wide.)
3. **Live find:** C logs `-partyLog OH` → assert OH lands in **B's** store
   without any reconnect. This is the item 0 fix's proof; it fails on current
   code.
4. **Removal:** `-partyUnlog` from C → gone from A and B, tombstoned everywhere.
5. Mutation test the relay guard: re-enable relay-on-no-change and confirm the
   harness/store shows no duplicates (idempotence), then restore.

SQLite assertions against each store, same as the two-device tests. No screenshots
needed except for the standings strip showing three faces.

## 10. Duplicate parties: verify, don't code

One `PartySession` per device is already enforced (`host()`/`browse()` call
`shared?.leave()` first), and the two-hosts-one-trip route is closed by item 4
(guest cannot host a joined trip). Remaining suspect: stale `nearby` entries — a
host that vanished without `lost` firing leaves a tappable ghost row. During the
three-device session, kill A uncleanly and watch B's list; if the ghost persists
past the framework's own timeout, add an age-out. **No code unless the test shows
it.** If the tester's report predates today's fixes, expect this to be resolved.

## 11. `hostPlayerID`: use it or lose it — use it

It travels in every snapshot and nothing reads it. Three cheap uses, in order:

- **Persist it**: `PartyLedger.Record` gains `hostPlayerID: UUID?`, written by
  guests from the snapshot. Together with item 8's `code` this makes the record
  the party's full identity: trip, role, rules, code, host.
- **Enforce it**: in `received`, accept `.tripUpdate` (rules changes) only from
  `hostPeer`. Today `broadcastTrip` guards the sending side; a guarded sender and
  an unguarded receiver is half a rule.
- **Say it**: the trip editor for a joined trip can show "Hosted by Anna" from
  the ledger (name via the player row `hostPlayerID` points at, falling back to
  `hostName`). Complements item 4's refusal text.

**Files:** `PartyLedger.swift`, `PartySession.swift`, `TripsScreen.swift`
(editor line).

---

## Order of work

1. **Item 0 + 9 together** — the relay, then the three-device test that proves it
   (test written first, watched failing on current code, then the fix).
2. **Item 8** — small, isolated, ledger-only.
3. **Items 5 + 7** — one popup flow with two variants; touches the same screen.
4. **Item 6** — presentation, quick.
5. **Item 11** — ledger + receive guard + editor line.
6. **Item 10** — pure verification during the item 9 session, plus the unclean-
   kill probe.

Each lands as its own commit, same discipline as the last round: build, harness
pass (`-partyMergeCheck`), and for anything touching the wire, a multi-device
run with SQLite assertions before it is called done.

## Risks and non-goals

- **The relay is the only wire-behavior change.** Old and new builds can share a
  party: a relayed envelope is indistinguishable from a direct one, and a v2 host
  that does not relay simply leaves v3 guests with today's behavior.
- **No envelope version bump, no schema change, no CloudKit impact.** Everything
  here is sidecar (`PartyLedger`) or in-memory.
- **Not doing:** host-only saving (rejected), friend graph, per-trip friend
  picker (superseded by participants scoping), any change to what a trip shows
  about people who genuinely spotted plates on it.
- **Open question for the tester** (does not block): where exactly they saw the
  leftover players — party trip, other trip, or book. If it was a book or another
  trip, that is a new bug this plan does not cover, and item 5's finish flow
  would not have masked it.
