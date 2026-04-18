# Helper Makefile to simplify running the secure agent container
# Usage: make run

.PHONY: build run clean shell

# Detect User ID and Group ID to prevent permission issues on Linux
HOST_UID := $(shell id -u)
HOST_GID := $(shell id -g)

# Create local data directory for persistence if using bind mount strategy
setup:
	mkdir -p .pi-data

# Build the docker image locally from source/npm
build:
	docker compose build

# Build without cache the docker image locally from source/npm
update:
	docker compose build --no-cache

# Run the agent in interactive mode
# Passes the current user's UID/GID to the container
run: setup
	UID=$(HOST_UID) GID=$(HOST_GID) docker compose run --rm pi-agent

# Run the agent with arguments (e.g., make args="--help" run-args)
run-args: setup
	UID=$(HOST_UID) GID=$(HOST_GID) docker compose run --rm pi-agent $(args)

# Access the container shell for debugging
shell: setup
	UID=$(HOST_UID) GID=$(HOST_GID) docker compose run --entrypoint /bin/bash --rm pi-agent

# Clean up stopped containers and networks
clean:
	docker compose down
