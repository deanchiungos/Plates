# dev

Everything that built the app and none of what ships in it.

Nothing under here is compiled, bundled, or referenced by `Plates.xcodeproj` — the
project has no build phase that reaches outside `ios/`. It is all reproducible
tooling and the source data that tooling reads, kept in the repo because the
generated resources in `ios/Plates/Resources` cannot be regenerated without it.

| | What it is |
|---|---|
| `tools/` | The generators. `plate_lookup_build.py` and `plate_history_build.py` write the app's JSON resources; `facts.py` and `plate_lookup_eval.py` check them; the rest scrape, audit and draw. |
| `research/` | The corpus they read: plate descriptions, colors, validity, credits, and ~400 reference photographs. The largest thing in the repo by far. |
| `docs/` | Plans written before the features they describe. Kept as a record of the reasoning, not as documentation of what the code now does — where the two disagree, the code is right. |
| `web/` | An early browser prototype of the game, predating the iOS app. Nothing links to it and nothing deploys it. |

## Regenerating the app's resources

Run from `dev/tools`. Each writes into `ios/Plates/Resources` and should produce
byte-identical output given an unchanged corpus.

    python3 plate_lookup_build.py                                   # PlateLookup.json + PlateShots
    python3 plate_history_build.py ../research/plate-history.csv \
        > ../../ios/Plates/Resources/PlateHistory.json              # PlateHistory.json
    python3 plate_lookup_eval.py                                    # search quality gate
    python3 facts.py                                                # PlateFacts.json lint

The scripts locate the repo by walking up from their own file, so they work from
any working directory but **not** from a copy at a different depth.
