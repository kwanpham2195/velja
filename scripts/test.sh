#!/usr/bin/env bash
# Runs the VeljaCore unit tests.
# With only the Command Line Tools installed, SwiftPM cannot find Swift Testing on its own,
# so this passes the framework and macro plugin paths explicitly. The Command Line Tools also
# ship the Testing+Foundation cross-import overlay without its module files, so cross-import
# overlays are turned off; the tests do not use anything from that overlay.
set -euo pipefail
cd "$(dirname "$0")/.."

developer_dir="$(xcode-select -p)"
testing_frameworks="$developer_dir/Library/Developer/Frameworks"
testing_plugins="$developer_dir/usr/lib/swift/host/plugins/testing"

extra_flags=()
if [[ "$developer_dir" == *CommandLineTools* && -d "$testing_frameworks/Testing.framework" ]]; then
  extra_flags=(
    -Xswiftc -F -Xswiftc "$testing_frameworks"
    -Xlinker -F -Xlinker "$testing_frameworks"
    -Xlinker -rpath -Xlinker "$testing_frameworks"
    -Xswiftc -plugin-path -Xswiftc "$testing_plugins"
    -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays
  )
fi

swift test "${extra_flags[@]}" "$@"
