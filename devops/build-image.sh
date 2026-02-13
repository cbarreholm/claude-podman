#!/bin/sh

CONTAINER=$(buildah from docker.io/node:current-alpine)
CLAUDE_VERSION=$(npm info @anthropic-ai/claude-code --json | jq .version -r)
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

#apk add --no-cache dash
buildah run "$CONTAINER" sh <<EOT
	npm config set os linux
	apk add --no-cache zsh
	npm --os=linux install --omit=dev --no-audit --no-fund -g @anthropic-ai/claude-code
	apk cache clean
	rm -rf /usr/local/lib/node_modules/npm/man/
	find . -type f -name '*.md' -delete 2> /dev/null
	adduser -D claude
EOT

buildah config \
	--author "Evan Carroll" \
	--env "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
	--env "SHELL=/bin/zsh" \
	--env "DISABLE_TELEMETRY=1" \
	--env "DISABLE_AUTOUPDATER=1" \
	--cmd "" \
	--entrypoint '[ "/usr/local/bin/node", "--no-warnings", "--enable-source-maps", "/usr/local/bin/claude" ]' \
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

buildah tag "$IMAGE" "$CLAUDE_VERSION"

echo Done!
echo ${IMAGE}:${CLAUDE_VERSION}
echo To use this image run /bin/claude
