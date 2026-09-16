#!/usr/bin/env bash
# Build, sign and install Sky Pie on a CONNECTED physical iPhone.
#
# The simulator counterpart is scripts/build-ios-sim.sh. This one exists
# because the device path differs in three ways that each cost a debugging
# session to rediscover:
#
#   1. The Swift runtime. A device keeps it at /usr/lib/swift and the binary
#      needs an LC_RPATH entry pointing there, or dyld fails at launch with
#      "Library not loaded: @rpath/libswiftCore.dylib". The simulator resolves
#      Swift from its runtime root and never needs the rpath, so a green
#      build-ios-sim.sh proves NOTHING about a device. The setting lives in
#      src-tauri/gen/apple/project.yml (LD_RUNPATH_SEARCH_PATHS), which is the
#      one tracked file under the otherwise-gitignored gen/.
#
#   2. Signing. DEVELOPMENT_TEAM also lives in project.yml. `tauri ios init`
#      PRESERVES an existing project.yml and regenerates the .xcodeproj from
#      it; `tauri ios build` regenerates nothing. So after editing project.yml
#      you must re-run init, not just build.
#
#   3. A free Apple Development profile lasts SEVEN DAYS. When the app stops
#      launching and nothing changed, check the expiry before anything else.
set -euo pipefail

cd "$(dirname "$0")/.."

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

# Same shim as build-ios-sim.sh: the Tauri CLI builds xcodebuild's environment
# from an allow-list and drops DEVELOPER_DIR, so it has to ride on PATH.
SHIM_DIR="$(mktemp -d)"
trap 'rm -rf "$SHIM_DIR"' EXIT
cat > "$SHIM_DIR/xcodebuild" <<EOF
#!/bin/sh
export DEVELOPER_DIR="$DEVELOPER_DIR"
exec /usr/bin/xcodebuild "\$@"
EOF
chmod +x "$SHIM_DIR/xcodebuild"
export PATH="$SHIM_DIR:$PATH"

# Match the UUID by SHAPE, not by column: a device name contains spaces
# ("iPhone de Álvaro"), so every field index shifts with it.
# Match the UUID by SHAPE, not by column: a device name contains spaces
# ("iPhone de Álvaro"), so every field index shifts with it. `|| true` keeps
# `set -e` from killing the script before the message below can explain.
PAIRED="$(xcrun devicectl list devices 2>/dev/null \
  | awk '/available \(paired\)/ {
      uuid = ""
      for (i = 1; i <= NF; i++)
        if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/) {
          uuid = $i
          name = ""
          for (j = 1; j < i - 1; j++) name = name $j " "
          break
        }
      if (uuid != "") print uuid "\t" name
    }' || true)"

if [ -n "${SKYPIE_IOS_DEVICE:-}" ]; then
  DEVICE="$SKYPIE_IOS_DEVICE"
  DEVICE_NAME="$(printf '%s\n' "$PAIRED" | awk -F'\t' -v u="$DEVICE" '$1 == u {print $2}')"
else
  COUNT="$(printf '%s' "$PAIRED" | grep -c . || true)"
  if [ "$COUNT" -eq 0 ]; then
    echo "No paired iPhone found. Connect one, trust this Mac, and retry." >&2
    echo "Override with: SKYPIE_IOS_DEVICE=<uuid> $0" >&2
    exit 1
  fi
  if [ "$COUNT" -gt 1 ]; then
    # Installing onto the wrong phone is silent, so make the choice explicit.
    echo "More than one paired device:" >&2
    printf '%s\n' "$PAIRED" | awk -F'\t' '{print "  " $1 "  " $2}' >&2
    echo "Pick one: SKYPIE_IOS_DEVICE=<uuid> $0" >&2
    exit 1
  fi
  DEVICE="$(printf '%s' "$PAIRED" | cut -f1)"
  DEVICE_NAME="$(printf '%s' "$PAIRED" | cut -f2)"
fi
echo "==> Device: ${DEVICE_NAME:-unknown} ($DEVICE)"

./scripts/inject-revenuecat-key.sh

# A left-over .app makes the CLI's move out of the archive fail with
# "Directory not empty" AFTER xcodebuild already said BUILD SUCCEEDED.
rm -rf src-tauri/gen/apple/build/skypie-ios_iOS.xcarchive \
       src-tauri/gen/apple/build/arm64

echo "==> Building (release, aarch64-apple-ios)"
pnpm tauri ios build --target aarch64

# NEWEST, not first: DerivedData can hold several skypie-ios-* directories (a
# worktree build makes its own), and `-print -quit` would take whichever the
# traversal reached first — verifying and installing a stale bundle while
# reporting success. `|| true` keeps the message below reachable under `set -e`.
APP="$(find "$HOME/Library/Developer/Xcode/DerivedData" -maxdepth 6 \
  -path '*release-iphoneos/Sky Pie.app' -print0 2>/dev/null \
  | xargs -0 -I{} stat -f '%m %N' {} 2>/dev/null \
  | sort -rn | head -1 | cut -d' ' -f2- || true)"
if [ -z "${APP:-}" ]; then
  echo "Built .app not found under DerivedData." >&2
  exit 1
fi

# The two regressions that are invisible until the app is on the phone.
# LC_RPATH entries ONLY. Grepping the whole `otool -l` dump matches the ~20
# LC_LOAD_DYLIB lines that name /usr/lib/swift/libswiftCore.dylib, which are
# present whether or not an LC_RPATH exists — so the naive grep can never fail
# and the guard would be decorative.
RPATHS="$(otool -l "$APP/Sky Pie" | awk '
  /LC_RPATH/ { in_rpath = 1; next }
  in_rpath && $1 == "path" { print $2; in_rpath = 0 }
')"
printf '%s\n' "$RPATHS" | grep -qx '/usr/lib/swift' \
  || { echo "FAIL: /usr/lib/swift is not an LC_RPATH — the app will die in dyld" >&2
       echo "      with \"Library not loaded: @rpath/libswiftCore.dylib\"." >&2
       echo "      Found: ${RPATHS:-(none)}" >&2
       echo "      Check LD_RUNPATH_SEARCH_PATHS in gen/apple/project.yml," >&2
       echo "      then re-run 'pnpm tauri ios init' (build alone will NOT do it)." >&2
       exit 1; }
echo "ok: /usr/lib/swift is an LC_RPATH"

SCHEME="$(/usr/libexec/PlistBuddy -c \
  "Print :CFBundleURLTypes:0:CFBundleURLSchemes:0" "$APP/Info.plist" 2>/dev/null || true)"
[ "$SCHEME" = "skypie" ] \
  || { echo "FAIL: the bundle registers no skypie:// handler (got '${SCHEME:-nothing}')." >&2
       echo "      Check deep-link.mobile in tauri.conf.json." >&2; exit 1; }
echo "ok: the bundle registers skypie://"

echo "==> Installing"
xcrun devicectl device install app --device "$DEVICE" "$APP"

echo
echo "Unlock the phone, then:"
echo "  xcrun devicectl device process launch --device $DEVICE ai.skypie.SkyPie"
echo
echo "First install on a NEW phone also needs, once:"
echo "  Settings > Privacy & Security > Developer Mode  (on, then restart)"
echo "  Settings > General > VPN & Device Management > Developer App > Trust"
echo
echo "Open a skypie:// link on it (iOS does not linkify custom schemes in text):"
echo "  xcrun devicectl device process launch --device $DEVICE \\"
echo "    --payload-url '<skypie://…>' ai.skypie.SkyPie"
