#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Nexus Agent — Uninstaller
# Cleanly removes Nexus and optionally its dependencies
# ============================================================================

NEXUS_HOME="${NEXUS_HOME:-$HOME/Nexus}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${BOLD}${CYAN}Nexus Agent — Uninstaller${NC}"
echo -e "${BOLD}════════════════════════════${NC}"
echo ""
echo "This will remove:"
echo "  1. Nexus launchd daemon (auto-start)"
echo "  2. Nexus application files ($NEXUS_HOME)"
echo ""
echo -e "${YELLOW}This will NOT remove:${NC}"
echo "  • Homebrew"
echo "  • PostgreSQL (your data is preserved)"
echo "  • Redis"
echo "  • Ollama + downloaded models"
echo "  • Node.js / Python"
echo ""
read -rp "Continue with uninstall? [y/N] " confirm
[[ "$confirm" =~ ^[Yy] ]] || { echo "Cancelled."; exit 0; }

echo ""

# --- Stop and remove daemon ---
echo -e "${BOLD}Stopping Nexus daemon...${NC}"
if launchctl list 2>/dev/null | grep -q "com.nexus.agent"; then
    launchctl bootout "gui/$(id -u)/com.nexus.agent" 2>/dev/null || \
        launchctl unload "$HOME/Library/LaunchAgents/com.nexus.agent.plist" 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} Daemon stopped"
else
    echo -e "  ${YELLOW}!${NC} Daemon was not running"
fi

if [[ -f "$HOME/Library/LaunchAgents/com.nexus.agent.plist" ]]; then
    rm "$HOME/Library/LaunchAgents/com.nexus.agent.plist"
    echo -e "  ${GREEN}✓${NC} Plist removed"
fi

# --- Kill any running Nexus process ---
echo -e "${BOLD}Stopping Nexus processes...${NC}"
if lsof -ti :8080 &>/dev/null; then
    kill $(lsof -ti :8080) 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} Port 8080 process stopped"
else
    echo -e "  ${YELLOW}!${NC} No process on port 8080"
fi

# --- Remove Nexus directory ---
echo ""
echo -e "${BOLD}Remove Nexus files?${NC}"
echo "  Directory: $NEXUS_HOME"

if [[ -d "$NEXUS_HOME" ]]; then
    read -rp "  Delete $NEXUS_HOME? [y/N] " confirm_dir
    if [[ "$confirm_dir" =~ ^[Yy] ]]; then
        rm -rf "$NEXUS_HOME"
        echo -e "  ${GREEN}✓${NC} Nexus directory removed"
    else
        echo -e "  ${YELLOW}!${NC} Nexus directory preserved"
    fi
else
    echo -e "  ${YELLOW}!${NC} Directory not found"
fi

# --- Drop PostgreSQL database ---
echo ""
echo -e "${BOLD}Remove PostgreSQL database?${NC}"
if psql -lqt 2>/dev/null | cut -d '|' -f 1 | grep -qw nexus; then
    read -rp "  Drop database 'nexus'? This deletes all conversation data. [y/N] " confirm_db
    if [[ "$confirm_db" =~ ^[Yy] ]]; then
        dropdb nexus 2>/dev/null || true
        echo -e "  ${GREEN}✓${NC} Database dropped"
    else
        echo -e "  ${YELLOW}!${NC} Database preserved"
    fi
else
    echo -e "  ${YELLOW}!${NC} Database not found"
fi

# --- Optional: remove system dependencies ---
echo ""
echo -e "${BOLD}Remove system dependencies?${NC}"
echo "  This would uninstall PostgreSQL, Redis, Ollama via Homebrew."
read -rp "  Remove system dependencies? [y/N] " confirm_deps
if [[ "$confirm_deps" =~ ^[Yy] ]]; then
    echo ""
    read -rp "  Remove PostgreSQL? [y/N] " c
    [[ "$c" =~ ^[Yy] ]] && { brew services stop postgresql@17 2>/dev/null; brew uninstall postgresql@17 2>/dev/null || true; echo -e "  ${GREEN}✓${NC} PostgreSQL removed"; }

    read -rp "  Remove Redis? [y/N] " c
    [[ "$c" =~ ^[Yy] ]] && { brew services stop redis 2>/dev/null; brew uninstall redis 2>/dev/null || true; echo -e "  ${GREEN}✓${NC} Redis removed"; }

    read -rp "  Remove Ollama? [y/N] " c
    [[ "$c" =~ ^[Yy] ]] && { brew services stop ollama 2>/dev/null; brew uninstall ollama 2>/dev/null || true; echo -e "  ${GREEN}✓${NC} Ollama removed"; }
else
    echo -e "  ${YELLOW}!${NC} System dependencies preserved"
fi

echo ""
echo -e "${GREEN}${BOLD}Uninstall complete.${NC}"
echo ""
