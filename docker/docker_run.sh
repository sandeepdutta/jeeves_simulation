#!/usr/bin/env bash
# Usage:
#   ./docker_run.sh                    — NVIDIA/WSL2 mode, attach if already running
#   ./docker_run.sh parallels          — Parallels VM / no-GPU mode
#   ./docker_run.sh fresh              — stop old container and start fresh from latest image
#   ./docker_run.sh parallels fresh    — Parallels + fresh start

PLATFORM="nvidia"
FRESH=false
for arg in "$@"; do
    case "$arg" in
        parallels) PLATFORM="parallels" ;;
        fresh)     FRESH=true ;;
    esac
done

DOCKER_USER="admin"
BASH_HISTORY_FILE=${PWD%/*}/.bash_history
BASH_RC_FILE=${PWD%/*}/docker/.bashrc

# ── Platform-specific settings ────────────────────────────────────────────────
if [ "$PLATFORM" = "parallels" ]; then
    CONTAINER_NAME="jeeves_simulation_humble_parallels"
    GPU_FLAGS=""
    PLATFORM_VOLUMES=""
    PLATFORM_ENV=(
        "--env=LIBGL_ALWAYS_SOFTWARE=1"
    )
else
    CONTAINER_NAME="jeeves_simulation_humble"
    GPU_FLAGS="--gpus all --env NVIDIA_DRIVER_CAPABILITIES=all"
    PLATFORM_VOLUMES="
        --volume=/usr/share/vulkan/icd.d:/usr/share/vulkan/icd.d:ro
        --volume=/usr/lib/wsl:/usr/lib/wsl:ro"
    PLATFORM_ENV=(
        "--env=LD_LIBRARY_PATH=/usr/lib/wsl/lib"
        "--env=MESA_LOADER_DRIVER_OVERRIDE=d3d12"
        "--env=MESA_GL_VERSION_OVERRIDE=4.5COMPAT"
        "--env=VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/dzn_icd.x86_64.json"
    )
fi

# ── X11 auth ──────────────────────────────────────────────────────────────────
docker_count=$(docker ps -a | grep "$CONTAINER_NAME" | wc -l)
((docker_count=docker_count+1))
XAUTH=/tmp/.docker.xauth_${CONTAINER_NAME}_$docker_count
sleep 0.1
touch $XAUTH
mkdir -p "${HOME}/.gz/sim"
xauth nlist $DISPLAY | sed -e 's/^..../ffff/' | xauth -f $XAUTH nmerge - 2>/dev/null || true

# ── Device passthrough ────────────────────────────────────────────────────────
device_options=""
for device in /dev/*; do
    [ -e "$device" ] && device_options+="--device=$device "
done
for device in /dev/dri/*; do
    [ -e "$device" ] && device_options+="--device=$device "
done

# ── Fresh mode: stop old container so the new image is used ──────────────────
if [ "$FRESH" = true ]; then
    echo "Fresh mode — stopping existing container $CONTAINER_NAME..."
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm   "$CONTAINER_NAME" 2>/dev/null || true
fi

# ── Attach if already running ─────────────────────────────────────────────────
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Container $CONTAINER_NAME already running — attaching new shell."
    echo "  (use './docker_run.sh fresh' to restart from the latest image)"
    docker exec -it $CONTAINER_NAME bash
    exit 0
fi

echo "Starting container: $CONTAINER_NAME  (platform: $PLATFORM)"

docker run -it --rm --pull never \
    --name $CONTAINER_NAME \
    $GPU_FLAGS \
    --user $(id -u):$(id -g) \
    --volume="${PWD%/*}:/home/$DOCKER_USER" \
    --volume="$BASH_HISTORY_FILE:/home/$DOCKER_USER/.bash_history" \
    --volume="$BASH_RC_FILE:/home/$DOCKER_USER/.bashrc" \
    --volume="/tmp/.X11-unix:/tmp/.X11-unix:rw" \
    --volume="$XAUTH:$XAUTH" \
    --volume="${HOME}/.gz:/home/$DOCKER_USER/.gz" \
    $PLATFORM_VOLUMES \
    --env="XAUTHORITY=$XAUTH" \
    --env="DISPLAY" \
    --env="QT_X11_NO_MITSHM=1" \
    "${PLATFORM_ENV[@]}" \
    --env="GZ_SIM_RESOURCE_PATH=/home/$DOCKER_USER/openrobotics" \
    --workdir="/home/$DOCKER_USER" \
    $device_options \
    --net=host \
    --privileged \
    sandeepdutta/jeeves_humble_final:latest

echo "Docker container exited."
