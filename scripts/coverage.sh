#!/bin/sh
# Enforce 100% line coverage for deterministic product logic.
# Native macOS/UI boundaries are listed and justified in docs/TESTING.md.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

./scripts/test.sh --enable-code-coverage "$@"
JSON="$(./scripts/test.sh --show-codecov-path)"

if [ ! -f "$JSON" ]; then
    echo "Coverage JSON not found: $JSON" >&2
    exit 1
fi

SCOPE='select(.filename |
    contains("/Sources/AutoLockCore/") or
    (contains("/Sources/AutoLockKit/") and (endswith("/BLEScanner.swift") | not)) or
    endswith("/Sources/AutoLockSystemAdapters/StagedAppVerifier.swift") or
    endswith("/Sources/AutoLockSystemAdapters/SelfUpdateCoordinator.swift")
)'

TOTALS="$(jq -r "[.data[0].files[] | $SCOPE | .summary.lines]
    | [(map(.covered) | add // 0), (map(.count) | add // 0)]
    | @tsv" "$JSON")"
COVERED="$(printf '%s' "$TOTALS" | cut -f1)"
COUNT="$(printf '%s' "$TOTALS" | cut -f2)"

if [ "$COUNT" -eq 0 ]; then
    echo "Coverage scope resolved to zero lines; refusing a false pass." >&2
    exit 1
fi

echo
echo "Meaningful coverage scope: $COVERED/$COUNT lines"
jq -r ".data[0].files[] | $SCOPE
    | [.summary.lines.percent, .summary.lines.covered, .summary.lines.count,
       (.filename | sub(\"^$ROOT/\"; \"\"))]
    | @tsv" "$JSON" | sort -n

if [ "$COVERED" -ne "$COUNT" ]; then
    echo "❌ Meaningful line coverage is below 100% ($COVERED/$COUNT)." >&2
    exit 1
fi

echo "✅ Meaningful line coverage: 100.00% ($COVERED/$COUNT)"
