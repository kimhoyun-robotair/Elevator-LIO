# syntax=docker/dockerfile:1.7

ARG ROS_DISTRO=humble
# Docker Official Images do not publish a Humble `desktop` tag. Start from the
# multi-architecture ros-base image and install the desktop metapackage below.
FROM ros:${ROS_DISTRO}-ros-base-jammy

ARG ROS_DISTRO
ARG BUILD_JOBS=4
ARG LIVOX_SDK2_REF=08f523c930b2f0ba1e98a6afaa8d7476bf479908
ARG LIVOX_ROS_DRIVER2_REF=4a1def929e5b59c7a8122d19fce6efba581ce9f7
ARG ORBBEC_ROS2_REF=ce08bce25f7a0a6fe939ece87ec945447109581f
ARG MICROSTRAIN_ROS2_REF=3ad64b9491f07a60fdaed1a3b990bc94421a58d9

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    ROS_DISTRO=${ROS_DISTRO} \
    ROS_DOMAIN_ID=73 \
    ROS_LOCALHOST_ONLY=0 \
    USE_LIVOX_DRIVER=true \
    USE_ORBBEC_CAMERA=false \
    USE_GX5_DRIVER=false \
    LIVOX_CONFIG_PATH=/tmp/lio-home/MID360_config.json \
    QT_X11_NO_MITSHM=1 \
    LD_LIBRARY_PATH=/usr/local/lib:${LD_LIBRARY_PATH}

# Keep the compiler toolchain in the final image so this remains a usable
# /ros2_ws development environment, not only a runtime image.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        cmake \
        git \
        iproute2 \
        libapr1-dev \
        libasio-dev \
        libboost-all-dev \
        libdw-dev \
        libeigen3-dev \
        libgflags-dev \
        libgl1 \
        libgl1-mesa-dri \
        libgoogle-glog-dev \
        libopencv-dev \
        libpcl-dev \
        libssl-dev \
        libtbb-dev \
        libusb-1.0-0-dev \
        libyaml-cpp-dev \
        mesa-utils \
        nlohmann-json3-dev \
        python3-colcon-common-extensions \
        python3-rosdep \
        qtbase5-dev \
        usbutils \
        xauth \
        ros-${ROS_DISTRO}-desktop \
        ros-${ROS_DISTRO}-ament-cmake-auto \
        ros-${ROS_DISTRO}-image-transport-plugins \
        ros-${ROS_DISTRO}-pcl-conversions \
        ros-${ROS_DISTRO}-pcl-ros \
    && rm -rf /var/lib/apt/lists/*

# Build Livox SDK2 natively for the image architecture. This is important on
# DGX Spark (linux/arm64): no amd64 prebuilt object is copied into the image.
RUN git clone --filter=blob:none https://github.com/Livox-SDK/Livox-SDK2.git /tmp/Livox-SDK2 \
    && git -C /tmp/Livox-SDK2 checkout --detach "${LIVOX_SDK2_REF}" \
    && cmake -S /tmp/Livox-SDK2 -B /tmp/Livox-SDK2/build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    && cmake --build /tmp/Livox-SDK2/build --parallel "${BUILD_JOBS}" \
    && cmake --install /tmp/Livox-SDK2/build \
    && ldconfig \
    && rm -rf /tmp/Livox-SDK2

WORKDIR /ros2_ws

# The upstream Livox driver stores ROS 1 and ROS 2 manifests side by side.
# Select the ROS 2 files before rosdep/colcon inspect the workspace.
RUN mkdir -p src \
    && git clone --filter=blob:none https://github.com/Livox-SDK/livox_ros_driver2.git \
        src/livox_ros_driver2 \
    && git -C src/livox_ros_driver2 checkout --detach "${LIVOX_ROS_DRIVER2_REF}" \
    && cp src/livox_ros_driver2/package_ROS2.xml src/livox_ros_driver2/package.xml \
    && rm -rf src/livox_ros_driver2/launch \
    && cp -a src/livox_ros_driver2/launch_ROS2 src/livox_ros_driver2/launch

# OrbbecSDK ROS2 v2 contains native SDK libraries for both x86_64 and aarch64;
# its CMake selects the matching directory at build time. Pin the exact release
# commit so amd64 and DGX Spark builds remain reproducible.
RUN git clone --filter=blob:none https://github.com/orbbec/OrbbecSDK_ROS2.git \
        src/OrbbecSDK_ROS2 \
    && git -C src/OrbbecSDK_ROS2 checkout --detach "${ORBBEC_ROS2_REF}"

# MicroStrain ROS2 4.8.1: build only the driver and its messages, including
# the pinned common code and MIP SDK, natively on amd64 and arm64.
RUN git clone --filter=blob:none https://github.com/LORD-MicroStrain/microstrain_inertial.git \
        src/microstrain_inertial \
    && git -C src/microstrain_inertial checkout --detach "${MICROSTRAIN_ROS2_REF}" \
    && git -C src/microstrain_inertial submodule update --init --recursive \
        microstrain_inertial_driver/microstrain_inertial_driver_common \
        microstrain_inertial_msgs/microstrain_inertial_msgs_common \
    && rm -rf src/microstrain_inertial/microstrain_inertial_description \
        src/microstrain_inertial/microstrain_inertial_examples \
        src/microstrain_inertial/microstrain_inertial_rqt

COPY . /ros2_ws/src/elevator_lio

RUN source "/opt/ros/${ROS_DISTRO}/setup.bash" \
    && rosdep update --rosdistro "${ROS_DISTRO}" \
    && apt-get update \
    && rosdep install \
        --from-paths src \
        --ignore-src \
        -y \
        --rosdistro "${ROS_DISTRO}" \
    && rm -rf /var/lib/apt/lists/* \
    && colcon build \
        --merge-install \
        --parallel-workers "${BUILD_JOBS}" \
        --cmake-args \
            -DBUILD_TESTING=OFF \
            -DCMAKE_BUILD_TYPE=Release \
            -DROS_EDITION=ROS2 \
            -DDISTRO_ROS="${ROS_DISTRO}"

RUN mkdir -p \
        /data \
        /tmp/lio-home/.ros \
        /ros2_ws/src/elevator_lio/PCD/Temp \
        /ros2_ws/src/elevator_lio/temp \
    && chmod 1777 \
        /data \
        /tmp/lio-home \
        /tmp/lio-home/.ros \
        /ros2_ws/src/elevator_lio/PCD \
        /ros2_ws/src/elevator_lio/PCD/Temp \
        /ros2_ws/src/elevator_lio/temp \
    && chmod -R a+rwX \
        /ros2_ws/build \
        /ros2_ws/install \
        /ros2_ws/log \
        /ros2_ws/src \
    && install -m 0755 /ros2_ws/src/elevator_lio/docker/entrypoint.sh \
        /usr/local/bin/elevator-lio-entrypoint \
    && install -m 0755 /ros2_ws/src/elevator_lio/docker/configure_livox.py \
        /usr/local/bin/elevator-lio-configure-livox

ENV DEBIAN_FRONTEND= \
    HOME=/tmp/lio-home

ENTRYPOINT ["/usr/local/bin/elevator-lio-entrypoint"]
CMD ["ros2", "launch", "lio", "docker_bringup.launch.py"]
