#!/bin/sh

CONTAINER=$(buildah from docker.io/alpine:latest)
IMAGE=claude-code
REPO_NAME="EvanCarroll/claude-podman"

# Process arguments
while [ "$#" -gt 0 ]; do
	case "$1" in
	--help)
		cat <<-'EOT'
			Usage: $0 [OPTIONS]

			Build image to run Claude Code in a Podman container

			Options:
			  --repo-name REPO_NAME  Use the specified repo name instead of the default "REPO_NAME"
			  --help                 Display this help message
		EOT
		exit 0
		;;
	--repo-name)
		REPO_NAME="$2"
		shift 2
		;;
	*)
		break
		;;
	esac
done

# Install dependencies and create user
buildah run "$CONTAINER" sh <<EOT
	apk add --no-cache bash curl libgcc libstdc++ ripgrep
	adduser -D claude
EOT

# Install Claude Code using native installer as the claude user
buildah run --user claude "$CONTAINER" bash -c 'curl -fsSL https://claude.ai/install.sh | bash'

# Get the installed version
CLAUDE_VERSION=$(buildah run --user claude "$CONTAINER" /home/claude/.local/bin/claude --version 2>/dev/null | head -1 | awk '{print $1}')

buildah config \
	--author "Evan Carroll" \
	--env "PATH=/home/claude/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
	--env "SHELL=/bin/bash" \
	--env "DISABLE_TELEMETRY=1" \
	--env "DISABLE_AUTOUPDATER=1" \
	--env "USE_BUILTIN_RIPGREP=0" \
	--cmd "" \
	--entrypoint '[ "/home/claude/.local/bin/claude" ]' \
	--annotation "org.anthropic.claudecode.version=$CLAUDE_VERSION" \
	--annotation "org.opencontainers.image.title=claude-code" \
	--annotation "org.opencontainers.image.description=Claude Code on Alpine ready for rootless podman" \
	--annotation "org.opencontainers.image.url=https://github.com/$REPO_NAME" \
	--annotation "org.opencontainers.image.source=https://github.com/$REPO_NAME" \
	--annotation "org.opencontainers.image.documentation=https://github.com/$REPO_NAME/blob/main/README.md" \
	--annotation "org.opencontainers.image.license=AGPL-3.0-or-later" \
	--annotation "org.opencontainers.image.created=$(date --iso-8601=seconds)" \
	"$CONTAINER"

buildah commit \
	--rm \
	"$CONTAINER" "$IMAGE"

buildah tag "$IMAGE" "$IMAGE:$CLAUDE_VERSION"

echo Done!
echo ${IMAGE}:${CLAUDE_VERSION}
echo To use this image run /bin/claude
