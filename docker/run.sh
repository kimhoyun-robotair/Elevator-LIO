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
  ./docker/run.sh                       Launch Elevator-LIO and RViz2
  ./docker/run.sh shell                 Open a sourced ROS 2 shell
  ./docker/run.sh <command> [args...]   Run any command in a temporary container

Environment:
  USE_RVIZ=false              Disable RViz2
  USE_LIVOX_DRIVER=true       Start the MID-360 driver in the same container
  LIVOX_CONFIG_FILE=/path     Mount a MID-360 JSON configuration
  LIO_CONFIG=root_config.yaml Select a root YAML under this repository's yaml/
  LIO_DATA_DIR=/path          Host directory mounted at /data
  ROS_DOMAIN_ID=0             DDS domain shared with host ROS 2 processes
  LIO_NVIDIA_GPU=0            Disable automatic NVIDIA GPU passthrough
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ "${1:-}" == "build" ]]; then
    exec docker build \
        --build-arg "BUILD_JOBS=${BUILD_JOBS}" \
        --tag "${IMAGE}" \
        "${REPO_ROOT}"
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
    GUI_ENABLED="${USE_RVIZ}"
else
    GUI_ENABLED="${default_launch}"
fi

HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
HOST_USER="$(id -un)"
DATA_DIR="${LIO_DATA_DIR:-${REPO_ROOT}/docker/data}"
PCD_DIR="${LIO_PCD_DIR:-${REPO_ROOT}/PCD}"
TEMP_DIR="${LIO_TEMP_DIR:-${REPO_ROOT}/temp}"

mkdir -p "${DATA_DIR}" "${PCD_DIR}/Temp" "${TEMP_DIR}"

docker_args=(
    --rm
    --interactive
    --tty
    --init
    --name "${CONTAINER_NAME}"
    --network host
    --ipc host
    --user "${HOST_UID}:${HOST_GID}"
    --env "HOME=/tmp/lio-home"
    --env "USER=${HOST_USER}"
    --env "LOGNAME=${HOST_USER}"
    --env "ROS_DOMAIN_ID=${ROS_DOMAIN_ID:-0}"
    --env "ROS_LOCALHOST_ONLY=${ROS_LOCALHOST_ONLY:-0}"
    --env "QT_X11_NO_MITSHM=1"
    --env "LIBGL_ALWAYS_SOFTWARE=${LIBGL_ALWAYS_SOFTWARE:-0}"
    --volume "${REPO_ROOT}/yaml:/ros2_ws/install/share/lio/yaml:ro"
    --volume "${PCD_DIR}:/ros2_ws/src/elevator_lio/PCD:rw"
    --volume "${TEMP_DIR}:/ros2_ws/src/elevator_lio/temp:rw"
    --volume "${DATA_DIR}:/data:rw"
    --workdir /ros2_ws
)

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

livox_config_path="/ros2_ws/install/share/livox_ros_driver2/config/MID360_config.json"
if [[ -n "${LIVOX_CONFIG_FILE:-}" ]]; then
    if [[ ! -f "${LIVOX_CONFIG_FILE}" ]]; then
        echo "LIVOX_CONFIG_FILE does not exist: ${LIVOX_CONFIG_FILE}" >&2
        exit 2
    fi
    docker_args+=(--volume "$(realpath "${LIVOX_CONFIG_FILE}"):/data/MID360_config.json:ro")
    livox_config_path="/data/MID360_config.json"
fi

if [[ "${default_launch}" == "true" ]]; then
    command=(
        ros2 launch lio docker_bringup.launch.py
        "use_rviz:=${GUI_ENABLED}"
        "use_livox_driver:=${USE_LIVOX_DRIVER:-false}"
        "config_path:=${LIO_CONFIG:-root_config.yaml}"
        "livox_config:=${livox_config_path}"
    )
elif [[ "$1" == "shell" ]]; then
    command=(bash)
else
    command=("$@")
fi

docker run "${docker_args[@]}" "${IMAGE}" "${command[@]}"
