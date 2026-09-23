# Accounts, handles, and why not Sign in with Apple

Not a plan. A note so the reasoning survives, because the obvious answer here is
the wrong one and it will look obvious again in six months.

## The short version

**Don't add Sign in with Apple. Add a globally unique handle on top of the
CloudKit identity the app already has.**

## Why not SIWA

Every iCloud user already has a stable, permanent, app-scoped identifier in our
container: `CKContainer.userRecordID()`. Same Apple ID, same value, every device,
forever, no UI at all. That is precisely what SIWA would hand us — except SIWA
also costs a sign-in screen, the hide-my-email relay, and a credential to store.
For an app whose entire sync story is already CloudKit, it is a toll booth on a
road we own.

SIWA earns its place when identity has to outlive the Apple ecosystem: an Android
app, a web leaderboard, an email address to contact people at, or a second
third-party login (add one and Apple requires SIWA beside it). None are on the
board. If one arrives, that is the moment — and it arrives with a real backend, a
privacy policy, and COPPA questions that are heavier here than in most apps,
because the players are children.

## The handle, without a server

A globally unique username needs exactly one thing: an atomic uniqueness check.
CloudKit's **public** database gives that away free, if the handle *is* the record
name.

- Record type `Handle`, `recordName` = the normalized (lowercased, trimmed) name.
- Fields: display name, emoji, colour index, owner's user record.
- Claiming is a create-only save. A record saved with no change tag fails when
  that name already exists — and that failure *is* the uniqueness guarantee,
  enforced server-side, atomically, by Apple.
- Public-DB defaults are world-readable, creator-writable, so nobody can take
  yours.
- Lookup is a fetch by record name, not a query. No index, no scan.

Same container (`iCloud.com.tagsmedia.tags`), same entitlement already shipped.
No server, no bill, on the order of 150 lines. It sits *on top of* the local
`Player` rather than replacing it — the handle is a fourth field, and the emoji
and colour stay exactly as they are.

## Three conditions on building it

1. **Claim it lazily, never during onboarding.** A handle only matters when
   reaching someone who is not in the car — sharing a book across town. Ask then.
   Onboarding is judged on time-to-first-plate, and "choose a globally unique
   username" is the worst possible thing to put in front of a kid in a back seat.
2. **Moderation is the real cost, and it is not technical.** A publicly visible,
   strangers-can-see-it name in a game played by nine-year-olds is user-generated
   content. A blocklist and a report path ship before the first handle exists,
   not after.
3. **Account deletion is required.** App Store guideline 5.1.1(v): an app that
   supports account creation must offer in-app deletion. Claiming a handle almost
   certainly counts, so "release my handle" ships in the same version.

## The actual reason to want it

Not friend-adding. The sightings dataset — the handle is the anchor that lets
pooled plate sightings be attributed without being personal, which is the only
route to a real "what are the odds you see a Wyoming plate" number that nobody
has published.

## Known costs

- First-come-first-served means somebody loses `dad`. No reclaim policy designed.
- Public-database storage counts against the *developer's* quota, not each user's
  — the opposite of the private database. Irrelevant for tiny text records, worth
  knowing before anything larger goes public.
- Children on managed Apple IDs may have restricted CloudKit access.
- Signed out of iCloud means unable to manage your own handle.

## Sequencing

After onboarding. It depends on nothing there, and onboarding is the thing with a
release attached.
