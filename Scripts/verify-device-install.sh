#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$PROJECT_DIR/Tracker.xcodeproj"
DERIVED_ROOT="${TRACKER_SIGNED_DERIVED_ROOT:-$HOME/Library/Developer/Xcode/DerivedData/TrackerSignedCLI}"
PRODUCT_ROOT="$DERIVED_ROOT/Build/Products"
INTERMEDIATE_ROOT="$DERIVED_ROOT/Build/Intermediates.noindex"
IPHONE_BUNDLE_ID="${TRACKER_IOS_BUNDLE_ID:-com.toby.WorkoutTracker2026}"
WATCH_BUNDLE_ID="${TRACKER_WATCH_BUNDLE_ID:-com.toby.WorkoutTracker2026.watchkitapp}"
APP_PATH="$PRODUCT_ROOT/Debug-iphoneos/Tracker.app"
WATCH_APP_PATH="$APP_PATH/Watch/TrackerWatch.app"
WATCH_HARDWARE_UDID=""
WATCH_DETAILS_AVAILABLE=false

cd "$PROJECT_DIR"

if [[ -z "${TRACKER_IPHONE_DEVICE:-}" || -z "${TRACKER_WATCH_DEVICE:-}" ]]; then
  cat <<'EOF'
Set TRACKER_IPHONE_DEVICE and TRACKER_WATCH_DEVICE before running this script.

Find connected CoreDevice identifiers with:
  xcrun devicectl list devices

Example:
  TRACKER_IPHONE_DEVICE="<iPhone identifier or name>" \
  TRACKER_WATCH_DEVICE="<Apple Watch identifier or name>" \
  Scripts/verify-device-install.sh
EOF
  exit 64
fi

IPHONE_DEVICE="$TRACKER_IPHONE_DEVICE"
WATCH_DEVICE="$TRACKER_WATCH_DEVICE"

run_with_retry() {
  local label="$1"
  shift

  if "$@"; then
    return 0
  fi

  echo "$label failed; retrying once..."
  sleep 2
  "$@"
}

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
fi

rm -rf "$DERIVED_ROOT"

watch_details="$(mktemp -t tracker-watch-details.XXXXXX)"
if xcrun devicectl device info details --device "$WATCH_DEVICE" --timeout 60 >"$watch_details" 2>&1; then
  WATCH_DETAILS_AVAILABLE=true
  if grep -q "developerModeStatus: enabled" "$watch_details"; then
    WATCH_HARDWARE_UDID="$(awk -F': ' '/• udid:/ { print $2; exit }' "$watch_details")"
    if [[ -n "$WATCH_HARDWARE_UDID" ]]; then
      echo "Preparing Watch signing profile for hardware UDID: $WATCH_HARDWARE_UDID"
      xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme TrackerWatch \
        -sdk watchos \
        -destination "platform=watchOS,id=$WATCH_HARDWARE_UDID" \
        -derivedDataPath "$DERIVED_ROOT/WatchProfile" \
        -allowProvisioningUpdates \
        -allowProvisioningDeviceRegistration \
        build \
        -quiet
    fi
  fi
fi

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme Tracker \
  -destination 'generic/platform=iOS' \
  SYMROOT="$PRODUCT_ROOT" \
  OBJROOT="$INTERMEDIATE_ROOT" \
  -allowProvisioningUpdates \
  build \
  -quiet

echo "Signed entitlements:"
codesign -d --entitlements :- "$APP_PATH" 2>/dev/null | grep -E "application-identifier|com.apple.developer.healthkit|com.apple.developer.team-identifier"
codesign -d --entitlements :- "$WATCH_APP_PATH" 2>/dev/null | grep -E "application-identifier|com.apple.developer.healthkit|com.apple.developer.team-identifier"

if [[ -n "$WATCH_HARDWARE_UDID" ]]; then
  embedded_watch_profile="$(mktemp -t tracker-embedded-watch-profile.XXXXXX)"
  security cms -D -i "$WATCH_APP_PATH/embedded.mobileprovision" >"$embedded_watch_profile"
  if ! grep -q "$WATCH_HARDWARE_UDID" "$embedded_watch_profile"; then
    echo "Embedded Watch provisioning profile does not include Watch UDID: $WATCH_HARDWARE_UDID"
    rm -f "$embedded_watch_profile" "$watch_details"
    exit 1
  fi
  rm -f "$embedded_watch_profile"
fi

echo "Installing iPhone app on: $IPHONE_DEVICE"
xcrun devicectl device install app \
  --device "$IPHONE_DEVICE" \
  --timeout 120 \
  "$APP_PATH"

echo "Launching iPhone app: $IPHONE_BUNDLE_ID"
run_with_retry "iPhone launch" xcrun devicectl device process launch \
  --device "$IPHONE_DEVICE" \
  --terminate-existing \
  --timeout 60 \
  "$IPHONE_BUNDLE_ID"

xcrun devicectl device info apps \
  --device "$IPHONE_DEVICE" \
  --bundle-id "$IPHONE_BUNDLE_ID" \
  --timeout 60

if [[ "$WATCH_DETAILS_AVAILABLE" == true ]]; then
  if grep -q "developerModeStatus: enabled" "$watch_details"; then
    echo "Installing Watch app on: $WATCH_DEVICE"
    run_with_retry "Watch install" xcrun devicectl device install app \
      --device "$WATCH_DEVICE" \
      --timeout 120 \
      "$WATCH_APP_PATH"

    echo "Launching Watch app: $WATCH_BUNDLE_ID"
    run_with_retry "Watch launch" xcrun devicectl device process launch \
      --device "$WATCH_DEVICE" \
      --terminate-existing \
      --timeout 60 \
      "$WATCH_BUNDLE_ID"

    xcrun devicectl device info apps \
      --device "$WATCH_DEVICE" \
      --bundle-id "$WATCH_BUNDLE_ID" \
      --timeout 60
  else
    echo "Skipping direct Watch install: Developer Mode is not enabled on $WATCH_DEVICE."
    grep "developerModeStatus:" "$watch_details" || true
  fi
else
  echo "Skipping direct Watch install: unable to read Watch device details."
  cat "$watch_details"
fi

rm -f "$watch_details"
