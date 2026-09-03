#!/usr/bin/env python3
"""Generate a Livox MID-360 configuration for the directly connected NIC."""

import argparse
import ipaddress
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path


def ipv4(value: str, label: str) -> ipaddress.IPv4Address:
    try:
        address = ipaddress.ip_address(value)
    except ValueError as exc:
        raise RuntimeError(f"{label} is not a valid IPv4 address: {value}") from exc
    if not isinstance(address, ipaddress.IPv4Address):
        raise RuntimeError(f"{label} must be an IPv4 address: {value}")
    if address.is_loopback or address.is_multicast or address.is_unspecified:
        raise RuntimeError(f"{label} is not a usable unicast address: {value}")
    return address


def host_addresses():
    try:
        result = subprocess.run(
            ["ip", "-o", "-4", "addr", "show", "up", "scope", "global"],
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        raise RuntimeError("could not inspect host-network IPv4 addresses with iproute2") from exc

    addresses = []
    for line in result.stdout.splitlines():
        found = re.search(r"^\d+:\s+([^\s]+).*?\sinet\s+(\d+\.\d+\.\d+\.\d+/\d+)", line)
        if not found:
            continue
        interface_name, cidr = found.groups()
        interface = ipaddress.ip_interface(cidr)
        addresses.append((interface_name, interface.ip, interface.network))
    return addresses


def choose_host_ip(lidar_ip: ipaddress.IPv4Address, requested: str):
    if requested:
        requested_ip = ipv4(requested, "LIVOX_HOST_IP")
        if requested_ip == lidar_ip:
            raise RuntimeError("LIVOX_HOST_IP and LIVOX_LIDAR_IP must be different")
        assigned = [item for item in host_addresses() if item[1] == requested_ip]
        if not assigned:
            raise RuntimeError(
                f"LIVOX_HOST_IP {requested_ip} is not assigned to an active host NIC"
            )
        name, address, network = assigned[0]
        if lidar_ip not in network:
            raise RuntimeError(
                f"LIVOX_HOST_IP {address} on {name} ({network}) is not on the "
                f"MID-360 {lidar_ip} subnet"
            )
        return address, f"explicit:{name}:{network}"

    matches = [item for item in host_addresses() if lidar_ip in item[2]]
    if not matches:
        raise RuntimeError(
            f"no active host NIC is on the same subnet as MID-360 {lidar_ip}; "
            "configure the Ethernet NIC (normally 192.168.1.50/24) or set "
            "LIVOX_HOST_IP explicitly"
        )
    if len(matches) > 1:
        choices = ", ".join(f"{name}={address} ({network})" for name, address, network in matches)
        raise RuntimeError(
            f"multiple NIC addresses can reach MID-360 {lidar_ip}: {choices}; "
            "set LIVOX_HOST_IP explicitly"
        )
    name, address, network = matches[0]
    return address, f"auto:{name}:{network}"


def build_config(host_ip: str, lidar_ip: str):
    return {
        "lidar_summary_info": {"lidar_type": 8},
        "MID360": {
            "lidar_net_info": {
                "cmd_data_port": 56100,
                "push_msg_port": 56200,
                "point_data_port": 56300,
                "imu_data_port": 56400,
                "log_data_port": 56500,
            },
            "host_net_info": {
                "cmd_data_ip": host_ip,
                "cmd_data_port": 56101,
                "push_msg_ip": host_ip,
                "push_msg_port": 56201,
                "point_data_ip": host_ip,
                "point_data_port": 56301,
                "imu_data_ip": host_ip,
                "imu_data_port": 56401,
                "log_data_ip": "",
                "log_data_port": 56501,
            },
        },
        "lidar_configs": [
            {
                "ip": lidar_ip,
                "pcl_data_type": 1,
                "pattern_mode": 0,
                "extrinsic_parameter": {
                    "roll": 0.0,
                    "pitch": 0.0,
                    "yaw": 0.0,
                    "x": 0.0,
                    "y": 0.0,
                    "z": 0.0,
                },
            }
        ],
    }


def write_atomic(path: Path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=path.parent, delete=False
    ) as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")
        temporary = Path(handle.name)
    temporary.replace(path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--lidar-ip", default=os.environ.get("LIVOX_LIDAR_IP", "")
    )
    parser.add_argument("--host-ip", default=os.environ.get("LIVOX_HOST_IP", ""))
    parser.add_argument(
        "--output",
        default=os.environ.get(
            "LIVOX_CONFIG_PATH", "/tmp/lio-home/MID360_config.json"
        ),
    )
    args = parser.parse_args()

    try:
        lidar_ip = ipv4(args.lidar_ip, "LIVOX_LIDAR_IP")
        host_ip, source = choose_host_ip(lidar_ip, args.host_ip)
        write_atomic(Path(args.output), build_config(str(host_ip), str(lidar_ip)))
    except RuntimeError as exc:
        print(f"[ERROR] Livox auto-configuration failed: {exc}", file=sys.stderr)
        return 2

    print(
        f"[INFO] MID-360 direct mode: host={host_ip} ({source}), "
        f"lidar={lidar_ip}, config={args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
