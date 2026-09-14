#!/usr/bin/env python3
"""One to three Gemini 336L cameras, with stable serial-to-namespace mapping."""

import re

from launch import LaunchDescription
from launch.actions import (
    DeclareLaunchArgument, GroupAction, IncludeLaunchDescription, OpaqueFunction,
    TimerAction,
)
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import EnvironmentVariable, LaunchConfiguration, PathJoinSubstitution
from launch_ros.substitutions import FindPackageShare


def launch_cameras(context):
    value = lambda name: LaunchConfiguration(name).perform(context)
    count_text = value("camera_count")
    if count_text not in ("1", "2", "3"):
        raise RuntimeError("ORBBEC_CAMERA_COUNT / camera_count must be 1, 2, or 3")
    count = int(count_text)
    cameras = []
    for index in range(1, count + 1):
        suffix = "" if index == 1 else f"_{index}"
        name = value(f"camera_name{suffix}").strip()
        serial = value(f"camera_serial_number{suffix}").strip()
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
            raise RuntimeError(f"Invalid camera namespace: {name!r}")
        if count > 1 and not serial:
            raise RuntimeError(
                "Multiple cameras require distinct serial numbers: set "
                "ORBBEC_SERIAL_NUMBER, ORBBEC_SERIAL_NUMBER_2, ORBBEC_SERIAL_NUMBER_3 "
                "in docker/sensors.env for the requested camera count"
            )
        cameras.append((name, serial))
    if len({name for name, _ in cameras}) != count:
        raise RuntimeError("Camera namespaces must be distinct")
    if count > 1 and len({serial.casefold() for _, serial in cameras}) != count:
        raise RuntimeError("Camera serial numbers must be distinct")

    upstream = PathJoinSubstitution([
        FindPackageShare("lio"), "launch", "gemini_336l_compat.launch.py",
    ])
    actions = []
    for index, (name, serial) in enumerate(cameras):
        arguments = {
            "camera_name": name,
            "serial_number": serial,
            "usb_port": value("camera_usb_port") if count == 1 else "",
            "device_num": str(count),
            "sync_mode": "standalone",
            "uvc_backend": "libuvc",
            "enable_color": value("camera_enable_color"),
            "enable_depth": value("camera_enable_depth"),
            "enable_point_cloud": value("camera_enable_point_cloud"),
            "enable_accel": value("camera_enable_imu"),
            "enable_gyro": value("camera_enable_imu"),
            "enable_sync_output_accel_gyro": value("camera_enable_imu"),
            "log_file_name": f"{name}.log",
        }
        # Separate launch scopes prevent the upstream arguments and namespace
        # from leaking to the next camera. Follow Orbbec's 2 s startup spacing.
        actions.append(TimerAction(period=2.0 * index, actions=[GroupAction([
            IncludeLaunchDescription(
                PythonLaunchDescriptionSource(upstream),
                launch_arguments=arguments.items(),
            ),
        ])]))
    return actions


def generate_launch_description():
    arguments = [DeclareLaunchArgument(
        "camera_count", default_value=EnvironmentVariable("ORBBEC_CAMERA_COUNT", default_value="1"),
    )]
    for index in range(1, 4):
        suffix = "" if index == 1 else f"_{index}"
        arguments.extend([
            DeclareLaunchArgument(
                f"camera_name{suffix}", default_value=EnvironmentVariable(
                    f"ORBBEC_CAMERA_NAME{suffix}", default_value=f"camera{suffix}",
                ),
            ),
            DeclareLaunchArgument(
                f"camera_serial_number{suffix}", default_value=EnvironmentVariable(
                    f"ORBBEC_SERIAL_NUMBER{suffix}", default_value="",
                ),
            ),
        ])
    arguments.append(DeclareLaunchArgument(
        "camera_usb_port", default_value=EnvironmentVariable("ORBBEC_USB_PORT", default_value=""),
    ))
    for stream in ("color", "depth", "point_cloud", "imu"):
        arguments.append(DeclareLaunchArgument(
            f"camera_enable_{stream}", default_value=EnvironmentVariable(
                f"ORBBEC_ENABLE_{stream.upper()}", default_value="true",
            ),
        ))
    return LaunchDescription(arguments + [OpaqueFunction(function=launch_cameras)])
