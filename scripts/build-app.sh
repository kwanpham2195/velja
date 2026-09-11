#!/usr/bin/env bash
# Builds build/Velja.app: compiles a release binary with SwiftPM, assembles the app bundle,
# and signs it ad hoc so macOS will run it and register its URL handlers.
#
# Environment:
#   VELJA_VERSION       CFBundleShortVersionString (default: 1.0.0)
#   VELJA_BUILD_NUMBER  CFBundleVersion (default: number of git commits, or 1)
set -euo pipefail
cd "$(dirname "$0")/.."

version="${VELJA_VERSION:-1.0.0}"
build_number="${VELJA_BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
app_bundle="build/Velja.app"

swift build -c release --product Velja
binary_path="$(swift build -c release --product Velja --show-bin-path)/Velja"

rm -rf "$app_bundle"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
cp "$binary_path" "$app_bundle/Contents/MacOS/Velja"
cp Resources/AppIcon.icns "$app_bundle/Contents/Resources/AppIcon.icns"
info_plist="$app_bundle/Contents/Info.plist"
cp Resources/Info.plist "$info_plist"
# plutil stores the values as-is, so versions containing "/" or "&" survive.
plutil -replace CFBundleShortVersionString -string "$version" "$info_plist"
plutil -replace CFBundleVersion -string "$build_number" "$info_plist"
printf 'APPL????' > "$app_bundle/Contents/PkgInfo"

plutil -lint "$info_plist" >/dev/null
codesign --force --sign - --timestamp=none "$app_bundle"
codesign --verify --strict "$app_bundle"

echo "Built $app_bundle (version $version, build $build_number)"
