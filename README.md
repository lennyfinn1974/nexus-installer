# Nexus Agent — macOS Installer

Single-command installer for the complete Nexus AI Agent system on macOS.

## What Gets Installed

- **Homebrew** (if not present)
- **Ollama** + AI models (kimi-k2.5, nomic-embed-text)
- **PostgreSQL 17** — conversation storage, knowledge graph
- **Redis** — caching, clustering coordination
- **Nexus Backend** — FastAPI server with 8 plugins, 38 skill actions
- **Nexus Chat UI** — React 19 + Vite web interface
- **Nexus Admin UI** — System management dashboard
- **RAG Pipeline** — embeddings, knowledge graph, vector search
- **Auto-start daemon** — launches on login, restarts on crash

## Requirements

- macOS 12+ (Monterey or later)
- Apple Silicon (M1/M2/M3) or Intel Mac
- 5GB+ free disk space
- Internet connection
- Git access to the Nexus repository

## Quick Install

```bash
git clone https://github.com/lennyfinn1974/nexus-installer.git
cd nexus-installer
chmod +x install.sh
./install.sh
```

The installer will prompt you for optional API keys during setup. Press Enter to skip any — all keys can be added later via the Admin UI.

## Custom Install Location

```bash
NEXUS_HOME=/path/to/nexus ./install.sh
```

Default: `~/Nexus`

## After Installation

- **Chat UI**: http://localhost:8080
- **Admin UI**: http://localhost:8080/admin
- **Health Check**: http://localhost:8080/health

## Scripts

| Script | Purpose |
|--------|---------|
| `install.sh` | Full system installation |
| `scripts/verify.sh` | Check all components are healthy |
| `scripts/uninstall.sh` | Clean removal with options |

### Verify Installation

```bash
./scripts/verify.sh
```

### Uninstall

```bash
./scripts/uninstall.sh
```

The uninstaller will ask before removing each component. Your PostgreSQL data and Ollama models are preserved by default.

## Managing the Daemon

Nexus runs as a launchd daemon — it starts automatically on login.

```bash
# Stop
launchctl bootout gui/$(id -u)/com.nexus.agent

# Start
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.nexus.agent.plist

# View logs
tail -f ~/Nexus/backend/logs/launchd-stdout.log
```

## Managing Services

```bash
brew services list                    # See all services
brew services restart postgresql@17   # Restart PostgreSQL
brew services restart redis           # Restart Redis
brew services restart ollama          # Restart Ollama
```

## Configuration

Edit `~/Nexus/backend/.env` to add or change API keys. Restart Nexus after changes:

```bash
launchctl bootout gui/$(id -u)/com.nexus.agent
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.nexus.agent.plist
```

Or use the Admin UI at http://localhost:8080/admin to configure settings without restarting.

## Troubleshooting

**Nexus not responding on port 8080:**
```bash
# Check if something else is using the port
lsof -ti :8080
# Check Nexus logs
tail -50 ~/Nexus/backend/logs/launchd-stderr.log
```

**PostgreSQL not starting:**
```bash
brew services restart postgresql@17
pg_isready
```

**Ollama models not downloading:**
```bash
ollama list              # See installed models
ollama pull kimi-k2.5:cloud   # Manual pull
```

## License

Private — requires access to the Nexus repository.
