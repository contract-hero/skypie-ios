#!/usr/bin/env bash
# Write the RevenueCat PUBLIC SDK key into the generated iOS Info.plist.
#
# `Info.ios.plist` carries the literal `$(REVENUECAT_API_KEY)`, which Xcode
# does not expand for a plist merged by the Tauri CLI. This script replaces it
# in the GENERATED plist, after `tauri ios init` and before each build.
#
# Run it from the iOS build scripts; it is a no-op with no key set, because an
# unconfigured build must still produce a working app that simply cannot sell
# anything.
#
#   export REVENUECAT_API_KEY=appl_xxxxxxxxxxxxxxxxxxxx
#   ./scripts/inject-revenuecat-key.sh
#
# The PUBLIC key only. It is designed to ship inside a client binary. The
# secret key belongs in the RevenueCat dashboard and nowhere near this repo.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST="${REPO_ROOT}/src-tauri/gen/apple/skypie-ios_iOS/Info.plist"

if [ ! -f "${PLIST}" ]; then
  echo "inject-revenuecat-key: ${PLIST} is missing; run 'pnpm tauri ios init' first" >&2
  exit 1
fi

KEY="${REVENUECAT_API_KEY:-}"
if [ -z "${KEY}" ]; then
  echo "inject-revenuecat-key: REVENUECAT_API_KEY is not set."
  echo "  The build continues. Reading works; the paywall will report the store"
  echo "  as unavailable, and no purchase can be made from this build."
  exit 0
fi

case "${KEY}" in
  appl_*) ;;
  sk_*|"sk "*)
    echo "inject-revenuecat-key: that is a SECRET key. Use the public 'appl_…' key." >&2
    exit 1
    ;;
  *)
    echo "inject-revenuecat-key: a RevenueCat iOS public key starts with 'appl_'." >&2
    exit 1
    ;;
esac

/usr/libexec/PlistBuddy -c "Set :RevenueCatAPIKey ${KEY}" "${PLIST}" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :RevenueCatAPIKey string ${KEY}" "${PLIST}"

echo "inject-revenuecat-key: set RevenueCatAPIKey (${KEY:0:9}…) in ${PLIST}"
