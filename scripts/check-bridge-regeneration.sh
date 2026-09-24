#!/usr/bin/env bash
# Independent oracle for the embedded bridge copies: regenerates every sample's
# generated composition roots from the canonical reference with the feature set
# the copy declares, and byte-diffs them against what is committed.
#
# check-bridge-copies.sh validates the copies with name-based heuristics (grep
# for a class, prop, or dependency), which cannot detect semantic drift that
# keeps the names — a wrong Omit list, an event type exported with the wrong
# shape, a hand-edit that still mentions every feature. This script instead
# re-runs the single author of those files (scripts/assemble-bridge.sh) and
# requires the output to match, so the committed roots must be exactly what the
# assembler produces. It also re-runs a second time to prove idempotence.
#
# The feature set is derived from the copy's own iOS registry order — that is
# the order the assembler emits, so a correct copy regenerates byte-identically
# (see assemble-bridge.sh's --features argument order). This is deliberately a
# read of the artifact under test: if the copy declares the wrong features, the
# copy-consistency checks in check-bridge-copies.sh flag it; here we only prove
# the roots are reproducible.
set -euo pipefail

cd "$(dirname "$0")/.."
REFERENCE="reference/brightcove-player"

# shellcheck source=scripts/feature-catalog.sh
. "$(dirname "$0")/feature-catalog.sh"

objc_to_feature() {
  local f oc
  for f in $ALL_FEATURES; do
    oc="$(feature_objc "$f" | cut -d: -f2)"
    [ "$oc" = "$1" ] && { echo "$f"; return; }
  done
}

# Portable content hash: GNU coreutils' sha256sum on CI, shasum elsewhere.
if command -v sha256sum >/dev/null 2>&1; then
  hash_file() { sha256sum "$1" | cut -d' ' -f1; }
  hash_stdin() { sha256sum | cut -d' ' -f1; }
else
  hash_file() { shasum -a 256 "$1" | cut -d' ' -f1; }
  hash_stdin() { shasum -a 256 | cut -d' ' -f1; }
fi

failed=0
checked=0
for module in samples/*/*/modules/brightcove-player; do
  [ -d "$module" ] || continue
  checked=$((checked + 1))
  sample="$(cd "$module/../.." && pwd)"
  registry="$module/ios/BrightcoveFeatureRegistry.mm"

  if [ ! -f "$registry" ]; then
    echo "MISSING: $registry (cannot derive the copy's feature set)"
    failed=1
    continue
  fi

  features=""
  while IFS= read -r oc; do
    [ -n "$oc" ] && features="$features $(objc_to_feature "$oc")"
  done < <(grep -oE "\[[A-Za-z0-9]+ new\]" "$registry" | sed -E 's/^\[//; s/ new\]$//')

  # Regenerate two directory levels below the sample so the assembler's
  # web-build detection (dest/../.. == the sample) resolves against this
  # sample's own package.json / webpack.config.js.
  regen="$sample/modules/.regen-$$"
  rm -rf "$regen"
  if ! "$PWD/scripts/assemble-bridge.sh" --features "$features" "$regen" >/dev/null; then
    echo "REGEN-FAIL: $module (features:${features:- none})"
    rm -rf "$regen"
    failed=1
    continue
  fi

  # Compare only source files: a sample built locally carries untracked build
  # output (android/build, ios/Pods, ...) the fresh regeneration does not, and
  # that is not drift. SHA the filtered relative-path/file-content stream of
  # each tree so a missing, extra, or changed source file is still caught.
  # Sample-owned files legitimately differ between the committed copy and a
  # fresh regeneration (README describes the copy; package.json/lock belong to
  # the sample), so only assembler-owned content participates.
  tree_digest_filtered() {
    local root="$1"
    ( cd "$root" && find . \
        \( -name build -o -name .gradle -o -name .cxx -o -name node_modules \
           -o -name Pods -o -name xcuserdata -o -name '.regen-*' \) -prune \
        -o -type f \
           ! -name README.md ! -name package.json ! -name package-lock.json \
           ! -name '.DS_Store' ! -name '*.log' ! -name local.properties -print \
      | LC_ALL=C sort | while IFS= read -r rel; do
          printf '%s  ' "$rel"; hash_file "$rel"
        done | hash_stdin )
  }

  if [ "$(tree_digest_filtered "$regen")" != "$(tree_digest_filtered "$module")" ]; then
    echo "DRIFT: $module (committed roots are not what --features '${features# }' produces)"
    diff -rq "$regen" "$module" 2>&1 \
      | grep -vE 'README.md|/package.json|package-lock.json|/build|\.gradle|\.cxx|/Pods|node_modules|\.regen-' || true
    failed=1
  fi

  # Idempotence: a second run into the same directory must reproduce the first.
  if ! "$PWD/scripts/assemble-bridge.sh" --features "$features" "$regen" >/dev/null; then
    echo "REGEN-NOT-IDEMPOTENT: $module"
    failed=1
  fi
  rm -rf "$regen"
done

rm -rf samples/*/*/modules/.regen-* 2>/dev/null || true

if [ "$checked" -eq 0 ]; then
  echo "No sample bridge copies found under samples/*/*/modules/brightcove-player."
  exit 1
fi

if [ "$failed" -ne 0 ]; then
  echo ""
  echo "A sample's generated bridge roots are not reproducible from the"
  echo "reference. The roots are owned by scripts/assemble-bridge.sh: propagate"
  echo "the reference fix and re-assemble, rather than hand-editing the roots."
  exit 1
fi
echo "All $checked sample bridge copies regenerate byte-identically from the reference."
