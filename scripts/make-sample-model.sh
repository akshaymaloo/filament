#!/usr/bin/env bash
# Regenerates the bundled sample model shown by the app's Quick Look setup window.
# Usage: scripts/make-sample-model.sh
set -euo pipefail
cd "$(dirname "$0")/.."
swift run filament-validate --write-sample "App/Filament/Resources/Filament Sample.3mf"
