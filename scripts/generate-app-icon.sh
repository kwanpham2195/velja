#!/usr/bin/env bash
# Regenerates Resources/AppIcon.icns from scripts/generate-app-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
iconset="$work_dir/AppIcon.iconset"
mkdir -p "$iconset"

swift scripts/generate-app-icon.swift "$work_dir/icon-1024.png"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$work_dir/icon-1024.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$work_dir/icon-1024.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil --convert icns --output Resources/AppIcon.icns "$iconset"
echo "Wrote Resources/AppIcon.icns"
