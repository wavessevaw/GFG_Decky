#!/usr/bin/env bash
# Runs a Swift command inside the official Swift Linux image (used in Linux containers without a native toolchain).
# Usage: scripts/linux-swift.sh swift test -c release --package-path Packages/SSMTCore
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${SWIFT_IMAGE:-mirror.gcr.io/library/swift:6.0-noble}"
exec docker run --rm -v "$ROOT":/w -v ssmt-swift-build:/w/.build-cache -w /w "$IMAGE" "$@"
