#!/bin/zsh
# Builds the fake-photo generator and runs it. With --import-simulator, the photos are
# added to the booted simulator's photo library afterwards.
#
#   Scripts/test-photos/generate.sh --count 100000 --out ~/PhotoSweepTestPhotos --verify 50
#   Scripts/test-photos/generate.sh --count 5000 --import-simulator
set -euo pipefail

here=${0:A:h}
binary="$here/.build/TestPhotoGenerator"
mkdir -p "$here/.build"
if [[ ! -x "$binary" || "$here/TestPhotoGenerator.swift" -nt "$binary" ]]; then
    echo "Building generator…"
    xcrun swiftc -O -o "$binary" "$here/TestPhotoGenerator.swift"
fi

import_simulator=false
out="TestPhotos"
args=()
while (( $# )); do
    case "$1" in
        --import-simulator) import_simulator=true ;;
        --out) out="$2"; args+=("$1" "$2"); shift ;;
        *) args+=("$1") ;;
    esac
    shift
done

"$binary" "${args[@]}"

if $import_simulator; then
    # simctl takes many files per call; batches keep the argument list within limits.
    echo "Importing into the booted simulator…"
    files=("$out"/*.jpg(N))
    total=${#files}
    for (( i = 1; i <= total; i += 500 )); do
        xcrun simctl addmedia booted "${files[@]:$((i - 1)):500}"
        echo "  $(( i + 499 < total ? i + 499 : total ))/$total"
    done
fi
