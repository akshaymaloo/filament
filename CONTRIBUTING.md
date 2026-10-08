# Contributing to Filament

Thanks for your interest in improving Filament! This document covers the dev
setup, test/coverage commands, project architecture, and the release process.

## Project layout

- **`FilamentKit`** (`Sources/FilamentKit`) — dependency-free core: a
  read-only ZIP reader (via the `Compression` framework), OPC / 3MF XML
  parsing including the Production Extension, STL/OBJ/PLY mesh parsing, a
  `ModelLoader` facade that dispatches by file type, plate/thumbnail/stat
  extraction, and SceneKit scene construction (`ModelSCNView`, cameras,
  lighting, shadows). This library ships inside the app and both extensions,
  so **keep it dependency-free**.
- **`FilamentTestSupport`** (`Sources/FilamentTestSupport`) — synthetic
  fixture generation (`FilamentFixtureFactory`), an in-memory ZIP writer, and
  a small internal self-test suite used only by `FilamentValidate` and
  `FilamentKitTests`. Not referenced by `project.yml`, so it never links into
  the app or extensions.
- **`FilamentValidate`** (`Sources/FilamentValidate`) — a standalone
  executable (`swift run filament-validate`) that exercises `FilamentKit`
  against synthetic and real fixtures without needing XCTest.
- **`Tests/FilamentKitTests`** — the XCTest suite (parsing, golden fixtures,
  offscreen render checks, performance guards).
- **`Filament`** (`App/Filament`) — the SwiftUI host app. Opens or drops a
  model file and browses build plates interactively. Declares the custom
  `com.filament3d.3mf` UTI and embeds both Quick Look extensions.
- **`ThumbnailExtension`** (`Extensions/ThumbnailExtension`) — a
  `QLThumbnailProvider` app extension for Finder/Spotlight thumbnails.
- **`PreviewExtension`** (`Extensions/PreviewExtension`) — a
  `QLPreviewingController` app extension for the full Space-bar preview
  panel.

The Xcode project (`Filament.xcodeproj`) is generated from `project.yml` via
[XcodeGen](https://github.com/yonaskolb/XcodeGen) and isn't checked in.

## Dev setup

Requires **Xcode 15 or later** and
**[XcodeGen](https://github.com/yonaskolb/XcodeGen)** (`brew install xcodegen`).

```bash
git clone https://github.com/akshaymaloo/filament.git
cd filament
./install.sh
```

`install.sh` checks prerequisites, generates the Xcode project, builds a
Release, signs it to run locally (no Apple Developer account required),
installs it to `~/Applications`, and registers the Quick Look extensions.
See the README's [Build from source](README.md#build-from-source) section
for the manual Xcode workflow and CI-style unsigned builds.

## FilamentKit: build, test, and coverage

`FilamentKit` is a dependency-free Swift package and can be built and tested
with the Swift toolchain alone, without opening Xcode:

```bash
swift build                      # build the library
swift run filament-validate      # self-contained validation suite (no XCTest needed)
swift test                       # XCTest: parsing, golden fixtures, render and performance guards
swift test --enable-code-coverage && scripts/check-coverage.sh   # fails below 85% line coverage
```

`scripts/check-coverage.sh` measures line coverage for `FilamentKit` only —
it ignores `Tests/`, `FilamentValidate`, and `FilamentTestSupport`.

## Releasing

1. Bump `MARKETING_VERSION` in `project.yml`.
2. Optionally add release notes at `docs/release-notes/vX.Y.Z.md`.
3. Add an entry to `CHANGELOG.md`.
4. Push a tag: `git tag vX.Y.Z && git push origin vX.Y.Z`.

`.github/workflows/release.yml` then builds a universal `Filament.app`,
signs it with the Developer ID certificate, notarizes and staples the app and
the DMG, packages `Filament.zip` / `Filament.dmg` / `SHA256SUMS.txt`, and
opens a **draft** GitHub release for review. Without the signing secrets
(e.g. on forks) it falls back to an ad-hoc build.

### Signing setup (maintainers, once)

1. In [Certificates, IDs & Profiles](https://developer.apple.com/account/resources/certificates/list),
   create a **Developer ID Application** certificate, install it, and export
   it from Keychain Access as a password-protected `.p12`.
2. In [App Store Connect › Users and Access › Integrations › Team Keys](https://appstoreconnect.apple.com/access/integrations/api),
   create an API key with the **Developer** role. Download `AuthKey_<KEYID>.p8`
   and note the **Issuer ID**.
3. Store them as repository secrets:

   ```bash
   scripts/set-release-secrets.sh DeveloperID.p12 AuthKey_<KEYID>.p8 <issuer-id>
   ```

   Then delete the local `.p12`/`.p8` copies or keep them somewhere safe
   outside the repo (`.gitignore` blocks them, but don't rely on it).

To build a signed, notarized package locally instead:

```bash
xcrun notarytool store-credentials filament --key AuthKey_<KEYID>.p8 --key-id <KEYID> --issuer <issuer-id>
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_KEYCHAIN_PROFILE=filament scripts/package-release.sh dist
```

## Pull request checklist

- [ ] `swift build` succeeds.
- [ ] `swift run filament-validate` passes (all checks).
- [ ] `swift test` passes.
- [ ] If you touched `FilamentKit`, `swift test --enable-code-coverage && scripts/check-coverage.sh` still meets the threshold.
- [ ] `FilamentKit` remains dependency-free (no new SwiftPM dependencies).
- [ ] `xcodegen generate && xcodebuild build -project Filament.xcodeproj -scheme Filament -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO` succeeds, if you touched the app or extensions.
- [ ] Updated the README and/or `CHANGELOG.md` if behavior or setup changed.

## Reporting bugs with a sample file

Most parsing bugs are easiest to diagnose with the actual file that triggers
them. When filing an issue:

1. Attach the `.3mf`/`.stl`/`.obj`/`.ply` file (or a minimal reproduction) —
   GitHub issues accept file attachments directly.
2. Include the output of `mdls -name kMDItemContentType the-file.3mf` (or
   whichever extension) so we can see which UTI Launch Services assigned it.
3. Note which exporter/slicer produced the file (e.g. Bambu Studio,
   OrcaSlicer, Shapr3D, OnShape), if known.
4. Say whether the problem is in the Quick Look preview, the Finder
   thumbnail, or the standalone app.

If a file is private, a minimal reproduction (even a hand-edited fixture)
that still exhibits the bug works just as well.
