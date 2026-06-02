#!/usr/bin/env bash
# Usage:
#   ./docker_build.sh           — auto-detect platform (arm64 on Apple Silicon, amd64 on x86)
#   ./docker_build.sh amd64     — force AMD64 (emulated on Apple Silicon via Rosetta)
#   ./docker_build.sh arm64     — force ARM64

set -e

# Detect native arch, allow override via argument
NATIVE_ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
ARCH=${1:-$NATIVE_ARCH}
PLATFORM="linux/$ARCH"

echo "Building for platform: $PLATFORM"

CONTAINER_NAME_BASE="jeeves_simulation_humble_base"
CONTAINER_NAME_URDF="jeeves_humble_urdf"
FINAL_IMAGE="sandeepdutta/jeeves_humble_final:latest"

echo "Building ROS2-Humble base image..."
docker build --rm \
    --platform "$PLATFORM" \
    -t $CONTAINER_NAME_BASE:latest \
    -f Dockerfile.base ./

echo "Building URDF image..."
docker build --rm \
    --platform "$PLATFORM" \
    -t $CONTAINER_NAME_URDF:latest \
    -f ../ros_ws/src/jeeves_production_description/docker/jeeves/Dockerfile.jeeves_sim \
    --build-arg BASE_IMAGE=$CONTAINER_NAME_BASE \
    ../ros_ws/src

echo "Building final image..."
docker build --rm \
    --platform "$PLATFORM" \
    -t $FINAL_IMAGE \
    -f Dockerfile.final \
    --build-arg BASE_IMAGE=$CONTAINER_NAME_URDF ./

echo "Docker Build Completed — $FINAL_IMAGE ($PLATFORM)"
