# MacEMUI

The shared window shell of mac4DSTEM and macTEM. An app package: SwiftUI, Metal, AppKit only where SwiftUI cannot, named in
a comment. No numerics, no kit except ImagoCore (`ScaleBarMath`). The suite's rules are in the suite `CLAUDE.md`; the look
is `process/design-dna.md`.

## Build and test
```sh
swift build
swift test -c release --parallel
```
Metal tests need a GPU and run on the Mac, not in hosted CI. Never `swift build --build-tests -c release`.

## Rules
- Swift 6 mode, MainActor default isolation. Never lower the mode to dodge a call-site error in an app.
- Public API is semver (0.x may break with a Migration paragraph). Keep it small: a helper only one app uses stays in that app.
- Slots only for what both apps need today. Scenes, welcome screens, room content and sidebar content stay app-side.
- Take a changed file from the app that owns the change, then the other app adopts it through the package.
- Pure SwiftUI; one line per setting; no app names in strings or errors.

## Closeout
Tests green, `CHANGELOG.md` entry with a Migration paragraph where an app must change, one commit on `main` whose last
paragraph is the hand-off. Paul tags with `tools/ship.sh`.
