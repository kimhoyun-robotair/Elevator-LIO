# Elevator-LIO Docker (amd64 + DGX Spark arm64)

이 구성은 동일한 `Dockerfile`을 Ubuntu amd64 노트북과 DGX Spark의 arm64에서 각각 네이티브로
빌드합니다. 이미지에는 Ubuntu 22.04 기반 ROS 2 Humble Desktop, `/ros2_ws/src`,
Livox-SDK2, `livox_ros_driver2`, Elevator-LIO, RViz2와 빌드 도구가 모두 들어갑니다.
Elevator-LIO 계산 자체는 CPU 기반이며, DGX GPU 전달은 RViz의 OpenGL 가속에만 선택적으로
사용됩니다.

## 빠른 시작

호스트에 Docker Engine이 설치되어 있어야 합니다. GUI를 사용할 때는 `xhost`도 필요합니다.

```bash
sudo apt install -y x11-xserver-utils
./docker/run.sh build
./docker/run.sh
```

스크립트는 현재 호스트 아키텍처를 자동으로 사용하므로 두 플랫폼에서 명령이 같습니다.
Docker는 amd64 노트북에서는 `linux/amd64`, DGX Spark에서는 `linux/arm64` 이미지를 빌드합니다.

헤드리스 실행과 ROS 셸:

```bash
USE_RVIZ=false ./docker/run.sh
./docker/run.sh shell
```

다른 호스트 ROS 2 프로세스와 통신하려면 같은 DDS domain을 사용합니다. 컨테이너는 host network와
host IPC를 사용하므로 multicast discovery와 LiDAR UDP 수신이 가능합니다.

```bash
ROS_DOMAIN_ID=7 ./docker/run.sh
ROS_DOMAIN_ID=7 ./docker/run.sh ros2 topic list
```

## Livox MID-360을 같은 컨테이너에서 실행

먼저 공식 설정을 호스트의 지속 디렉터리로 복사합니다.

```bash
./docker/run.sh shell
cp /ros2_ws/install/share/livox_ros_driver2/config/MID360_config.json /data/
exit
```

`docker/data/MID360_config.json`의 `host_ip`/data IP와 LiDAR IP를 실제 유선 NIC 구성에 맞게
수정한 다음 실행합니다. host network를 사용하므로 여기의 host IP는 Docker bridge 주소가 아니라
호스트의 LiDAR 연결 NIC 주소입니다.

```bash
USE_LIVOX_DRIVER=true \
LIVOX_CONFIG_FILE=./docker/data/MID360_config.json \
./docker/run.sh
```

이미 호스트나 다른 컨테이너에서 드라이버를 실행 중이면 `USE_LIVOX_DRIVER=false`(기본값)를
유지하고 `/livox/lidar`, `/livox/imu` 토픽만 같은 `ROS_DOMAIN_ID`로 전달하면 됩니다.

## 설정과 결과 파일

- 호스트 `yaml/`은 컨테이너의 설치된 `lio` 설정 디렉터리에 read-only로 연결됩니다.
- `LIO_CONFIG=my_root.yaml`로 `yaml/` 아래의 다른 root 설정을 선택할 수 있습니다.
- `PCD/`와 `temp/`는 호스트에 그대로 보존됩니다.
- `docker/data/`는 rosbag, Livox JSON 등 큰 데이터를 넣는 `/data` 볼륨입니다.

예:

```bash
LIO_CONFIG=root_config.yaml ./docker/run.sh
USE_RVIZ=false ./docker/run.sh ros2 bag play /data/my_bag
```

bag 재생과 LIO를 동시에 실행하려면 첫 터미널에서 LIO를 실행하고, 두 번째 터미널에서 같은
`ROS_DOMAIN_ID`로 `ros2 bag play`를 실행합니다. 두 임시 컨테이너 모두 host network를 사용합니다.

## Docker Compose

스크립트 없이 Compose로도 실행할 수 있습니다.

```bash
export HOST_UID="$(id -u)" HOST_GID="$(id -g)"
mkdir -p PCD/Temp temp docker/data
xhost "+SI:localuser:$(id -un)"
docker compose build
docker compose up
xhost "-SI:localuser:$(id -un)"
```

Compose 경로는 범용성을 위해 GPU/DRI 자동 전달을 하지 않습니다. `docker/run.sh`는 `/dev/dri`와
정상 동작하는 NVIDIA Container Toolkit을 감지해 자동 전달합니다. DGX에서 이 자동 전달을 끄려면
`LIO_NVIDIA_GPU=0`을 설정합니다.

## 멀티아키텍처 레지스트리 이미지 만들기

각 호스트에서 네이티브 빌드하는 대신 하나의 태그로 두 아키텍처를 배포하려면 buildx builder와
쓰기 가능한 registry를 준비한 후 다음처럼 push합니다.

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag REGISTRY/elevator-lio:humble \
  --push .
```

빌드는 Livox-SDK2와 ROS 드라이버를 각 target architecture에서 소스 컴파일하며, 기본 참조 commit은
재현성을 위해 `Dockerfile`에 고정되어 있습니다.

## English quick reference

The same image definition builds natively on amd64 Ubuntu laptops and arm64 DGX Spark. It uses host
networking/IPC for ROS 2 DDS and LiDAR UDP, mounts X11 for RViz2, persists `PCD/` and `temp/`, and includes
the complete `/ros2_ws/src` workspace. Run `./docker/run.sh build`, then `./docker/run.sh`; use
`USE_RVIZ=false` for headless operation and `USE_LIVOX_DRIVER=true LIVOX_CONFIG_FILE=...` to start the
MID-360 driver in the same container.
