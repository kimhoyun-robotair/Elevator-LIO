#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
IMAGE="${LIO_IMAGE:-elevator-lio:humble}"
BUILD_JOBS="${BUILD_JOBS:-4}"

usage() {
    cat <<'EOF'
Usage:
  ./docker/run.sh build                 Build for the current host architecture
  ./docker/run.sh setup-camera          Install the Gemini 336L host udev rule
  ./docker/run.sh                       Launch sensors, Elevator-LIO, and RViz2
  ./docker/run.sh exec [command...]     Run inside the active elevator-lio container
  ./docker/run.sh shell                 Open a temporary development container
  ./docker/run.sh <command> [args...]   Run any command in a temporary container

Environment:
  LIO_SENSOR_ENV_FILE=/path     Load settings (default: docker/sensors.env if present)
  USE_RVIZ=false                Disable RViz2
  USE_LIVOX_DRIVER=false        Disable direct MID-360 driver (default: true)
  LIVOX_LIDAR_IP=<address>       MID-360 address (required without custom JSON)
  LIVOX_HOST_IP=<address>        LiDAR NIC address (default: auto-detect)
  LIVOX_CONFIG_FILE=/path       Mount a complete custom MID-360 JSON instead
  USE_ORBBEC_CAMERA=auto        Auto-start a connected Gemini 336L
  ORBBEC_CAMERA_NAME=camera     Camera namespace
  ORBBEC_CAMERA_COUNT=1         Number of cameras (1-3); multi-camera needs all serials
  ORBBEC_SERIAL_NUMBER=...      Select one camera by serial number
  ORBBEC_SERIAL_NUMBER_2=...    Second Gemini 336L serial (namespace: camera_2)
  ORBBEC_SERIAL_NUMBER_3=...    Third Gemini 336L serial (namespace: camera_3)
  ORBBEC_USB_PORT=...           Select one camera by USB topology path
  ORBBEC_ENABLE_IMU=false       Disable the camera's synchronized IMU topic
  ORBBEC_ENABLE_POINT_CLOUD=false  Disable the camera point cloud
  ORBBEC_ENABLE_COLOR=false     Disable the camera color stream
  ORBBEC_ENABLE_DEPTH=false     Disable the camera depth stream
  USE_GX5_DRIVER=auto           Start two GX5-AHRS units when their ports are configured
  GX5_PORT_1=/dev/serial/by-id/...  First GX5 host port (namespace: gx5_1)
  GX5_PORT_2=/dev/serial/by-id/...  Second GX5 host port (namespace: gx5_2)
  LIO_CONFIG=root_config.yaml   Select a root YAML under this repository's yaml/
  LIO_MOUNT_CONFIG=true         Mount host yaml/ for a custom launch command
  LIO_DATA_DIR=/path            Host directory mounted at /data
  LIO_LOG_DIR=/path             Persist ROS state/logs (default: docker/log)
  ROS_DOMAIN_ID=73              DDS domain shared with host ROS 2 processes
  ROS_LOCALHOST_ONLY=0          Allow non-loopback ROS 2 discovery
  LIO_NVIDIA_GPU=0              Disable automatic NVIDIA GPU passthrough
EOF
}

normalize_boolean() {
    case "${1,,}" in
        1|true|yes|on) echo true ;;
        0|false|no|off) echo false ;;
        *)
            echo "Expected a boolean, got: $1" >&2
            return 2
            ;;
    esac
}

gemini_336l_present() {
    local vendor_file product_file
    for vendor_file in /sys/bus/usb/devices/*/idVendor; do
        [[ -r "${vendor_file}" ]] || continue
        product_file="${vendor_file%/idVendor}/idProduct"
        [[ -r "${product_file}" ]] || continue
        if [[ "$(<"${vendor_file}")" == "2bc5" ]] \
            && [[ "$(<"${product_file}")" == "0807" ]]; then
            return 0
        fi
    done
    return 1
}

check_gemini_permissions() {
    local vendor_file product_file device_dir bus_raw dev_raw bus dev device_node
    for vendor_file in /sys/bus/usb/devices/*/idVendor; do
        [[ -r "${vendor_file}" ]] || continue
        device_dir="${vendor_file%/idVendor}"
        product_file="${device_dir}/idProduct"
        [[ -r "${product_file}" ]] || continue
        if [[ "$(<"${vendor_file}")" != "2bc5" ]] \
            || [[ "$(<"${product_file}")" != "0807" ]]; then
            continue
        fi
        [[ -r "${device_dir}/busnum" && -r "${device_dir}/devnum" ]] || continue
        bus_raw="$(<"${device_dir}/busnum")"
        dev_raw="$(<"${device_dir}/devnum")"
        printf -v bus '%03d' "$((10#${bus_raw}))"
        printf -v dev '%03d' "$((10#${dev_raw}))"
        device_node="/dev/bus/usb/${bus}/${dev}"
        if [[ ! -r "${device_node}" || ! -w "${device_node}" ]]; then
            echo "No read/write permission for Gemini 336L at ${device_node}." >&2
            echo "Run './docker/run.sh setup-camera', reconnect the camera, and retry." >&2
            return 2
        fi
    done
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ "${1:-}" == "setup-camera" ]]; then
    exec "${SCRIPT_DIR}/setup_orbbec_udev.sh"
fi

if [[ "${1:-}" == "exec" ]]; then
    shift
    # Inherit the domain and discovery settings from the running container.
    exec_args=()
    if [[ -t 0 && -t 1 ]]; then
        exec_args+=(--interactive --tty)
    fi
    if [[ $# -eq 0 ]]; then
        set -- bash
    fi
    exec docker exec "${exec_args[@]}" \
        "${LIO_CONTAINER_NAME:-elevator-lio}" \
        bash -c \
        'source "/opt/ros/${ROS_DISTRO:-humble}/setup.bash"; source /ros2_ws/install/setup.bash; exec "$@"' \
        elevator-lio-exec "$@"
fi

if [[ "${1:-}" == "build" ]]; then
    exec docker build \
        --build-arg "BUILD_JOBS=${BUILD_JOBS}" \
        --tag "${IMAGE}" \
        "${REPO_ROOT}"
fi

# Local sensor identities stay outside Git and the image. The example uses
# default assignments so an environment variable can still override a setting.
sensor_env="${LIO_SENSOR_ENV_FILE:-${SCRIPT_DIR}/sensors.env}"
if [[ -f "${sensor_env}" ]]; then
    set -a
    source "${sensor_env}"
    set +a
elif [[ -n "${LIO_SENSOR_ENV_FILE:-}" ]]; then
    echo "LIO_SENSOR_ENV_FILE does not exist: ${sensor_env}" >&2
    exit 2
fi

if [[ $# -eq 0 ]]; then
    early_livox_enabled="$(normalize_boolean "${USE_LIVOX_DRIVER:-true}")"
    if [[ "${early_livox_enabled}" == "true" \
        && -z "${LIVOX_CONFIG_FILE:-}" \
        && -z "${LIVOX_LIDAR_IP:-}" ]]; then
        echo "Direct MID-360 mode requires LIVOX_LIDAR_IP or LIVOX_CONFIG_FILE." >&2
        echo "Example: LIVOX_LIDAR_IP=192.168.1.112 ./docker/run.sh" >&2
        exit 2
    fi
    if [[ -n "${LIVOX_CONFIG_FILE:-}" && ! -f "${LIVOX_CONFIG_FILE}" ]]; then
        echo "LIVOX_CONFIG_FILE does not exist: ${LIVOX_CONFIG_FILE}" >&2
        exit 2
    fi
fi

if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
    echo "Image ${IMAGE} does not exist; building it first." >&2
    docker build \
        --build-arg "BUILD_JOBS=${BUILD_JOBS}" \
        --tag "${IMAGE}" \
        "${REPO_ROOT}"
fi

default_launch=false
if [[ $# -eq 0 ]]; then
    default_launch=true
fi

if [[ -n "${LIO_CONTAINER_NAME:-}" ]]; then
    CONTAINER_NAME="${LIO_CONTAINER_NAME}"
elif [[ "${default_launch}" == "true" ]]; then
    CONTAINER_NAME="elevator-lio"
else
    # Allow helper shells, rosbag playback, and topic inspection alongside the
    # primary Elevator-LIO container without a name collision.
    CONTAINER_NAME="elevator-lio-${$}"
fi

if [[ -n "${USE_RVIZ:-}" ]]; then
    GUI_ENABLED="$(normalize_boolean "${USE_RVIZ}")"
else
    GUI_ENABLED="${default_launch}"
fi

if [[ -n "${USE_LIVOX_DRIVER:-}" ]]; then
    LIVOX_ENABLED="$(normalize_boolean "${USE_LIVOX_DRIVER}")"
else
    LIVOX_ENABLED="${default_launch}"
fi

ORBBEC_REQUEST="${USE_ORBBEC_CAMERA:-auto}"
LIVOX_LAUNCH_CONFIG=""
if [[ "${ORBBEC_REQUEST,,}" != "auto" ]]; then
    ORBBEC_ENABLED="$(normalize_boolean "${ORBBEC_REQUEST}")"
elif [[ "${default_launch}" == "true" ]] && gemini_336l_present; then
    ORBBEC_ENABLED=true
else
    ORBBEC_ENABLED=false
fi

GX5_REQUEST="${USE_GX5_DRIVER:-auto}"
if [[ "${GX5_REQUEST,,}" != "auto" ]]; then
    GX5_ENABLED="$(normalize_boolean "${GX5_REQUEST}")"
elif [[ "${default_launch}" == "true" \
    && ( -n "${GX5_PORT_1:-}" || -n "${GX5_PORT_2:-}" ) ]]; then
    GX5_ENABLED=true
else
    GX5_ENABLED=false
fi

# Keep wrapper resources aligned when a caller supplies launch arguments to a
# custom command instead of using the environment variables above.
if [[ "${default_launch}" == "false" ]]; then
    for argument in "$@"; do
        case "${argument}" in
            use_rviz:=*)
                GUI_ENABLED="$(normalize_boolean "${argument#use_rviz:=}")"
                ;;
            use_livox_driver:=*)
                LIVOX_ENABLED="$(normalize_boolean "${argument#use_livox_driver:=}")"
                ;;
            use_orbbec_camera:=*)
                ORBBEC_ENABLED="$(normalize_boolean "${argument#use_orbbec_camera:=}")"
                ;;
            use_gx5_driver:=*)
                GX5_ENABLED="$(normalize_boolean "${argument#use_gx5_driver:=}")"
                ;;
            livox_config:=*)
                LIVOX_LAUNCH_CONFIG="${argument#livox_config:=}"
                ;;
        esac
    done
fi

HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
HOST_USER="$(id -un)"
DATA_DIR="${LIO_DATA_DIR:-${REPO_ROOT}/docker/data}"
LOG_DIR="${LIO_LOG_DIR:-${REPO_ROOT}/docker/log}"
PCD_DIR="${LIO_PCD_DIR:-${REPO_ROOT}/PCD}"
TEMP_DIR="${LIO_TEMP_DIR:-${REPO_ROOT}/temp}"

mkdir -p "${DATA_DIR}" "${LOG_DIR}" "${PCD_DIR}/Temp" "${TEMP_DIR}"

docker_args=(
    --rm
    --init
    --name "${CONTAINER_NAME}"
    --network host
    --ipc host
    --user "${HOST_UID}:${HOST_GID}"
    --env "HOME=/tmp/lio-home"
    --env "USER=${HOST_USER}"
    --env "LOGNAME=${HOST_USER}"
    --env "ROS_DOMAIN_ID=${ROS_DOMAIN_ID:-73}"
    --env "ROS_LOCALHOST_ONLY=${ROS_LOCALHOST_ONLY:-0}"
    --env "USE_LIVOX_DRIVER=${LIVOX_ENABLED}"
    --env "LIVOX_LIDAR_IP=${LIVOX_LIDAR_IP:-}"
    --env "LIVOX_HOST_IP=${LIVOX_HOST_IP:-}"
    --env "USE_ORBBEC_CAMERA=${ORBBEC_ENABLED}"
    --env "ORBBEC_SERIAL_NUMBER=${ORBBEC_SERIAL_NUMBER:-}"
    --env "ORBBEC_USB_PORT=${ORBBEC_USB_PORT:-}"
    --env "ORBBEC_CAMERA_COUNT=${ORBBEC_CAMERA_COUNT:-1}"
    --env "ORBBEC_SERIAL_NUMBER_2=${ORBBEC_SERIAL_NUMBER_2:-}"
    --env "ORBBEC_SERIAL_NUMBER_3=${ORBBEC_SERIAL_NUMBER_3:-}"
    --env "ORBBEC_CAMERA_NAME_2=${ORBBEC_CAMERA_NAME_2:-camera_2}"
    --env "ORBBEC_CAMERA_NAME_3=${ORBBEC_CAMERA_NAME_3:-camera_3}"
    --env "USE_GX5_DRIVER=${GX5_ENABLED}"
    --env "QT_X11_NO_MITSHM=1"
    --env "LIBGL_ALWAYS_SOFTWARE=${LIBGL_ALWAYS_SOFTWARE:-0}"
    --volume "${PCD_DIR}:/ros2_ws/src/elevator_lio/PCD:rw"
    --volume "${TEMP_DIR}:/ros2_ws/src/elevator_lio/temp:rw"
    --volume "${DATA_DIR}:/data:rw"
    --volume "${LOG_DIR}:/tmp/lio-home/.ros:rw"
    --workdir /ros2_ws
)

if [[ -t 0 && -t 1 ]]; then
    docker_args+=(--interactive --tty)
fi

if [[ -n "${LIO_MOUNT_CONFIG:-}" ]]; then
    MOUNT_CONFIG="$(normalize_boolean "${LIO_MOUNT_CONFIG}")"
else
    MOUNT_CONFIG="${default_launch}"
fi
if [[ "${MOUNT_CONFIG}" == "true" ]]; then
    docker_args+=(
        --volume "${REPO_ROOT}/yaml:/ros2_ws/install/share/lio/yaml:ro"
    )
fi

cleanup_xhost=false
if [[ "${GUI_ENABLED}" == "true" ]]; then
    if [[ -z "${DISPLAY:-}" ]]; then
        echo "DISPLAY is not set. Set USE_RVIZ=false for headless use." >&2
        exit 2
    fi
    display_number="${DISPLAY##*:}"
    display_number="${display_number%%.*}"
    if [[ ! -S /tmp/.X11-unix/X"${display_number}" ]]; then
        echo "The X11 socket for DISPLAY=${DISPLAY} is not available." >&2
        exit 2
    fi
    if command -v xhost >/dev/null 2>&1; then
        xhost "+SI:localuser:${HOST_USER}" >/dev/null
        cleanup_xhost=true
    else
        echo "xhost is required for GUI use (apt install x11-xserver-utils)." >&2
        exit 2
    fi
    docker_args+=(
        --env "DISPLAY=${DISPLAY}"
        --volume /tmp/.X11-unix:/tmp/.X11-unix:rw
    )
fi

cleanup() {
    if [[ "${cleanup_xhost}" == "true" ]]; then
        xhost "-SI:localuser:${HOST_USER}" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT INT TERM

# Mesa/Intel/AMD rendering when a DRM device is present.
if [[ -d /dev/dri ]]; then
    docker_args+=(--device /dev/dri:/dev/dri)
    for host_group in video render; do
        group_id="$(getent group "${host_group}" | cut -d: -f3 || true)"
        if [[ -n "${group_id}" ]]; then
            docker_args+=(--group-add "${group_id}")
        fi
    done
fi

# DGX Spark normally has NVIDIA Container Toolkit. The algorithm itself is
# CPU-only; this passthrough primarily accelerates RViz/OpenGL.
if [[ "${GUI_ENABLED}" == "true" ]] \
    && [[ "${LIO_NVIDIA_GPU:-auto}" != "0" ]] \
    && command -v nvidia-smi >/dev/null 2>&1 \
    && nvidia-smi >/dev/null 2>&1 \
    && docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q 'nvidia'; then
    docker_args+=(
        --gpus all
        --env NVIDIA_VISIBLE_DEVICES=all
        --env NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics,display
    )
fi

# libuvc accesses the USB bus directly. The cgroup rule also permits a camera
# that is reconnected after the container has started, without --privileged.
if [[ "${ORBBEC_ENABLED}" == "true" ]]; then
    if [[ ! -d /dev/bus/usb ]]; then
        echo "/dev/bus/usb is unavailable; cannot pass Gemini 336L through." >&2
        exit 2
    fi
    check_gemini_permissions
    docker_args+=(
        --mount type=bind,src=/dev/bus/usb,dst=/dev/bus/usb
        --device-cgroup-rule "c 189:* rmw"
    )
fi

# Resolve persistent host identities once and expose two predictable paths.
# --device grants only these serial devices; supplementary numeric groups
# preserve access for the existing non-root container user.
if [[ "${GX5_ENABLED}" == "true" ]]; then
    gx5_devices=()
    for index in 1 2; do
        port_variable="GX5_PORT_${index}"
        host_port="${!port_variable:-}"
        if [[ -z "${host_port}" || ! -c "${host_port}" ]]; then
            echo "Set ${port_variable} to the GX5 character device under /dev/serial/by-id/ in docker/sensors.env." >&2
            exit 2
        fi
        host_port="$(realpath "${host_port}")"
        device_identity="$(stat -Lc '%t:%T' "${host_port}")"
        if [[ "${index}" == "2" && "${device_identity}" == "${gx5_devices[0]}" ]]; then
            echo "GX5_PORT_1 and GX5_PORT_2 refer to the same device; select two different units." >&2
            exit 2
        fi
        gx5_devices+=("${device_identity}")
        docker_args+=(
            --device "${host_port}:/dev/gx5_${index}:rw"
            --group-add "$(stat -Lc '%g' "${host_port}")"
        )
    done
fi

if [[ -n "${LIVOX_CONFIG_FILE:-}" ]]; then
    if [[ ! -f "${LIVOX_CONFIG_FILE}" ]]; then
        echo "LIVOX_CONFIG_FILE does not exist: ${LIVOX_CONFIG_FILE}" >&2
        exit 2
    fi
    docker_args+=(
        --volume "$(realpath "${LIVOX_CONFIG_FILE}"):/data/MID360_config.json:ro"
        --env "LIVOX_CONFIG_FILE=/data/MID360_config.json"
    )
elif [[ -n "${LIVOX_LAUNCH_CONFIG}" ]]; then
    docker_args+=(--env "LIVOX_CONFIG_FILE=${LIVOX_LAUNCH_CONFIG}")
else
    docker_args+=(--env "LIVOX_CONFIG_FILE=")
fi

if [[ "${default_launch}" == "true" ]]; then
    echo "[INFO] ROS_DOMAIN_ID=${ROS_DOMAIN_ID:-73}, MID-360=${LIVOX_ENABLED}, Gemini 336L=${ORBBEC_ENABLED} (count=${ORBBEC_CAMERA_COUNT:-1}), GX5 x2=${GX5_ENABLED}"
    if [[ "${ORBBEC_REQUEST,,}" == "auto" && "${ORBBEC_ENABLED}" == "false" ]]; then
        echo "[INFO] Gemini 336L (USB 2bc5:0807) was not detected; camera driver is disabled."
    fi
fi

if [[ "${default_launch}" == "true" ]]; then
    command=(
        ros2 launch lio docker_bringup.launch.py
        "use_rviz:=${GUI_ENABLED}"
        "use_livox_driver:=${LIVOX_ENABLED}"
        "use_orbbec_camera:=${ORBBEC_ENABLED}"
        "use_gx5_driver:=${GX5_ENABLED}"
        "config_path:=${LIO_CONFIG:-root_config.yaml}"
        "camera_name:=${ORBBEC_CAMERA_NAME:-camera}"
        "camera_enable_color:=${ORBBEC_ENABLE_COLOR:-true}"
        "camera_enable_depth:=${ORBBEC_ENABLE_DEPTH:-true}"
        "camera_enable_point_cloud:=${ORBBEC_ENABLE_POINT_CLOUD:-true}"
        "camera_enable_imu:=${ORBBEC_ENABLE_IMU:-true}"
    )
elif [[ "$1" == "shell" ]]; then
    command=(bash)
else
    command=("$@")
fi

docker run "${docker_args[@]}" "${IMAGE}" "${command[@]}"
