#!/usr/bin/env bash
# ==============================================================================
# smoke_questing_ide.sh — Real-server smoke test for the Questing IDE
#
# Runs against a live QueryServer (:3030) and Editor (:3031), checking every
# endpoint the IDE panels consume. Exits non-zero on the FIRST failure with a
# specific error message naming what broke.
#
# Required gate before archive (spec: "Verification Requirements / Real-Server
# Smoke Test" — `openspec/changes/questing-ide-remediation/specs/questing-ide/spec.md`).
#
# Usage:
#   ./scripts/smoke_questing_ide.sh          # assumes :3030 + :3031 on localhost
#   QUERY_PORT=3030 EDITOR_PORT=3031 ./scripts/smoke_questing_ide.sh  # explicit ports
#
# Depends on: curl, jq (for JSON field validation).
# ==============================================================================

set -euo pipefail

QUERY_HOST="${QUERY_HOST:-127.0.0.1}"
QUERY_PORT="${QUERY_PORT:-3030}"
EDITOR_PORT="${EDITOR_PORT:-3031}"
QUERY_BASE="http://${QUERY_HOST}:${QUERY_PORT}"
EDITOR_BASE="http://${QUERY_HOST}:${EDITOR_PORT}"

pass=0
fail=0

check() {
    local label="$1"
    shift
    if eval "$@"; then
        echo "  ✅ ${label}"
        pass=$((pass + 1))
    else
        echo "  ❌ ${label}"
        fail=$((fail + 1))
    fi
}

check_json_field() {
    local label="$1"
    local url="$2"
    local field="$3"
    local file
    file=$(mktemp)
    if curl -sSf -o "$file" "$url" 2>/dev/null; then
        if jq -e "has(\"${field}\")" "$file" >/dev/null 2>&1; then
            echo "  ✅ ${label} (field \"${field}\" present)"
            pass=$((pass + 1))
        else
            echo "  ❌ ${label} — field \"${field}\" missing in response from ${url}"
            echo "     Response: $(head -c 500 "$file")"
            fail=$((fail + 1))
        fi
    else
        echo "  ❌ ${label} — HTTP error from ${url}"
        fail=$((fail + 1))
    fi
    rm -f "$file"
}

check_json_fields() {
    local label="$1"
    local url="$2"
    shift 2
    local file
    file=$(mktemp)
    if curl -sSf -o "$file" "$url" 2>/dev/null; then
        local missing=""
        for f in "$@"; do
            if ! jq -e "has(\"${f}\")" "$file" >/dev/null 2>&1; then
                missing="${missing} ${f}"
            fi
        done
        if [ -z "$missing" ]; then
            echo "  ✅ ${label} (all fields present: $*)"
            pass=$((pass + 1))
        else
            echo "  ❌ ${label} — missing field(s):${missing}"
            echo "     Response keys: $(jq 'keys | join(", ")' "$file" 2>/dev/null || echo "unparseable")"
            fail=$((fail + 1))
        fi
    else
        echo "  ❌ ${label} — HTTP error from ${url}"
        fail=$((fail + 1))
    fi
    rm -f "$file"
}

check_post() {
    local label="$1"
    local url="$2"
    local body="$3"
    local file
    file=$(mktemp)
    if curl -sSf -o "$file" -X POST -H "Content-Type: application/json" -d "$body" "$url" 2>/dev/null; then
        echo "  ✅ ${label} (POST ${url})"
        pass=$((pass + 1))
    else
        echo "  ❌ ${label} — POST failed to ${url}"
        echo "     Body: ${body}"
        echo "     Response: $(head -c 500 "$file" 2>/dev/null)"
        fail=$((fail + 1))
    fi
    rm -f "$file"
}

echo ""
echo "========================================================================"
echo "  Smoke Test — Questing IDE"
echo "  QueryServer: ${QUERY_BASE}"
echo "  Editor:      ${EDITOR_BASE}"
echo "========================================================================"
echo ""

# ---------------------------------------------------------------------------
# 1. Health check
# ---------------------------------------------------------------------------
echo "--- 1. Health Check ---"
check "QueryServer health responds" "curl -sSf '${QUERY_BASE}/health' >/dev/null 2>&1"

# ---------------------------------------------------------------------------
# 2. GET /quests/search?q=wolf — zoned summaries with `zone` field
# ---------------------------------------------------------------------------
echo "--- 2. Quest Search (zoned summaries) ---"
check_json_field "GET /quests/search?q=wolf returns results with zone" \
    "${QUERY_BASE}/quests/search?q=wolf" \
    "zone"

# ---------------------------------------------------------------------------
# 3. GET /npc/567 — extended fields (level, classification, loot, quests)
# ---------------------------------------------------------------------------
echo "--- 3. NPC Detail (extended fields, PR4) ---"
check_json_fields "GET /npc/567 extended fields" \
    "${QUERY_BASE}/npc/567" \
    "level" "classification" "loot" "quests"

# ---------------------------------------------------------------------------
# 4. GET /zone/12/spawns — aggregates creatures
# ---------------------------------------------------------------------------
echo "--- 4. Zone Spawns ---"
check_json_field "GET /zone/12/spawns returns creatures array" \
    "${QUERY_BASE}/zone/12/spawns" \
    "creatures"

# ---------------------------------------------------------------------------
# 5. GET /spawns/nearby — position-filtered results
# ---------------------------------------------------------------------------
echo "--- 5. Nearby Spawns ---"
check_json_field "GET /spawns/nearby returns creatures" \
    "${QUERY_BASE}/spawns/nearby?map=0&x=-8940&y=-140&radius=100" \
    "creatures"

# ---------------------------------------------------------------------------
# 6. POST /travel/route — mixed walk+taxi segments
# ---------------------------------------------------------------------------
echo "--- 6. Travel Route ---"
check_post "POST /travel/route with mixed segments" \
    "${QUERY_BASE}/travel/route" \
    '{"segments":[{"from":{"map":0,"x":-8940,"y":-140,"z":83},"to":{"map":0,"x":-8912,"y":-132,"z":83}},{"type":"taxi","from_node":1,"to_node":2}]}'

# ---------------------------------------------------------------------------
# 7. Editor round-trip — create → list → open
# ---------------------------------------------------------------------------
echo "--- 7. Editor create/list/open round-trip ---"

# 7a. Create campaign
SMOKE_CAMPAIGN="smoke_test_$(date +%s)"
check_post "Editor: create campaign '${SMOKE_CAMPAIGN}'" \
    "${EDITOR_BASE}/editor/campaigns/${SMOKE_CAMPAIGN}" \
    '{"nodes":[],"edges":[]}'

# 7b. List campaigns — verify it appears
check "Editor: list contains '${SMOKE_CAMPAIGN}'" \
    "curl -sSf '${EDITOR_BASE}/editor/campaigns/' | jq -e 'map(select(.name == \"${SMOKE_CAMPAIGN}\")) | length > 0' >/dev/null 2>&1"

# 7c. Open campaign — verify it loads with empty graph
check_json_field "Editor: open campaign returns graph" \
    "${EDITOR_BASE}/editor/campaigns/${SMOKE_CAMPAIGN}" \
    "nodes"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "========================================================================"
echo "  Results: ${pass} passed, ${fail} failed"
echo "========================================================================"

if [ "${fail}" -gt 0 ]; then
    echo ""
    echo "  ❌ SMOKE TEST FAILED — do not archive until all checks pass."
    echo "     Fix the failing service(s) above and re-run."
    exit 1
else
    echo ""
    echo "  ✅ All checks passed. Gate clearance granted for archive."
    exit 0
fi
