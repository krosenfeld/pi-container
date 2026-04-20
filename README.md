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
| repo root (`make run`) / current dir (`pie`) | `/workspace` | read-write |
| `./.pi-data` (in the pi-container repo) | `/home/node/.pi` | read-write |
| `~/.agents/skills` (or `$SKILLS_DIR`) | `/home/node/.agents/skills` | read-only |

## Running pi from any directory

After `make build`, the `pie` wrapper script mounts your **current directory** as `/workspace`, so you can use the agent on any project without modifying it.

Install it as a **symlink** (not a copy) — the script locates `.env` and `.pi-data` relative to the real script location, and resolves symlinks to find them.

```bash
# From inside the pi-container repo:
sudo ln -s "$(pwd)/pie" /usr/local/bin/pie   # /usr/local/bin typically requires sudo
# or, without sudo, drop it somewhere already on your PATH, e.g.:
#   mkdir -p ~/.local/bin && ln -s "$(pwd)/pie" ~/.local/bin/pie

cd ~/my-other-project
pie                           # interactive TUI
pie "Explain this codebase"   # one-off prompt
pie --version
```

`pie` calls `docker run` directly (bypassing Compose), reads `.env` from the pi-container repo automatically, and always sources `.pi-data` from there — so installed packages, settings, and login state are shared across all projects.

`pie` auto-detects whether it is being run interactively: it passes `-i -t` to `docker run` only when both stdin and stdout are attached to a terminal, passes just `-i` when stdin is a pipe/file (so you can `echo ... | pie ...`), and omits both when run fully non-interactively (e.g. `pie --version` in CI). This keeps the interactive TUI working while making scripted use safe.

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
