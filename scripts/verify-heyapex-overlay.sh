#!/usr/bin/env bash
# Verifies all non-negotiable HeyApex Eye overlay contracts after edits or upstream Coucou merges:
#   1. nb.sock & NotchBuddy IPC path in HookServer.swift (used by electron/terminal/coucou-bridge.js)
#   2. group.fr.louisraille.Coucou App Group (shared with iOS companion & widgets)
#   3. Verbatim upstream MIT attribution in WeeklyRecapView.swift
#   4. Pace.swift existence & syntax check
#   5. HeyApex Eye bundle identity & HeyApexHost bottom-pill collision guard
#   6. Fast Swift contract unit suites
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_ROOT}"

fail() {
  echo "✗ [verify-heyapex-overlay] $*" >&2
  exit 1
}

pass() {
  echo "✓ $*"
}

echo "== HeyApex Eye Overlay Contract Gate =="

# 1. nb.sock & NotchBuddy support directory contract
HOOK_SERVER="NotchBuddy/Sources/App/HookServer.swift"
[ -f "${HOOK_SERVER}" ] || fail "missing ${HOOK_SERVER}"
grep -q '"NotchBuddy"' "${HOOK_SERVER}" || fail "NotchBuddy supportDir contract missing in ${HOOK_SERVER}"
grep -q '"nb.sock"' "${HOOK_SERVER}" || fail "nb.sock socket contract missing in ${HOOK_SERVER}"
pass "HookServer.swift preserves ~/Library/Application Support/NotchBuddy/nb.sock IPC contract"

# 2. App Group contract
SHARED_SESSIONS="NotchBuddy/Sources/Phone/SharedSessions.swift"
WIDGET_ENTITLEMENTS="NotchBuddy/Resources/CoucouWidgets.entitlements"
PHONE_ENTITLEMENTS="NotchBuddy/Resources/CoucouPhone.entitlements"
grep -q 'group.fr.louisraille.Coucou' "${SHARED_SESSIONS}" || fail "App Group missing in ${SHARED_SESSIONS}"
grep -q 'group.fr.louisraille.Coucou' "${WIDGET_ENTITLEMENTS}" || fail "App Group missing in ${WIDGET_ENTITLEMENTS}"
grep -q 'group.fr.louisraille.Coucou' "${PHONE_ENTITLEMENTS}" || fail "App Group missing in ${PHONE_ENTITLEMENTS}"
pass "App Group group.fr.louisraille.Coucou preserved across Phone & Widgets"

# 3. Verbatim upstream attribution in WeeklyRecapView.swift
RECAP_VIEW="NotchBuddy/Sources/App/WeeklyRecapView.swift"
[ -f "${RECAP_VIEW}" ] || fail "missing ${RECAP_VIEW}"
grep -Fq 'Text("Coucou · github.com/Louis-CFM/coucou")' "${RECAP_VIEW}" \
  || fail "verbatim attribution Text(\"Coucou · github.com/Louis-CFM/coucou\") missing in ${RECAP_VIEW}"
pass "Verbatim upstream attribution preserved in WeeklyRecapView.swift"

# 4. Pace.swift existence & parse check
PACE_SWIFT="NotchBuddy/Sources/CoucouKit/Pace.swift"
[ -f "${PACE_SWIFT}" ] || fail "missing ${PACE_SWIFT}"
swiftc -parse "${PACE_SWIFT}"
pass "Pace.swift exists and passes swiftc -parse"

# 5. HeyApex Eye bundle identity & HeyApexHost bottom-pill overlap guard
PBXPROJ="NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj"
FLOW_PILL="NotchBuddy/Sources/App/FlowPill.swift"
grep -q 'PRODUCT_BUNDLE_IDENTIFIER = ai.heyapex.eye;' "${PBXPROJ}" \
  || fail "ai.heyapex.eye bundle identifier missing in ${PBXPROJ}"
grep -q 'PRODUCT_NAME = "HeyApex Eye";' "${PBXPROJ}" \
  || fail "HeyApex Eye PRODUCT_NAME missing in ${PBXPROJ}"
grep -q 'com.aboringbusiness.heyapex' "${FLOW_PILL}" \
  || fail "HeyApexHost desktop bundle detection missing in ${FLOW_PILL}"
pass "HeyApex Eye pbxproj identity and HeyApexHost bottom-pill collision guard verified"

# 6. Fast Swift contract unit tests
CONTRACT_TESTS=(
  "scripts/test-pill-colors.sh"
  "scripts/test-plan-gauge.sh"
  "scripts/test-approval-queue.sh"
  "scripts/test-island-fsm.sh"
  "scripts/test-flow-keys.sh"
  "scripts/test-notetaker.sh"
)

for script in "${CONTRACT_TESTS[@]}"; do
  [ -f "${script}" ] || fail "missing test script ${script}"
  echo "→ Running ${script}..."
  bash "${script}"
done

pass "All HeyApex Eye overlay contracts and fast Swift suites passed"
