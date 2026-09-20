# MacZ

Native SwiftUI utility. Swift 6, macOS 14+, no third-party dependencies.

- `Sources/MacZCore/`: hardware queries, sampling, report allowlist.
- `Sources/MacZ/`: app lifecycle and native UI.
- `Tests/MacZCoreTests/`: calculations, live API checks, report privacy.
- `tools/build-app.sh`: build and ad-hoc sign `dist/MacZ.app`; `--universal` builds both architectures.
- `swift test`: run tests. `swift run MacZ --report`: text report.
- `python3 -m unittest discover -s Tests/PackagingTests`: isolated packaging failure tests.
- [Release review](docs/release-review.md): verified fixes and remaining release requirements.
- [Project](docs/project.md), [UI conventions](docs/styles.md).

Never add actual device reports, identifiers, secrets, signing credentials, personal paths, or build products to source control. Do not read actual `.env` files. Keep reports allowlisted and sampling unprivileged.
