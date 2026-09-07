#!/usr/bin/env python3

from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, IncludeLaunchDescription
from launch.conditions import IfCondition
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import (
    EnvironmentVariable,
    LaunchConfiguration,
    PathJoinSubstitution,
)
from launch_ros.actions import Node
from launch_ros.substitutions import FindPackageShare


def generate_launch_description():
    config_path = LaunchConfiguration("config_path")
    use_rviz = LaunchConfiguration("use_rviz")
    use_livox_driver = LaunchConfiguration("use_livox_driver")
    livox_config = LaunchConfiguration("livox_config")
    frame_id = LaunchConfiguration("frame_id")
    use_orbbec_camera = LaunchConfiguration("use_orbbec_camera")
    camera_name = LaunchConfiguration("camera_name")
    camera_serial_number = LaunchConfiguration("camera_serial_number")
    camera_usb_port = LaunchConfiguration("camera_usb_port")
    camera_enable_color = LaunchConfiguration("camera_enable_color")
    camera_enable_depth = LaunchConfiguration("camera_enable_depth")
    camera_enable_point_cloud = LaunchConfiguration("camera_enable_point_cloud")
    camera_enable_imu = LaunchConfiguration("camera_enable_imu")

    default_livox_config = EnvironmentVariable(
        "LIVOX_CONFIG_FILE",
        default_value="/tmp/lio-home/MID360_config.json",
    )
    orbbec_launch = PathJoinSubstitution(
        [
            FindPackageShare("lio"),
            "launch",
            "gemini_336l_multi.launch.py",
        ]
    )

    return LaunchDescription(
        [
            DeclareLaunchArgument("config_path", default_value="root_config.yaml"),
            DeclareLaunchArgument("use_rviz", default_value="true"),
            DeclareLaunchArgument(
                "use_livox_driver",
                default_value=EnvironmentVariable(
                    "USE_LIVOX_DRIVER", default_value="true"
                ),
            ),
            DeclareLaunchArgument("livox_config", default_value=default_livox_config),
            DeclareLaunchArgument("frame_id", default_value="livox_frame"),
            DeclareLaunchArgument(
                "use_orbbec_camera",
                default_value=EnvironmentVariable(
                    "USE_ORBBEC_CAMERA", default_value="false"
                ),
            ),
            DeclareLaunchArgument("camera_name", default_value="camera"),
            DeclareLaunchArgument(
                "camera_serial_number",
                default_value=EnvironmentVariable(
                    "ORBBEC_SERIAL_NUMBER", default_value=""
                ),
            ),
            DeclareLaunchArgument(
                "camera_usb_port",
                default_value=EnvironmentVariable("ORBBEC_USB_PORT", default_value=""),
            ),
            DeclareLaunchArgument("camera_enable_color", default_value="true"),
            DeclareLaunchArgument("camera_enable_depth", default_value="true"),
            DeclareLaunchArgument("camera_enable_point_cloud", default_value="true"),
            DeclareLaunchArgument("camera_enable_imu", default_value="true"),
            DeclareLaunchArgument(
                "use_gx5_driver", default_value=EnvironmentVariable(
                    "USE_GX5_DRIVER", default_value="false"
                ),
            ),
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
                    }
                ],
            ),
            IncludeLaunchDescription(
                PythonLaunchDescriptionSource(orbbec_launch),
                condition=IfCondition(use_orbbec_camera),
                launch_arguments={
                    "camera_name": camera_name,
                    "camera_serial_number": camera_serial_number,
                    "camera_usb_port": camera_usb_port,
                    "camera_enable_color": camera_enable_color,
                    "camera_enable_depth": camera_enable_depth,
                    "camera_enable_point_cloud": camera_enable_point_cloud,
                    "camera_enable_imu": camera_enable_imu,
                }.items(),
            ),
            IncludeLaunchDescription(
                PythonLaunchDescriptionSource(PathJoinSubstitution([
                    FindPackageShare("lio"), "launch", "gx5_dual.launch.py",
                ])),
                condition=IfCondition(LaunchConfiguration("use_gx5_driver")),
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
