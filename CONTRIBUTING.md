# Contributing to MacEMUI

Thank you for your interest. Bug reports, questions, documentation fixes and pull requests are welcome.

## Build and test

MacEMUI is a Swift package (Swift 6.2 or newer; macOS only: SwiftUI, Metal and a little AppKit).

```bash
swift build
swift test -c release --parallel
```

Tests use XCTest and Swift Testing. The Metal tests need a GPU and are skipped on a machine without one. Do not run
`swift build --build-tests -c release`.

## Scope

MacEMUI is the window shell, controls and Metal image view that two apps share. A helper only one app uses belongs in
that app. There are no numerics here; ImagoCore gives `ScaleBarMath`, and the shared EDS room calls SpectroKit, FormatoKit and ImagoFilters for
every number it shows.

## Pull requests

- Keep each pull request focused, with tests that fail before the change and pass after it.
- Public API is semver (0.x may break). A break gets a `CHANGELOG.md` entry with a Migration paragraph.
- SwiftUI first; AppKit only where SwiftUI cannot do the job, with a comment saying why.

## Reporting issues

Please include what you did, what you saw and what you expected. For security problems, see
[`SECURITY.md`](SECURITY.md).

By contributing you agree that your contribution is licensed under the GPL-3.0 (see [`LICENSE`](LICENSE)).
