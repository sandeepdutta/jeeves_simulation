#!/usr/bin/bash

# Set Contianer Name
CONTAINER_NAME_BASE="jeeves_simulation_humble_base"

echo "Building ROS2-Humble Container"
docker build --rm -t $CONTAINER_NAME_BASE:latest -f Dockerfile.base ./
CONTAINER_NAME_URDF="jeeves_humble_urdf"
docker build --rm -t $CONTAINER_NAME_URDF:latest \
        -f ../ros_ws/src/jeeves_production_description/docker/jeeves/Dockerfile.jeeves_sim \
        --build-arg BASE_IMAGE=$CONTAINER_NAME_BASE \
        ../ros_ws/src
docker build --rm -t jeeves_humble_final:latest -f Dockerfile.final \
        --build-arg BASE_IMAGE=$CONTAINER_NAME_URDF ./
echo "Docker Build Completed"