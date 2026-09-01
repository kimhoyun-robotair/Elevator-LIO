#!/usr/bin/env bash
set -e

source "/opt/ros/${ROS_DISTRO:-humble}/setup.bash"
source /ros2_ws/install/setup.bash

mkdir -p "${HOME:-/tmp/lio-home}"

exec "$@"
