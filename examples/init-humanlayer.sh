#!/bin/bash
# Init script for the --init-script flag: installs the HumanLayer CLI
# and launches its daemon. Runs as root inside the container after
# startup; the daemon itself is dropped to the claude user, which is
# what the agent CLI runs as.
#
#   read -rs HUMANLAYER_LAUNCH_TOKEN && export HUMANLAYER_LAUNCH_TOKEN
#   claude-podman \
#     --init-script examples/init-humanlayer.sh \
#     --init-env HUMANLAYER_LAUNCH_TOKEN
#
# The token is read from the environment, never passed on the command
# line: an argument would be visible to every user on the host via `ps`,
# and would land in your shell history.
set -euo pipefail

if [ -z "${HUMANLAYER_LAUNCH_TOKEN:-}" ]; then
	echo "HUMANLAYER_LAUNCH_TOKEN is not set; pass it with --init-env" >&2
	exit 1
fi

# Pinned for reproducible installs. Bump deliberately; "latest" would
# silently pull whatever npm serves at container start.
HUMANLAYER_VERSION="0.31.0"

# nodejs/npm to run the CLI, gcompat/libstdc++ because HumanLayer ships
# glibc-linked binaries and the container is musl (Alpine)
apk add --no-cache nodejs npm gcompat libstdc++

# Disable install scripts for every npm invocation in this container,
# including any the agent runs later. Pre/post-install hooks are the
# main way an npm package executes arbitrary code at install time.
# Written to the global npmrc (root-owned, so the container user cannot
# undo it), though note a user-level ~/.npmrc still overrides it.
npm config set ignore-scripts true --location=global

# Install as root into /usr/local: already on PATH, and the container
# user cannot tamper with it. The flag is redundant given the config
# above, but keeps this line correct on its own.
npm install -g --ignore-scripts "@humanlayer/cli@${HUMANLAYER_VERSION}"

humanlayer --version

# The daemon runs as the agent does: uid 1000, the container's `claude`
# user, which bin/claude maps to your host account via --userns=keep-id.
# HumanLayer keeps its socket and session state under $HOME/.humanlayer,
# so a root-owned daemon would put both where the CLI never looks — and
# would give the approval broker root in the container for no reason.
# Install as root, run as claude.
DAEMON_USER=claude
DAEMON_UID=$(id -u "$DAEMON_USER")
if [ "$DAEMON_UID" != 1000 ]; then
	echo "expected $DAEMON_USER to be uid 1000, got $DAEMON_UID" >&2
	exit 1
fi

# `daemon launch` only runs in the foreground and has no detach flag, so
# it must be backgrounded here — otherwise the init script never returns
# and the agent CLI never starts. setsid detaches it from this exec
# session; the process reparents to the container's init and lives as
# long as the container does. There is no supervisor: if the daemon dies
# mid-session it stays dead until you restart the container.
#
# The log may contain session details, so it belongs to the daemon user
# and nobody else.
LOG=/var/log/humanlayer-daemon.log
touch "$LOG"
chown "$DAEMON_USER" "$LOG"
chmod 600 "$LOG"

# su, not setpriv: Alpine's busybox setpriv has no --reuid. su also
# gives the daemon claude's HOME, which is half the point of dropping to
# it. Only HOME/SHELL/USER/LOGNAME are replaced, so the token still
# reaches the inner shell through the environment instead of su's argv.
setsid su "$DAEMON_USER" -c \
	'exec humanlayer daemon launch --launch-token "$HUMANLAYER_LAUNCH_TOKEN"' \
	>>"$LOG" 2>&1 </dev/null &
DAEMON_PID=$!

# Give it a moment, then confirm it is actually up: without this a bad
# token just lands in the log and the session starts daemon-less.
sleep 3
if ! kill -0 "$DAEMON_PID" 2>/dev/null; then
	echo "humanlayer daemon exited immediately; last log lines:" >&2
	tail -n 20 "$LOG" >&2
	exit 1
fi

echo "humanlayer daemon running (pid $DAEMON_PID), logging to $LOG"
