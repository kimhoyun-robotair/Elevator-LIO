#!/usr/bin/env python3
"""Gemini 336L launch adapter for the installed OrbbecSDK ROS2 v2.9.3.

Firmware 1.2.81 rejects depth AE priority (property 2052), including when
loading the Default preset. Preserve the device preset and omit this write;
keep upstream stream profiles and all other launch parameters intact.
"""

import importlib.util
from pathlib import Path

from ament_index_python.packages import get_package_share_directory


def generate_launch_description():
    path = Path(get_package_share_directory("orbbec_camera")) / "launch" / "gemini_330_series.launch.py"
    spec = importlib.util.spec_from_file_location("lio_orbbec_336l_upstream", path)
    upstream = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(upstream)
    load_parameters = upstream.load_parameters

    def compatible_parameters(context, args):
        parameters = load_parameters(context, args)
        parameters.pop("enable_depth_auto_exposure_priority", None)
        parameters["device_preset"] = ""
        return parameters

    upstream.load_parameters = compatible_parameters
    return upstream.generate_launch_description()
