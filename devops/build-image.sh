#!/bin/sh
set -eu

# opencode release pin. To upgrade: bump the version, then update both
# checksums from the new release assets (compute with sha256sum after
# downloading from https://github.com/anomalyco/opencode/releases).
OPENCODE_VERSION="1.18.13"
OPENCODE_SHA256_X86_64="93f1506f26ad8b6e867754d144bea43e6c707ec518bac227fdf959048d020d74"
OPENCODE_SHA256_AARCH64="a5b90d6111d2d826fe14952c769d0d4bcf00db7810c0c92d9f4541d3768f03ef"

IMAGE=opencode
REPO_NAME="ingby/opencode-podman"

# Process arguments
while [ "$#" -gt 0 ]; do
	case "$1" in
	--help)
		cat <<-'EOT'
			Usage: $0 [OPTIONS]

			Build image to run opencode in a Podman container

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

case "$(uname -m)" in
x86_64)
	OPENCODE_ASSET="opencode-linux-x64-musl.tar.gz"
	OPENCODE_SHA256="$OPENCODE_SHA256_X86_64"
	;;
aarch64 | arm64)
	OPENCODE_ASSET="opencode-linux-arm64-musl.tar.gz"
	OPENCODE_SHA256="$OPENCODE_SHA256_AARCH64"
	;;
*)
	echo "Unsupported architecture: $(uname -m)" >&2
	exit 1
	;;
esac

CONTAINER=$(buildah from docker.io/alpine:latest)

# Install dependencies and create user
buildah run "$CONTAINER" sh <<EOT
	set -eu
	apk add --no-cache bash curl git libgcc libstdc++ ripgrep
	adduser -D opencode
EOT

# Install opencode from a pinned GitHub release tarball, verifying its
# sha256 against the checksum committed in this repo. The binary is
# installed root-owned outside the user's home so opencode cannot
# replace itself even if an update were attempted.
buildah run "$CONTAINER" sh <<EOT
	set -eu
	cd /tmp
	curl --proto '=https' --tlsv1.2 -fsSLo "$OPENCODE_ASSET" \
		"https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/${OPENCODE_ASSET}"
	echo "$OPENCODE_SHA256  $OPENCODE_ASSET" | sha256sum -c -
	tar -xzf "$OPENCODE_ASSET" -C /usr/local/bin opencode
	chown root:root /usr/local/bin/opencode
	chmod 755 /usr/local/bin/opencode
	rm -f "$OPENCODE_ASSET"
EOT

# Bake a default config that disables autoupdate. If the config dir is
# bind-mounted at runtime this file is shadowed, so the
# OPENCODE_DISABLE_AUTOUPDATE env var below is the authoritative switch.
buildah run --user opencode "$CONTAINER" sh <<'EOT'
	set -eu
	mkdir -p /home/opencode/.config/opencode
	cat > /home/opencode/.config/opencode/opencode.json <<'JSON'
{
  "$schema": "https://opencode.ai/config.json",
  "autoupdate": false
}
JSON
EOT

buildah config \
	--author "Christer Barreholm" \
	--env "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
	--env "SHELL=/bin/bash" \
	--env "OPENCODE_DISABLE_AUTOUPDATE=true" \
	--cmd "" \
	--entrypoint '[ "/usr/local/bin/opencode" ]' \
	--annotation "ai.opencode.version=$OPENCODE_VERSION" \
	--annotation "org.opencontainers.image.title=opencode" \
	--annotation "org.opencontainers.image.description=opencode on Alpine ready for rootless podman" \
	--annotation "org.opencontainers.image.url=https://github.com/$REPO_NAME" \
	--annotation "org.opencontainers.image.source=https://github.com/$REPO_NAME" \
	--annotation "org.opencontainers.image.documentation=https://github.com/$REPO_NAME/blob/main/README.md" \
	--annotation "org.opencontainers.image.license=AGPL-3.0-or-later" \
	--annotation "org.opencontainers.image.created=$(date --iso-8601=seconds)" \
	"$CONTAINER"

buildah commit \
	--rm \
	"$CONTAINER" "$IMAGE"

buildah tag "$IMAGE" "$IMAGE:$OPENCODE_VERSION"

echo Done!
echo ${IMAGE}:${OPENCODE_VERSION}
echo To use this image run /bin/opencode
