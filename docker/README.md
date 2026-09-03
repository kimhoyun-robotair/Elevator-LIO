# Elevator-LIO Docker (amd64 + DGX Spark arm64)

동일한 `Dockerfile`이 amd64 노트북과 DGX Spark arm64에서 네이티브로 빌드됩니다. 이미지에는
Ubuntu 22.04, ROS 2 Humble Desktop, `/ros2_ws/src`, Livox-SDK2,
`livox_ros_driver2`, OrbbecSDK ROS2 v2.9.3, Elevator-LIO와 RViz2가 포함됩니다.

기본 `ROS_DOMAIN_ID`는 충돌 가능성이 낮고 Linux 권장 범위 안에 있는 `73`입니다. 컨테이너는
host network/IPC를 사용하므로 호스트 또는 다른 컨테이너와 통신할 때 포트 매핑은 필요하지
않습니다.

## 빠른 시작

```bash
sudo apt install -y x11-xserver-utils
./docker/run.sh build
```

MID-360과 Gemini 336L을 연결한 뒤 아래 센서별 준비를 수행합니다. MID-360용 Ethernet NIC에는
LiDAR와 같은 subnet의 주소가 먼저 설정되어 있어야 합니다. 자세한 NIC 예시는 다음 절을
참조하십시오.

```bash
./docker/run.sh setup-camera
# Gemini 336L USB 케이블을 뽑았다 다시 연결

LIVOX_LIDAR_IP=192.168.1.112 ./docker/run.sh
```

`LIVOX_LIDAR_IP`에는 실제 장치 주소를 반드시 넣으십시오. 또는
`LIVOX_CONFIG_FILE=/absolute/path/MID360_config.json`을 사용할 수 있습니다. Gemini 336L은
USB에서 `2bc5:0807` 장치가 발견되면 자동 실행됩니다.

센서 없이 이미지나 LIO만 확인하려면 다음과 같이 드라이버를 끕니다.

```bash
USE_LIVOX_DRIVER=false USE_ORBBEC_CAMERA=false ./docker/run.sh
```

## MID-360을 컨테이너에서 직접 실행

ROS 2 배포판이 서로 다른 컨테이너 간 통신은 호환이 보장되지 않습니다. 이 구성은 DGX Spark
호스트의 Ubuntu 24.04나 다른 ROS 컨테이너를 거치지 않고, 물리 Ethernet의 Livox UDP를 Humble
컨테이너가 직접 수신합니다. 같은 컨테이너 안에서 드라이버가 아래 토픽을 발행하므로
Elevator-LIO의 기본 설정과 바로 연결됩니다.

| 토픽 | 형식 |
|---|---|
| `/livox/lidar` | `livox_ros_driver2/msg/CustomMsg` |
| `/livox/imu` | `sensor_msgs/msg/Imu` |

MID-360은 별도 9–27 V 전원이 필요하며 Ethernet PoE로 전원을 공급하면 안 됩니다. 또한 하나의
LiDAR에는 master Livox SDK를 하나만 실행해야 하므로, 기존 Livox 드라이버 컨테이너는 먼저
중지하십시오.

호스트의 LiDAR 전용 NIC는 LiDAR와 같은 subnet이어야 합니다. MID-360 출고 주소는 일반적으로
`192.168.1.1XX/24`이며 `XX`는 시리얼 번호 끝 두 자리입니다. 예를 들어 실제 LiDAR 주소가
`192.168.1.112`라면 현재 부팅 세션에서 전용 NIC를 다음처럼 설정할 수 있습니다. 먼저 이
인터페이스가 다른 네트워크에 사용되지 않는 LiDAR 전용 포트인지 확인하고, `enp6s0`을 실제
인터페이스명으로 바꾸십시오. 영구 설정은 호스트의 NetworkManager/netplan에 별도로 저장해야
합니다.

```bash
ip -br link
sudo ip link set enp6s0 up
sudo ip address replace 192.168.1.50/24 dev enp6s0
ping -c 3 192.168.1.112
```

실행 시 컨테이너가 같은 subnet의 활성 NIC 주소를 찾아 MID-360 JSON을 자동 생성합니다.

```bash
LIVOX_LIDAR_IP=192.168.1.112 ./docker/run.sh
```

후보 NIC가 둘 이상이거나 자동 탐지가 불가능하면 명시합니다.

```bash
LIVOX_HOST_IP=192.168.1.50 \
LIVOX_LIDAR_IP=192.168.1.112 \
./docker/run.sh
```

기존 JSON 설정을 그대로 쓰는 것도 가능합니다.

```bash
LIVOX_CONFIG_FILE=/absolute/path/MID360_config.json ./docker/run.sh
```

방화벽을 사용한다면 LiDAR 전용 NIC와 LiDAR source IP에 한정해 UDP 56000, 56100, 56101,
56200, 56201, 56300, 56301, 56400, 56401, 56500, 56501만 허용하십시오.

## Gemini 336L USB 카메라

이미지는 공식 `orbbec/OrbbecSDK_ROS2` v2.9.3을 소스에서 빌드합니다. 이 버전은 Gemini 336L,
ROS 2 Humble, Linux x86_64와 ARM64를 지원합니다. 공식 권장 Gemini 336L firmware는 1.8.10입니다.
Orbbec은 ARM64 계열을 지원하지만 공식 검증 장치 목록은 Jetson/Thor이며 DGX Spark를 별도로
명시하지는 않습니다. 따라서 새 카메라 통합은 DGX Spark에서 USB 실기동을 확인해야 합니다.
호스트가 USB 장치 노드를 생성하므로 udev 규칙은 컨테이너가 아니라 호스트에 한 번 설치해야
합니다.

```bash
./docker/run.sh setup-camera
# 카메라를 뽑았다 다시 연결
```

`run.sh`는 Gemini 336L을 자동 탐지합니다. USB 재연결을 지원하기 위해 `/dev/bus/usb` 전체를
read-write bind하고 USB character-device major 189를 허용하지만, `--privileged`는 사용하지
않습니다. 다른 USB 장치도 이 cgroup 범위 안에 들어오므로 신뢰할 수 있는 센서 호스트에서
실행하십시오. 실행 중 카메라를 나중에 연결하려면 자동 탐지 대신 드라이버를 강제로 켭니다.

```bash
USE_ORBBEC_CAMERA=true ./docker/run.sh
```

기본 카메라 토픽은 다음과 같습니다.

| 토픽 | 형식 |
|---|---|
| `/camera/color/image_raw` | `sensor_msgs/msg/Image` |
| `/camera/depth/image_raw` | `sensor_msgs/msg/Image` |
| `/camera/depth/points` | `sensor_msgs/msg/PointCloud2` |
| `/camera/gyro_accel/sample` | `sensor_msgs/msg/Imu` |

카메라 namespace와 스트림은 환경 변수로 바꿀 수 있습니다.

```bash
ORBBEC_CAMERA_NAME=front_camera \
ORBBEC_ENABLE_POINT_CLOUD=true \
ORBBEC_ENABLE_IMU=true \
./docker/run.sh
```

카메라 IMU는 `/livox/imu`로 remap하지 마십시오. 두 센서는 외부 파라미터와 시간 기준이 다르며,
현재 Elevator-LIO는 Livox 내장 IMU만 사용합니다. Gemini 토픽은 향후 perception/fusion용으로
독립 발행됩니다.

## ROS 2 통신과 확인

같은 ROS graph에 참여할 모든 프로세스와 컨테이너는 `ROS_DOMAIN_ID=73`과
`ROS_LOCALHOST_ONLY=0`을 사용해야 합니다. 다른 domain이 필요하면 모든 실행에 같은 값으로
재정의할 수 있습니다.

```bash
ROS_DOMAIN_ID=73 LIVOX_LIDAR_IP=192.168.1.112 ./docker/run.sh

# 별도 터미널: 실행 중인 동일 컨테이너에서 확인
./docker/run.sh exec ros2 topic list
./docker/run.sh exec ros2 topic info -v /livox/lidar
./docker/run.sh exec ros2 topic info -v /camera/depth/image_raw

# 아래 명령에서 주기 값이 계속 출력되어야 실제 센서 데이터가 들어오는 것입니다(Ctrl-C로 종료).
./docker/run.sh exec ros2 topic hz /livox/lidar
./docker/run.sh exec ros2 topic hz /livox/imu
./docker/run.sh exec ros2 topic hz /camera/depth/image_raw
```

호스트의 ROS CLI domain을 바꾼 뒤 이전 graph가 보이면 `ros2 daemon stop`을 실행하고 다시
조회하십시오.

## GUI, 헤드리스, 데이터

```bash
LIVOX_LIDAR_IP=192.168.1.112 USE_RVIZ=false ./docker/run.sh
# 실행 중인 컨테이너로 진입
./docker/run.sh exec
# 별도의 일회성 개발 컨테이너
./docker/run.sh shell
colcon build --merge-install --parallel-workers "${BUILD_JOBS:-4}"
```

`shell`은 `--rm` 개발 컨테이너이므로 그 안에서 만든 build/install 결과는 종료 시 사라집니다.
대신 이 모드에서는 설치된 YAML을 read-only mount하지 않으므로 `/ros2_ws`에서 위와 같이
`--merge-install` 레이아웃으로 다시 빌드할 수 있습니다. 지속할 소스 변경은 호스트 저장소에서
수정한 뒤 이미지를 재빌드하십시오.

- 호스트 `yaml/`은 설치된 LIO 설정 디렉터리에 read-only로 연결됩니다.
- `LIO_CONFIG=my_root.yaml`로 `yaml/` 아래의 다른 root 설정을 선택합니다.
- `PCD/`와 `temp/` 결과는 호스트에 보존됩니다.
- `docker/data/`는 rosbag과 센서 설정용 `/data` 볼륨입니다.
- ROS CLI 상태와 ROS/Orbbec 로그는 기본적으로 호스트 `docker/log/` 아래에 보존됩니다.
- DGX GPU는 LIO 계산이 아니라 RViz/OpenGL 가속에만 선택적으로 사용됩니다.

## Docker Compose

Compose는 USB bus를 항상 전달하므로 먼저 udev 규칙을 설치합니다.

```bash
./docker/run.sh setup-camera
export HOST_UID="$(id -u)" HOST_GID="$(id -g)"
export ROS_DOMAIN_ID=73
export LIVOX_LIDAR_IP=192.168.1.112
export COMPOSE_USE_ORBBEC_CAMERA=true
mkdir -p PCD/Temp temp docker/data docker/log
xhost "+SI:localuser:$(id -un)"
docker compose build
docker compose up
xhost "-SI:localuser:$(id -un)"
```

Compose에서 custom Livox JSON을 쓸 때는 파일을 `docker/data/` 아래에 두고 컨테이너 경로로
지정합니다. 예: `LIVOX_CONFIG_CONTAINER_PATH=/data/MID360_config.json`. Compose 카메라 토글은
자동 탐지 문자열을 받지 않으며 `COMPOSE_USE_ORBBEC_CAMERA=true` 또는 `false`를 사용합니다.

Compose 경로는 GPU/DRI 자동 전달을 하지 않습니다. `docker/run.sh`는 `/dev/dri`와 정상 동작하는
NVIDIA Container Toolkit을 감지해 자동 전달합니다.

## 멀티아키텍처 레지스트리 이미지

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag REGISTRY/elevator-lio:humble \
  --push .
```

Livox-SDK2와 두 ROS 드라이버는 target architecture용으로 빌드되며, upstream 참조는 재현성을
위해 `Dockerfile`에 commit SHA로 고정되어 있습니다.

## Upstream references

- [Livox ROS Driver 2](https://github.com/Livox-SDK/livox_ros_driver2)
- [Livox SDK2](https://github.com/Livox-SDK/Livox-SDK2)
- [OrbbecSDK ROS2 v2.9.3](https://github.com/orbbec/OrbbecSDK_ROS2/releases/tag/v2.9.3)
- [Orbbec ROS2 topics](https://orbbec.github.io/OrbbecSDK_ROS2/en/source/camera_devices/4_application_guide/topics.html)
- [ROS 2 domain ID guidance](https://docs.ros.org/en/humble/Concepts/Intermediate/About-Domain-ID.html)
