#!/usr/bin/env bash
# Fetches upstream https://github.com/Louis-CFM/coucou.git, classifies any new commits
# since the last reviewed upstream SHA into [ENGINE/FIX CANDIDATE] vs [SKIP STOCK MOCHI/BRANDING],
# and runs verify-heyapex-overlay.sh so zero stock Coucou animations or assets ever leak in.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_ROOT}"

UPSTREAM_URL="https://github.com/Louis-CFM/coucou.git"
STATE_FILE="${REPO_ROOT}/.upstream-coucou-state"

if ! git remote | grep -qx "upstream"; then
  git remote add upstream "${UPSTREAM_URL}"
fi

git fetch upstream main --quiet

LATEST_SHA="$(git rev-parse upstream/main)"
REVIEWED_SHA=""
if [ -f "${STATE_FILE}" ]; then
  REVIEWED_SHA="$(awk -F= '/^LAST_REVIEWED_SHA=/{print $2}' "${STATE_FILE}" | tr -d '[:space:]')"
fi

if [ "${1:-}" = "--mark-reviewed" ]; then
  cat > "${STATE_FILE}" <<EOF
LAST_REVIEWED_SHA=${LATEST_SHA}
UPSTREAM_REPO=${UPSTREAM_URL}
EOF
  echo "✓ Marked upstream/main (${LATEST_SHA:0:7}) as reviewed in .upstream-coucou-state"
  exit 0
fi

echo "== Upstream Coucou GitHub Sync Check (${UPSTREAM_URL}) =="
echo "Latest upstream/main : ${LATEST_SHA:0:7}"
echo "Last reviewed SHA    : ${REVIEWED_SHA:-<none>}"

if [ -n "${REVIEWED_SHA}" ] && git cat-file -e "${REVIEWED_SHA}^{commit}" 2>/dev/null; then
  if [ "${LATEST_SHA}" = "${REVIEWED_SHA}" ]; then
    echo "✓ Up to date with reviewed upstream (${LATEST_SHA:0:7}) — 0 unreviewed commits."
  else
    echo "→ Unreviewed upstream commits (${REVIEWED_SHA:0:7}..${LATEST_SHA:0:7}):"
    git log "${REVIEWED_SHA}..${LATEST_SHA}" --oneline | while IFS= read -r line; do
      sha="${line%% *}"
      msg="${line#* }"
      files="$(git show --name-only --pretty="" "${sha}" | tr '\n' ' ')"
      if echo "${msg} ${files}" | grep -Eqi 'mochi|greeting|wardrobe|outfit|Assets\.xcassets|cask|CHANGELOG'; then
        echo "  [SKIP STOCK/MOCHI]     ${line}"
      else
        echo "  [ENGINE/FIX CANDIDATE] ${line}"
      fi
    done
  fi
else
  echo "→ Recent upstream/main commits:"
  git log -n 10 --oneline upstream/main
fi

bash "${REPO_ROOT}/scripts/verify-heyapex-overlay.sh"
