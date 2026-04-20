# Helper Makefile to simplify running the secure agent container
# Usage: make run

.PHONY: build run clean shell check-uid

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

# Export so docker compose (which reads HOST_UID/HOST_GID from the
# environment via docker-compose.yml) picks them up consistently.
export HOST_UID
export HOST_GID

# Run the agent in interactive mode
# Passes the current user's UID/GID to the container
run: setup
	docker compose run --rm pi-agent

# Run the agent with arguments (e.g., make args="--help" run-args)
run-args: setup
	docker compose run --rm pi-agent $(args)

# Access the container shell for debugging
shell: setup
	docker compose run --entrypoint /bin/bash --rm pi-agent

# Verify that the container actually runs as the host UID/GID.
# Regression guard for the HOST_UID/HOST_GID wiring between the
# Makefile and docker-compose.yml.
check-uid: setup
	@actual_uid=$$(docker compose run --rm --no-TTY --entrypoint id pi-agent -u); \
	actual_gid=$$(docker compose run --rm --no-TTY --entrypoint id pi-agent -g); \
	if [ "$$actual_uid" != "$(HOST_UID)" ] || [ "$$actual_gid" != "$(HOST_GID)" ]; then \
		echo "FAIL: container uid:gid = $$actual_uid:$$actual_gid, expected $(HOST_UID):$(HOST_GID)"; \
		exit 1; \
	fi; \
	echo "OK: container runs as $$actual_uid:$$actual_gid"

# Clean up stopped containers and networks
clean:
	docker compose down
