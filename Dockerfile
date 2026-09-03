# syntax=docker/dockerfile:1.7

ARG ROS_DISTRO=humble
# Docker Official Images do not publish a Humble `desktop` tag. Start from the
# multi-architecture ros-base image and install the desktop metapackage below.
FROM ros:${ROS_DISTRO}-ros-base-jammy

ARG ROS_DISTRO
ARG BUILD_JOBS=4
ARG LIVOX_SDK2_REF=08f523c930b2f0ba1e98a6afaa8d7476bf479908
ARG LIVOX_ROS_DRIVER2_REF=4a1def929e5b59c7a8122d19fce6efba581ce9f7

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    ROS_DISTRO=${ROS_DISTRO} \
    ROS_DOMAIN_ID=0 \
    ROS_LOCALHOST_ONLY=0 \
    QT_X11_NO_MITSHM=1 \
    LD_LIBRARY_PATH=/usr/local/lib:${LD_LIBRARY_PATH}

# Keep the compiler toolchain in the final image so this remains a usable
# /ros2_ws development environment, not only a runtime image.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        cmake \
        git \
        libapr1-dev \
        libasio-dev \
        libboost-all-dev \
        libeigen3-dev \
        libgl1 \
        libgl1-mesa-dri \
        libopencv-dev \
        libpcl-dev \
        libtbb-dev \
        libyaml-cpp-dev \
        mesa-utils \
        nlohmann-json3-dev \
        python3-colcon-common-extensions \
        python3-rosdep \
        qtbase5-dev \
        xauth \
        ros-${ROS_DISTRO}-desktop \
        ros-${ROS_DISTRO}-ament-cmake-auto \
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

# The upstream driver stores ROS 1 and ROS 2 manifests side by side. Select the
# ROS 2 files before rosdep/colcon inspect the workspace.
RUN mkdir -p src \
    && git clone --filter=blob:none https://github.com/Livox-SDK/livox_ros_driver2.git \
        src/livox_ros_driver2 \
    && git -C src/livox_ros_driver2 checkout --detach "${LIVOX_ROS_DRIVER2_REF}" \
    && cp src/livox_ros_driver2/package_ROS2.xml src/livox_ros_driver2/package.xml \
    && rm -rf src/livox_ros_driver2/launch \
    && cp -a src/livox_ros_driver2/launch_ROS2 src/livox_ros_driver2/launch

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
        /tmp/lio-home \
        /ros2_ws/src/elevator_lio/PCD/Temp \
        /ros2_ws/src/elevator_lio/temp \
    && chmod 1777 \
        /data \
        /tmp/lio-home \
        /ros2_ws/src/elevator_lio/PCD \
        /ros2_ws/src/elevator_lio/PCD/Temp \
        /ros2_ws/src/elevator_lio/temp \
    && chmod -R a+rwX \
        /ros2_ws/build \
        /ros2_ws/install \
        /ros2_ws/log \
        /ros2_ws/src \
    && install -m 0755 /ros2_ws/src/elevator_lio/docker/entrypoint.sh \
        /usr/local/bin/elevator-lio-entrypoint

ENV DEBIAN_FRONTEND= \
    HOME=/tmp/lio-home

ENTRYPOINT ["/usr/local/bin/elevator-lio-entrypoint"]
CMD ["ros2", "launch", "lio", "docker_bringup.launch.py"]
