# Elevator-LIO

[中文](README.md) | [English](README_en.md)

作者：Yifan Zhang, Yudong Huang, Yuchong Zhang, Changze Li, Haoran Liu, Ming Yang, Tong Qin*

Elevator-LIO 是面向电梯非惯性运动和跨楼层定位的 LiDAR-惯性里程计。主要测试平台为 Livox MID-360，同时支持其他雷达如 Ouster、Velodyne、XT32 等，但除MID360外尚未经过大规模测试。



[![Project Page](https://img.shields.io/badge/Project-Page-blue)](https://xiaofan4122.github.io/Elevator_LIO_Page/)
[![arXiv](https://img.shields.io/badge/arXiv-2605.24495-b31b1b)](https://arxiv.org/abs/2605.24495)
[![Dataset](https://img.shields.io/badge/HuggingFace-Dataset-ffcc00)](https://huggingface.co/datasets/xiaofan0100/Elevator-LIO-Dataset)

数据集下载与使用说明见 [DATASET.md](DATASET.md)。

关闭 YAML 中的电梯模式后，Elevator-LIO 可作为普通 LIO 使用，并保留触发式更新和自适应降采样等功能。

<p align="center">
  <img src="docs/images/background.jpg" alt="Elevator-LIO overview" width="100%">
</p>

> [!WARNING]
> Elevator-LIO 允许机器人在电梯内自由移动，但建议使用 Livox MID-360 这类视场较大的 LiDAR，并采用倾斜安装，以获得尽可能多方向上的几何约束。如果您的 LiDAR 水平安装，且机器人在电梯内基本不会产生上下运动，请将 `yaml/runtime` 中的 `elevator.strong_prior_enable` 设置为 `true`。该选项会将 IMU 垂直方向加速度强约束解释为电梯加速度，使系统在此类安装条件下也能正常工作。

## 时间节点

- **2026-05-23**：[arXiv 预印本](https://arxiv.org/abs/2605.24495)公开。
- **2026-05-26**：[小红书](http://xhslink.com/o/9MTzcbzjGaQ) 公开宣传。
- **2026-06-06**：[@编程猫小渐](http://xhslink.com/o/5bhSpWqEbeO) 复现 Elevator-LIO 论文结果。
- **2026-06-20**：[Elevator-LIO 数据集](https://huggingface.co/datasets/xiaofan0100/Elevator-LIO-Dataset)公开，包含 20 条序列和 79 次电梯乘坐；额外收录 @编程猫小渐 的两条数据。
- **2026-06-22**：发布 [rosbag 管理器视频](https://www.bilibili.com/video/BV1n3jt64Eoi/?share_source=copy_web&vd_source=392db04838f1edf7d12e58a3d68775d8)，该工具随 Elevator-LIO 一同开源。
- **2026-06-26**：ROS 1 源码发布。
- **2026-07-29**：正式发布 ROS 2 Humble 支持；同一套源码兼容 ROS 1 Noetic 与 ROS 2 Humble。
- **计划中**：更多数据集发布，包括更多带图像的完整序列。
- **计划中**：手持采集平台软硬件源码与文档公开。

## 支持工作

欢迎参观课题组其他工作，Elevator-LIO 为以下工作提供了定位支持：

- [SCAN-Planner](https://github.com/wuyi2121/SCAN-Planner)：面向路线引导长距离四足导航的空间碰撞感知局部规划器，可为自主探索、视觉语言导航等上层任务提供底层规划基础。
- [TravExplorer](https://github.com/wuyi2121/TravExplorer)：面向跨楼层具身探索的可通行性驱动 3D 规划系统，支持单楼层与跨楼层目标导航。

## 场景展示

![Elevator-LIO 多楼层与电梯场景](docs/images/Scenarios.png)

## 方法概述

传统 LIO 假设导航坐标系为惯性系，但在运动的电梯轿厢内，IMU 会感受到电梯运动，而 LiDAR 主要观测轿厢内的相对几何，现有 LIO 方法几乎全部失效。Elevator-LIO 将机器人相对电梯的运动与电梯自身运动解耦，并通过模式相关的迭代误差状态卡尔曼滤波实现连续跨楼层定位：普通室内环境使用标准 LIO 传播，进入电梯后启用非惯性状态传播和约束更新。

![Elevator-LIO 系统总览](docs/images/system_overview.png)

系统按照时间顺序处理 IMU 和 LiDAR 数据，依次完成静态 IMU 初始化、自适应降采样、模式相关传播、IESKF LiDAR 更新、可能的退出电梯更新和增量 ikd-Tree 建图。

### 电梯模式管理

进入检测使用 LiDAR 距离统计量判断机器人是否由开放区域进入封闭轿厢；退出检测根据估计的电梯竖直运动状态及其方差判断电梯是否停稳。两种事件也可以通过 ROS 话题手动触发。

<p align="center">
  <img src="docs/images/elevator_mode_manager.png" alt="电梯模式进入与退出检测" width="70%">
</p>

### 退出电梯更新

电梯停稳后，系统施加零速度和零加速度约束，将估计的电梯竖直位移重新锚定到机器人状态，并重置电梯相关状态，从而抑制电梯运行期间累积的高度漂移。

<p align="center">
  <img src="docs/images/exit_update.png" alt="退出电梯时的事件触发更新" width="70%">
</p>

### 自适应降采样

系统在线调整体素大小，使降采样后的有效点数保持在目标值附近，在电梯轿厢内保留足够的几何信息，同时控制开放场景中的计算量。

<p align="center">
  <img src="docs/images/adaptive_downsampling.png" alt="自适应体素降采样" width="70%">
</p>

## 数据采集平台

<p align="center">
  <img src="docs/images/handheld_platform.png" alt="Elevator-LIO 手持采集设备" width="85%">
</p>

数据使用集成 Livox MID-360、工业相机和 Jetson Orin Nano 的便携式手持设备采集。

> [!NOTE]
> - [ ] 后续将开源手持设备的软硬件设计与相关文档。
>

## 🔥 设计理念

Elevator-LIO 的设计遵循开箱即用的原则，集成了许多便于使用的功能，具有完善的注释方便您进行后续开发，日志与调试系统比较完善。

小巧思包括：

- **ROS 1 可独立编译，ROS 2 与实机类型一致**：ROS 1 在包内生成 Livox 消息；ROS 2 直接使用
  `livox_ros_driver2/msg/CustomMsg`，与 MID-360 驱动发布的话题严格匹配
- **初始重力对齐**：无论雷达以何种方向放置，世界系都会初始化为水平方向
- **球形/长方体包围盒滤除**：除了指定球形滤除框，也可以指定长方体区域内点云滤除
- **预留额外的 body 系输出**：可在 `yaml/sensors` 中配置 `offset.lidar_R_body` 和
  `offset.lidar_t_body`
- **简单的重定位功能**：支持加载 PCD 地图，然后在原点启动并运行重定位
- **协方差矩阵可视化**：可在 `yaml/logging` 中打开，方便调试
- **高频输出**：可在 `yaml/runtime` 中打开，将 IMU 预积分位姿也输出出来，方便下游应用

不同于主流 LIO，Elevator-LIO 没有显式打包概念，遵循“谁来谁更新”的设计理念，在框架上更适合多传感器融合；但这也带来了额外开销：状态机需要以较高频率轮询并检测是否有数据输入。


## 🛠️ 安装与运行

### Docker（amd64 / DGX Spark arm64）

仓库提供同一个多架构 Docker 配置，在 amd64 Ubuntu 笔记本和 arm64 DGX Spark 上原生构建
Ubuntu 22.04、ROS 2 Humble、Livox-SDK2、Livox ROS Driver 2、OrbbecSDK ROS2、MicroStrain ROS2、
Elevator-LIO 与 RViz2。同一容器可驱动 Ethernet MID-360、最多三台 USB Gemini 336L 和两台
USB 3DM-GX5-AHRS，使用 host
network/IPC 和 X11；默认 ROS_DOMAIN_ID 为 73。传感器网络、udev 与完整用法见
[Docker 指南](docker/README.md)。
将 `docker/sensors.env.example` 复制为 `docker/sensors.env`，填写三台相机序列号、
两台 AHRS 设备路径和 LiDAR IP，之后使用 `./docker/run.sh` 启动全部传感器。

```bash
./docker/run.sh build
./docker/run.sh setup-camera
LIVOX_LIDAR_IP=192.168.1.112 ./docker/run.sh
```

### 센서 Docker 명령어 모음 (한국어)

아래 명령은 **호스트의 저장소 루트**에서 실행합니다. 현재 호스트 설정은 MID-360 1대,
Gemini 336L 3대(`front`, `left`, `right`), GX5-AHRS 2대(`gx5_1`, `gx5_2`)입니다.
장치 정보는 `docker/sensors.env`에 보존되며, 기본 ROS 도메인은 `73`입니다.
다른 호스트에서는 먼저 [센서 설정 가이드](docker/README.md)를 따라 설정합니다.

#### 실행·종료·컨테이너 접속

```bash
# 터미널 A: 전체 센서 + LIO + RViz 실행 (이 터미널은 계속 열어둡니다)
./docker/run.sh

# GUI 없이 전체 센서 + LIO 실행
USE_RVIZ=false ./docker/run.sh

# GX5를 제외하고 기존 LiDAR + 카메라만 실행
USE_GX5_DRIVER=false ./docker/run.sh

# 실행 상태 / CPU·메모리 사용량
docker ps --filter name=elevator-lio
docker stats --no-stream elevator-lio

# 터미널 B: 실행 중인 컨테이너에 접속 (ROS 환경 자동 설정)
./docker/run.sh exec
# 접속한 쉘에서 빠져나오기: exit (센서 실행은 유지됩니다)

# 실행 로그: Ctrl-C는 로그 조회만 종료
docker logs --tail 100 -f elevator-lio

# 센서 종료: 터미널 A에서 Ctrl-C 또는 다른 터미널에서 아래 명령
docker stop elevator-lio
# 재실행
./docker/run.sh
```

위 실행 예제는 용도에 맞게 **하나만** 선택합니다. 기본 컨테이너는 종료 시 삭제되므로
`docker start` 대신 `./docker/run.sh`로 다시 생성합니다. `exec`는 실행 중인 컨테이너가
필요하며, `No such container`가 나오면 먼저 실행 상태를 확인합니다.
`./docker/run.sh shell`은 별도의 임시 개발 컨테이너입니다.

#### 토픽·노드·파라미터 확인

아래 명령은 센서가 실행 중일 때 **다른 터미널**에서 실행합니다.

```bash
./docker/run.sh exec ros2 topic list
./docker/run.sh exec ros2 topic list -t
./docker/run.sh exec ros2 node list
./docker/run.sh exec ros2 node info /gx5_1/microstrain_inertial_driver
./docker/run.sh exec ros2 topic info -v /gx5_1/ekf/imu/data
./docker/run.sh exec ros2 topic type /livox/lidar
./docker/run.sh exec ros2 interface show sensor_msgs/msg/Imu
./docker/run.sh exec ros2 service list
./docker/run.sh exec ros2 param list /gx5_1/microstrain_inertial_driver
./docker/run.sh exec ros2 param get /gx5_1/microstrain_inertial_driver port
./docker/run.sh exec ros2 param get /gx5_2/microstrain_inertial_driver frame_id
```

| 토픽 | 내용 |
|---|---|
| `/livox/lidar` | LiDAR 점군, `livox_ros_driver2/msg/CustomMsg`, 설정 10 Hz |
| `/livox/imu` | Livox 내장 IMU, LIO 입력 |
| `/{front,left,right}/color/image_raw` | 각 카메라 RGB 영상 |
| `/{front,left,right}/depth/image_raw` | 각 카메라 depth 영상 |
| `/{front,left,right}/color/camera_info`, `…/depth/camera_info` | 영상 보정 정보 |
| `/{front,left,right}/depth/points` | 각 카메라 depth 점군 |
| `/{front,left,right}/gyro_accel/sample` | 각 카메라 IMU |
| `/{gx5_1,gx5_2}/imu/data_raw` | GX5 가속도·각속도, 설정 100 Hz |
| `/{gx5_1,gx5_2}/ekf/imu/data` | GX5 AHRS 자세 포함 IMU, 설정 100 Hz |
| `/{gx5_1,gx5_2}/imu/mag` | GX5 자기장, 설정 100 Hz |
| `/{gx5_1,gx5_2}/ekf/status` | 모델·시리얼·필터 상태·오류 플래그, 1 Hz |
| `/LIO/odom_imu`, `/LIO/odom_vehicle` | LIO 추정 자세·위치 |
| `/LIO/global_map`, `/LIO/clouds_lidar` | LIO 지도·점군 |
| `/tf`, `/tf_static` | 좌표 변환 |

표의 `{…}`는 여러 namespace를 줄여 쓴 표기입니다. 실제 명령에는 `/front/...`처럼
하나의 이름을 넣습니다. GX5 토픽은 독립 발행되며 LIO는 기존 Livox IMU 입력을 유지합니다.

#### 실제 값·AHRS 상태·수신 주기 확인

```bash
# 한 메시지만 출력하고 종료
./docker/run.sh exec ros2 topic echo /livox/imu --once
./docker/run.sh exec ros2 topic echo /gx5_1/ekf/status --once
./docker/run.sh exec ros2 topic echo /gx5_2/ekf/status --once
./docker/run.sh exec ros2 topic echo /gx5_1/ekf/imu/data --field orientation --once
./docker/run.sh exec ros2 topic echo /gx5_2/imu/mag --once
./docker/run.sh exec ros2 topic echo /LIO/odom_imu --field pose.pose --once
# 영상 바이트 전체 대신 header 확인
./docker/run.sh exec ros2 topic echo /front/color/image_raw --field header --once

# 각각 실행하고 Ctrl-C로 조회 종료
./docker/run.sh exec ros2 topic hz /livox/lidar
./docker/run.sh exec ros2 topic hz /livox/imu
./docker/run.sh exec ros2 topic hz /front/color/image_raw
./docker/run.sh exec ros2 topic hz /left/depth/image_raw
./docker/run.sh exec ros2 topic hz /right/depth/image_raw
./docker/run.sh exec ros2 topic hz /gx5_1/ekf/imu/data
./docker/run.sh exec ros2 topic hz /gx5_2/ekf/imu/data
./docker/run.sh exec ros2 topic bw /front/color/image_raw
```

GX5 상태에서 `serial_number`, `filter_state`, `status_flags`를 확인합니다. 이 호스트의
매핑은 `gx5_1=6253.211422`, `gx5_2=6253.219818`이고, 실기 검증에서 두 대 모두
`Solution Valid` 및 빈 오류 플래그를 확인했습니다. `hz`는 CLI가 실제 받은 주기이므로
영상·점군 동시 구독에 따른 부하와 QoS에 영향을 받을 수 있습니다.

#### rosbag 녹화 — 컨테이너를 지워도 데이터 보존

ROS 2에서는 `ros2 bag record -a`를 사용합니다. **터미널 A의 센서는 켜두고**, 터미널 B에서
아래 녹화 예제 중 하나를 실행합니다. `/data`는 기본적으로 호스트 `docker/data/`에
연결됩니다. `LIO_DATA_DIR`을 지정했다면 해당 디렉터리에 저장됩니다.

```bash
# 모든 공개 토픽 녹화 (RGB/depth/점군/LIO 출력 포함)
./docker/run.sh exec ros2 bag record -a -o "/data/all_$(date +%Y%m%d_%H%M%S)"

# LiDAR + GX5만 선택 녹화
./docker/run.sh exec ros2 bag record \
  -o "/data/lidar_gx5_$(date +%Y%m%d_%H%M%S)" \
  /livox/lidar /livox/imu \
  /gx5_1/imu/data_raw /gx5_1/ekf/imu/data /gx5_1/imu/mag /gx5_1/ekf/status \
  /gx5_2/imu/data_raw /gx5_2/ekf/imu/data /gx5_2/imu/mag /gx5_2/ekf/status

# 센서 namespace + TF만 녹화 (LIO 출력 제외)
./docker/run.sh exec ros2 bag record \
  -e '^/(livox|front|left|right|gx5_1|gx5_2)/|^/tf(_static)?$' \
  -o "/data/sensors_$(date +%Y%m%d_%H%M%S)"

# 전체 토픽을 60초 단위 파일로 분할 (60초 후 종료가 아니라 계속 녹화)
./docker/run.sh exec ros2 bag record -a -d 60 \
  -o "/data/split_$(date +%Y%m%d_%H%M%S)"

# 전체 토픽을 녹화하되 압축 영상·카메라 점군처럼 중복 용량이 큰 항목 제외
./docker/run.sh exec ros2 bag record -a \
  -x '/(compressed|compressedDepth|theora)$|^/(front|left|right)/depth/points$' \
  -o "/data/reduced_$(date +%Y%m%d_%H%M%S)"
```

녹화 종료는 **녹화 터미널에서 Ctrl-C**입니다. 저장 완료 후 센서 컨테이너를 종료합니다.
기본 저장 형식은 SQLite3(`metadata.yaml` + `.db3`)이며 출력 디렉터리 이름은 새 이름을
사용합니다. 영상 3대와 점군 전체 녹화는 저장 용량·쓰기 대역폭을 많이 사용합니다.

```bash
# 호스트에서 저장 위치·남은 공간 확인
ls -lh docker/data/
du -sh docker/data/*
df -h docker/data/

# 실제 생성된 bag 디렉터리명으로 변경
BAG_DIR=/data/all_20260914_140000
./docker/run.sh exec ros2 bag info "$BAG_DIR"
```

#### 센서가 꺼져 있어도 bag 정보 확인·재생

`exec` 없이 사용자 명령을 넘기면 작업용 임시 컨테이너를 실행합니다. 아래 명령은
LiDAR/GX5 드라이버를 시작하지 않으며 카메라 launch도 실행하지 않습니다. 로컬 설정에
따라 카메라 USB 마운트·권한 검사는 수행될 수 있습니다.

```bash
# 실제 bag 디렉터리명으로 변경
BAG_DIR=/data/all_20260914_140000
USE_LIVOX_DRIVER=false USE_GX5_DRIVER=false \
  ./docker/run.sh ros2 bag info "$BAG_DIR"

# 실시간 센서(domain 73)와 분리된 domain 74에서 재생
ROS_DOMAIN_ID=74 USE_LIVOX_DRIVER=false USE_GX5_DRIVER=false \
  ./docker/run.sh ros2 bag play "$BAG_DIR"

# 0.5배속 재생 (위 기본 재생 대신 선택)
ROS_DOMAIN_ID=74 USE_LIVOX_DRIVER=false USE_GX5_DRIVER=false \
  ./docker/run.sh ros2 bag play "$BAG_DIR" --rate 0.5

# 선택 토픽만 반복 재생
ROS_DOMAIN_ID=74 USE_LIVOX_DRIVER=false USE_GX5_DRIVER=false \
  ./docker/run.sh ros2 bag play "$BAG_DIR" --loop \
  --topics /gx5_1/ekf/imu/data /gx5_2/ekf/imu/data
```

재생 종료는 Ctrl-C입니다. 재생 데이터를 보는 노드도 `ROS_DOMAIN_ID=74`를 사용합니다.
예를 들어 다른 터미널에서 다음과 같이 확인합니다.

```bash
ROS_DOMAIN_ID=74 USE_LIVOX_DRIVER=false USE_GX5_DRIVER=false \
  ./docker/run.sh ros2 topic echo /gx5_1/ekf/imu/data --once
```

#### 연결 문제 확인

```bash
# 호스트의 LiDAR NIC / IP / USB 연결과 속도
ip -br link
ip -br -4 addr
ping -c 3 192.168.1.126
lsusb
lsusb -t
ls -l /dev/serial/by-id/

# 컨테이너에서 GX5 장치 및 ROS 도메인 확인
./docker/run.sh exec ls -l /dev/gx5_1 /dev/gx5_2
./docker/run.sh exec printenv ROS_DOMAIN_ID
```

LiDAR IP는 실제 `docker/sensors.env` 값으로 바꿉니다. GX5 USB를 재연결하면
`docker stop elevator-lio` 후 `./docker/run.sh`로 다시 시작합니다.
호스트 ROS CLI를 직접 쓸 때는 설치된 ROS 환경을 source하고 `export ROS_DOMAIN_ID=73`을
설정합니다. 도메인을 바꾼 뒤 이전 목록이 보이면 `ros2 daemon stop` 후 다시 조회합니다.
호스트에 Livox/MicroStrain 메시지 패키지가 없다면 위 `./docker/run.sh exec ...` 방식을 사용합니다.

### 环境要求

当前代码使用同一套源码和 `package.xml` 支持：

- Ubuntu 20.04 + ROS 1 Noetic
- Ubuntu 22.04 + ROS 2 Humble

此前的 Docker 镜像已在 x86_64 与 DGX Spark arm64 上完成原生构建验证。
当前主机已验证 MID-360、三台 Gemini 336L、两台 GX5-AHRS 的并行数据接收及容器重建后启动。其他主机/架构仍需分别验证。Livox-SDK2、
`livox_ros_driver2`、Orbbec、MicroStrain 驱动和 Elevator-LIO 会针对目标架构构建；
不同架构之间不能复用镜像内的二进制文件。

OpenCV 目前只用于协方差矩阵和电梯状态曲线的调试窗口，默认配置中这些窗口均关闭；但源码和 CMake
仍会包含并链接 OpenCV，您可以自行修改代码取消这些依赖。

仿真节点需要 JSON 依赖：

```bash
sudo apt install -y nlohmann-json3-dev
```

### 编译

ROS 1：将代码放入 catkin 工作空间的 `src` 目录后编译：

```bash
ROS1_WS=~/catkin_ws
cd "$ROS1_WS"
source /opt/ros/noetic/setup.bash
rosdep install --from-paths src --ignore-src -r -y
catkin_make -DCMAKE_BUILD_TYPE=Release
source devel/setup.bash
```

ROS 2 使用 `livox_ros_driver2/msg/CustomMsg`。推荐先在独立工作空间中构建 Humble 版
Livox ROS Driver 2，再构建 Elevator-LIO：

```bash
# 首次构建 Livox ROS Driver 2
LIVOX_WS=~/ws_livox_ros_driver2
cd "$LIVOX_WS/src/livox_ros_driver2"
source /opt/ros/humble/setup.bash
./build.sh humble

# 构建 Elevator-LIO
LIO_ROS2_WS=~/ws_elevator_lio_ros2
cd "$LIO_ROS2_WS"
source /opt/ros/humble/setup.bash
source "$LIVOX_WS/install/setup.bash"
rosdep install --from-paths src --ignore-src -r -y
colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release
source install/setup.bash
```

也可以把驱动与 Elevator-LIO 放在同一个 colcon 工作空间，但必须从驱动目录执行
`./build.sh humble`，让驱动先切换到 ROS 2 的 `package.xml`；驱动仍处于 ROS 1 清单状态时，
不能直接执行裸 `colcon build`。

### 运行

ROS 1 使用 `roslaunch` 运行：

```bash
roslaunch lio start.launch
```

可以指定对应的 YAML 文件参数。默认配置为 `root_config.yaml`，也可以创建自己的配置文件：

```bash
roslaunch lio start.launch config_path:=path_to_yaml
```

ROS 2 使用 Python launch 文件运行：

```bash
ros2 launch lio start_ros2.launch.py
ros2 launch lio start_ros2.launch.py config_path:=path_to_yaml
```

`config_path` 从软件包的 `yaml/` 目录读取。如果不需要 RViz/RViz2，
ROS 2 launch 可添加 `use_rviz:=false`。ROS 1 使用 `rviz/LIO.rviz`，ROS 2 使用
`rviz/LIO_ros2.rviz`；电梯状态面板在两个版本中均会构建。

### 电梯模式说明

电梯功能由统一开关控制：

```yaml
elevator:
  enable: true
```

自动进入电梯模式由门关闭检测控制：

```yaml
elevator:
  door_detector:
    enable: true
```

该检测基于点云距离分位数，在狭窄场景（如楼道）中可能误触发。可以关闭自动检测，改用话题手动触发。

进入电梯模式（通过话题触发）：

```bash
rostopic pub /LIO/set_elevator_flag std_msgs/Bool "data: true" -1
```

退出电梯模式（通过话题触发）：

```bash
rostopic pub /LIO/set_elevator_flag std_msgs/Bool "data: false" -1
```

ROS 2 的对应命令为：

```bash
ros2 topic pub --once /LIO/set_elevator_flag std_msgs/msg/Bool "{data: true}"
ros2 topic pub --once /LIO/set_elevator_flag std_msgs/msg/Bool "{data: false}"
```

自动退出通过下面参数控制：

```yaml
elevator:
  self_exit_detector: true # 打开时会根据估计出的电梯速度及其方差信息，自动退出电梯模式
```

程序内部的电梯状态会和 LiDAR 信息同频率发布：`/LIO/in_elevator` 保留布尔模式标志；`/LIO/elevator_state` 发布电梯模式以及估计的相对位移、速度和加速度，并供 RViz 电梯状态面板显示。

### 仿真节点

在程序开发早期，我们设计了仿真节点 `sim_node`，用于构造电梯场景并生成 LiDAR 与 IMU 消息。具体程序与配置位于 `src/sim` 中。

仿真仍沿用原有路径语义，默认配置和生成的 CSV 位于源码的 `src/sim/`：

```bash
# ROS 1（先启动 roscore）
rosrun lio sim_node

# ROS 2
ros2 run lio sim_node
```

### 参数修改

在 `root_config.yaml` 中分别选择传感器、运行和日志配置：

```yaml

sensor_config: "sensors/livox.yaml"
runtime_config: "runtime/mapping.yaml"
logging_config: "logging/default.yaml"
```

详细说明见 [yaml/README.md](yaml/README.md)。

部分关键配置：

- **降采样参数**。如在嵌入式设备上无法实时运行，可以增大 `point_filter_num`、降低
  `adaptive.target_points`，或增大 `adaptive.min_voxel`：

```yaml
downsample:
  point_filter_num: 2 # 订阅点云时的降采样比例 [确保为正整数]
  blind: 0.8 # 忽略距离小于 blind 的点 [m]
  use_box_blind: false # true 时改为删除下述长方体内的点
  box_corner: # LiDAR 坐标系下的三轴范围 [min, max]，单位 m
    box_corner_x: [-0.7, 0.1]
    box_corner_y: [-0.3, 0.3]
    box_corner_z: [-0.4, 0.4]
  filter_size: 0.1 # 固定模式的体素大小；自适应模式下的初始体素大小
  adaptive:
    enable: true # 启用自适应体素降采样
    target_points: 20000 # 目标每秒点数（程序会按帧时间折算）
    alpha: 1.2 # 幂律调节指数
    min_voxel: 0.05 # 最小体素大小
    max_voxel: 0.8 # 最大体素大小
```

- **电梯功能配置**。关闭 `elevator.enable` 后，系统会退化为普通 LIO；开启时可使用 LiDAR 门关闭检测自动进入电梯模式，并通过 IMU 运动状态自动退出：

```yaml
elevator:
  enable: true # 电梯模式总开关
  self_exit_detector: true # 根据 IMU 电梯运动阶段与停稳检测自动退出
  door_detector:
    enable: true # 是否启用电梯门关闭自动检测
    dist_threshold: 3.0 # 过滤后最远点小于该距离时认为轿厢封闭 [m]
    time_threshold: 2.0 # 封闭状态持续多久后触发电梯模式 [s]
    filter_percent: 0.06 # 计算最远距离时忽略最远端点的比例
    cooldown_time: 5.0 # 两次自动触发之间的冷却时间 [s]
  zupt:
    enable: true # 电梯相关 ZUPT 总开关
    waiting:
      enable: true # 进入电梯后的等待阶段是否周期性触发 ZUPT
      period_s: 3.0
      vz_abs_thresh: 0.1
      az_abs_thresh: 0.1
  exit_icp_z:
    enable: false # 退出电梯后是否用已有 ikd-tree 地图做仅 z 方向 ICP 修正
```

> [!WARNING]
> 电梯退出检测相对稳定，但自动进入检测在狭窄走廊等封闭环境中可能误触发。您可以根据场景调整 `door_detector` 相关阈值，或自行发布触发信号；话题触发方式请参考上方“电梯模式说明”中的通过话题触发小节。重定位配置中默认开启 `exit_icp_z.enable`，建图配置中默认关闭，详细参数见 [yaml/README.md](yaml/README.md)。

- **重定位设置**，启用重定位时记得修改参考地图文件

```yaml
relocation:
  relocation_enable: false # 是否开启重定位
  pcd_load_name: "scans.pcd" # 重定位时加载的 .pcd 文件名称，相对 PCD 文件夹
```

## 目录结构

每次建图结束后，地图都会保存到 `PCD` 文件夹下。

日志文件会生成在项目的 `temp` 文件夹下。

核心代码位于 `src` 和 `include` 文件夹下。

`temp` 文件夹下会生成当前批次运行得到的一些关键数据记录。


```text
├── CMakeLists.txt
├── PCD                         # 建图结果、重定位地图和临时点云
│   └── Temp                    # 运行过程中生成的临时点云
├── docs                        # README 使用的说明文档与资源
│   └── images                  # 项目图片、流程图和效果图
├── include                     # C++ 头文件
│   ├── support                 # 公共类型、配置读取、缓存和节点接口
│   │   ├── common_lib.h
│   │   ├── LIONode.h
│   │   ├── SharedBuffers.h
│   │   ├── TopicProcess.h
│   │   ├── YamlReader.*
│   │   ├── ros_compat.h
│   │   └── type.h
│   ├── elevator                # 电梯检测、状态机和 ZUPT 接口
│   │   ├── ElevatorProcess.h
│   ├── estimator               # ESEKF 与 IMU 预积分/传播接口
│   │   ├── ESEKF.h
│   │   └── IMUProcess.h
│   ├── AdaptiveFilter          # 自适应体素降采样
│   │   ├── AdaptiveVoxelFilter.hpp
│   │   └── AdaptiveVoxelPController.hpp
│   ├── ikd_tree                # 增量式 ikd-tree 地图与近邻查询
│   │   ├── IkdMap.hpp
│   │   ├── IkdNearestQuery.hpp
│   │   └── ikd_Tree.*
│   ├── node                    # LiDAR 处理流水线等节点内部接口
│   └── rviz                    # 算法调试可视化接口
├── launch                      # ROS 节点启动文件
│   ├── start.launch
│   └── start_ros2.launch.py
├── msg                         # 项目自定义 ROS 消息
│   └── *.msg
├── package.xml
├── README.md
├── README_en.md
├── rviz                        # RViz 显示配置
│   ├── LIO.rviz
│   └── LIO_ros2.rviz
├── scripts                     # Bag Runner、数据分析和绘图脚本
│   ├── bag_runner_ui.py
│   ├── convert_rosbag1_to_rosbag2.py
│   └── download_dataset.sh
├── src                         # C++ 源码实现
│   ├── main.cpp
│   ├── elevator                # 电梯检测、状态机和 ZUPT 实现
│   │   └── ElevatorProcess.cpp
│   ├── estimator               # ESEKF 与 IMU 处理实现
│   │   ├── ESEKF.cpp
│   │   └── IMUProcess.cpp
│   ├── node                    # ROS 回调、地图、发布、保存和服务
│   │   ├── callbacks.cpp
│   │   ├── map.cpp
│   │   ├── publish.cpp
│   │   ├── save.cpp
│   │   └── service.cpp
│   ├── rviz                    # rviz 配置文件
│   ├── support                 # 公共配置、日志和话题接收实现
│   │   ├── common_lib.cpp
│   │   └── TopicReceive.cpp
│   └── sim                     # 仿真节点
│       └── run_sim_node.cpp
├── yaml                        # 分层运行配置
│   ├── root_config.yaml
│   ├── sensors                 # 雷达类型、外参和订阅话题
│   ├── runtime                 # 建图、重定位、估计器和电梯参数
│   └── logging                 # 控制台、文件日志和调试可视化
```

## 引用

使用本软件或数据集时，请引用 Elevator-LIO 论文：

```bibtex
@article{zhang2026elevatorlio,
  title={Elevator-LIO: Robust LiDAR-Inertial Odometry for Multi-Floor Navigation under Elevator-Induced Non-Inertial Motion},
  author={Zhang, Yifan and Huang, Yudong and Zhang, Yuchong and Li, Changze and Liu, Haoran and Yang, Ming and Qin, Tong},
  journal={arXiv preprint arXiv:2605.24495},
  year={2026}
}
```

## 许可证

本项目自有代码以 [GNU General Public License v2.0 or later](LICENSE) 发布。仓库包含的独立
MIT 组件继续保留各自文件头中的 MIT 标识；ikd-Tree 等第三方代码保留其上游 GPLv2
授权说明，来源和本地修改见 [THIRD_PARTY.md](include/ikd_tree/THIRD_PARTY.md)。
