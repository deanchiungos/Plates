# Copy audit

Every user-facing string in the app: **325** of them across **32** files.

**Edit copy in Xcode**, in `Plates/Localizable.xcstrings` — **427** entries. This file is the cross-check, not the source.

✓ in the String Catalog · ✗ source-only (**10**)

The ✗ rows are expected to be a short list with reasons — search photographs, plate names, and CloudKit's own error text. A ✗ on an ordinary sentence is a bug in the source, not in this report.

| context | count |
| --- | --- |
| Text | 101 |
| localized | 60 |
| popup choice | 34 |
| popup button | 28 |
| accessibility | 21 |
| button | 20 |
| section | 15 |
| nav title | 13 |
| popup message | 8 |
| placeholder | 7 |
| popup title | 7 |
| subtitle | 6 |
| detail | 5 |


## ios/Plates/Design/AppIconArt.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 187 | ✓ | Text | ROAD TRIP |
| 233 | ✓ | Text | 86 \u{00B7} 60 \u{00B7} 40 \u{00B7} 29 pt |

## ios/Plates/Design/DisclosureBar.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 35 | ✓ | Text | \(count) |

## ios/Plates/Design/FontLab.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 102 | ✓ | Text | LEGENDARY |
| 105 | ✓ | Text | New Jersey |
| 108 | ✓ | Text | The first drive-in theatre opened in Camden, New Jersey, in 1933. |
| 112 | ✓ | Text | Playing with others?  Start a party |
| 115 | ✓ | Text | Rarity is scored against this route. |

## ios/Plates/Design/PlateGallery.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 88 | ✓ | Text | Plate catalogue |

## ios/Plates/Design/PlateTile.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 154 | ✓ | Text | \(repeatCount) |

## ios/Plates/Design/PopupPicker.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 95 | ✓ | Text | Nothing called \u{201C}\(query)\u{201D} |
| 127 | ✓ | Text | \(count) |
| 201 | ✓ | placeholder | Search \(total) |
| 216 | ✓ | accessibility | Clear search |

## ios/Plates/Design/RarityTier.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 41 | ✓ | localized | COMMON |
| 42 | ✓ | localized | UNCOMMON |
| 43 | ✓ | localized | RARE |
| 44 | ✓ | localized | EPIC |
| 45 | ✓ | localized | LEGENDARY |
| 223 | ✓ | Text | tap to dismiss |
| 240 | ✓ | accessibility | \(tier.label) find. \(plateName). \(fact ??  |

## ios/Plates/Design/SharePoster.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 241 | ✓ | Text | \(entry.score) |
| 253 | ✓ | Text | PLATES |
| 308 | ✓ | popup choice | All time |

## ios/Plates/Domain/CloudBackup.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 139 | ✓ | localized | No connection to iCloud. Your plates will copy over once you are back online. |
| 141 | ✓ | localized | Sign in to iCloud in Settings to back up your plates. |
| 143 | ✓ | localized | Your iCloud storage is full, so nothing new can be copied over. |
| 145 | ✓ | localized | This iCloud account is not allowed to store app data. |
| 147 | ✓ | localized | iCloud is busy. This will retry on its own. |
| 159 | ✗ | localized | Your plates could not be copied to iCloud. This is being looked into. |
| 187 | ✓ | localized | Not backed up |
| 188 | ✓ | localized | Sign in to iCloud |
| 189 | ✓ | localized | Backing up to iCloud |
| 190 | ✓ | localized | Backed up to iCloud |
| 191 | ✓ | localized | Backup problem |
| 201 | ✓ | localized | Your plates live on this phone only. Losing it loses the book. |
| 203 | ✓ | localized | Your plates live on this phone only. \(reason) |
| 205 | ✓ | localized | Your plates are on this phone only until you sign in, in Settings. |
| 207 | ✓ | localized | Your plates will copy to iCloud shortly. |
| 209 | ✓ | localized | Copying now\u{2026} |
| 211 | ✓ | localized | Last copied \(when.formatted(.relative(presentation: .named))). |

## ios/Plates/Domain/Models.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 11 | ✓ | localized | Classic scoring |
| 12 | ✓ | localized | Weighted scoring |
| 13 | ✓ | localized | Unlimited scoring |
| 19 | ✓ | localized | One point per state, however many times you see it. |
| 20 | ✓ | localized | Rarer plates are worth more, judged against your route. |
| 21 | ✓ | localized | Every sighting scores, so keep counting. |

## ios/Plates/Domain/Party/PartySession.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 318 | ✓ | localized | Could not join \(target.tripName). Check the four characters on \(target.hostName)'s phone and tap the trip again. |

## ios/Plates/Domain/PlateFilter.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 79 | ✓ | localized | States |
| 81 | ✓ | localized | Territories |
| 82 | ✓ | localized | Canada |
| 91 | ✓ | localized | All 50 |
| 92 | ✓ | localized | District of Columbia |
| 93 | ✓ | localized | Puerto Rico |
| 94 | ✓ | localized | \(n) provinces and territories |

## ios/Plates/Domain/PlateIntents.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 26 | ✓ | popup choice | \(name) |
| 26 | ✓ | popup choice | \(id) |
| 127 | ✓ | popup choice | Plate |
| 210 | ✓ | popup choice | Plate |
| 291 | ✓ | popup choice | Plate |

## ios/Plates/Domain/TripReminders.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 102 | ✓ | localized | Still traveling? |
| 103 | ✓ | localized | You have \(trip.statesFound) of 50 states on \(trip.name). |

## ios/Plates/Domain/VoiceLogger.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 106 | ✓ | localized | Voice mode needs the microphone and speech recognition. Both can be turned on in Settings. |

## ios/Plates/Screens/CollectionScreen.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 105 | ✓ | nav title | Books |
| 137 | ✓ | accessibility | Start a new book |
| 286 | ✓ | accessibility | Shared |
| 289 | ✓ | Text | SWITCH |
| 340 | ✓ | accessibility | Edit \(book.name) |
| 431 | ✓ | detail | \(b.found(in: plates)) / \(plates.count) |
| 484 | ✓ | popup title | Which book? |
| 485 | ✓ | popup message | Picking a book here changes what you are looking at, and which book Drive fills. |
| 488 | ✓ | popup choice | All time |
| 489 | ✓ | subtitle | Every plate ever, across all books and trips |
| 496 | ✓ | popup button | New book |
| 522 | ✓ | popup button | Empty book |
| 534 | ✓ | popup button | Keep them |
| 545 | ✓ | popup button | Delete book |
| 555 | ✓ | popup button | Cancel |
| 633 | ✗ | Text | \u{00D7}\(entry.count) |
| 719 | ✓ | Text | Plates are checked off on the Drive screen. |
| 725 | ✓ | popup choice | Facts |
| 725 | ✓ | popup choice | \(seen.count) of \(total) |
| 769 | ✓ | button | Done |
| 829 | ✓ | Text | BOOK NAME |
| 834 | ✓ | placeholder | My Plate Book |
| 877 | ✓ | button | Cancel |
| 901 | ✓ | accessibility | Share this book |
| 921 | ✓ | Text | \(book.statesFound) of \(Plate.stateTotal) states |
| 1025 | ✓ | Text | Invite somebody to fill this book with you. You both add plates to the same book, from wherever you are. |

## ios/Plates/Screens/GameScreen.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 203 | ✓ | Text | A trip is one drive with a route and a finish. A book you just keep adding to. |
| 206 | ✓ | button | Start a trip |
| 209 | ✓ | button | Start a book |
| 374 | ✓ | popup choice | Who's playing? |
| 413 | ✓ | accessibility | Voice mode |
| 414 | ✓ | accessibility | Listens and logs plates as you say them |
| 463 | ✓ | Text | Playing with others? Start a party |
| 493 | ✓ | popup choice | States |
| 494 | ✓ | detail | \(collection.statesFound) / \(Plate.stateTotal) found |
| 505 | ✓ | popup choice | Bonus plates |
| 506 | ✓ | detail | \(collection.bonusFound) / \(Plate.bonus.count) found |
| 570 | ✓ | Text | Canada |
| 579 | ✓ | Text | \(collection.provincesFound) / \(Plate.provinces.count) found |
| 610 | ✓ | Text | Nothing left to find |
| 613 | ✓ | Text | Every plate in the sets you are hunting is already found. |
| 619 | ✓ | button | Show everything |
| 723 | ✓ | popup title | Show |
| 723 | ✓ | popup title | Choose what the grid draws. |
| 830 | ✓ | popup title | Remove \(plate.name)? |
| 831 | ✓ | popup button | Remove it |
| 835 | ✓ | popup button | Keep it |
| 890 | ✓ | popup button | Remove all \(mine.count) |
| 895 | ✓ | popup button | Cancel |
| 942 | ✓ | popup message | Everyone plays from their own phone instead of sharing yours, so Plates no longer asks who spotted each plate. Every plate you have already collected is untouched. Start a party from the More tab. |
| 944 | ✓ | popup button | Got it |
| 1071 | ✓ | popup title | What are you filling? |
| 1072 | ✓ | popup message | Plates are saved against whichever of these is picked. New trips and books are made on the Trips and Books tabs. |

## ios/Plates/Screens/HistoricalPlatesScreen.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 45 | ✓ | nav title | Historical plates |
| 99 | ✓ | accessibility | Jurisdiction: \(plate?.name ?? code). Change |
| 138 | ✓ | Text | Photographs from Wikimedia Commons and the jurisdictions' own sites, each credited on its card. Designs without a photograph are not listed. |
| 151 | ✓ | Text | No photographs yet |
| 154 | ✓ | Text | Nobody has photographed a \(plate?.name ?? code) plate for Wikimedia Commons. |
| 182 | ✓ | localized | States |
| 183 | ✓ | localized | Canada |
| 184 | ✓ | localized | Other |
| 205 | ✓ | Text | Nothing matches \u{201C}\(query)\u{201D}. |
| 214 | ✓ | nav title | Jurisdiction |
| 223 | ✓ | button | Cancel |
| 248 | ✓ | Text | \(PlateHistoryBook.designs(for: plate.code).count) |
| 286 | ✓ | Text | IN ISSUE |
| 409 | ✓ | localized | Status |
| 409 | ✓ | localized | Still in issue |
| 413 | ✓ | localized | Photograph |
| 413 | ✓ | localized | Wikipedia gives this era the design above it, so this is that plate |
| 436 | ✓ | nav title | \(jurisdiction) \(PlateDates.start(design.dates)) |
| 440 | ✓ | button | Done |

## ios/Plates/Screens/MapScreen.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 39 | ✓ | localized | Found |
| 40 | ✓ | localized | Rarity |
| 105 | ✓ | nav title | Map |
| 320 | ✓ | Text | \(found) / \(total) |
| 387 | ✓ | button | Done |
| 406 | ✓ | Text | Rarity \(rarity) of 10\(trip?.route == nil ?  |
| 422 | ✓ | popup choice | Facts |
| 422 | ✓ | popup choice | \(seen.count) of \(total) |
| 428 | ✓ | Text | Facts unlock as you spot this plate. Every sighting reveals a new one. |
| 453 | ✓ | Text | Locked |

## ios/Plates/Screens/MoreScreen.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 25 | ✓ | localized | While you play |
| 26 | ✓ | popup choice | Party |
| 30 | ✓ | popup choice | Plate lookup |
| 33 | ✓ | localized | Looking back |
| 34 | ✓ | popup choice | Trail |
| 38 | ✓ | popup choice | Historical plates |
| 41 | ✓ | localized | App |
| 42 | ✓ | popup choice | Settings |
| 51 | ✓ | nav title | More |
| 87 | ✓ | Text | PLATES |

## ios/Plates/Screens/PartyScreen.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 63 | ✓ | nav title | Party |
| 70 | ✓ | popup choice | Who's playing? |
| 154 | ✓ | section | Play together |
| 156 | ✓ | Text | Everyone spots on their own phone |
| 159 | ✓ | Text | One person starts the party and reads out the code. Plates anyone calls show up on every screen, and it all works with no signal. |
| 177 | ✓ | section | Not this one |
| 254 | ✓ | popup choice | Finish the trip |
| 255 | ✓ | subtitle | Files it away. Nothing is lost. |
| 261 | ✓ | popup choice | Discard this trip |
| 262 | ✓ | subtitle | Removes your copy only. |
| 267 | ✓ | popup choice | Finish and keep it |
| 268 | ✓ | subtitle | Files it away with your trips. |
| 274 | ✓ | popup button | Leave it open |
| 282 | ✓ | section | Your code |
| 291 | ✓ | Text | Read this out. Everyone else taps Join and types it in. |
| 316 | ✓ | section | Rules |
| 318 | ✓ | popup choice | Protect what people find |
| 319 | ✓ | detail | Only the person who spotted a plate can take it back. |
| 330 | ✓ | popup choice | Everyone can claim a plate |
| 331 | ✓ | detail | A state stays open after the first person calls it, so it counts for all of you. |
| 383 | ✓ | section | Joining |
| 386 | ✓ | Text | Asking \(target.hostName) to let you in\u{2026} |
| 394 | ✓ | section | Nearby |
| 398 | ✓ | Text | Looking for parties in the car\u{2026} |
| 417 | ✗ | Text | Hosted by \(found.hostName) |
| 454 | ✓ | Text | The code \(target.hostName) is showing |
| 458 | ✓ | placeholder | ABCD |
| 477 | ✓ | nav title | Join \(target.tripName) |
| 481 | ✓ | button | Cancel |
| 484 | ✓ | button | Join |
| 499 | ✓ | section | In the party |
| 525 | ✓ | section | Trouble |
| 580 | ✓ | localized | \(host ?? String(localized:  |
| 580 | ✗ | localized | )) started \(trip.name) and shared it with you, so only they can start a party for it. Start one on a trip of your own instead. |

## ios/Plates/Screens/PlateFilterPanel.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 42 | ✓ | accessibility | Choose which plates to show |
| 47 | ✓ | localized | \(leftCount) left |
| 50 | ✓ | localized | ^[\(filter.sets.count) set](inflect: true) |
| 73 | ✓ | popup choice | Only what's left |
| 74 | ✓ | subtitle | Hide plates you have already found |
| 82 | ✓ | Text | SETS |
| 97 | ✗ | localized | \(leftInRegion(region)) left of \(region.plates.count) |
| 110 | ✓ | popup button | Show everything |
| 117 | ✓ | popup button | Done |

## ios/Plates/Screens/PlateLookupScreen.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 53 | ✓ | nav title | Plate lookup |
| 94 | ✓ | placeholder | Describe the plate you saw |
| 109 | ✓ | accessibility | Clear |
| 127 | ✓ | Text | Saw a plate you couldn't name? |
| 136 | ✓ | Text | Type whatever you remember about it. Any of these work: |
| 147 | ✓ | Text | Mixing them works best: green plate with a lighthouse. Results come back one row per state, newest design first. Tap any of them to see the photo big, next to every other plate that state has issued. |
| 153 | ✓ | Text | TRY ONE |
| 164 | ✓ | Text | \(PlateLookup.designs.count) designs, current and historic, each with a photograph. |
| 185 | ✓ | Text | Nothing matched that |
| 192 | ✗ | Text | No plate description mentions \(unknown.map {  |
| 192 | ✗ | Text |  }.joined(separator:  |
| 198 | ✓ | Text | Try a color, something drawn on it, or a word printed on it. |
| 393 | ✓ | Text | \(variantCount) |
| 491 | ✓ | Text | EVERY \(design.jurisdiction.uppercased()) DESIGN |
| 531 | ✓ | button | Done |
| 562 | ✓ | Text | Photo: \(attribution) |

## ios/Plates/Screens/PlateSearch.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 78 | ✓ | placeholder | State or code |
| 88 | ✓ | accessibility | Search plates by state or code |
| 91 | ✓ | Text | \(matchCount) |
| 104 | ✓ | accessibility | Clear search |
| 121 | ✓ | button | Cancel |

## ios/Plates/Screens/PlayersScreen.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 43 | ✓ | Text | NAME |
| 48 | ✓ | placeholder | Who is playing? |
| 64 | ✓ | Text | FACE |
| 82 | ✓ | Text | COLOR |
| 109 | ✗ | accessibility | Color \(i + 1)\(taken ?  |
| 116 | ✓ | Text | Remove player |
| 135 | ✓ | button | Cancel |

## ios/Plates/Screens/RegionMapView.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 303 | ✓ | accessibility | \(foundCount) of \(G.codes.count) regions found |

## ios/Plates/Screens/SettingsScreen.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 49 | ✓ | nav title | Settings |
| 69 | ✓ | section | Playing as |
| 124 | ✓ | section | Other people |
| 150 | ✓ | Text | Remove |
| 168 | ✓ | localized | No plates on this phone |
| 169 | ✓ | localized | ^[\(n) plate](inflect: true) they spotted |
| 176 | ✓ | popup message | Plates they spotted stay collected, and every count is unchanged. Only their line in the standings goes. |
| 178 | ✓ | popup button | Remove |
| 184 | ✓ | popup button | Cancel |
| 197 | ✓ | section | Your collection |
| 224 | ✓ | section | Location |
| 226 | ✓ | Text | Following the drive |
| 261 | ✓ | section | Reminders |
| 265 | ✓ | Text | Unfinished trips |
| 268 | ✓ | Text | A nudge if a trip goes a day without a plate. |
| 313 | ✓ | section | Voice |
| 315 | ✓ | Text | Hands free |
| 318 | ✓ | Text | Say \u{201C}Hey Siri, log a plate in Plates\u{201D}, or name it outright: \u{201C}log New Jersey in Plates\u{201D}. Either one opens voice mode and keeps listening, so the rest of the trip needs no phone at all. Say \u{201C}stop\u{201D} when you are done. |
| 331 | ✓ | section | Feedback |
| 333 | ✓ | Text | Haptics |
| 360 | ✓ | Text | Plates \(short) (\(build)) |

## ios/Plates/Screens/Trail.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 93 | ✓ | nav title | Trail |
| 211 | ✓ | localized | All time |
| 212 | ✓ | localized | Every plate ever logged |
| 253 | ✓ | popup title | Show which drive? |
| 255 | ✓ | popup button | Cancel |
| 359 | ✓ | Text | No trail yet |
| 362 | ✓ | Text | Plates get a pin here when you log them with location turned on. Older ones have no pin. The app was not watching at the time. |
| 874 | ✓ | Text | \(pins.count) |
| 1116 | ✓ | button | Done |
| 1314 | ✓ | Text | No plate here matches \u{201C}\(query)\u{201D}. |
| 1327 | ✓ | button | Done |

## ios/Plates/Screens/TripComparison.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 31 | ✓ | popup choice | Compare trips |
| 41 | ✓ | Text | Newest first. The bar compares states found. |
| 73 | ✓ | Text | \(summary.statesFound) |
| 77 | ✓ | Text | states |

## ios/Plates/Screens/TripHeader.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 82 | ✓ | Text | \(trip.isActive ?  |
| 82 | ✗ | Text | ) TRIP \u{00B7} DAY \(trip.dayNumber) |
| 88 | ✓ | Text | SWITCH |
| 123 | ✓ | Text | \(trip.statesFound) of \(Plate.stateTotal) |
| 162 | ✓ | Text | PLATE BOOK |
| 168 | ✓ | Text | SWITCH |
| 194 | ✓ | Text | Collecting |
| 196 | ✓ | Text | \(book.statesFound) of \(Plate.stateTotal) |
| 287 | ✓ | Text | \(entry.score) |
| 306 | ✓ | accessibility | \(entry.player.name), \(entry.score) points\(isLeader ?  |
| 374 | ✓ | Text | Allow |

## ios/Plates/Screens/TripsScreen.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 61 | ✓ | Text | A trip is one journey: it has a route, and it ends. For everyday spotting on the way to school or the shops, use a plate book instead: it just keeps going. |
| 63 | ✓ | button | New trip |
| 71 | ✓ | nav title | Trips |
| 163 | ✓ | Text | New trip |
| 177 | ✓ | Text | Tap a trip to play it, or swipe one left to pin it or mark it done. A trip is one journey; for everyday spotting, fill a book instead. |
| 209 | ✓ | popup choice | Finished |
| 216 | ✓ | popup choice | Reopen |
| 219 | ✓ | popup choice | Archive |
| 248 | ✓ | popup choice | Archived |
| 255 | ✓ | popup choice | Reopen |
| 339 | ✓ | popup message | ^[\(trip.platesFound) plate](inflect: true) found on \(trip.name) will be un-collected. The trip itself stays. |
| 341 | ✓ | popup button | Clear plates |
| 345 | ✓ | popup button | Keep them |
| 354 | ✓ | popup button | Mark as done |
| 358 | ✓ | popup button | Cancel |
| 365 | ✓ | popup message | It stops appearing anywhere you pick a trip. Nothing is deleted. Its ^[\(trip.platesFound) plate](inflect: true) stay in your history, and you can bring it back. |
| 367 | ✓ | popup button | Archive |
| 371 | ✓ | popup button | Cancel |
| 380 | ✓ | popup button | Delete trip |
| 384 | ✓ | popup button | Cancel |
| 393 | ✓ | popup title | Add \(trip.name) to which book? |
| 400 | ✓ | popup button | Cancel |
| 409 | ✓ | popup message | The ^[\(folded.count) sighting](inflect: true) this trip added leave the book. Plates the book collected on its own stay, and the trip itself is untouched. |
| 411 | ✓ | popup button | Remove |
| 415 | ✓ | popup button | Cancel |
| 428 | ✓ | popup message | The trip keeps its plates either way. The book just shows them too, and you can take them back out whenever you like. |
| 430 | ✓ | popup choice | Stack everything |
| 431 | ✓ | subtitle | All ^[\(total) sighting](inflect: true) carry over. Plates the book already has count again. |
| 434 | ✓ | popup choice | Fill the gaps |
| 440 | ✓ | popup button | Cancel |
| 607 | ✓ | accessibility | Currently playing |
| 616 | ✓ | accessibility | Played as a party |
| 623 | ✓ | accessibility | Pinned |
| 648 | ✓ | Text | \(trip.statesFound) |
| 652 | ✓ | Text | of \(Plate.stateTotal) |
| 665 | ✓ | accessibility | Edit \(trip.name) |
| 863 | ✓ | Text | The host sets the scoring while you are in a party. |
| 890 | ✓ | button | Cancel |
| 915 | ✓ | accessibility | Share this trip |
| 920 | ✓ | button | Done |
| 997 | ✓ | Text | \(host)'s trip, from their party. This is your copy of it. |
| 1083 | ✓ | Text | PLATES \u{00B7} IN ORDER FOUND |
| 1168 | ✓ | Text | SCORING |
| 1181 | ✓ | Text | SCORING |
| 1345 | ✓ | Text | TRIP NAME |
| 1350 | ✓ | placeholder | Summer roadtrip |

## ios/Plates/Screens/VoiceModeScreen.swift

| line | ✓ | context | string |
| --- | --- | --- | --- |
| 74 | ✓ | nav title | Voice mode |
| 174 | ✓ | button | Open Settings |
| 191 | ✗ | Text | Voice sounds robotic? Download a natural one in \(VoiceSpeaker.voiceSettingsPath), then tap the \u{2913} beside a voice marked Enhanced or Premium. |
| 247 | ✓ | Text | Nothing logged yet |
| 285 | ✓ | button | Undo |
