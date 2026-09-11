#!/usr/bin/env bash
# End-to-end tests for Linkfork.
#
# Runs the real build/Linkfork.app against a temporary settings folder and sends it links through
# Launch Services with `open`, the same path a clicked link takes. Links are routed to a fake
# browser (e2e/FakeBrowser) that records every link and launch argument it receives, so no real
# browser opens and your real settings are never read or written.
#
# Two links in this suite end in the browser picker; it shows on screen until the run finishes.
#
# Environment:
#   VELJA_E2E_SKIP_BUILD=1   use the existing build/Linkfork.app instead of rebuilding it
set -euo pipefail
cd "$(dirname "$0")/.."

lsregister=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
velja_app="$PWD/build/Linkfork.app"
fake_bundle_id="com.kwanpham.VeljaE2EBrowser"

if pgrep -x Linkfork >/dev/null; then
  echo "e2e: another Linkfork is running. Quit it first; Launch Services would deliver the test links to it." >&2
  exit 1
fi

if [[ "${VELJA_E2E_SKIP_BUILD:-}" != 1 ]]; then
  ./scripts/build-app.sh >/dev/null
fi

# Inside build/, not /tmp: Launch Services never returns apps registered from /tmp, so Linkfork would
# not see the fake browser.
mkdir -p build
work_dir="$(cd "$(mktemp -d "$PWD/build/e2e-run.XXXXXX")" && pwd -P)"
fake_app="$work_dir/Velja E2E Browser.app"
record_file="$work_dir/fake-browser-record.tsv"
support_dir="$work_dir/support"
chromium_user_data="$work_dir/chromium-user-data"
velja_log="$work_dir/velja.log"
velja_pid=""
log_stream_pid=""

# Process paths use the folder names as stored on disk, which can differ in case from $PWD, so
# process lookups by path ignore case.
cleanup() {
  [[ -n "$velja_pid" ]] && kill "$velja_pid" 2>/dev/null || true
  [[ -n "$log_stream_pid" ]] && kill "$log_stream_pid" 2>/dev/null || true
  pkill -if "$fake_app/Contents/MacOS/FakeBrowser" 2>/dev/null || true
  [[ -d "$fake_app" ]] && "$lsregister" -u "$fake_app" 2>/dev/null || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

# --- Fixtures -------------------------------------------------------------------------------

mkdir -p "$fake_app/Contents/MacOS" "$support_dir" "$chromium_user_data"
swiftc -swift-version 6 -O -o "$fake_app/Contents/MacOS/FakeBrowser" e2e/FakeBrowser/main.swift
cp e2e/FakeBrowser/Info.plist "$fake_app/Contents/Info.plist"
plutil -replace VeljaE2ERecordFile -string "$record_file" "$fake_app/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$fake_app" 2>/dev/null
"$lsregister" -f "$fake_app"
touch "$record_file"

# The fake browser gets two Chromium-style profiles through VELJA_CHROMIUM_USER_DATA_DIRECTORIES.
cat > "$chromium_user_data/Local State" <<'JSON'
{"profile": {"info_cache": {"Default": {"name": "Personal"}, "Profile 1": {"name": "Work"}},
             "profiles_order": ["Default", "Profile 1"]}}
JSON

# App links are all off, so a Zoom or Teams link can never launch a real app during the run.
cat > "$support_dir/Settings.json" <<JSON
{
  "primaryBrowser": {"kind": "browser", "target": {"bundleIdentifier": "$fake_bundle_id"}},
  "alternativeBrowser": {"kind": "browserPicker"},
  "removesTrackingParameters": true,
  "keepsLinkHistory": true,
  "disabledNativeAppLinkHandlers": ["zoom", "microsoftTeams", "figma", "spotify", "discord", "appleMusic"],
  "rules": [
    {"name": "Work profile", "urlMatchers": [{"kind": "domain", "pattern": "work.example"}],
     "action": {"kind": "openInBrowser", "target": {"bundleIdentifier": "$fake_bundle_id", "profileDirectory": "Profile 1"}}},
    {"name": "From fake browser", "urlMatchers": [{"kind": "domain", "pattern": "from-fake.example"}], "sourceAppBundleIdentifiers": ["$fake_bundle_id"],
     "action": {"kind": "openInBrowser", "target": {"bundleIdentifier": "$fake_bundle_id", "profileDirectory": "Default"}}},
    {"name": "Missing browser", "urlMatchers": [{"kind": "domain", "pattern": "gone.example"}],
     "action": {"kind": "openInBrowser", "target": {"bundleIdentifier": "com.example.NotInstalled"}}}
  ]
}
JSON

# --- Launch Linkfork ------------------------------------------------------------------------

/usr/bin/log stream --level info --style compact --predicate 'subsystem == "com.kwanpham.Velja"' > "$velja_log" 2>&1 &
log_stream_pid=$!
sleep 1

VELJA_SUPPORT_DIRECTORY="$support_dir" \
VELJA_CHROMIUM_USER_DATA_DIRECTORIES="$fake_bundle_id=$chromium_user_data" \
  "$velja_app/Contents/MacOS/Linkfork" >"$work_dir/velja.stdout" 2>&1 &
velja_pid=$!

# --- Helpers --------------------------------------------------------------------------------

passed=0
failed=0
tab=$'\t'

pass() { passed=$((passed + 1)); echo "  ok    $1"; }
fail() { failed=$((failed + 1)); echo "  FAIL  $1"; shift; for detail in "$@"; do echo "        $detail"; done; }

# Waits up to 15 seconds for a line in a file to match an extended regex.
wait_for_line() {
  local file="$1" pattern="$2" deadline=$((SECONDS + 15))
  while (( SECONDS < deadline )); do
    if tr -d '\000' < "$file" | grep -Eq -- "$pattern"; then
      return 0
    fi
    sleep 0.2
  done
  return 1
}

regex_escape() { printf '%s' "$1" | sed -e 's/[]\/$*.^|?+(){}[]/\\&/g'; }

# A regex for a log line from this run's Linkfork process containing the literal message.
velja_log_pattern() { echo "Linkfork\\[$velja_pid:.*$(regex_escape "$1")"; }

send_link() { open -a "$velja_app" "$1"; }

expect_record() {
  local name="$1" pattern="$2"
  if wait_for_line "$record_file" "$pattern"; then pass "$name"; else fail "$name" "expected fake browser record matching: $pattern" "records:" "$(cat "$record_file")"; fi
}

expect_velja_log() {
  local name="$1" message="$2"
  if wait_for_line "$velja_log" "$(velja_log_pattern "$message")"; then pass "$name"; else fail "$name" "expected Linkfork log line containing: $message"; fi
}

expect_no_record() {
  local name="$1" fragment="$2"
  sleep 2
  if grep -qF -- "$fragment" "$record_file"; then fail "$name" "the fake browser received a link containing: $fragment"; else pass "$name"; fi
}

echo "Linkfork end-to-end tests"

if wait_for_line "$velja_log" "$(velja_log_pattern "Menu bar icon added")"; then
  pass "Linkfork launches with the test settings"
else
  fail "Linkfork launches with the test settings" "no startup log line; stdout:" "$(cat "$work_dir/velja.stdout")"
  exit 1
fi

# --- Tests: links that open in the fake browser ---------------------------------------------

send_link 'https://example.net/page?utm_source=e2e&keep=1&fbclid=abc#top'
expect_record "primary browser gets the link without tracking parameters" \
  "^open${tab}$(regex_escape 'https://example.net/page?keep=1#top')\$"

send_link 'https://docs.work.example/a?b=1'
expect_record "domain rule opens the link in a Chromium-style profile" \
  "^launch${tab}--profile-directory=Profile 1${tab}$(regex_escape 'https://docs.work.example/a?b=1')\$"

send_link "linkfork:open?url=https%3A%2F%2Fexample.com%2Fcommand&app=$fake_bundle_id"
expect_record "linkfork:open opens the named browser" \
  "^open${tab}$(regex_escape 'https://example.com/command')\$"

printf '<!doctype html><title>Linkfork e2e</title>\n' > "$work_dir/page.html"
open -a "$velja_app" "$work_dir/page.html"
expect_record "HTML files open in the primary browser" \
  "^open${tab}file://.*/page\\.html\$"

# The "From fake browser" rule needs both its domain and the fake browser as the source app.
# Links sent with `open` have no app of their own, so Linkfork falls back to the frontmost app; wait
# until the fake browser has quit so that fallback cannot be the fake browser.
deadline=$((SECONDS + 15))
while pgrep -if "$fake_app/Contents/MacOS/FakeBrowser" >/dev/null && (( SECONDS < deadline )); do
  sleep 0.3
done
send_link 'https://from-fake.example/direct'
expect_record "source app rule ignores links from other apps" \
  "^open${tab}$(regex_escape 'https://from-fake.example/direct')\$"

open -n -a "$fake_app" --args --send-link-to-velja "$velja_app" 'https://from-fake.example/link'
expect_record "source app rule matches the app the link came from" \
  "^launch${tab}--profile-directory=Default${tab}$(regex_escape 'https://from-fake.example/link')\$"

# --- Tests: link history --------------------------------------------------------------------

sleep 1
history_check="$(python3 - "$support_dir/History.json" "$fake_bundle_id" <<'PYTHON'
import json, os, sys
if not os.path.exists(sys.argv[1]):
    print("History.json was not written")
    sys.exit(0)
entries = json.load(open(sys.argv[1]))["entries"]
fake_bundle_id = sys.argv[2]
problems = []
def find(predicate):
    return next((entry for entry in entries if predicate(entry)), None)
primary = find(lambda e: e["url"] == "https://example.net/page?keep=1#top")
if not primary or primary["reasonDescription"] != "Primary browser":
    problems.append(f"no 'Primary browser' entry for the cleaned link: {primary}")
from_fake = find(lambda e: e["url"] == "https://from-fake.example/link")
if not from_fake or from_fake.get("sourceAppBundleIdentifier") != fake_bundle_id \
        or from_fake["reasonDescription"] != "Rule: From fake browser" \
        or from_fake["destinationName"] != "Velja E2E Browser — Personal":
    problems.append(f"source app entry is wrong: {from_fake}")
print("\n".join(problems))
PYTHON
)"
if [[ -z "$history_check" ]]; then
  pass "history records the source app, rule, and profile"
else
  fail "history records the source app, rule, and profile" "$history_check"
fi

# --- Tests: links that must not reach a browser ---------------------------------------------

open -a "$velja_app" 'linkfork:open?url=file%3A%2F%2F%2Fetc%2Fhosts'
expect_velja_log "linkfork:open refuses local files" "Ignored an invalid linkfork: URL"
expect_no_record "linkfork:open never passes a local file on" "/etc/hosts"

send_link 'linkfork:open?url=https%3A%2F%2Fexample.com%2Fterminal-attempt&app=com.apple.Terminal'
expect_velja_log "linkfork:open with a non-browser app shows the picker" "Showing browser picker (linkfork:open command)"
expect_no_record "linkfork:open with a non-browser app opens nothing by itself" "terminal-attempt"

send_link 'https://gone.example/x'
expect_velja_log "a rule for an uninstalled browser falls back to the picker" "Showing browser picker (Configured browser is not installed)"
expect_no_record "a rule for an uninstalled browser opens nothing by itself" "gone.example"

if kill -0 "$velja_pid" 2>/dev/null; then pass "Linkfork is still running"; else fail "Linkfork is still running" "Linkfork exited during the run"; fi

echo "$passed passed, $failed failed"
[[ "$failed" -eq 0 ]]
