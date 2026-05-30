#!/usr/bin/env bash

BASH_HISTORY_FILE=${PWD%/*}/.bash_history
BASH_RC_FILE=${PWD%/*}/docker/.bashrc

CONTAINER_NAME="jeeves_simulation_humble"
DOCKER_USER="admin"

docker_count=$(docker ps -a | grep CONTAINER_NAME | wc -l)
((docker_count=docker_count+1))

XAUTH=/tmp/.docker.xauth_$docker_count
sleep 0.1
touch $XAUTH
xauth nlist $DISPLAY | sed -e 's/^..../ffff/' | xauth -f $XAUTH nmerge -

# Create a string with all --device options for each device in /dev/
device_options=""
for device in /dev/*; do
    if [ -e "$device" ]; then
        device_options+="--device=$device "
    fi
done

if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Container $CONTAINER_NAME already running — attaching new shell."
    docker exec -it $CONTAINER_NAME bash
    exit 0
fi

docker run -it --rm \
    --name $CONTAINER_NAME \
    --gpus all \
    --env NVIDIA_DRIVER_CAPABILITIES=all \
    --user $(id -u):$(id -g) \
    --volume="${PWD%/*}:/home/$DOCKER_USER" \
    --volume="$BASH_HISTORY_FILE:/home/$DOCKER_USER/.bash_history" \
    --volume="$BASH_RC_FILE:/home/$DOCKER_USER/.bashrc" \
    --volume="/tmp/.X11-unix:/tmp/.X11-unix:rw" \
    --volume="$XAUTH:$XAUTH" \
    --volume="${HOME}/.ignition:/home/$DOCKER_USER/.ignition" \
    --env="XAUTHORITY=$XAUTH" \
    --env="DISPLAY" \
    --env="QT_X11_NO_MITSHM=1" \
    --workdir="/home/$DOCKER_USER" \
    $device_options \
    --net=host \
    --privileged \
    sandeepdutta/jeeves_humble_final:latest

echo "Docker container exited."