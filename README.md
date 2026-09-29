<p align="center">
  <img src="docs/icon.png" width="128" alt="Filament app icon">
</p>

<h1 align="center">Filament</h1>

<p align="center">
  A native macOS Quick Look app for 3D-printing and 3D-model files.<br>
  Select a file in Finder, press <b>Space</b>, and get an interactive 3D preview — no slicer required.
</p>

<p align="center">
  <a href="https://github.com/akshaymaloo/filament/releases/latest"><img src="https://img.shields.io/github/v/release/akshaymaloo/filament" alt="Latest release"></a>
  <img src="https://img.shields.io/github/downloads/akshaymaloo/filament/total" alt="Downloads">
  <a href="https://ko-fi.com/akshaymaloo"><img src="https://img.shields.io/badge/Ko--fi-Support%20development-FF5E5B?logo=ko-fi&logoColor=white" alt="Support on Ko-fi"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license">
</p>

<p align="center"><b>English</b> · <a href="README.es-ES.md">Español</a></p>

---

### See it in action

Press <b>Space</b> in Finder to preview any supported file, toggle between full
color and a neutral studio look, and orbit the model — then open it full-screen
in the app.

<p align="center">
  <img src="docs/demo.gif" width="80%" alt="Previewing 3MF and STL files in Finder with Quick Look, toggling color, and opening in the Filament app">
</p>

## Download

**Recommended — one line, no Xcode required.** Open Terminal and run:

```bash
curl -fsSL https://raw.githubusercontent.com/akshaymaloo/filament/main/scripts/install-release.sh | bash
```

This downloads the latest release, verifies its checksum, installs it to
`~/Applications`, and registers the Quick Look extensions.

**Manual install:**

1. Download **Filament.dmg** from the [latest release](https://github.com/akshaymaloo/filament/releases/latest)
   and drag Filament into Applications.
2. Open Filament. Because the build isn't notarized yet, macOS blocks the
   first launch — go to **System Settings › Privacy & Security** and click
   **Open Anyway** (or run `xattr -dr com.apple.quarantine /Applications/Filament.app`).
3. Opening the app once registers its Quick Look extensions with Finder.

Builds run on both **Apple silicon and Intel** Macs, macOS 14 or later.
Notarizing releases needs a paid Apple Developer account — if Filament is
useful to you, [supporting it on Ko-fi](https://ko-fi.com/akshaymaloo) goes
toward that.

## Supported formats & features

Filament adds **Finder thumbnails** and **interactive Quick Look previews**
(orbit, pan, zoom, soft studio lighting) for:

- **`.3mf`** — 3D Manufacturing Format, including Bambu Studio / OrcaSlicer
  project files: multi-plate, embedded plate thumbnails, print stats, and the
  3MF **Production Extension** where geometry lives in external model parts.
- **`.stl`** — binary and ASCII.
- **`.obj`** — Wavefront OBJ.
- **`.ply`** — ASCII and binary (little/big endian).

<p align="center">
  <img src="docs/color-preview.gif" width="45%" alt="Interactive full-color 3MF preview spinning in Filament">
</p>
<p align="center"><sub>Multi-material 3MF models render in their real filament colors.</sub></p>

- **Instant thumbnails.** 3MF uses the slicer-embedded plate image for a
  near-instant icon; STL/OBJ/PLY are rendered on the fly.
- **Full-color multi-material.** Bambu/Orca 3MF models painted with multiple
  filaments render in their real slicer colors; toggle to a neutral
  monochrome studio look.
- **Browse all build plates.** Multi-plate 3MF projects get a plate selector.
- **Model info.** Dimensions (W × D × H mm) and triangle count; print time,
  weight, and printer for 3MF.
- **Open in the app.** Double-click a supported file (or drag-and-drop) to
  open it in the Filament window; drag another file in to swap the model
  instantly.
- **Fast on big models.** A dedicated streaming 3MF parser opens multi-
  million-triangle files in about a second.
- **Keyboard shortcuts.** Open (⌘O), Reload (⌘R), Reveal in Finder (⇧⌘R), and
  Close File (⌘W).
- **Default opener.** `install.sh` makes Filament the default app for `.3mf`
  and `.stl` (skip with `--no-defaults`). For a downloaded build, select a
  file in Finder, press ⌘I and choose **Open with › Filament › Change All**.
- **Privacy-friendly & offline.** Everything runs locally — no network, no
  telemetry.

### STL/OBJ/PLY previews on macOS 26+

macOS 26 ships its own 3D Quick Look extension
(`com.apple.HydraQLPreviewExtension`) that claims STL, OBJ, and PLY and
always wins over third-party extensions, so by default Apple previews those
formats and Filament previews 3MF. To use Filament for all of them instead:

```bash
# one-liner installer
curl -fsSL https://raw.githubusercontent.com/akshaymaloo/filament/main/scripts/install-release.sh | bash -s -- --prefer-filament-stl
curl -fsSL https://raw.githubusercontent.com/akshaymaloo/filament/main/scripts/install-release.sh | bash -s -- --restore-apple-stl   # undo

# or, building from source
./install.sh --prefer-filament-stl
./install.sh --restore-apple-stl     # undo
```

This runs `pluginkit -e ignore -i com.apple.HydraQLPreviewExtension` — a
per-user, reversible setting that doesn't modify system files. While it's
active, USD / MaterialX / Alembic files fall back to Apple's generic SceneKit
preview. Uninstalling restores Apple's preview automatically.

> If Space-bar previews don't show up right after install, log out and back
> in once so Finder reloads the Quick Look extensions.

## Roadmap

Planned work is tracked in [Issues](https://github.com/akshaymaloo/filament/issues) — feature requests welcome.

## Troubleshooting

### STL/OBJ/PLY open in Apple's preview instead of Filament

That's Apple's built-in Hydra preview on macOS 26+. See
[STL / OBJ / PLY previews on macOS 26+](#stlobjply-previews-on-macos-26)
above.

### 3MF Quick Look shows a generic file instead of the 3D preview

Another app may have registered its own UTI for `.3mf`. Filament's extensions
claim the common ones (including Shapr3D's `com.shapr3d.3d-manufacturing.3mf`).
If previews are still missing:

1. Reinstall (or log out and back in) so Launch Services and Quick Look
   reload.
2. Confirm the extensions are registered: `pluginkit -m | grep -i filament`
3. Check the file's type: `mdls -name kMDItemContentType the-file.3mf`

If you see an identifier Filament doesn't list, please
[open an issue](https://github.com/akshaymaloo/filament/issues) with that UTI.

### Some 3MF files fail to open (OnShape and similar)

Filament's ZIP reader understands Zip64 extra fields, including archives that
put `0xFFFFFFFF` sentinels in every central-directory size/offset even when
the file is small (OnShape's exporter does this). If a file still fails to
parse, please attach it to an issue.

### A very large model shows a generic icon in Finder

Finder thumbnails are rendered with a budget of 3 million triangles and about
20 seconds, so a huge model can't stall Finder. Above that, a 3MF with an
embedded slicer thumbnail still shows that image; other files fall back to
the default icon. The Space-bar preview opens models up to 20 million
triangles, and the Filament app handles even larger ones.

## Build from source

Building from source requires **Xcode 15 or later** and
**[XcodeGen](https://github.com/yonaskolb/XcodeGen)** (`brew install xcodegen`);
the Xcode project is generated from `project.yml` and isn't checked in.

```bash
git clone https://github.com/akshaymaloo/filament.git
cd filament
./install.sh
```

`install.sh` checks prerequisites (Xcode, and XcodeGen — installed via
Homebrew if needed), generates the Xcode project, builds a Release, **signs
it to run locally** (no Apple Developer account required), installs it to
`~/Applications`, and registers the Quick Look extensions. To sign with your
own Apple Developer team instead, pass `DEVELOPMENT_TEAM`:

```bash
DEVELOPMENT_TEAM=ABCDE12345 ./install.sh
```

Uninstall any time with `./install.sh --uninstall`.

<details>
<summary>Build in Xcode (manual)</summary>

#### 1. Clone and generate the project

```bash
git clone https://github.com/akshaymaloo/filament.git
cd filament
brew install xcodegen      # if you don't have it
xcodegen generate          # creates Filament.xcodeproj
open Filament.xcodeproj
```

#### 2. Set a signing team

macOS only loads a Quick Look **app extension** if the containing app is
code-signed and registered with Launch Services. In Xcode:

1. Select the **Filament** project in the navigator.
2. For **each** of the three targets — `Filament`, `ThumbnailExtension`,
   `PreviewExtension` — open **Signing & Capabilities** and pick your
   **Team**. Signing is preconfigured as *Automatic*; you only choose the
   team.
   - No paid Apple Developer account is required: signing in to Xcode with a
     free Apple ID gives you a **Personal Team** that works for local use.
   - Alternatively, set the signing certificate to **"Sign to Run Locally"**
     (ad-hoc) to run on your own Mac without any Apple ID.

The bundle identifier prefix is `com.filament3d` (e.g.
`com.filament3d.Filament`). Change it to your own reverse-DNS identifier if
you plan to distribute the app.

#### 3. Build & run once

Build and run the **Filament** app target (⌘R) at least once. Launching the
app registers its embedded Quick Look extensions with the system.

For system-wide Finder integration, move the built app to `/Applications` (or
`~/Applications`) and launch it once from there.

#### 4. Verify Quick Look

```bash
# Reset the Quick Look daemon so it picks up the newly registered extensions
qlmanage -r
qlmanage -r cache

# Confirm the extensions are registered
pluginkit -m | grep -i filament
```

Then select a `.3mf`, `.stl`, `.obj`, or `.ply` file in Finder and press
**Space** for the preview, or view it in an icon-view window for the
thumbnail.

</details>

<details>
<summary>Command-line build (CI / no signing)</summary>

To verify the app and both extensions compile and link **without** a signing
identity (e.g. on a CI runner):

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild build \
  -project Filament.xcodeproj -scheme Filament \
  -destination 'platform=macOS' -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

Building the `Filament` scheme also builds both embedded extensions (they are
target dependencies). This produces an unsigned `.app` suitable for
compile/link verification only — it will not register its Quick Look
extensions system-wide.

</details>

## Development

`ThreeMFKit` is a dependency-free Swift package and can be built and tested
with the Swift toolchain alone:

```bash
swift build                     # build the library
swift run three-mf-validate     # self-contained validation suite (no XCTest needed)
swift test                      # XCTest: parsing, golden fixtures, render and performance guards
swift test --enable-code-coverage && scripts/check-coverage.sh   # fails below 85% line coverage
```

### Architecture

- **`ThreeMFKit`** (`Sources/ThreeMFKit`) — dependency-free core: a read-only
  ZIP reader (via the `Compression` framework), OPC / 3MF XML parsing
  including the Production Extension, STL/OBJ/PLY mesh parsing, a
  `ModelLoader` facade that dispatches by file type, plate/thumbnail/stat
  extraction, and SceneKit scene construction (`ModelSCNView`, cameras,
  lighting, shadows).
- **`Filament`** (`App/Filament`) — the SwiftUI host app. Opens or drops a
  model file and browses build plates interactively. Declares the custom
  `com.filament3d.3mf` UTI and embeds both Quick Look extensions.
- **`ThumbnailExtension`** (`Extensions/ThumbnailExtension`) — a
  `QLThumbnailProvider` app extension for Finder/Spotlight thumbnails.
- **`PreviewExtension`** (`Extensions/PreviewExtension`) — a
  `QLPreviewingController` app extension for the full Space-bar preview
  panel.

### Uniform Type Identifiers

- `com.filament3d.3mf` — custom imported type for `.3mf` (conforms to
  `public.data` and `public.3d-content`, MIME `model/3mf`).
- STL/OBJ/PLY use the system-declared types
  `public.standard-tesselated-geometry-format`,
  `public.geometry-definition-format`, and `public.polygon-file-format`.

3MF has no Apple-defined UTI, so other apps (Shapr3D, Bambu Studio, Cadova, …)
each declare their own identifier for `.3mf`. Launch Services then resolves
those files to *that* UTI, and Quick Look will not invoke Filament unless the
extensions also claim it. The preview and thumbnail extensions therefore list
the common third-party 3MF UTIs in `QLSupportedContentTypes` in addition to
`com.filament3d.3mf`.

### Releasing

1. Bump `MARKETING_VERSION` in `project.yml`.
2. Optionally add release notes at `docs/release-notes/vX.Y.Z.md`.
3. Push a tag: `git tag vX.Y.Z && git push origin vX.Y.Z`.

`.github/workflows/release.yml` then builds a universal, ad-hoc-signed
`Filament.app`, packages it into `Filament.zip` / `Filament.dmg` /
`SHA256SUMS.txt`, and opens a **draft** GitHub release for review.

## Contributing

Issues and pull requests are welcome. Please keep `ThreeMFKit` dependency-free,
and make sure `swift run three-mf-validate` and `swift build` pass before
opening a PR (CI runs these plus an Xcode build on every push).

## Support

Filament is free and open source. If you find it useful, you can support its
development:

<a href="https://ko-fi.com/akshaymaloo"><img src="https://ko-fi.com/img/githubbutton_sm.svg" alt="Support me on Ko-fi" height="36"></a>

Releases today are **ad-hoc "signed to run locally"**, so macOS shows a
Gatekeeper warning on first launch. Donations go toward an **Apple Developer
Program** membership so future releases can be **notarized** — no Gatekeeper
warnings — and, eventually, published on the **Mac App Store**. Thank you! 🙏

## License

Released under the [MIT License](LICENSE).
