# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses date-based release tags (`vX.Y.Z`) rather than strict
semantic versioning.

## [Unreleased]

### Added

- Release pipeline support for Developer ID signing (hardened runtime,
  secure timestamp) and notarization with stapling for both the app and the
  DMG. `scripts/set-release-secrets.sh` configures the GitHub secrets; builds
  without secrets (e.g. forks) fall back to ad-hoc signing.

### Changed

- Repository restructure for open-source readability: the SwiftPM package and
  library target were renamed `ThreeMFKit` → **`FilamentKit`** (product
  `three-mf-validate` → **`filament-validate`**), and format-agnostic public
  types (`ThreeMFError` → `FilamentError`, `ThreeMFDocument` → `ModelDocument`)
  were renamed to drop the 3MF-specific name now that they're used by every
  supported format (3MF, STL, OBJ, PLY). Names that really are 3MF-only
  (`ThreeMFLoader`, the 3MF parsers) were left as-is.
- Test-only code (synthetic fixture generation, the in-memory ZIP writer, and
  the internal self-test suite) moved out of `FilamentKit` into a new
  `FilamentTestSupport` SwiftPM target, so the app and Quick Look extensions
  no longer link it.
- Added `CONTRIBUTING.md`, `SECURITY.md`, issue/PR templates, and an
  `.editorconfig`; moved README images into `docs/images/`.

## [0.3.0] - 2026-09-29

### Added

- Prebuilt, checksummed downloads: CI now builds a universal `Filament.dmg` /
  `Filament.zip` for every release, and a one-line `install-release.sh`
  installs them without needing Xcode.
- Optional Filament previews for STL/OBJ/PLY on macOS 26, via
  `--prefer-filament-stl` (opts out of Apple's built-in Hydra 3D preview for
  the current user only, reversible with `--restore-apple-stl`).
- Spanish README (`README.es-ES.md`).
- A much larger regression test suite (58 → 172 tests): golden fixtures,
  offscreen render checks, and performance guards, with a CI-enforced code
  coverage floor.

### Fixed

- OnShape and other ZIP64-style `.3mf` files (0xFFFFFFFF central-directory
  sentinels) now open correctly.
- Filament now works alongside other apps (e.g. Shapr3D) that register their
  own UTI for `.3mf`.
- The installer no longer shows a false "not registered" warning.

### Changed

- Hardened parsing against malformed and hostile files: limits on memory use,
  triangle counts, and decompression; safe handling of out-of-range indices
  and overflowing numbers; protection against "zip bomb" style archives; and
  cancellation support when navigating away from a large model mid-load.
- Very large models (over ~3M triangles) now show Finder's generic icon
  instead of hanging the thumbnail provider; the full preview still opens
  them.

## [0.2.0] - 2026-07-06

### Added

- Full-color multi-material 3MF rendering: models painted with multiple
  filaments (e.g. Bambu MMU/AMS) render in their real slicer colors, with a
  **Color / Mono** toggle, per-triangle `paint_color` decoding, and
  per-filament materials.
- New app icon — a rainbow filament "f" extruded from a print nozzle,
  full-bleed for macOS 26 (Tahoe).
- File-menu keyboard shortcuts: Open (⌘O), Reload (⌘R), Reveal in Finder
  (⇧⌘R), Close File (⌘W).

### Changed

- ~10x faster loading: a dedicated streaming 3MF parser replaces
  Foundation's `XMLParser` (a 2.1M-triangle file now opens in about a
  second instead of ~10s).
- Models are framed to fill ~80% of the viewport on open.
- Removed the 2D/3D toggle in favor of a single interactive 3D view (orbit,
  pan, zoom).
- Removed the contact shadow / ground plane by default.
- The preview backdrop now follows the system light/dark appearance.

### Fixed

- Dragging a new file onto an open window (or opening one) now reliably
  swaps the model.
- Fixed a grey screen that appeared when orbiting below the model.

## [0.1.0] - 2026-07-05

### Added

- First release of Filament: a native macOS Quick Look app adding Finder
  thumbnails and interactive Space-bar previews for 3D-printing / 3D-model
  files — no slicer required.
- Support for `.3mf` (Bambu Studio / OrcaSlicer projects: multi-plate,
  embedded thumbnails, print stats, and the 3MF Production Extension),
  `.stl` (binary + ASCII), `.obj`, and `.ply` (ASCII + binary).
- Interactive preview (orbit / pan / zoom, soft shadows, studio lighting),
  a 2D front / 3D toggle, build-plate browsing, and model dimensions
  (W×D×H mm) + triangle count.
- `install.sh` registers Filament as the default opener for `.3mf` and
  `.stl`.
- Fully local and offline — no network access, no telemetry.

[Unreleased]: https://github.com/akshaymaloo/filament/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/akshaymaloo/filament/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/akshaymaloo/filament/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/akshaymaloo/filament/releases/tag/v0.1.0
