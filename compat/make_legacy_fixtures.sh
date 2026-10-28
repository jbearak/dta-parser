#!/bin/sh
# Write fixtures for releases 104 to 111 with ReadStat's writer (MIT,
# https://github.com/WizardMac/ReadStat), fetched at a pinned commit and
# built here; neither haven nor pandas writes these releases.
# Run from the repository root: sh compat/make_legacy_fixtures.sh
set -e
COMMIT=1434a0770a51b4fdb2c09515ea33c38f4fa51be8
work=$(mktemp -d)
git clone -q https://github.com/WizardMac/ReadStat.git "$work/ReadStat"
git -C "$work/ReadStat" checkout -q "$COMMIT"
src="$work/ReadStat/src"
cc -O1 -I"$src" -o "$work/write_fixture" compat/readstat/write_fixture.c \
  "$src"/readstat_*.c "$src"/CKHashTable.c "$src"/stata/*.c -liconv -lm
for release in 104 105 108 110 111; do
  "$work/write_fixture" "$release" "compat/fixtures/readstat_$release.dta"
done
rm -rf "$work"
