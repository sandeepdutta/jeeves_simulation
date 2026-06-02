#!/usr/bin/env bash
# Usage:
#   ./docker_build.sh           — auto-detect platform (arm64 on Apple Silicon, amd64 on x86)
#   ./docker_build.sh amd64     — force AMD64 (emulated on Apple Silicon via Rosetta)
#   ./docker_build.sh arm64     — force ARM64

set -e

# Resolve absolute paths from this script's location regardless of call directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ROS_SRC="$PROJECT_DIR/ros_ws/src"
JEEVES_SIM_DOCKERFILE="$ROS_SRC/jeeves_production_description/docker/jeeves/Dockerfile.jeeves_sim"

echo "Project root : $PROJECT_DIR"
echo "ROS src      : $ROS_SRC"

# Detect native arch, allow override via argument
NATIVE_ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
ARCH=${1:-$NATIVE_ARCH}
PLATFORM="linux/$ARCH"

echo "Building for platform: $PLATFORM"

CONTAINER_NAME_BASE="jeeves_simulation_humble_base"
CONTAINER_NAME_URDF="jeeves_humble_urdf"
FINAL_IMAGE="sandeepdutta/jeeves_humble_final:latest"

# Remove old images so Docker cannot reuse stale layers
echo "Removing old images..."
docker rmi "$FINAL_IMAGE" "$CONTAINER_NAME_URDF:latest" 2>/dev/null || true

echo "Building ROS2-Humble base image..."
docker build --rm \
    --platform "$PLATFORM" \
    -t $CONTAINER_NAME_BASE:latest \
    -f "$SCRIPT_DIR/Dockerfile.base" \
    "$SCRIPT_DIR"

echo "Building URDF image..."
docker build --rm \
    --platform "$PLATFORM" \
    -t $CONTAINER_NAME_URDF:latest \
    -f "$JEEVES_SIM_DOCKERFILE" \
    --build-arg BASE_IMAGE=$CONTAINER_NAME_BASE \
    "$ROS_SRC"

echo "Building final image..."
docker build --rm \
    --platform "$PLATFORM" \
    -t $FINAL_IMAGE \
    -f "$SCRIPT_DIR/Dockerfile.final" \
    --build-arg BASE_IMAGE=$CONTAINER_NAME_URDF \
    "$SCRIPT_DIR"

echo "Docker Build Completed — $FINAL_IMAGE ($PLATFORM)"
