#!/usr/bin/env python3
"""Two independent 3DM-GX5-AHRS drivers; no fusion or mounting transforms."""

from pathlib import Path

import yaml
from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import OpaqueFunction
from launch_ros.actions import Node


def launch_drivers(context):
    driver_share = Path(get_package_share_directory("microstrain_inertial_driver"))
    with (driver_share / "microstrain_inertial_driver_common/config/params.yml").open() as source:
        defaults = yaml.safe_load(source)
    config = str(Path(get_package_share_directory("lio")) / "yaml/sensors/gx5_ahrs.yaml")
    return [
        Node(
            package="microstrain_inertial_driver",
            # The official plain node configures and activates itself on startup.
            executable="microstrain_inertial_driver_node",
            namespace=f"gx5_{index}",
            name="microstrain_inertial_driver",
            output="screen",
            parameters=[defaults, config, {
                "port": f"/dev/gx5_{index}",
                "frame_id": f"gx5_{index}_link",
            }],
        )
        for index in (1, 2)
    ]


def generate_launch_description():
    return LaunchDescription([OpaqueFunction(function=launch_drivers)])
