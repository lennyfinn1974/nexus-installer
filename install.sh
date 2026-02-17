#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Nexus Agent — macOS Installer
# Single-pass installation of the complete Nexus AI Agent system
# ============================================================================

NEXUS_REPO="https://github.com/lennyfinn1974/nexus2.0.git"
NEXUS_BRANCH="main"
NEXUS_HOME="${NEXUS_HOME:-$HOME/Nexus}"
INSTALLER_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="/tmp/nexus-install-$(date +%Y%m%d-%H%M%S).log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()   { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1" | tee -a "$LOG_FILE"; }
err()   { echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"; }
info()  { echo -e "${BLUE}[→]${NC} $1" | tee -a "$LOG_FILE"; }
header(){ echo -e "\n${BOLD}${CYAN}═══ $1 ═══${NC}\n" | tee -a "$LOG_FILE"; }

die() { err "$1"; echo "See log: $LOG_FILE"; exit 1; }

# ============================================================================
# Pre-flight checks
# ============================================================================
preflight() {
    header "Pre-flight Checks"

    [[ "$(uname)" == "Darwin" ]] || die "This installer is for macOS only."
    log "macOS detected: $(sw_vers -productVersion)"

    if [[ "$(uname -m)" == "arm64" ]]; then
        log "Apple Silicon detected"
        BREW_PREFIX="/opt/homebrew"
    else
        log "Intel Mac detected"
        BREW_PREFIX="/usr/local"
    fi

    # Check for Xcode CLT
    if ! xcode-select -p &>/dev/null; then
        info "Installing Xcode Command Line Tools..."
        xcode-select --install 2>/dev/null || true
        echo "Press Enter after Xcode CLT installation completes..."
        read -r
    fi
    log "Xcode Command Line Tools present"

    # Check Git
    command -v git &>/dev/null || die "Git not found. Install Xcode CLT first."
    log "Git available: $(git --version)"

    # Check disk space (need ~5GB)
    local free_gb
    free_gb=$(df -g "$HOME" | awk 'NR==2{print $4}')
    [[ "$free_gb" -ge 5 ]] || die "Need at least 5GB free disk space (have ${free_gb}GB)"
    log "Disk space OK: ${free_gb}GB free"
}

# ============================================================================
# Install Homebrew
# ============================================================================
install_homebrew() {
    header "Homebrew"

    if command -v brew &>/dev/null; then
        log "Homebrew already installed: $(brew --version | head -1)"
    else
        info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

        # Add to PATH for this session
        if [[ -f "$BREW_PREFIX/bin/brew" ]]; then
            eval "$("$BREW_PREFIX/bin/brew" shellenv)"
        fi
        log "Homebrew installed"
    fi

    # Ensure brew is on PATH
    export PATH="$BREW_PREFIX/bin:$PATH"
}

# ============================================================================
# Install system dependencies via Homebrew
# ============================================================================
install_system_deps() {
    header "System Dependencies"

    local deps=(python@3.12 node postgresql@17 redis ollama)

    for dep in "${deps[@]}"; do
        if brew list "$dep" &>/dev/null; then
            log "$dep already installed"
        else
            info "Installing $dep..."
            brew install "$dep" 2>&1 | tail -1 | tee -a "$LOG_FILE"
            log "$dep installed"
        fi
    done

    # Start services
    info "Starting PostgreSQL..."
    brew services start postgresql@17 2>/dev/null || true
    sleep 2
    log "PostgreSQL running"

    info "Starting Redis..."
    brew services start redis 2>/dev/null || true
    sleep 1
    log "Redis running"

    info "Starting Ollama..."
    brew services start ollama 2>/dev/null || true
    sleep 3
    log "Ollama running"
}

# ============================================================================
# Clone Nexus repository
# ============================================================================
clone_nexus() {
    header "Nexus Source Code"

    if [[ -d "$NEXUS_HOME/.git" ]]; then
        warn "Nexus repo already exists at $NEXUS_HOME"
        info "Pulling latest changes..."
        cd "$NEXUS_HOME"
        git pull origin "$NEXUS_BRANCH" 2>&1 | tee -a "$LOG_FILE"
        log "Repository updated"
    else
        info "Cloning Nexus from $NEXUS_REPO..."
        git clone --branch "$NEXUS_BRANCH" "$NEXUS_REPO" "$NEXUS_HOME" 2>&1 | tee -a "$LOG_FILE"
        log "Repository cloned to $NEXUS_HOME"
    fi

    cd "$NEXUS_HOME"
}

# ============================================================================
# Python virtual environment + dependencies
# ============================================================================
setup_python() {
    header "Python Environment"

    local python_bin
    python_bin="$(brew --prefix python@3.12)/bin/python3.12"

    if [[ ! -f "$python_bin" ]]; then
        python_bin="$(which python3)"
    fi

    log "Using Python: $($python_bin --version)"

    if [[ ! -d "$NEXUS_HOME/venv" ]]; then
        info "Creating virtual environment..."
        "$python_bin" -m venv "$NEXUS_HOME/venv"
        log "Virtual environment created"
    else
        log "Virtual environment already exists"
    fi

    # Activate
    source "$NEXUS_HOME/venv/bin/activate"

    # Upgrade pip
    info "Upgrading pip..."
    pip install --upgrade pip setuptools wheel 2>&1 | tail -1 | tee -a "$LOG_FILE"

    # Install requirements
    info "Installing Python dependencies (this may take a few minutes)..."
    pip install -r "$NEXUS_HOME/requirements.txt" 2>&1 | tail -5 | tee -a "$LOG_FILE"
    log "Python dependencies installed"

    # Install Playwright Chromium
    info "Installing Playwright Chromium for web rendering..."
    python -m playwright install chromium 2>&1 | tail -2 | tee -a "$LOG_FILE"
    log "Playwright Chromium installed"
}

# ============================================================================
# Build frontend UIs
# ============================================================================
build_frontends() {
    header "Frontend UIs"

    # Chat UI
    if [[ -d "$NEXUS_HOME/chat-ui" ]]; then
        info "Building Chat UI (React 19 + Vite)..."
        cd "$NEXUS_HOME/chat-ui"
        npm install 2>&1 | tail -2 | tee -a "$LOG_FILE"
        npm run build 2>&1 | tail -2 | tee -a "$LOG_FILE"
        log "Chat UI built → frontend/chat-build/"
    else
        warn "chat-ui/ directory not found — skipping"
    fi

    # Admin UI
    if [[ -d "$NEXUS_HOME/admin-ui" ]]; then
        info "Building Admin UI (Radix + Tailwind)..."
        cd "$NEXUS_HOME/admin-ui"
        npm install 2>&1 | tail -2 | tee -a "$LOG_FILE"
        npm run build 2>&1 | tail -2 | tee -a "$LOG_FILE"
        log "Admin UI built → frontend/admin-build/"
    else
        warn "admin-ui/ directory not found — skipping"
    fi

    cd "$NEXUS_HOME"
}

# ============================================================================
# PostgreSQL database setup
# ============================================================================
setup_database() {
    header "PostgreSQL Database"

    # Wait for PostgreSQL to be ready
    local retries=10
    while ! pg_isready -q 2>/dev/null && [[ $retries -gt 0 ]]; do
        sleep 1
        ((retries--))
    done

    if ! pg_isready -q 2>/dev/null; then
        die "PostgreSQL is not responding"
    fi

    # Create database if it doesn't exist
    if psql -lqt 2>/dev/null | cut -d '|' -f 1 | grep -qw nexus; then
        log "Database 'nexus' already exists"
    else
        info "Creating database 'nexus'..."
        createdb nexus 2>&1 | tee -a "$LOG_FILE"
        log "Database 'nexus' created"
    fi
}

# ============================================================================
# Pull Ollama models
# ============================================================================
setup_ollama() {
    header "Ollama Models"

    # Wait for Ollama to be ready
    local retries=15
    while ! curl -s http://localhost:11434/api/tags &>/dev/null && [[ $retries -gt 0 ]]; do
        sleep 2
        ((retries--))
    done

    if ! curl -s http://localhost:11434/api/tags &>/dev/null; then
        warn "Ollama not responding — models will be pulled on first use"
        return
    fi

    # Embedding model (required for RAG)
    info "Pulling nomic-embed-text (274MB embedding model)..."
    ollama pull nomic-embed-text:latest 2>&1 | tail -1 | tee -a "$LOG_FILE"
    log "nomic-embed-text ready"

    # Primary LLM
    info "Pulling kimi-k2.5:cloud (primary LLM — this may take a while)..."
    ollama pull kimi-k2.5:cloud 2>&1 | tail -1 | tee -a "$LOG_FILE"
    log "kimi-k2.5:cloud ready"
}

# ============================================================================
# Environment configuration with onboarding prompts
# ============================================================================
setup_environment() {
    header "Environment Configuration"

    local env_file="$NEXUS_HOME/backend/.env"

    if [[ -f "$env_file" ]]; then
        warn ".env file already exists — keeping existing configuration"
        return
    fi

    # Copy template
    if [[ -f "$INSTALLER_DIR/templates/env.template" ]]; then
        cp "$INSTALLER_DIR/templates/env.template" "$env_file"
    else
        # Generate minimal .env
        cat > "$env_file" << 'ENVEOF'
# Nexus Agent — Environment Configuration
# Generated by nexus-installer

HOST=0.0.0.0
PORT=8080
ALLOWED_ORIGINS=http://localhost:8080,http://127.0.0.1:8080

# Database
DATABASE_URL=postgresql+asyncpg://localhost/nexus

# Redis
REDIS_URL=redis://localhost:6379

# Admin Access Key (change this!)
ADMIN_API_KEY=change-me-to-a-random-secret

# === Optional API Keys ===
# Anthropic Claude (cloud fallback model)
ANTHROPIC_API_KEY=

# Brave Search
BRAVE_API_KEY=

# Mem0 (cloud memory service)
MEM0_API_KEY=

# Telegram Bot
TELEGRAM_BOT_TOKEN=

# GitHub
GITHUB_TOKEN=
ENVEOF
    fi

    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║     Nexus Agent — API Key Setup          ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo "Nexus works out of the box with Ollama (local AI)."
    echo "The following API keys are OPTIONAL and enable additional features."
    echo "Press Enter to skip any key — you can add them later in the Admin UI."
    echo ""

    # Admin key
    local admin_key
    admin_key=$(openssl rand -hex 16 2>/dev/null || echo "nexus-$(date +%s)")
    sed -i '' "s|ADMIN_API_KEY=change-me-to-a-random-secret|ADMIN_API_KEY=${admin_key}|" "$env_file"
    log "Admin API key generated"

    # Anthropic
    echo -e "${YELLOW}Anthropic API Key${NC} (enables Claude cloud fallback):"
    read -rp "  → " api_key
    if [[ -n "$api_key" ]]; then
        sed -i '' "s|ANTHROPIC_API_KEY=|ANTHROPIC_API_KEY=${api_key}|" "$env_file"
        log "Anthropic API key configured"
    else
        info "Skipped — Nexus will use Ollama only"
    fi

    # Brave Search
    echo -e "${YELLOW}Brave Search API Key${NC} (enables web search):"
    read -rp "  → " api_key
    if [[ -n "$api_key" ]]; then
        sed -i '' "s|BRAVE_API_KEY=|BRAVE_API_KEY=${api_key}|" "$env_file"
        log "Brave Search key configured"
    fi

    # Telegram
    echo -e "${YELLOW}Telegram Bot Token${NC} (enables Telegram integration):"
    read -rp "  → " api_key
    if [[ -n "$api_key" ]]; then
        sed -i '' "s|TELEGRAM_BOT_TOKEN=|TELEGRAM_BOT_TOKEN=${api_key}|" "$env_file"
        log "Telegram bot token configured"
    fi

    # GitHub
    echo -e "${YELLOW}GitHub Token${NC} (enables GitHub plugin):"
    read -rp "  → " api_key
    if [[ -n "$api_key" ]]; then
        sed -i '' "s|GITHUB_TOKEN=|GITHUB_TOKEN=${api_key}|" "$env_file"
        log "GitHub token configured"
    fi

    echo ""
    log "Environment configured at $env_file"
    echo -e "  Admin UI key: ${BOLD}${admin_key}${NC}"
    echo "  Save this key — you'll need it to access the Admin dashboard."
    echo ""
}

# ============================================================================
# Install launchd daemon for auto-start
# ============================================================================
install_daemon() {
    header "System Daemon"

    local plist_src="$INSTALLER_DIR/templates/com.nexus.agent.plist"
    local plist_dst="$HOME/Library/LaunchAgents/com.nexus.agent.plist"

    # Stop existing daemon if running
    if launchctl list 2>/dev/null | grep -q "com.nexus.agent"; then
        info "Stopping existing Nexus daemon..."
        launchctl bootout "gui/$(id -u)/com.nexus.agent" 2>/dev/null || true
        sleep 1
    fi

    # Create logs directory
    mkdir -p "$NEXUS_HOME/backend/logs"

    if [[ -f "$plist_src" ]]; then
        info "Installing launchd daemon..."
        sed "s|__NEXUS_HOME__|${NEXUS_HOME}|g" "$plist_src" > "$plist_dst"
    else
        warn "Plist template not found — generating from defaults..."
        cat > "$plist_dst" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.nexus.agent</string>
    <key>ProgramArguments</key>
    <array>
        <string>${NEXUS_HOME}/venv/bin/python</string>
        <string>-m</string>
        <string>uvicorn</string>
        <string>main:app</string>
        <string>--host</string>
        <string>0.0.0.0</string>
        <string>--port</string>
        <string>8080</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${NEXUS_HOME}/backend</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>${NEXUS_HOME}/venv/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>VIRTUAL_ENV</key>
        <string>${NEXUS_HOME}/venv</string>
        <key>PYTHONPATH</key>
        <string>${NEXUS_HOME}/backend</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>ThrottleInterval</key>
    <integer>5</integer>
    <key>StandardOutPath</key>
    <string>${NEXUS_HOME}/backend/logs/launchd-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${NEXUS_HOME}/backend/logs/launchd-stderr.log</string>
    <key>SoftResourceLimits</key>
    <dict>
        <key>NumberOfFiles</key>
        <integer>4096</integer>
    </dict>
    <key>HardResourceLimits</key>
    <dict>
        <key>NumberOfFiles</key>
        <integer>8192</integer>
    </dict>
    <key>Nice</key>
    <integer>0</integer>
</dict>
</plist>
PLISTEOF
    fi

    # Load the daemon
    launchctl bootstrap "gui/$(id -u)" "$plist_dst" 2>/dev/null || \
        launchctl load "$plist_dst" 2>/dev/null || true

    log "Nexus daemon installed and started"
    log "Nexus will auto-start on login and restart on crash"
}

# ============================================================================
# Post-install verification
# ============================================================================
verify_installation() {
    header "Verification"

    local pass=0
    local fail=0

    # Check services
    if brew services list 2>/dev/null | grep postgresql | grep -q started; then
        log "PostgreSQL: running"; ((pass++))
    else
        err "PostgreSQL: not running"; ((fail++))
    fi

    if brew services list 2>/dev/null | grep redis | grep -q started; then
        log "Redis: running"; ((pass++))
    else
        err "Redis: not running"; ((fail++))
    fi

    if curl -s http://localhost:11434/api/tags &>/dev/null; then
        log "Ollama: running"; ((pass++))
    else
        err "Ollama: not running"; ((fail++))
    fi

    # Check Nexus files
    [[ -f "$NEXUS_HOME/backend/main.py" ]] && { log "Backend: present"; ((pass++)); } || { err "Backend: missing"; ((fail++)); }
    [[ -d "$NEXUS_HOME/venv" ]] && { log "Python venv: present"; ((pass++)); } || { err "Python venv: missing"; ((fail++)); }
    [[ -d "$NEXUS_HOME/frontend/chat-build" ]] && { log "Chat UI: built"; ((pass++)); } || { err "Chat UI: not built"; ((fail++)); }
    [[ -d "$NEXUS_HOME/frontend/admin-build" ]] && { log "Admin UI: built"; ((pass++)); } || { err "Admin UI: not built"; ((fail++)); }
    [[ -f "$NEXUS_HOME/backend/.env" ]] && { log "Environment: configured"; ((pass++)); } || { err "Environment: missing"; ((fail++)); }

    # Wait for Nexus to start
    info "Waiting for Nexus to start..."
    local retries=15
    while ! curl -s http://localhost:8080/health &>/dev/null && [[ $retries -gt 0 ]]; do
        sleep 2
        ((retries--))
    done

    if curl -s http://localhost:8080/health &>/dev/null; then
        log "Nexus server: responding on port 8080"; ((pass++))
    else
        err "Nexus server: not responding (check logs at $NEXUS_HOME/backend/logs/)"; ((fail++))
    fi

    echo ""
    echo -e "${BOLD}Results: ${GREEN}${pass} passed${NC}, ${RED}${fail} failed${NC}"

    return $fail
}

# ============================================================================
# Final summary
# ============================================================================
print_summary() {
    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║                                                      ║${NC}"
    echo -e "${BOLD}${CYAN}║        Nexus Agent — Installation Complete           ║${NC}"
    echo -e "${BOLD}${CYAN}║                                                      ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}Chat UI:${NC}   http://localhost:8080"
    echo -e "  ${BOLD}Admin UI:${NC}  http://localhost:8080/admin"
    echo -e "  ${BOLD}Health:${NC}    http://localhost:8080/health"
    echo ""
    echo -e "  ${BOLD}Install dir:${NC}  $NEXUS_HOME"
    echo -e "  ${BOLD}Config:${NC}       $NEXUS_HOME/backend/.env"
    echo -e "  ${BOLD}Logs:${NC}         $NEXUS_HOME/backend/logs/"
    echo -e "  ${BOLD}Install log:${NC}  $LOG_FILE"
    echo ""
    echo -e "  ${BOLD}Manage daemon:${NC}"
    echo "    Stop:    launchctl bootout gui/$(id -u)/com.nexus.agent"
    echo "    Start:   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.nexus.agent.plist"
    echo "    Logs:    tail -f $NEXUS_HOME/backend/logs/launchd-stdout.log"
    echo ""
    echo -e "  ${BOLD}Manage services:${NC}"
    echo "    brew services list"
    echo "    brew services restart postgresql@17"
    echo "    brew services restart redis"
    echo "    brew services restart ollama"
    echo ""
}

# ============================================================================
# Main
# ============================================================================
main() {
    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║                                                      ║${NC}"
    echo -e "${BOLD}${CYAN}║          Nexus Agent — macOS Installer               ║${NC}"
    echo -e "${BOLD}${CYAN}║          Complete AI Agent System                     ║${NC}"
    echo -e "${BOLD}${CYAN}║                                                      ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "This will install:"
    echo "  • Homebrew (if needed)"
    echo "  • Ollama + AI models (kimi-k2.5, nomic-embed-text)"
    echo "  • PostgreSQL 17 + Redis"
    echo "  • Nexus backend (FastAPI + 8 plugins + 38 skill actions)"
    echo "  • Nexus Chat UI (React 19)"
    echo "  • Nexus Admin UI (Radix + Tailwind)"
    echo "  • RAG pipeline, Knowledge Graph, Embeddings"
    echo "  • Auto-start daemon (launchd)"
    echo ""
    echo -e "Install location: ${BOLD}$NEXUS_HOME${NC}"
    echo ""
    read -rp "Press Enter to begin installation (Ctrl+C to cancel)... "

    preflight
    install_homebrew
    install_system_deps
    clone_nexus
    setup_python
    build_frontends
    setup_database
    setup_ollama
    setup_environment
    install_daemon

    if verify_installation; then
        print_summary
        log "Installation completed successfully!"
    else
        print_summary
        warn "Installation completed with some issues — check the log for details"
    fi
}

main "$@"
