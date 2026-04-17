# pi-container

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

## Credits

Based on [gni/pi-coding-agent-container](https://github.com/gni/pi-coding-agent-container).
