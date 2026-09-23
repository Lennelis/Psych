#!/usr/bin/env bash
# Builds lime with input timestamps in it.
#
# SDL stamps every key and touch event with the moment it happened. Lime 8.1.2 reads
# the keycode and the window id off those events and throws the timestamp away before
# Haxe ever sees it, so the game only knows an input arrived "some time during the last
# frame" - which is where the up-to-a-frame lateness on every judgement comes from.
#
# patches/lime-precise-input/ carries the number through. It touches lime's C++, so the
# native library has to be rebuilt afterwards for the Haxe side to have anything to read.
# That is all this script does: patch the installed copy once, then rebuild it for
# whichever architecture it was handed.
#
#   ./setup/patch-lime.sh -Dandroid -DHXCPP_ARM64 -DPLATFORM=android-21
#   ./setup/patch-lime.sh -DHXCPP_M64
#
# The flags are passed straight to hxcpp and are the same ones `lime rebuild` would
# have used. Going through hxcpp directly is what makes building one architecture
# possible: `lime rebuild android` builds all four, which is most of an hour for three
# nobody ships.
#
# Safe to run twice - the second run skips the patch and rebuilds, which is a no-op
# once the objects are there.
set -e

FLAGS=("$@")
if [ ${#FLAGS[@]} -eq 0 ]; then
	echo "usage: $0 <hxcpp flags...>" >&2
	exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCH="$ROOT/patches/lime-precise-input/lime-8.1.2-precise-input.patch"

if [ ! -f "$PATCH" ]; then
	echo "No patch at $PATCH" >&2
	exit 1
fi

LIME="$(haxelib libpath lime | tr -d '\r' | tail -1)"
# Git Bash gets C:\... back from haxelib and cannot cd into it.
if command -v cygpath > /dev/null 2>&1; then
	LIME="$(cygpath -u "$LIME")"
fi

# haxelib prints a trailing separator, which turns every path built from it into one with
# a doubled slash. Harmless in most places and not worth risking anywhere.
LIME="${LIME%/}"

if [ ! -d "$LIME/project" ]; then
	echo "Could not find lime's sources - haxelib says $LIME" >&2
	echo "What is actually there:" >&2
	ls -A "$LIME" >&2 2>/dev/null || echo "  (could not list it - the path may be wrong)" >&2
	echo >&2
	echo "If there is no project/ directory, the haxelib release of lime ships without" >&2
	echo "its C++ sources and cannot be rebuilt in place. That would need a git checkout" >&2
	echo "of lime with its submodules, which is a different and much larger job." >&2
	exit 1
fi

# The patch is written against 8.1.2 exactly. It would very likely apply to a nearby
# version, but "very likely" and a silently half-patched lime are a bad combination.
VERSION="$(grep -o '"version"[^,]*' "$LIME/haxelib.json" | head -1 | grep -o '[0-9][0-9.]*')"
if [ "$VERSION" != "8.1.2" ]; then
	echo "This patch is for lime 8.1.2; the installed copy is $VERSION." >&2
	exit 1
fi

# Keyed on the patch's contents, so editing the patch re-applies it rather than
# leaving the old version in place and claiming it is current.
STAMP="$( (cksum < "$PATCH") | awk '{print $1 "-" $2}')"
MARKER="$LIME/.precise-input-applied"

if [ -f "$MARKER" ] && [ "$(cat "$MARKER")" = "$STAMP" ]; then
	echo "lime is already patched."
else
	if [ -f "$MARKER" ]; then
		echo "lime carries a different version of this patch. Reinstall it first:" >&2
		echo "  haxelib remove lime 8.1.2 && haxelib install lime 8.1.2" >&2
		exit 1
	fi

	echo "Patching lime at $LIME"
	# git apply is atomic and is present wherever this runs; GNU patch is the fallback
	# for a git too old to apply outside a work tree.
	if ! ( cd "$LIME" && git apply -p1 --whitespace=nowarn "$PATCH" ); then
		patch -p1 -d "$LIME" < "$PATCH"
	fi
	echo "$STAMP" > "$MARKER"
fi

# hxcpp otherwise reports a failed compile and exits 0, which would leave the build
# going with a half-built library and no sign anything went wrong.
export HXCPP_EXIT_ON_ERROR=1

echo "Rebuilding lime: ${FLAGS[*]}"
( cd "$LIME/project" && haxelib run hxcpp Build.xml "${FLAGS[@]}" )

echo "Done. Build the game with -D PATCHED_LIME to switch PreciseInput on."
