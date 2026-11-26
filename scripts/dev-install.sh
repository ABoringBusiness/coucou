#!/usr/bin/env bash
# Builds HeyApex Eye (the branded Coucou fork) and installs it cleanly in
# /Applications/HeyApex Eye.app (falling back gracefully if Coucou.app is built),
# removing stale DerivedData copies so macOS TCC permissions (Accessibility,
# Screen Recording, Microphone) stay attached to a single app bundle.
#
#   ./scripts/dev-install.sh                # incremental build + install + launch
#   ./scripts/dev-install.sh --regenerate   # regenerate xcodeproj via xcodegen + re-apply HeyApex Eye identity
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGENERATE=0
for arg in "$@"; do
  case "$arg" in
    --regenerate) REGENERATE=1 ;;
    *) echo "Usage: $0 [--regenerate]" >&2; exit 1 ;;
  esac
done

SCHEME="${HEYAPEX_BUILD_SCHEME:-}"
CONFIG="${HEYAPEX_BUILD_CONFIG:-}"
DERIVED="${HOME}/Library/Developer/Xcode/DerivedData/HeyApexEyeDev"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
DEFAULT_TEAM="${HEYAPEX_DEV_TEAM:-A9MHJC28M3}"

apply_heyapex_pbxproj_identity() {
  local pbx="$1"
  [ -f "$pbx" ] || return 0
  python3 - "$pbx" "${DEFAULT_TEAM}" <<'PY'
import re, sys
path, team = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as f:
    src = f.read()
src = src.replace("DEVELOPMENT_TEAM = 256AUJ9555;", f"DEVELOPMENT_TEAM = {team};")
src = src.replace("PRODUCT_BUNDLE_IDENTIFIER = fr.louisraille.NotchBuddy;", "PRODUCT_BUNDLE_IDENTIFIER = ai.heyapex.eye;")
src = src.replace("PRODUCT_BUNDLE_IDENTIFIER = fr.louisraille.Coucou.NotificationContent;", "PRODUCT_BUNDLE_IDENTIFIER = ai.heyapex.eye.NotificationContent;")
src = src.replace("PRODUCT_BUNDLE_IDENTIFIER = fr.louisraille.Coucou.Widgets;", "PRODUCT_BUNDLE_IDENTIFIER = ai.heyapex.eye.Widgets;")
src = src.replace("PRODUCT_BUNDLE_IDENTIFIER = fr.louisraille.Coucou;", "PRODUCT_BUNDLE_IDENTIFIER = ai.heyapex.eye;")
src = re.sub(r'\bPRODUCT_NAME = Coucou;', 'PRODUCT_NAME = "HeyApex Eye";', src)
src = src.replace("PRODUCT_NAME = CoucouNotificationContent;", "PRODUCT_NAME = HeyApexEyeNotificationContent;")
src = src.replace("PRODUCT_NAME = CoucouWidgets;", "PRODUCT_NAME = HeyApexEyeWidgets;")
with open(path, "w", encoding="utf-8") as f:
    f.write(src)
PY
}

cd "${REPO_ROOT}/NotchBuddy"
if [ "${REGENERATE}" -eq 1 ] || [ ! -d "NotchBuddy.xcodeproj" ]; then
  echo "Generating NotchBuddy.xcodeproj (xcodegen + HeyApex Eye identity)..."
  xcodegen >/dev/null
fi
apply_heyapex_pbxproj_identity "NotchBuddy.xcodeproj/project.pbxproj"

# Prefer Boomslang AI Developer ID Release build + direct Developer ID signing when available
# in Keychain so /Applications/HeyApex Eye.app preserves TeamIdentifier (A9MHJC28M3) and TCC grants
# without requiring upstream's "Coucou Developer ID" provisioning profile.
DEVID_CERT=$(security find-identity -v -p codesigning 2>/dev/null | sed -n "s/.*\"\(Developer ID Application:.*(${DEFAULT_TEAM})\)\".*/\1/p" | head -n 1)

if [ -z "${SCHEME}" ] || [ -z "${CONFIG}" ]; then
  SCHEME="${SCHEME:-NotchBuddy}"
  if [ -n "${DEVID_CERT}" ]; then
    CONFIG="${CONFIG:-Release}"
  else
    CONFIG="${CONFIG:-Debug}"
  fi
fi

# Upstream HookServer.swift uses Swift 6.2 Sendable DispatchSource (Xcode 26+); on Xcode 16.x
# compile with SWIFT_VERSION=5.0 so upstream HookServer.swift stays untouched & conflict-free.
XCODE_MAJOR=$(xcodebuild -version 2>/dev/null | awk '/^Xcode / { split($2, a, "."); print a[1] }')
BUILD_EXTRA=(
  "DEVELOPMENT_TEAM=${DEFAULT_TEAM}"
  "CODE_SIGNING_ALLOWED=NO"
  "CODE_SIGNING_REQUIRED=NO"
  "PROVISIONING_PROFILE_SPECIFIER="
  "SWIFT_ACTIVE_COMPILATION_CONDITIONS="
)
if [ -n "${XCODE_MAJOR}" ] && [ "${XCODE_MAJOR}" -lt 26 ]; then
  BUILD_EXTRA+=("SWIFT_VERSION=5.0" "OTHER_SWIFT_FLAGS=")
fi

echo "Building HeyApex Eye (${SCHEME} / ${CONFIG})..."
xcodebuild -project NotchBuddy.xcodeproj -scheme "${SCHEME}" -configuration "${CONFIG}" \
  -derivedDataPath "${DERIVED}" \
  "${BUILD_EXTRA[@]}" -quiet build

PRODUCT_DIR="${DERIVED}/Build/Products/${CONFIG}"
if [ -d "${PRODUCT_DIR}/HeyApex Eye.app" ]; then
  BUILT="${PRODUCT_DIR}/HeyApex Eye.app"
  APP_BASENAME="HeyApex Eye.app"
elif [ -d "${PRODUCT_DIR}/Coucou.app" ]; then
  BUILT="${PRODUCT_DIR}/Coucou.app"
  APP_BASENAME="Coucou.app"
else
  echo "error: expected built app in ${PRODUCT_DIR} (HeyApex Eye.app or Coucou.app)" >&2
  exit 1
fi

if [ -n "${DEVID_CERT}" ]; then
  echo "Signing ${APP_BASENAME} with ${DEVID_CERT}..."
  if [ -d "${BUILT}/Contents/Frameworks" ]; then
    find "${BUILT}/Contents/Frameworks" \( -name "*.dylib" -o -name "*.framework" \) -print0 | while IFS= read -r -d '' fw; do
      codesign --force --options runtime --sign "${DEVID_CERT}" "$fw"
    done
  fi
  codesign --force --options runtime --entitlements "${REPO_ROOT}/NotchBuddy/Resources/Coucou.entitlements" --sign "${DEVID_CERT}" "${BUILT}"
else
  codesign --force --deep --sign - "${BUILT}" >/dev/null 2>&1 || true
fi

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${BUILT}/Contents/Info.plist" 2>/dev/null || echo "ai.heyapex.eye")
EXEC_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "${BUILT}/Contents/Info.plist" 2>/dev/null || echo "${APP_BASENAME%.app}")

TARGET="/Applications/${APP_BASENAME}"
if [ -d "${TARGET}" ]; then
  EXISTING=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${TARGET}/Contents/Info.plist" 2>/dev/null || echo "")
  if [ -n "${EXISTING}" ] && [ "${EXISTING}" != "${BUNDLE_ID}" ] && [ "${EXISTING}" != "fr.louisraille.NotchBuddy" ]; then
    mkdir -p "${HOME}/Applications"
    TARGET="${HOME}/Applications/${APP_BASENAME}"
    echo "/Applications/${APP_BASENAME} belongs to ${EXISTING}: installing in ${TARGET} instead."
  fi
fi
if [ ! -w "/Applications" ] && [ "${TARGET}" = "/Applications/${APP_BASENAME}" ]; then
  mkdir -p "${HOME}/Applications"
  TARGET="${HOME}/Applications/${APP_BASENAME}"
fi

echo "Quitting ${EXEC_NAME} (${BUNDLE_ID})..."
osascript -e "tell application id \"${BUNDLE_ID}\" to quit" >/dev/null 2>&1 || true
for _ in 1 2 3 4 5; do
  pgrep -x "${EXEC_NAME}" >/dev/null 2>&1 || break
  sleep 1
done
pkill -x "${EXEC_NAME}" 2>/dev/null || true

echo "Installing in ${TARGET}..."
rm -rf "${TARGET}"
ditto "${BUILT}" "${TARGET}"

# Keep the incremental build cache in DerivedData, but unregister DerivedData app bundles
# from LaunchServices so macOS never counts them as duplicate apps.
"${LSREGISTER}" -u "${BUILT}" >/dev/null 2>&1 || true
for old in \
  "${HOME}"/Library/Developer/Xcode/DerivedData/NotchBuddy-*/Build/Products/*/"HeyApex Eye.app" \
  "${HOME}"/Library/Developer/Xcode/DerivedData/NotchBuddy-*/Build/Products/*/Coucou.app \
  "${HOME}"/Library/Developer/Xcode/DerivedData/CoucouDev/Build/Products/*/"HeyApex Eye.app" \
  "${HOME}"/Library/Developer/Xcode/DerivedData/CoucouDev/Build/Products/*/Coucou.app; do
  [ -d "$old" ] || continue
  "${LSREGISTER}" -u "$old" >/dev/null 2>&1 || true
  rm -rf "$old"
  echo "Removed stale DerivedData app: $old"
done
"${LSREGISTER}" -f "${TARGET}" >/dev/null 2>&1 || true

open "${TARGET}"
echo "${APP_BASENAME%.app} (${BUNDLE_ID}) is running from ${TARGET}."
