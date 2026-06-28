#!/usr/bin/env bash
# tests/test-platform-mobile-mcp-docs.sh
#
# Docs/code-lint tests for three S3 findings closed by
# PR fix/platform-mobile-mcp-fwprofile-expo-split:
#
#   T1 (platform-modules-mobile-mcp-2): init.sh fw_profile case must
#       have an explicit mcp_server) arm (not a silent wildcard) AND
#       docs/platform-modules/mcp_server.md must document the
#       CDF web-api profile fall-through.
#
#   T2 (platform-modules-mobile-mcp-2): init.sh target_platform case
#       must have an explicit mcp_server) arm that emits a clearer
#       descriptor than the raw token so the CDF discovery JSON
#       targetPlatform string is self-explanatory.
#
#   T3 (platform-modules-mobile-mcp-4): docs/platform-modules/mobile.md
#       must NOT contain a worked example using expo-in-app-purchases
#       (Expo removed this package; docs.expo.dev/.../in-app-purchases
#       returns 404). The §5.4 React Native / Expo block must reference
#       react-native-iap as the worked example.
#
#   T4 (platform-modules-mobile-mcp-7): docs/platform-modules/mobile.md
#       §2.1 Option B (per-platform branches android/ios) must carry an
#       'advanced / not supported by Solo gates' warning string AND must
#       reference phase-state.json reconciliation, so future edits
#       cannot silently restore Option B to peer status with Option A.
#
# Style mirrors tests/test-lint-counter-antipattern.sh and
# tests/test-intake-wizard-fixes.sh: set -uo pipefail, per-case
# pass/fail counters, no shared state between cases.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_SH="$REPO_ROOT/init.sh"
MOBILE_MD="$REPO_ROOT/docs/platform-modules/mobile.md"
MCP_MD="$REPO_ROOT/docs/platform-modules/mcp_server.md"

for f in "$INIT_SH" "$MOBILE_MD" "$MCP_MD"; do
  if [ ! -f "$f" ]; then
    echo "FATAL: required file not found: $f" >&2
    exit 2
  fi
done

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# ----------------------------------------------------------------
# T1: init.sh fw_profile case statement must have an explicit
# mcp_server) arm; the fallthrough must be explicit and documented.
# AND mcp_server.md must document the web-api profile mapping.
# ----------------------------------------------------------------
echo ""
echo "T1: init.sh fw_profile has explicit mcp_server arm + mcp_server.md documents it"

# Extract the fw_profile case block (~10 lines after `local fw_profile`).
fw_block=$(awk '
  /^[[:space:]]*local fw_profile[[:space:]]*$/ { capture=1; lines=0; next }
  capture && lines < 12 { print; lines++ }
  capture && /esac/ { capture=0 }
' "$INIT_SH")

if printf '%s\n' "$fw_block" | grep -qE '^\s*mcp_server\)\s*fw_profile="web-api"'; then
  pass "T1a: init.sh fw_profile case has explicit mcp_server) → web-api arm"
else
  fail_ "T1a" "fw_profile case missing explicit mcp_server) arm (silent wildcard fall-through). Block was:
$fw_block"
fi

# The mcp_server module doc must explain the CDF profile choice so
# operators are not surprised. Look for the canonical phrase pattern.
if grep -qiE 'web-api[^A-Za-z0-9]+profile|CDF.*web-api|web-api.*profile' "$MCP_MD"; then
  pass "T1b: mcp_server.md documents web-api profile mapping"
else
  fail_ "T1b" "mcp_server.md does not mention the web-api CDF profile fall-through"
fi

# ----------------------------------------------------------------
# T2: init.sh target_platform case must have an explicit mcp_server)
# arm with a clearer descriptor than the raw token.
# ----------------------------------------------------------------
echo ""
echo "T2: init.sh target_platform has explicit mcp_server arm"

tp_block=$(awk '
  /^[[:space:]]*local target_platform="\$PLATFORM"[[:space:]]*$/ { capture=1; lines=0; next }
  capture && lines < 10 { print; lines++ }
  capture && /esac/ { capture=0 }
' "$INIT_SH")

if printf '%s\n' "$tp_block" | grep -qE '^\s*mcp_server\)\s*target_platform='; then
  pass "T2: init.sh target_platform case has explicit mcp_server) arm"
else
  fail_ "T2" "target_platform case missing explicit mcp_server) arm. Block was:
$tp_block"
fi

# ----------------------------------------------------------------
# T3 (platform-modules-mobile-mcp-4): mobile.md must NOT recommend
# the deprecated expo-in-app-purchases package. The §5.4 React Native
# / Expo block must reference react-native-iap as the worked example.
# ----------------------------------------------------------------
echo ""
echo "T3: mobile.md §5.4 uses react-native-iap (not deprecated expo-in-app-purchases)"

# Forbid USAGE patterns (imports, recommend-as-install, header-list as
# a peer to react-native-iap). Deprecation notes that name the old
# package to explain WHY it was removed are allowed — we want the
# package name searchable so operators on older docs find the warning.
forbidden_matches=$(grep -nE "from ['\"]expo-in-app-purchases['\"]|import .* expo-in-app-purchases|npm install .*expo-in-app-purchases|using \`expo-in-app-purchases\` or" "$MOBILE_MD" || true)
if [ -n "$forbidden_matches" ]; then
  fail_ "T3a" "mobile.md still uses/recommends the deprecated expo-in-app-purchases package:
$forbidden_matches"
else
  pass "T3a: mobile.md no longer uses or recommends expo-in-app-purchases (deprecation-note mentions allowed)"
fi

# The §5.4 worked example must use react-native-iap. Detect the IAP
# block boundary by looking for "React Native / Expo" near a code fence.
if awk '
  /^### 5\.4/ { in_section=1 }
  in_section && /React Native.*Expo/ { in_block=1; next }
  in_block && /```/ { in_code = !in_code; next }
  in_block && in_code && /react-native-iap|RevenueCat/ { found=1; exit }
  /^### 5\.5/ { in_section=0; in_block=0; in_code=0 }
  END { exit (found ? 0 : 1) }
' "$MOBILE_MD"; then
  pass "T3b: mobile.md §5.4 React Native/Expo block references react-native-iap or RevenueCat"
else
  fail_ "T3b" "mobile.md §5.4 React Native/Expo IAP code block does not reference react-native-iap or RevenueCat"
fi

# ----------------------------------------------------------------
# T4 (platform-modules-mobile-mcp-7): mobile.md §2.1 Option B must
# carry an 'advanced / not supported by Solo gates' warning string
# AND reference phase-state.json reconciliation.
# ----------------------------------------------------------------
echo ""
echo "T4: mobile.md §2.1 Option B (branch isolation) is demoted with explicit gate-integration warning"

# Extract the §2.1-ish split-machine block (between "Split-machine" and
# next "### 2." or "### 2.2"). Search within that block for Option B,
# the advanced/unsupported warning, and a phase-state.json mention.
split_block=$(awk '
  /Split-machine development/ { capture=1 }
  capture { print }
  capture && /^### / && !/Split-machine/ { exit }
' "$MOBILE_MD")

if printf '%s\n' "$split_block" | grep -qE 'Option B'; then
  :  # found Option B header
else
  fail_ "T4-pre" "split-machine block does not contain Option B heading"
fi

# Required: an explicit advanced-or-unsupported warning near Option B.
if printf '%s\n' "$split_block" | grep -qiE 'advanced.*(unsupported|not supported|not validated|outside)|unsupported.*by.*Solo.*gates|not.*supported.*by.*Solo.*gates'; then
  pass "T4a: Option B is marked advanced/unsupported by Solo gates"
else
  fail_ "T4a" "Option B is not marked advanced/unsupported (no 'advanced'+'unsupported'/'not supported' near it)"
fi

# Required: phase-state.json reconciliation is mentioned in the same block.
if printf '%s\n' "$split_block" | grep -q 'phase-state.json'; then
  pass "T4b: Option B block references phase-state.json reconciliation"
else
  fail_ "T4b" "Option B block does not reference phase-state.json"
fi

# Required: UAT-session reconciliation guidance (UAT must run on main).
if printf '%s\n' "$split_block" | grep -qiE 'UAT.*(main|merge)|main.*UAT'; then
  pass "T4c: Option B block mentions UAT-session reconciliation"
else
  fail_ "T4c" "Option B block does not mention UAT-session reconciliation"
fi

# ----------------------------------------------------------------
# Summary
# ----------------------------------------------------------------
echo ""
echo "=================================================="
echo "Results: $PASSED passed, $FAILED failed"
echo "=================================================="
[ "$FAILED" -eq 0 ] || exit 1
exit 0
