#!/bin/sh

BASE_TAG="6.6-24.04_beta"
BASE_IMAGE="docker.io/ubuntu/squid:$BASE_TAG@sha256:6a097f68bae708cedbabd6188d68c7e2e7a38cedd05a176e1cc0ba29e3bbe029"
CONTAINER=$(buildah from "$BASE_IMAGE")
IMAGE=claude-squid
REPO_NAME="cbarreholm/claude-podman"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Process arguments
while [ "$#" -gt 0 ]; do
	case "$1" in
	--help)
		cat <<-'EOT'
			Usage: $0 [OPTIONS]

			Build Squid proxy image for claude-podman restricted network

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

# Copy squid config into the image
buildah copy "$CONTAINER" "${SCRIPT_DIR}/squid.conf" /etc/squid/squid.conf

buildah config \
	--annotation "org.opencontainers.image.title=claude-squid" \
	--annotation "org.opencontainers.image.description=Squid proxy for claude-podman restricted network" \
	--annotation "org.opencontainers.image.url=https://github.com/$REPO_NAME" \
	--annotation "org.opencontainers.image.source=https://github.com/$REPO_NAME" \
	--annotation "org.opencontainers.image.license=AGPL-3.0-or-later" \
	--annotation "org.opencontainers.image.created=$(date --iso-8601=seconds)" \
	"$CONTAINER"

buildah commit \
	--rm \
	"$CONTAINER" "$IMAGE"

buildah tag "$IMAGE" "$IMAGE:$BASE_TAG"

echo Done!
echo "${IMAGE}:${BASE_TAG}"
