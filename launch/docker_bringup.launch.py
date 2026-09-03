#!/usr/bin/env python3

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.conditions import IfCondition
from launch.substitutions import LaunchConfiguration, PathJoinSubstitution
from launch_ros.actions import Node
from launch_ros.substitutions import FindPackageShare


def generate_launch_description():
    config_path = LaunchConfiguration("config_path")
    use_rviz = LaunchConfiguration("use_rviz")
    use_livox_driver = LaunchConfiguration("use_livox_driver")
    livox_config = LaunchConfiguration("livox_config")
    frame_id = LaunchConfiguration("frame_id")

    default_livox_config = (
        get_package_share_directory("livox_ros_driver2") + "/config/MID360_config.json"
    )

    return LaunchDescription(
        [
            DeclareLaunchArgument("config_path", default_value="root_config.yaml"),
            DeclareLaunchArgument("use_rviz", default_value="true"),
            DeclareLaunchArgument("use_livox_driver", default_value="false"),
            DeclareLaunchArgument("livox_config", default_value=default_livox_config),
            DeclareLaunchArgument("frame_id", default_value="livox_frame"),
            Node(
                package="livox_ros_driver2",
                executable="livox_ros_driver2_node",
                name="livox_lidar_publisher",
                output="screen",
                condition=IfCondition(use_livox_driver),
                parameters=[
                    {
                        "xfer_format": 1,
                        "multi_topic": 0,
                        "data_src": 0,
                        "publish_freq": 10.0,
                        "output_data_type": 0,
                        "frame_id": frame_id,
                        "user_config_path": livox_config,
                        "cmdline_input_bd_code": "livox0000000001",
                    }
                ],
            ),
            Node(
                package="lio",
                executable="lio",
                name="lio_node",
                output="screen",
                parameters=[{"config_path": config_path}],
            ),
            Node(
                package="rviz2",
                executable="rviz2",
                name="rviz2",
                output="screen",
                arguments=[
                    "-d",
                    PathJoinSubstitution(
                        [FindPackageShare("lio"), "rviz", "LIO_ros2.rviz"]
                    ),
                ],
                condition=IfCondition(use_rviz),
            ),
        ]
    )
