# Elevator-LIO Docker (amd64 + DGX Spark arm64)

동일한 `Dockerfile`이 amd64 노트북과 DGX Spark arm64에서 네이티브로 빌드됩니다. 이미지에는
Ubuntu 22.04, ROS 2 Humble Desktop, `/ros2_ws/src`, Livox-SDK2,
`livox_ros_driver2`, OrbbecSDK ROS2 v2.9.3, MicroStrain ROS2 4.8.1,
Elevator-LIO와 RViz2가 포함됩니다. Gemini 336L 최대 3대와 3DM-GX5-AHRS 2대를
같은 컨테이너에서 동시에 실행합니다.

기본 `ROS_DOMAIN_ID`는 충돌 가능성이 낮고 Linux 권장 범위 안에 있는 `73`입니다. 컨테이너는
host network/IPC를 사용하므로 호스트 또는 다른 컨테이너와 통신할 때 포트 매핑은 필요하지
않습니다.

## 빠른 시작: MID-360 + Gemini 336L 3대 + GX5-AHRS 2대

```bash
sudo apt install -y x11-xserver-utils
./docker/run.sh build
./docker/run.sh setup-camera
cp docker/sensors.env.example docker/sensors.env
```

카메라 USB 케이블을 한 번 재연결합니다. 아래 명령으로 카메라 시리얼과 GX5 장치 경로를
확인합니다. 다른 카메라/GX5 드라이버는 중지한 상태에서 조회하십시오.

```bash
USE_LIVOX_DRIVER=false USE_ORBBEC_CAMERA=true USE_GX5_DRIVER=false \
  ./docker/run.sh ros2 run orbbec_camera list_devices_node
ls -l /dev/serial/by-id/
```

`docker/sensors.env`에서 아래 빈 값을 실제 장치 값으로 채웁니다. 예를 들어
`export ORBBEC_SERIAL_NUMBER="${ORBBEC_SERIAL_NUMBER:-}"`의 `:-` 뒤에 실제 시리얼을 넣습니다.

| 설정 | 입력값 |
|---|---|
| `LIVOX_LIDAR_IP` | MID-360의 실제 IP |
| `ORBBEC_SERIAL_NUMBER` | 첫 번째 Gemini 336L 시리얼 |
| `ORBBEC_SERIAL_NUMBER_2` | 두 번째 Gemini 336L 시리얼 |
| `ORBBEC_SERIAL_NUMBER_3` | 세 번째 Gemini 336L 시리얼 |
| `GX5_PORT_1` | 첫 번째 GX5의 `/dev/serial/by-id/...` 전체 경로 |
| `GX5_PORT_2` | 두 번째 GX5의 `/dev/serial/by-id/...` 전체 경로 |

MID-360용 Ethernet NIC에는 LiDAR와 같은 subnet의 주소가 설정되어 있어야 합니다.
이후에는 아래 명령 하나로 모두 실행하고 Ctrl-C로 함께 종료합니다.

```bash
./docker/run.sh
```

로컬 `docker/sensors.env`는 자동으로 읽히며 Git과 이미지에 포함되지 않습니다. 이 파일은
Bash 설정 파일이므로 예제의 기본값 문법을 유지하면 명령 앞의 환경 변수로 덮어쓸 수 있습니다.
설정 파일 없이 실행하면 이전과 같이 Gemini 1대 자동 탐지, GX5 비활성화가 기본입니다.
새 드라이버 추가 후에는 **기존 실행을 Ctrl-C로 종료 → `git pull` → `./docker/run.sh build`
→ `./docker/run.sh`** 순서로 적용합니다. 기존 이미지를 미리 삭제할 필요는 없습니다.

센서 없이 이미지나 LIO만 확인하려면 다음과 같이 드라이버를 끕니다.

```bash
USE_LIVOX_DRIVER=false USE_ORBBEC_CAMERA=false USE_GX5_DRIVER=false ./docker/run.sh
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

## Gemini 336L USB 카메라 3대

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

`ORBBEC_CAMERA_COUNT=3`으로 설정하면 3대가 실행됩니다. 이때 3개의 시리얼을 모두 입력해야
하며 빈 값이나 중복된 시리얼/namespace는 실행 오류로 처리합니다. `ORBBEC_CAMERA_COUNT=1`
또는 `2`도 사용할 수 있습니다. 단일 카메라는 기존 `ORBBEC_USB_PORT` 선택도 지원합니다.
각 카메라는 별도 프로세스와 launch scope를 사용하며, 제조사 예제에 따라 2초 간격으로
초기화한 뒤 함께 스트리밍합니다. 동시 실행이며 하드웨어 트리거 동기화는 설정하지 않습니다.

각 카메라를 USB 3.x 포트에 연결하고 호스트에서 `lsusb -t`로 연결 속도를 확인하십시오.
3대의 RGB/depth 전송은 USB 대역폭을 공유하므로 가능하면 서로 다른 USB 컨트롤러에 분산합니다.
전력 부족이나 공유 허브 대역폭 부족은 드라이버만으로 해결되지 않습니다.

기본 토픽은 아래와 같으며 두 번째·세 번째 카메라는 `/camera` 대신 `/camera_2`, `/camera_3`입니다.

| 토픽 | 형식 |
|---|---|
| `/camera/color/image_raw` | `sensor_msgs/msg/Image` |
| `/camera/depth/image_raw` | `sensor_msgs/msg/Image` |
| `/camera/depth/points` | `sensor_msgs/msg/PointCloud2` |
| `/camera/gyro_accel/sample` | `sensor_msgs/msg/Imu` |

카메라 namespace와 스트림은 환경 변수로 바꿀 수 있습니다.

```bash
ORBBEC_CAMERA_NAME=front_camera \
ORBBEC_CAMERA_NAME_2=left_camera \
ORBBEC_CAMERA_NAME_3=right_camera \
ORBBEC_ENABLE_POINT_CLOUD=true \
ORBBEC_ENABLE_IMU=true \
./docker/run.sh
```

카메라 IMU는 `/livox/imu`로 remap하지 마십시오. 두 센서는 외부 파라미터와 시간 기준이 다르며,
현재 Elevator-LIO는 Livox 내장 IMU만 사용합니다. Gemini 토픽은 독립 발행됩니다.

## 3DM-GX5-AHRS 2대

공식 `LORD-MicroStrain/microstrain_inertial`의 ROS2 4.8.1 드라이버와 메시지, MIP SDK를
commit SHA로 고정하여 소스 빌드합니다. USB 연결을 기준으로 `GX5_PORT_1`, `GX5_PORT_2`를
지정하면 두 드라이버가 실행됩니다. `USE_GX5_DRIVER=false`로 둘 다 끌 수 있습니다.
예제 설정 없이도 포트가 지정된 경우 기본 `auto` 모드가 두 드라이버를 켭니다.

`/dev/ttyACM0`, `/dev/ttyACM1`은 연결 순서에 따라 바뀌므로 `/dev/serial/by-id/...`를 사용합니다.
각 장치를 한 대씩 연결하여 경로를 확인하면 물리 장치와 토픽의 대응을 고정할 수 있습니다.
`/dev/microstrain_main` 같은 공용 symlink는 두 대를 구별하지 못하므로 사용하지 마십시오.
USB-serial 어댑터를 사용한다면 어댑터의 고유 경로를 사용하고 아래 YAML의 baudrate를
실제 장치 설정과 맞추십시오. 어댑터에 고유 ID가 없으면 고정 USB 포트의 `/dev/serial/by-path/`
경로를 사용할 수 있습니다.

`run.sh`는 지정한 장치를 `/dev/gx5_1`, `/dev/gx5_2`로 전달하고 장치 소유 그룹을 컨테이너에
추가합니다. 호스트 전체 `/dev`를 전달하거나 privileged 모드를 사용하지 않습니다.
GX5 USB를 재연결한 경우에는 Ctrl-C 후 `./docker/run.sh`로 컨테이너를 다시 시작합니다.

| 토픽 (두 번째 장치는 `gx5_2`) | 형식 / 기본 주기 |
|---|---|
| `/gx5_1/imu/data_raw` | `sensor_msgs/msg/Imu`, 100 Hz |
| `/gx5_1/ekf/imu/data` | `sensor_msgs/msg/Imu`, 장치 AHRS 자세 포함, 100 Hz |
| `/gx5_1/imu/mag` | `sensor_msgs/msg/MagneticField`, 100 Hz |
| `/gx5_1/ekf/status` | 드라이버의 AHRS 상태 |

프레임 이름도 `gx5_1_link`, `gx5_2_link`로 구분합니다. 주기와 baudrate는 호스트의
`yaml/sensors/gx5_ahrs.yaml`에서 수정 후 실행을 재시작하면 반영됩니다. 공식 일반 노드가
시작 시 장치를 configure/activate하므로 별도의 lifecycle 명령은 필요하지 않습니다.
AHRS 내부 필터가 초기화될 때까지 자세값과 상태를 확인하십시오. 장치 설정은 비휘발성 메모리에
저장하지 않습니다. 두 GX5 토픽의 LIO 입력 연결, 센서 융합, 장착 위치 TF는 추가하지 않습니다.

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
./docker/run.sh exec ros2 topic hz /camera_2/depth/image_raw
./docker/run.sh exec ros2 topic hz /camera_3/depth/image_raw
./docker/run.sh exec ros2 topic hz /gx5_1/ekf/imu/data
./docker/run.sh exec ros2 topic hz /gx5_2/ekf/imu/data
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
source docker/sensors.env
export HOST_UID="$(id -u)" HOST_GID="$(id -g)"
export ROS_DOMAIN_ID=73
export LIVOX_LIDAR_IP=192.168.1.112
export COMPOSE_USE_ORBBEC_CAMERA=true
export GX5_GID_1="$(stat -Lc '%g' "$GX5_PORT_1")"
export GX5_GID_2="$(stat -Lc '%g' "$GX5_PORT_2")"
mkdir -p PCD/Temp temp docker/data docker/log
xhost "+SI:localuser:$(id -un)"
docker compose build
docker compose -f compose.yaml -f docker/compose.gx5.yaml up
xhost "-SI:localuser:$(id -un)"
```

Compose에서 custom Livox JSON을 쓸 때는 파일을 `docker/data/` 아래에 두고 컨테이너 경로로
지정합니다. 예: `LIVOX_CONFIG_CONTAINER_PATH=/data/MID360_config.json`. Compose 카메라 토글은
자동 탐지 문자열을 받지 않으며 `COMPOSE_USE_ORBBEC_CAMERA=true` 또는 `false`를 사용합니다.

Compose 경로는 GPU/DRI 자동 전달을 하지 않습니다. `docker/run.sh`는 `/dev/dri`와 정상 동작하는
NVIDIA Container Toolkit을 감지해 자동 전달합니다.
GX5 없이 사용하려면 기존 `docker compose up`을 사용합니다. 두 포트가 지정된 경우에만
`docker/compose.gx5.yaml` overlay를 추가하고, 서로 다른 장치 경로인지 확인하십시오.

## 멀티아키텍처 레지스트리 이미지

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag REGISTRY/elevator-lio:humble \
  --push .
```

Livox-SDK2와 세 종류의 ROS 드라이버는 target architecture용으로 빌드되며, upstream 참조는 재현성을
위해 `Dockerfile`에 commit SHA로 고정되어 있습니다.

이번 3-camera/2-AHRS 구성은 실제 Docker 빌드와 센서 스트리밍 검증이 필요합니다.
변경 작업 환경에는 Docker daemon과 센서가 없어 해당 검증은 수행하지 못했습니다.

## Upstream references

- [Livox ROS Driver 2](https://github.com/Livox-SDK/livox_ros_driver2)
- [Livox SDK2](https://github.com/Livox-SDK/Livox-SDK2)
- [OrbbecSDK ROS2 v2.9.3](https://github.com/orbbec/OrbbecSDK_ROS2/releases/tag/v2.9.3)
- [Orbbec 다중 카메라 공식 예제](https://github.com/orbbec/OrbbecSDK_ROS2/blob/v2.9.3/orbbec_camera/launch/multi_camera.launch.py)
- [MicroStrain ROS2 4.8.1](https://github.com/LORD-MicroStrain/microstrain_inertial/tree/ros2-4.8.1)
- [Orbbec ROS2 topics](https://orbbec.github.io/OrbbecSDK_ROS2/en/source/camera_devices/4_application_guide/topics.html)
- [ROS 2 domain ID guidance](https://docs.ros.org/en/humble/Concepts/Intermediate/About-Domain-ID.html)
