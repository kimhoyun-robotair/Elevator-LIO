#!/usr/bin/env bash
set -Eeuo pipefail

# ROS/ament setup scripts intentionally probe optional variables without
# nounset-safe expansions. Disable nounset only while sourcing them, then
# restore strict mode for the rest of this entrypoint.
set +u
source "/opt/ros/${ROS_DISTRO:-humble}/setup.bash"
source /ros2_ws/install/setup.bash
set -u

mkdir -p "${HOME:-/tmp/lio-home}"

is_true() {
    case "${1,,}" in
        1|true|yes|on) return 0 ;;
        *) return 1 ;;
    esac
}

if is_true "${USE_LIVOX_DRIVER:-true}"; then
    if [[ -n "${LIVOX_CONFIG_FILE:-}" ]]; then
        if [[ ! -r "${LIVOX_CONFIG_FILE}" ]]; then
            echo "[ERROR] LIVOX_CONFIG_FILE is not readable: ${LIVOX_CONFIG_FILE}" >&2
            exit 2
        fi
        echo "[INFO] MID-360 direct mode uses ${LIVOX_CONFIG_FILE}"
    else
        if [[ -z "${LIVOX_LIDAR_IP:-}" ]]; then
            echo "[ERROR] Direct MID-360 mode needs LIVOX_LIDAR_IP." >&2
            echo "Set the device IP (for example 192.168.1.112) or provide LIVOX_CONFIG_FILE." >&2
            exit 2
        fi
        export LIVOX_CONFIG_FILE="${LIVOX_CONFIG_PATH:-/tmp/lio-home/MID360_config.json}"
        elevator-lio-configure-livox \
            --lidar-ip "${LIVOX_LIDAR_IP}" \
            --host-ip "${LIVOX_HOST_IP:-}" \
            --output "${LIVOX_CONFIG_FILE}"
    fi
fi

exec "$@"
