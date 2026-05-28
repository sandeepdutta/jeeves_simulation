#!/bin/bash

# Source ROS installation
source /opt/ros/humble/setup.bash

# Directory path to the ROS2 Workspace
ROS_WS="ros2_workspace"

# Source the workspace if it exists
if [ -f "/home/$USER/$ROS_WS/install/setup.bash" ]; then
    source "/home/$USER/$ROS_WS/install/setup.bash"
fi

# Execute the command passed to the script
exec "$@"
