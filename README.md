# pi-container  (🥧)

A sandboxed Docker environment for running the [pi coding agent](https://github.com/badlogic/pi-mono), isolated from your host while sharing your workspace, persistent agent data, and local skills.

## Features

- **pi coding agent**, **Python 3 + uv**, **Git + GitHub CLI**, and common build tools
- Runs as a **non-root user** with **UID/GID mapping** so files stay owned by you
- Only **explicit mounts** are exposed; skills are mounted **read-only**
- **Built from source** — no pre-built images

## Quick start

```bash
cp .env.example .env        # set GitHub token, git identity, UID/GID
make build
make run
```

### Commands

| Command | Description |
|---|---|
| `make build` | Build the Docker image |
| `make update` | Rebuild without cache (e.g., update pi) |
| `make run` | Launch pi in interactive TUI mode |
| `make args="..." run-args` | Run pi with arguments (see below) |
| `make shell` | Open a bash shell in the container |
| `make clean` | Stop and remove containers/networks |

```bash
make args="--version" run-args
make args="/login" run-args
make args="'Create a snake game in python'" run-args
```

## Volumes

| Host path | Container path | Mode |
|---|---|---|
| `./workspace` | `/workspace` | read-write |
| `./.pi-data` | `/home/node/.pi` | read-write |
| `~/.agents/skills` (or `$SKILLS_DIR`) | `/home/node/.agents/skills` | read-only |

## Running pi from any directory

After `make build`, the `pie` wrapper script mounts your **current directory** as `/workspace`, so you can use the agent on any project without modifying it.

```bash
# From inside the pi-container repo:
ln -s "$(pwd)/pie" /usr/local/bin/pie

cd ~/my-other-project
pie                           # interactive TUI
pie "Explain this codebase"   # one-off prompt
pie --version
```

`pie` calls `docker run` directly (bypassing Compose), reads `.env` from the pi-container repo automatically, and always sources `.pi-data` from there — so installed packages, settings, and login state are shared across all projects.

## Extending pi from inside the container

Because mounts are read-write, pi can extend itself and changes persist:

| What you do | Persists? |
|---|---|
| `pi install npm:...` / `pi install git:...` (→ `.pi-data/`) | ✅ |
| `pi config` changes (→ `.pi-data/agent/settings.json`) | ✅ |
| Write extensions/skills/themes into `/workspace` | ✅ |
| Modify pi's source in `/usr/local/lib/node_modules/...` | ❌ lost on restart |
| Write to `~/.agents/skills/` | ❌ read-only |

Recommended workflow: use `pi install`, or place local extensions/skills in `/workspace` and reference them from a project-level `.pi/settings.json`.

## Credits

Based on [gni/pi-coding-agent-container](https://github.com/gni/pi-coding-agent-container).
