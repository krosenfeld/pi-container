# pi-container 🥧

A sandboxed Docker environment for running the [pi coding agent](https://github.com/badlogic/pi-mono). The container isolates the agent from your host system while providing access to your project workspace, persistent agent data, and local skills.

## What's included

- **pi coding agent** — installed globally from npm
- **Python 3 + uv** — for Python development with fast dependency management
- **Git + GitHub CLI (`gh`)** — for version control and GitHub workflows
- **Common tools** — curl, wget, build-essential

## Security

- Runs as a **non-root user** inside the container
- Only **explicit mounts** are exposed (workspace, agent data, skills)
- Skills directory is mounted **read-only**
- **UID/GID mapping** ensures files are owned by your host user
- **Built from source** — no pre-built images; you audit what you run

## Quick start

### 1. Configure

```bash
cp .env.example .env
# Edit .env with your GitHub token, git identity, and UID/GID
```

### 2. Build

```bash
make build
```

### 3. Run

```bash
make run
```

## Usage

| Command | Description |
|---|---|
| `make build` | Build the Docker image |
| `make update` | Rebuild without cache (e.g., to update pi) |
| `make run` | Launch pi in interactive TUI mode |
| `make args="..." run-args` | Run with arguments (see examples below) |
| `make shell` | Open a bash shell inside the container |
| `make clean` | Stop and remove containers/networks |

### Examples

```bash
# Check version
make args="--version" run-args

# Login to providers
make args="/login" run-args

# Run with a one-off prompt
make args="'Create a snake game in python'" run-args
```

## Volumes

| Host path | Container path | Mode |
|---|---|---|
| `./workspace` | `/workspace` | read-write |
| `./.pi-data` | `/home/node/.pi` | read-write |
| `~/.agents/skills` | `/home/node/.agents/skills` | read-only |

The skills source path can be overridden by setting `SKILLS_DIR` in `.env`.

## Extending pi from inside the container

You can use pi to extend itself from within the container, and changes will persist thanks to the read-write volume mounts.

| What you do | Where it lives | Persists? |
|---|---|---|
| `pi install npm:...` / `pi install git:...` | `~/.pi/` → `.pi-data/` on host | ✅ Yes |
| `pi config` (enable/disable resources) | `~/.pi/agent/settings.json` | ✅ Yes |
| Write extensions/skills/themes to `/workspace` | `./workspace/` on host | ✅ Yes |
| Modify pi's own source in `/usr/local/lib/node_modules/...` | Container overlay filesystem | ❌ No — lost on restart |
| Write to `~/.agents/skills/` | Read-only mount | ❌ Not allowed |

The recommended workflow is to install packages (`pi install`) or place local extensions/skills in `/workspace` and reference them with a project-level `.pi/settings.json`. Both locations are backed by host-side read-write mounts and survive container restarts.

## Credits

Based on [gni/pi-coding-agent-container](https://github.com/gni/pi-coding-agent-container).
