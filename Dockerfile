# syntax=docker/dockerfile:1

# -----------------------------------------------------------------------------
# Pinned versions for reproducible builds.
# Bump these deliberately; avoid `latest` so image contents don't drift.
# -----------------------------------------------------------------------------
ARG UV_VERSION=0.11.7
ARG PI_AGENT_VERSION=0.67.68

FROM node:22-bookworm-slim AS base

# Set environment variables for production and non-interactive installation
ENV NODE_ENV=production
ENV DEBIAN_FRONTEND=noninteractive
ENV NPM_CONFIG_LOGLEVEL=warn

# Install essential system tools required by pi-coding-agent and common dev workflows
# - git: Required for 'pi install git:...' and version control operations
# - curl/wget: For downloading external resources
# - procps: For process monitoring
# - build-essential: For compiling native add-ons (if extensions require them)
# - ca-certificates: Ensure SSL connections work securely
# - python3/python3-venv: For Python development (venv needed by uv)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    wget \
    ca-certificates \
    procps \
    build-essential \
    python3 \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Install GitHub CLI (gh)
# -----------------------------------------------------------------------------
RUN mkdir -p -m 755 /etc/apt/keyrings \
    && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Install uv (fast Python package manager) at a pinned version
# https://docs.astral.sh/uv/
# -----------------------------------------------------------------------------
ARG UV_VERSION
COPY --from=ghcr.io/astral-sh/uv:${UV_VERSION} /uv /uvx /usr/local/bin/

FROM base AS release

# Install the pi-coding-agent globally at a pinned version
# We verify the registry connection implicitly during install
ARG PI_AGENT_VERSION
RUN npm install -g @mariozechner/pi-coding-agent@${PI_AGENT_VERSION}

# Transparently route GitHub SSH remotes over HTTPS so that `gh`'s credential
# helper can authenticate pushes without requiring an ssh client or SSH keys.
RUN git config --system --add url."https://github.com/".insteadOf "git@github.com:" \
 && git config --system --add url."https://github.com/".insteadOf "ssh://git@github.com/"

# Create a non-root user setup
# We use the existing 'node' user (UID 1000) provided by the base image
# Create the .pi directory structure to ensure permissions are correct when mounted
RUN mkdir -p /home/node/.pi/agent && \
    mkdir -p /home/node/.agents/skills && \
    mkdir -p /workspace && \
    chown -R node:node /home/node/.pi && \
    chown -R node:node /home/node/.agents && \
    chown -R node:node /workspace

# Set the working directory to the project workspace
WORKDIR /workspace

# Switch to non-root user for security
USER node

# Verify installation
RUN pi --version && uv --version

ENTRYPOINT ["pi"]
CMD []
