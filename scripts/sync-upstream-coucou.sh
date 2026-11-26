#!/usr/bin/env bash
# Automated upstream Coucou sync pipeline for HeyApex Eye.
#
#   ./scripts/sync-upstream-coucou.sh --check     # read-only status/remote check (zero git/network mutation)
#   ./scripts/sync-upstream-coucou.sh --dry-run   # fetch upstream/main (if online) & preview merge without mutating history
#   ./scripts/sync-upstream-coucou.sh             # merge upstream/main + run verify-heyapex-overlay.sh gate
#   ./scripts/sync-upstream-coucou.sh --install   # merge upstream/main + verify + build & relaunch /Applications/HeyApex Eye.app
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPSTREAM_URL="${COUCOU_UPSTREAM_URL:-https://github.com/Louis-CFM/coucou.git}"
UPSTREAM_BRANCH="${COUCOU_UPSTREAM_BRANCH:-main}"

MODE="sync"
INSTALL_AFTER=0

for arg in "$@"; do
  case "$arg" in
    --check)   MODE="check" ;;
    --dry-run) MODE="dry-run" ;;
    --install) INSTALL_AFTER=1 ;;
    -h|--help)
      sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "error: unknown option '$arg' (expected --check, --dry-run, or --install)" >&2
      exit 1
      ;;
  esac
done

cd "${REPO_ROOT}"

ORIGIN_URL=$(git remote get-url origin 2>/dev/null || echo "<unset>")
CURRENT_UPSTREAM=$(git remote get-url upstream 2>/dev/null || echo "")
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")

if [ "${MODE}" = "check" ]; then
  echo "== HeyApex Eye Upstream Sync Check (read-only) =="
  echo "  repo:            ${REPO_ROOT}"
  echo "  branch:          ${BRANCH} ($(git rev-parse --short HEAD))"
  echo "  origin:          ${ORIGIN_URL}"
  if [ -z "${CURRENT_UPSTREAM}" ]; then
    echo "  upstream:        <not yet configured — sync will add ${UPSTREAM_URL}>"
  elif [ "${CURRENT_UPSTREAM}" = "${UPSTREAM_URL}" ]; then
    echo "  upstream:        ${CURRENT_UPSTREAM} (ok)"
  else
    echo "  upstream:        ${CURRENT_UPSTREAM} (sync will update to ${UPSTREAM_URL})"
  fi

  [ -f ".gitattributes" ] || { echo "error: .gitattributes missing" >&2; exit 1; }
  [ -x "scripts/verify-heyapex-overlay.sh" ] || { echo "error: scripts/verify-heyapex-overlay.sh missing or not executable" >&2; exit 1; }
  [ -x "scripts/dev-install.sh" ] || { echo "error: scripts/dev-install.sh missing or not executable" >&2; exit 1; }

  if git diff --quiet && git diff --cached --quiet; then
    echo "  working tree:    clean"
  else
    echo "  working tree:    has uncommitted changes (commit or stash before running full sync)"
  fi

  if git rev-parse --verify --quiet "refs/remotes/upstream/${UPSTREAM_BRANCH}" >/dev/null; then
    AHEAD_BEHIND=$(git rev-list --left-right --count "HEAD...upstream/${UPSTREAM_BRANCH}" 2>/dev/null || echo "? ?")
    echo "  cached divergence (HEAD vs upstream/${UPSTREAM_BRANCH}): ${AHEAD_BEHIND}"
  else
    echo "  cached upstream: refs/remotes/upstream/${UPSTREAM_BRANCH} not fetched yet"
  fi
  echo "✓ Sync pipeline configuration verified (no git history or remotes modified)."
  exit 0
fi

if [ "${MODE}" = "dry-run" ]; then
  echo "== HeyApex Eye Upstream Sync Dry Run =="
  if [ -z "${CURRENT_UPSTREAM}" ]; then
    echo "Note: 'upstream' remote is not configured yet (would set to ${UPSTREAM_URL})."
    if git ls-remote --exit-code "${UPSTREAM_URL}" "refs/heads/${UPSTREAM_BRANCH}" >/dev/null 2>&1; then
      UPSTREAM_TIP=$(git ls-remote "${UPSTREAM_URL}" "refs/heads/${UPSTREAM_BRANCH}" | awk '{print $1}')
      echo "✓ Reachable ${UPSTREAM_URL} (${UPSTREAM_BRANCH} @ ${UPSTREAM_TIP:0:7})."
    else
      echo "⚠ Network unavailable or cannot reach ${UPSTREAM_URL}; skipping remote check."
    fi
    exit 0
  fi

  if git fetch --dry-run upstream "${UPSTREAM_BRANCH}" 2>/dev/null; then
    git fetch upstream "${UPSTREAM_BRANCH}"
    COUNTS=$(git rev-list --left-right --count "HEAD...upstream/${UPSTREAM_BRANCH}")
    AHEAD=$(echo "${COUNTS}" | awk '{print $1}')
    BEHIND=$(echo "${COUNTS}" | awk '{print $2}')
    echo "HEAD (${BRANCH}) is ${AHEAD} commit(s) ahead and ${BEHIND} commit(s) behind upstream/${UPSTREAM_BRANCH}."
    if [ "${BEHIND}" -gt 0 ] && git merge-tree --write-tree HEAD "upstream/${UPSTREAM_BRANCH}" >/dev/null 2>&1; then
      echo "✓ Merge preview is clean (zero conflicts)."
    elif [ "${BEHIND}" -gt 0 ]; then
      echo "⚠ Merge preview detected conflicts — inspect with: git merge --no-commit --no-ff upstream/${UPSTREAM_BRANCH}"
    fi
  else
    echo "⚠ Offline or unable to fetch upstream/${UPSTREAM_BRANCH}; dry-run stopped without changes."
  fi
  exit 0
fi

# Full sync mode
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "error: working tree has uncommitted changes. Commit or stash before syncing upstream." >&2
  exit 1
fi

# Enable git's built-in `ours` merge driver used by .gitattributes for branded assets & scripts.
git config --local merge.ours.driver true

if [ -z "${CURRENT_UPSTREAM}" ]; then
  echo "Adding upstream remote -> ${UPSTREAM_URL}"
  git remote add upstream "${UPSTREAM_URL}"
elif [ "${CURRENT_UPSTREAM}" != "${UPSTREAM_URL}" ]; then
  echo "Updating upstream remote -> ${UPSTREAM_URL}"
  git remote set-url upstream "${UPSTREAM_URL}"
fi

echo "Fetching upstream/${UPSTREAM_BRANCH}..."
git fetch upstream "${UPSTREAM_BRANCH}"

BEHIND=$(git rev-list --count "HEAD..upstream/${UPSTREAM_BRANCH}")
if [ "${BEHIND}" -eq 0 ]; then
  echo "Already up to date with upstream/${UPSTREAM_BRANCH}."
else
  echo "Merging ${BEHIND} upstream commit(s) from upstream/${UPSTREAM_BRANCH}..."
  git merge --no-edit "upstream/${UPSTREAM_BRANCH}"

  # Ensure HeyApex Eye pbxproj bundle identity stays intact if upstream regenerated project.pbxproj.
  python3 - "NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj" <<'PY'
import re, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    orig = f.read()
src = orig
src = src.replace("DEVELOPMENT_TEAM = 256AUJ9555;", "DEVELOPMENT_TEAM = A9MHJC28M3;")
src = src.replace("PRODUCT_BUNDLE_IDENTIFIER = fr.louisraille.NotchBuddy;", "PRODUCT_BUNDLE_IDENTIFIER = ai.heyapex.eye;")
src = src.replace("PRODUCT_BUNDLE_IDENTIFIER = fr.louisraille.Coucou.NotificationContent;", "PRODUCT_BUNDLE_IDENTIFIER = ai.heyapex.eye.NotificationContent;")
src = src.replace("PRODUCT_BUNDLE_IDENTIFIER = fr.louisraille.Coucou.Widgets;", "PRODUCT_BUNDLE_IDENTIFIER = ai.heyapex.eye.Widgets;")
src = src.replace("PRODUCT_BUNDLE_IDENTIFIER = fr.louisraille.Coucou;", "PRODUCT_BUNDLE_IDENTIFIER = ai.heyapex.eye;")
src = re.sub(r'\bPRODUCT_NAME = Coucou;', 'PRODUCT_NAME = "HeyApex Eye";', src)
src = src.replace("PRODUCT_NAME = CoucouNotificationContent;", "PRODUCT_NAME = HeyApexEyeNotificationContent;")
src = src.replace("PRODUCT_NAME = CoucouWidgets;", "PRODUCT_NAME = HeyApexEyeWidgets;")
if src != orig:
    with open(path, "w", encoding="utf-8") as f:
        f.write(src)
PY
  if ! git diff --quiet -- "NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj"; then
    git add "NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj"
    git commit --amend --no-edit
  fi
fi

echo "Running HeyApex Eye overlay verification gate..."
bash "${REPO_ROOT}/scripts/verify-heyapex-overlay.sh"

if [ "${INSTALL_AFTER}" -eq 1 ]; then
  echo "Building and installing updated HeyApex Eye.app..."
  bash "${REPO_ROOT}/scripts/dev-install.sh"
else
  echo ""
  echo "✓ Synced and verified against upstream/${UPSTREAM_BRANCH}."
  echo "  Next steps:"
  echo "    ./scripts/dev-install.sh     # build & relaunch /Applications/HeyApex Eye.app"
  echo "    git push origin ${BRANCH}    # publish synced branch to ABoringBusiness/coucou"
fi
