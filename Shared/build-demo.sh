#!/bin/zsh
set -e
cd "$(dirname "$0")"
OUT="${1:-build}"
mkdir -p "$OUT"
swiftc -O -o "$OUT/ds-demo" Demo/main.swift *.swift -framework AppKit
cp Fonts/GoogleSansFlex.ttf "$OUT/GoogleSansFlex.ttf"
echo "Built $OUT/ds-demo"
