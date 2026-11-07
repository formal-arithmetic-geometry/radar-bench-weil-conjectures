#!/usr/bin/env bash
# radar bench script for formal-arithmetic-geometry/weil-conjectures.
#
# Called by the radar runner as `bench.sh` from this repo's root, with
#   RADAR_REPO   a fresh checkout of the weil-conjectures commit under test
#   RADAR_OUT    where the measurements (JSON lines) must end up
#   RADAR_CACHE  a directory that survives between runs of this repo
#
# What is measured is a clean build of weil-conjectures' *own* modules. Dependencies are
# set up first and not timed: Mathlib's oleans come from its cache, and every other module
# the project imports (proetale, mostly) is built in an unmeasured pass. Both live in
# RADAR_CACHE, so a dependency is only rebuilt when lake-manifest.json moves it.
set -euo pipefail

BENCH_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
export BENCH_DIR

cd "$RADAR_REPO"
lean --version # installs the toolchain through elan, and fails early if there is none

# Dependency checkouts and their builds, kept between runs.
mkdir -p "$RADAR_CACHE/packages" .lake
rm -rf .lake/packages
ln -s "$RADAR_CACHE/packages" .lake/packages

echo "::group::dependencies (not measured)"
lake exe cache get

# Every module imported from a dependency, built now so that the measured build below
# compiles nothing but weil-conjectures. Lake accepts module names as targets.
#
# The grep is a cheap overapproximation: doc comments contain prose lines that begin with
# "import", and core modules (Lean.*, Std.*) come with the toolchain and are no Lake target.
# So a candidate is kept only if some dependency package has its source file. One that is
# missed is not an error -- it is merely built, and timed, in the measured build instead.
external=()
while IFS= read -r module; do
  if compgen -G ".lake/packages/*/${module//.//}.lean" > /dev/null; then
    external+=("$module")
  fi
done < <(
  grep -rhoE '^(public |meta |private )*import (all )?[A-Za-z0-9_.]+' WeilConjectures WeilConjectures.lean Comparator 2>/dev/null \
    | awk '{print $NF}' \
    | grep -vE '^(WeilConjectures|Weil)(\.|$)' \
    | sort -u
)
echo "pre-building ${#external[@]} imported dependency modules"
if [ "${#external[@]}" -gt 0 ]; then
  lake build "${external[@]}"
fi
echo "::endgroup::"

# The measured build. Lake runs `lean` through the wrapper in fake-root/, which records
# instructions and line counts per module and the `lean --profile` categories; the
# wrapper reports the real toolchain's githash, so traces and Mathlib's cache still match.
REAL_PREFIX="$(lean --print-prefix)"
FAKE_ROOT="$BENCH_DIR/fake-root"
for entry in "$REAL_PREFIX"/*; do
  [[ "$(basename "$entry")" == bin ]] || ln -sfn "$entry" "$FAKE_ROOT/"
done
for entry in "$REAL_PREFIX"/bin/*; do
  [[ "$(basename "$entry")" == lean ]] || ln -sfn "$entry" "$FAKE_ROOT/bin/"
done

rm -rf .lake/build
: > "$RADAR_OUT"

LAKE_OVERRIDE_LEAN=true \
  LEAN="$FAKE_ROOT/bin/lean" \
  WRAPPER_OUT="$RADAR_OUT" \
  WRAPPER_PREFIX="$FAKE_ROOT" \
  timeout -s KILL 3h \
  "$BENCH_DIR/measure.py" -t build -d -a -o "$RADAR_OUT" -- lake build

echo "$(wc -l < "$RADAR_OUT") measurements written"
