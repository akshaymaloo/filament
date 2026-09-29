#!/usr/bin/env bash
# Fails CI if ThreeMFKit's XCTest line coverage drops below a threshold.
#
# Usage: scripts/check-coverage.sh [threshold]
#   threshold - minimum acceptable TOTAL line-coverage percentage (default 85)
#
# Requires the test binary and profile data to already exist, i.e. run
# `swift test --enable-code-coverage` first.
set -euo pipefail

threshold="${1:-85}"

bin_path="$(swift build --show-bin-path)"
test_binary="${bin_path}/ThreeMFKitTests.xctest/Contents/MacOS/ThreeMFKitTests"
profdata="${bin_path}/codecov/default.profdata"

if [[ ! -f "$test_binary" ]]; then
  echo "error: test binary not found at ${test_binary} — run 'swift test --enable-code-coverage' first" >&2
  exit 1
fi
if [[ ! -f "$profdata" ]]; then
  echo "error: coverage profile not found at ${profdata} — run 'swift test --enable-code-coverage' first" >&2
  exit 1
fi

report="$(xcrun llvm-cov report "$test_binary" \
  -instr-profile="$profdata" \
  -ignore-filename-regex='(Tests|\.build|ThreeMFValidate)/')"

total_line="$(echo "$report" | grep '^TOTAL')"
if [[ -z "$total_line" ]]; then
  echo "error: could not find a TOTAL line in llvm-cov output" >&2
  echo "$report" >&2
  exit 1
fi

# The TOTAL line's columns are: Regions, Missed Regions, Region-Cover%,
# Functions, Missed Functions, Function-Cover%, Lines, Missed Lines,
# Line-Cover%, Branches, Missed Branches, Branch-Cover%. The line-coverage
# percentage is therefore the 10th whitespace-separated field.
line_coverage="$(echo "$total_line" | awk '{print $10}' | tr -d '%')"

if [[ -z "$line_coverage" ]]; then
  echo "error: could not parse line coverage from: ${total_line}" >&2
  exit 1
fi

echo "ThreeMFKit line coverage: ${line_coverage}% (threshold: ${threshold}%)"

# Compare as integers scaled by 100 to avoid depending on bc/awk float quirks.
coverage_scaled="$(awk -v v="$line_coverage" 'BEGIN { printf "%d", v * 100 }')"
threshold_scaled="$(awk -v v="$threshold" 'BEGIN { printf "%d", v * 100 }')"

if (( coverage_scaled < threshold_scaled )); then
  echo "error: line coverage ${line_coverage}% is below the ${threshold}% threshold" >&2
  exit 1
fi

echo "OK: line coverage meets the ${threshold}% threshold."
