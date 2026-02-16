#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Nexus Agent — Post-Install Verification
# Run this to check that all components are healthy
# ============================================================================

NEXUS_HOME="${NEXUS_HOME:-$HOME/Nexus}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

pass=0
fail=0
warn_count=0

check() {
    local name="$1" cmd="$2"
    if eval "$cmd" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $name"
        ((pass++))
    else
        echo -e "  ${RED}✗${NC} $name"
        ((fail++))
    fi
}

check_warn() {
    local name="$1" cmd="$2"
    if eval "$cmd" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $name"
        ((pass++))
    else
        echo -e "  ${YELLOW}!${NC} $name (optional)"
        ((warn_count++))
    fi
}

echo ""
echo -e "${BOLD}Nexus Agent — System Verification${NC}"
echo -e "${BOLD}══════════════════════════════════${NC}"
echo ""

# --- Services ---
echo -e "${BOLD}Services:${NC}"
check "PostgreSQL running"    "pg_isready -q"
check "Redis running"         "redis-cli ping 2>/dev/null | grep -q PONG"
check "Ollama running"        "curl -sf http://localhost:11434/api/tags"
check "Nexus responding"      "curl -sf http://localhost:8080/health"

# --- Files ---
echo ""
echo -e "${BOLD}Files:${NC}"
check "Backend present"       "[[ -f '$NEXUS_HOME/backend/main.py' ]]"
check "Python venv"           "[[ -f '$NEXUS_HOME/venv/bin/python' ]]"
check "Chat UI built"         "[[ -d '$NEXUS_HOME/frontend/chat-build' ]]"
check "Admin UI built"        "[[ -d '$NEXUS_HOME/frontend/admin-build' ]]"
check ".env configured"       "[[ -f '$NEXUS_HOME/backend/.env' ]]"
check "Logs directory"        "[[ -d '$NEXUS_HOME/backend/logs' ]]"

# --- Daemon ---
echo ""
echo -e "${BOLD}Daemon:${NC}"
check "launchd plist"         "[[ -f '$HOME/Library/LaunchAgents/com.nexus.agent.plist' ]]"
check "Daemon loaded"         "launchctl list 2>/dev/null | grep -q com.nexus.agent"

# --- Ollama Models ---
echo ""
echo -e "${BOLD}Ollama Models:${NC}"
check_warn "nomic-embed-text" "ollama list 2>/dev/null | grep -q nomic-embed-text"
check_warn "kimi-k2.5:cloud"  "ollama list 2>/dev/null | grep -q kimi-k2.5"

# --- Python packages ---
echo ""
echo -e "${BOLD}Key Python Packages:${NC}"
check "FastAPI"     "$NEXUS_HOME/venv/bin/python -c 'import fastapi'"
check "SQLAlchemy"  "$NEXUS_HOME/venv/bin/python -c 'import sqlalchemy'"
check "Redis"       "$NEXUS_HOME/venv/bin/python -c 'import redis'"
check "Anthropic"   "$NEXUS_HOME/venv/bin/python -c 'import anthropic'"

# --- Database ---
echo ""
echo -e "${BOLD}Database:${NC}"
check "nexus DB exists" "psql -lqt 2>/dev/null | cut -d'|' -f1 | grep -qw nexus"

# --- Nexus Health Details ---
echo ""
echo -e "${BOLD}Nexus Health:${NC}"
if curl -sf http://localhost:8080/health &>/dev/null; then
    health=$(curl -sf http://localhost:8080/health)
    echo "  $health" | python3 -m json.tool 2>/dev/null || echo "  $health"
else
    echo -e "  ${RED}Server not responding${NC}"
fi

# --- Summary ---
echo ""
echo -e "${BOLD}══════════════════════════════════${NC}"
echo -e "  ${GREEN}Passed: $pass${NC}  ${RED}Failed: $fail${NC}  ${YELLOW}Warnings: $warn_count${NC}"

if [[ $fail -eq 0 ]]; then
    echo ""
    echo -e "  ${GREEN}${BOLD}All checks passed! Nexus is healthy.${NC}"
    echo -e "  Chat UI:  http://localhost:8080"
    echo -e "  Admin UI: http://localhost:8080/admin"
else
    echo ""
    echo -e "  ${RED}${BOLD}Some checks failed.${NC} Review the output above."
    echo -e "  Logs: $NEXUS_HOME/backend/logs/"
fi
echo ""

exit $fail
