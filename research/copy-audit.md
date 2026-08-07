# User-facing copy

Every string the app shows a person, with its source line.

Edit the text at `file:line`. Strings containing `\(…)` splice in a value at
runtime — reword around them, but keep the `\(…)` parts exactly as they are.

- **323 strings** across **28 files**
- **77** contain `\(…)` interpolation
- **270** unique (so 53 are duplicated — reword one, search for the rest)


## Screens/GameScreen.swift

| line | where | text |
|---|---|---|
| 201 | Label | Nothing to fill yet |
| 203 | Text | A trip is one drive with a route and a finish. A book you just keep adding to. |
| 206 | Button | Start a trip |
| 209 | Button | Start a book |
| 360 | title: | Who's playing? |
| 399 | a11yLabel | Voice mode |
| 400 | a11yHint | Listens and logs plates as you say them |
| 448 | Text | Playing with others? Start a party |
| 478 | title: | States |
| 479 | detail: | \(collection.statesFound) / \(Plate.stateTotal) found |
| 490 | title: | Bonus plates |
| 491 | detail: | \(collection.bonusFound) / \(Plate.bonus.count) found |
| 555 | Text | Canada |
| 564 | Text | \(collection.provincesFound) / \(Plate.provinces.count) found |
| 595 | Text | Nothing left to find |
| 598 | Text | Every plate in the sets you are hunting is already found. |
| 604 | Button | Show everything |
| 708 | popup.present | Show |
| 708 | popup message | Choose what the grid draws. |
| 818 | PopupButton | Remove all \(mine.count) |
| 823 | PopupButton | Cancel |
| 870 | popup message | Everyone plays from their own phone instead of sharing  |
| 875 | PopupButton | Got it |
| 994 | popup.present | What are you filling? |
| 995 | popup message | Plates are saved against whichever of these is picked. |
| 998 | PopupButton | New trip |
| 1002 | PopupButton | New book |

## Screens/TripHeader.swift

| line | where | text |
|---|---|---|
| 82 | Text | \(trip.isActive ?  |
| 88 | Text | SWITCH |
| 123 | Text | \(trip.statesFound) of \(Plate.stateTotal) |
| 162 | Text | PLATE BOOK |
| 168 | Text | SWITCH |
| 194 | Text | Collecting |
| 196 | Text | \(book.statesFound) of \(Plate.stateTotal) |
| 282 | Text | \(entry.score) |
| 301 | a11yLabel | \(entry.player.name), \(entry.score) points\(isLeader ?  |
| 369 | Text | Allow |
| 390 | return "…" (copy) | location.circle.fill |
| 391 | return "…" (copy) | location.slash |
| 392 | return "…" (copy) | mappin.and.ellipse |
| 393 | return "…" (copy) | location.magnifyingglass |
| 400 | return "…" (copy) | Location is off |
| 401 | return "…" (copy) | Where are you heading? |
| 402 | return "…" (copy) | Finding you\u{2026} |
| 417 | return "…" (copy) | Pin a destination on this trip and the rail will show how far is left. |

## Screens/CollectionScreen.swift

| line | where | text |
|---|---|---|
| 113 | navTitle | Collection |
| 123 | a11yLabel | Start a new book |
| 260 | a11yLabel | Shared |
| 263 | Text | SWITCH |
| 314 | a11yLabel | Edit \(book.name) |
| 331 | return "…" (copy) | Across every book and trip |
| 393 | detail: | \(b.found(in: plates)) / \(plates.count) |
| 421 | Text | Trips you run will be listed here to compare. |
| 433 | Text | Every trip you have run, newest first. The bar compares states found. |
| 471 | popup.present | Which book? |
| 472 | popup message | Picking a book here changes what you are looking at, and which book Drive fills. |
| 475 | PopupChoice | All time |
| 476 | subtitle: | Every plate ever, across all books and trips |
| 483 | PopupButton | New book |
| 502 | popup message | \(count) plate\(count == 1 ?  |
| 505 | PopupButton | Empty book |
| 517 | PopupButton | Keep them |
| 528 | PopupButton | Delete book |
| 538 | PopupButton | Cancel |
| 576 | Text | \u{00D7}\(entry.count) |
| 615 | Text | \(summary.statesFound) |
| 619 | Text | states |
| 643 | Label | \(summary.platesFound) plates |
| 644 | Label | \(summary.days)d |
| 718 | Text | Plates are checked off on the Drive screen. |
| 724 | title: | Facts |
| 724 | detail: | \(seen.count) of \(total) |
| 738 | Text | Locked |
| 757 | Button | Done |
| 810 | Text | BOOK NAME |
| 815 | TextField | My Plate Book |
| 855 | Button | Cancel |
| 874 | Text | \(book.statesFound) of \(Plate.stateTotal) states |
| 978 | Text | Invite somebody to fill this book with you. You both add plates to the same book, from wherever you are. |

## Screens/TripsScreen.swift

| line | where | text |
|---|---|---|
| 51 | Label | No trips yet |
| 59 | Text | A trip is one journey \u{2014} it has a route, and it ends.  |
| 63 | Button | New trip |
| 71 | navTitle | Trips |
| 144 | Text | New trip |
| 158 | Text | Tap a trip to play it, or swipe one left to pin it or mark it done.  |
| 189 | Text | Archived |
| 191 | Text | \(archived.count) |
| 208 | title: | Reopen |
| 286 | popup message | \(trip.platesFound) plate\(trip.platesFound == 1 ?  |
| 288 | PopupButton | Clear plates |
| 292 | PopupButton | Keep them |
| 304 | PopupButton | Mark as done |
| 308 | PopupButton | Cancel |
| 315 | popup message | It stops appearing anywhere you pick a trip. Nothing is deleted \u{2014} its \(trip.platesFound) plate\(trip.platesFound == 1 ?  |
| 317 | PopupButton | Archive |
| 321 | PopupButton | Cancel |
| 330 | PopupButton | Delete trip |
| 334 | PopupButton | Cancel |
| 343 | popup.present | Add \(trip.name) to which book? |
| 350 | PopupButton | Cancel |
| 359 | popup message | The \(folded.count) sighting\(folded.count == 1 ?  |
| 363 | PopupButton | Remove |
| 367 | PopupButton | Cancel |
| 380 | popup message | The trip keeps its plates either way \u{2014} the book shows  |
| 383 | PopupChoice | Stack everything |
| 384 | subtitle: | All \(total) sighting\(total == 1 ?  |
| 388 | PopupChoice | Fill the gaps |
| 394 | PopupButton | Cancel |
| 406 | return "…" (copy) | \(what) ends the party on this phone.  |
| 572 | a11yLabel | Currently playing |
| 581 | a11yLabel | Played as a party |
| 588 | a11yLabel | Pinned |
| 613 | Text | \(trip.statesFound) |
| 617 | Text | of \(Plate.stateTotal) |
| 630 | a11yLabel | Edit \(trip.name) |
| 662 | return "…" (copy) | \(start) \u{2013} \(ended.formatted(.dateTime.month(.abbreviated).day())) |
| 664 | return "…" (copy) | \(start) \u{00B7} day \(trip.dayNumber) |
| 820 | Text | The host sets the scoring while you are in a party. |
| 847 | Button | Cancel |
| 852 | Button | Done |
| 978 | Text | PLATES \u{00B7} IN ORDER FOUND |
| 1042 | a11yLabel | \(sighting.plate?.name ?? sighting.plateCode), \(logTime(sighting.spottedAt)) |
| 1053 | return "…" (copy) | Day \(max(1, day)) \u{00B7} \(clock) |
| 1059 | Text | SCORING |
| 1073 | Text | SCORING |
| 1132 | Text | Count trucks and SUVs |
| 1279 | Text | TRIP NAME |
| 1284 | TextField | Summer roadtrip |

## Screens/MapScreen.swift

| line | where | text |
|---|---|---|
| 104 | navTitle | Map |
| 319 | Text | \(found) / \(total) |
| 386 | Button | Done |
| 405 | Text | Rarity \(rarity) of 10\(trip?.route == nil ?  |
| 421 | title: | Facts |
| 421 | detail: | \(seen.count) of \(total) |
| 427 | Text | Facts unlock as you spot this plate. Every sighting reveals a new one. |
| 452 | Text | Locked |

## Screens/PlayersScreen.swift

| line | where | text |
|---|---|---|
| 43 | Text | NAME |
| 48 | TextField | Who is playing? |
| 64 | Text | FACE |
| 82 | Text | COLOUR |
| 109 | a11yLabel | Colour \(i + 1)\(taken ?  |
| 116 | Text | Remove player |
| 135 | Button | Cancel |

## Screens/PartyScreen.swift

| line | where | text |
|---|---|---|
| 62 | navTitle | Party |
| 69 | title: | Who's playing? |
| 153 | Text | Everyone spots on their own phone |
| 156 | Text | One person starts the party and reads out the code.  |
| 175 | Text | Parties are for trips. Switch to a trip on the Game screen to start one. |
| 220 | Text | Read this out. Everyone else taps Join and types it in. |
| 248 | title: | Protect what people find |
| 249 | detail: | Only the person who spotted a plate can take it back. |
| 260 | title: | Everyone can claim a plate |
| 261 | detail: | A state stays open after the first person calls it, so it counts for all of you. |
| 308 | Text | Looking for parties in the car\u{2026} |
| 327 | Text | Hosted by \(found.hostName) |
| 360 | Text | The code \(target.hostName) is showing |
| 364 | TextField | ABCD |
| 383 | navTitle | Join \(target.tripName) |
| 387 | Button | Cancel |
| 390 | Button | Join |

## Screens/VoiceModeScreen.swift

| line | where | text |
|---|---|---|
| 74 | navTitle | Voice mode |
| 78 | Button | Done |
| 174 | Button | Open Settings |
| 191 | Text | Voice sounds robotic? Download a natural one in \(VoiceSpeaker.voiceSettingsPath), then tap the \u{2913} beside a voice marked Enhanced or Premium. |
| 206 | return "…" (copy) | Listening |
| 207 | return "…" (copy) | Starting… |
| 208 | return "…" (copy) | Paused |
| 209 | return "…" (copy) | Microphone is off |
| 210 | return "…" (copy) | Could not listen |
| 222 | return "…" (copy) | Just say the states as you see them — \u{201C}New Jersey\u{201D}, \u{201C}Ohio\u{201D}, \u{201C}that\u{2019}s a Texas\u{201D}. |
| 224 | return "…" (copy) | \u{201C} |
| 245 | Text | Nothing logged yet |
| 283 | Button | Undo |

## Screens/SettingsScreen.swift

| line | where | text |
|---|---|---|
| 44 | navTitle | Settings |
| 145 | Text | Remove |
| 167 | popup message | Plates they spotted stay collected \u{2014} every count is unchanged.  |
| 170 | PopupButton | Remove |
| 176 | PopupButton | Cancel |
| 218 | Text | Following the drive |
| 244 | return "…" (copy) | Not asked yet |
| 258 | Text | Hands free |
| 261 | Text | Say \u{201C}Hey Siri, log a plate in Plates\u{201D} \u{2014} or name it outright, \u{201C}log New Jersey in Plates\u{201D}. Either one opens voice mode and keeps listening, so the rest of the trip needs no phone at all. Say \u{201C}stop\u{201D} when you are done. |
| 276 | Text | Haptics |
| 303 | Text | Plates \(short) (\(build)) |

## Screens/MoreScreen.swift

| line | where | text |
|---|---|---|
| 26 | title: | Party |
| 30 | title: | Plate lookup |
| 34 | title: | Trail |
| 38 | title: | Historical plates |
| 42 | title: | Settings |
| 51 | navTitle | More |
| 87 | Text | PLATES |

## Design/PlateTile.swift

| line | where | text |
|---|---|---|
| 154 | Text | \(repeatCount) |

## Design/PopupPicker.swift

| line | where | text |
|---|---|---|
| 82 | Text | Nothing called \u{201C}\(query)\u{201D} |
| 108 | Text | \(count) |
| 124 | Text | Show all \(matches.count) |
| 167 | TextField | Search \(total) |
| 182 | a11yLabel | Clear search |

## Design/RarityTier.swift

| line | where | text |
|---|---|---|
| 38 | return "…" (copy) | COMMON |
| 39 | return "…" (copy) | UNCOMMON |
| 40 | return "…" (copy) | RARE |
| 41 | return "…" (copy) | EPIC |
| 42 | return "…" (copy) | LEGENDARY |
| 220 | Text | tap to dismiss |
| 237 | a11yLabel | \(tier.label) find. \(plateName). \(fact ??  |

## Domain/CloudBackup.swift

| line | where | text |
|---|---|---|
| 139 | return "…" (copy) | No connection to iCloud. Your plates will copy over once you are back online. |
| 141 | return "…" (copy) | Sign in to iCloud in Settings to back up your plates. |
| 143 | return "…" (copy) | Your iCloud storage is full, so nothing new can be copied over. |
| 145 | return "…" (copy) | This iCloud account is not allowed to store app data. |
| 147 | return "…" (copy) | iCloud is busy. This will retry on its own. |
| 154 | return "…" (copy) | iCloud rejected the data (\(ck.code.rawValue)).  |
| 157 | return "…" (copy) | Your plates could not be copied to iCloud. This is being looked into. |
| 185 | return "…" (copy) | Not backed up |
| 186 | return "…" (copy) | Sign in to iCloud |
| 187 | return "…" (copy) | Backing up to iCloud |
| 188 | return "…" (copy) | Backed up to iCloud |
| 189 | return "…" (copy) | Backup problem |
| 200 | return "…" (copy) | Your plates are on this phone only until you sign in, in Settings. |
| 202 | return "…" (copy) | Your plates will copy to iCloud shortly. |
| 204 | return "…" (copy) | Copying now\u{2026} |
| 206 | return "…" (copy) | Last copied \(when.formatted(.relative(presentation: .named))). |
| 221 | return "…" (copy) | checkmark.icloud.fill |
| 222 | return "…" (copy) | arrow.trianglehead.2.clockwise.rotate.90.icloud |
| 223 | return "…" (copy) | person.icloud |
| 224 | return "…" (copy) | exclamationmark.icloud |

## Domain/Models.swift

| line | where | text |
|---|---|---|
| 11 | return "…" (copy) | Classic scoring |
| 12 | return "…" (copy) | Weighted scoring |
| 13 | return "…" (copy) | Unlimited scoring |
| 19 | return "…" (copy) | One point per state, however many times you see it. |
| 20 | return "…" (copy) | Rarer plates are worth more, judged against your route. |
| 21 | return "…" (copy) | Every sighting scores, so keep counting. |
| 230 | return "…" (copy) | \(from) \u{2192} \(to) |
| 231 | return "…" (copy) | From \(from) |
| 232 | return "…" (copy) | To \(to) |

## Domain/PlateDates.swift

| line | where | text |
|---|---|---|
| 61 | return "…" (copy) | \(first) – now |
| 62 | return "…" (copy) | \(first) |
| 63 | return "…" (copy) | \(first) – \(last) |
| 81 | return "…" (copy) | \(span) year\(span == 1 ?  |

## Domain/PlateFilter.swift

| line | where | text |
|---|---|---|
| 75 | return "…" (copy) | States |
| 76 | return "…" (copy) | D.C. |
| 77 | return "…" (copy) | Territories |
| 78 | return "…" (copy) | Canada |
| 87 | return "…" (copy) | All 50 |
| 88 | return "…" (copy) | District of Columbia |
| 89 | return "…" (copy) | Puerto Rico |
| 90 | return "…" (copy) | \(n) provinces and territories |
| 124 | return "…" (copy) | \(hideFound ?  |

## Domain/PlateIntents.swift

| line | where | text |
|---|---|---|
| 26 | subtitle: | \(id) |
| 26 | title: | \(name) |
| 127 | title: | Plate |
| 210 | title: | Plate |
| 291 | title: | Plate |

## Domain/Shared/SharedBookSync.swift

| line | where | text |
|---|---|---|
| 305 | return "…" (copy) | Sign in to iCloud to share books. |
| 307 | return "…" (copy) | No connection \u{2014} this will catch up later. |
| 308 | return "…" (copy) | Your iCloud storage is full. |
| 310 | return "…" (copy) | That shared book is no longer available. |
| 311 | return "…" (copy) | You do not have permission to change that book. |

## Domain/VoiceSpeaker.swift

| line | where | text |
|---|---|---|
| 104 | return "…" (copy) | Settings \u{203A} Accessibility \u{203A} Read & Speak \u{203A} Voices \u{203A} English |
| 106 | return "…" (copy) | Settings \u{203A} Accessibility \u{203A} Spoken Content \u{203A} Voices \u{203A} English |
| 171 | return "…" (copy) | \(plate.name) has already been seen. |

## Screens/HistoricalPlatesScreen.swift

| line | where | text |
|---|---|---|
| 45 | navTitle | Historical plates |
| 99 | a11yLabel | Jurisdiction: \(plate?.name ?? code). Change |
| 134 | return "…" (copy) | \(count), \(first)\u{2013}\(last) |
| 138 | Text | Photographs from Wikimedia Commons and the jurisdictions' own sites, each credited on its card. Designs without a photograph are not listed. |
| 151 | Text | No photographs yet |
| 154 | Text | Nobody has photographed a \(plate?.name ?? code) plate for Wikimedia Commons. |
| 205 | Text | Nothing matches \u{201C}\(query)\u{201D}. |
| 214 | navTitle | Jurisdiction |
| 223 | Button | Cancel |
| 248 | Text | \(PlateHistoryBook.designs(for: plate.code).count) |
| 286 | Text | IN ISSUE |
| 405 | navTitle | \(jurisdiction) \(PlateDates.start(design.dates)) |
| 409 | Button | Done |

## Screens/PlaceField.swift

| line | where | text |
|---|---|---|
| 295 | Label | Map unavailable |
| 486 | return "…" (copy) | \(distance.string(fromDistance: route.distance)) \u{00B7} \(time) |

## Screens/PlateFilterPanel.swift

| line | where | text |
|---|---|---|
| 42 | a11yHint | Choose which plates to show |
| 47 | return "…" (copy) | \(leftCount) left |
| 50 | return "…" (copy) | \(filter.sets.count) sets |
| 73 | PopupChoice | Only what's left |
| 74 | subtitle: | Hide plates you have already found |
| 82 | Text | SETS |
| 105 | PopupButton | Show everything |
| 112 | PopupButton | Done |

## Screens/PlateLookupScreen.swift

| line | where | text |
|---|---|---|
| 44 | navTitle | Plate lookup |
| 85 | TextField | Describe the plate you saw |
| 100 | a11yLabel | Clear |
| 118 | Text | Saw a plate you couldn't name? |
| 127 | Text | Type whatever you remember about it. Any of these work: |
| 128 | Text | • a colour, like blue or orange and black\n |
| 133 | Text | Mixing them works best: green plate with a lighthouse.  |
| 142 | Text | TRY ONE |
| 153 | Text | \(PlateLookup.designs.count) designs, current and historic,  |
| 175 | Text | Nothing matched that |
| 180 | Text | No plate description mentions  |
| 188 | Text | Try a colour, something drawn on it, or a word printed on it. |
| 383 | Text | \(variantCount) |
| 481 | Text | EVERY \(design.jurisdiction.uppercased()) DESIGN |
| 521 | Button | Done |
| 552 | Text | Photo:  |

## Screens/PlateSearch.swift

| line | where | text |
|---|---|---|
| 78 | TextField | State or code |
| 88 | a11yLabel | Search plates by state or code |
| 91 | Text | \(matchCount) |
| 104 | a11yLabel | Clear search |
| 121 | Button | Cancel |

## Screens/RegionMapView.swift

| line | where | text |
|---|---|---|
| 303 | a11yValue | \(foundCount) of \(G.codes.count) regions found |

## Screens/RootView.swift

| line | where | text |
|---|---|---|
| 84 | Label | Game |
| 88 | Label | Map |
| 92 | Label | Book |
| 96 | Label | Trips |
| 100 | Label | More |

## Screens/Trail.swift

| line | where | text |
|---|---|---|
| 93 | navTitle | Trail |
| 140 | return "…" (copy) | pin- |
| 141 | return "…" (copy) | stop- |
| 207 | title: | All time |
| 208 | subtitle: | Every plate ever logged |
| 249 | popup.present | Show which drive? |
| 251 | PopupButton | Cancel |
| 269 | return "…" (copy) | All time |
| 355 | Text | No trail yet |
| 358 | Text | Plates get a pin here when you log them with location turned on. Older ones have no pin \u{2014} the app was not watching at the time. |
| 870 | Text | \(pins.count) |
| 1112 | Button | Done |
| 1310 | Text | No plate here matches \u{201C}\(query)\u{201D}. |
| 1323 | Button | Done |
