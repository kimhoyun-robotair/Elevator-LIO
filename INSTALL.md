# Elevator-LIO ROS 2 Humble 설치 및 실행

이 문서는 Ubuntu 22.04와 ROS 2 Humble 환경에서 다음 워크스페이스 구성을 기준으로 한다.

```text
/home/kimhoyun/elevator_ws/
└── src/
    ├── Elevator-LIO/       # ROS 패키지 이름: lio
    ├── livox_ros_driver2/
    └── Livox-SDK2/         # CMake 프로젝트 이름: livox_sdk2
```

현재 사용하는 SOSLAB FLASH LiDAR는 Livox 드라이버로 구동하지 않는다. 그러나 Elevator-LIO의 ROS 2 소스가 `livox_ros_driver2/msg/CustomMsg`를 컴파일 시 참조하므로 `livox_ros_driver2`는 빌드 의존성으로 필요하다.

## 1. 사전 준비

Livox 소스가 없다면 워크스페이스의 `src` 아래에 준비한다.

```bash
cd /home/kimhoyun/elevator_ws/src
git clone https://github.com/Livox-SDK/livox_ros_driver2.git
git clone https://github.com/Livox-SDK/Livox-SDK2.git
```

이미 두 디렉터리가 존재한다면 clone 명령은 실행하지 않는다.

Livox SDK2를 먼저 빌드하여 시스템에 설치한다. 아래 명령은 컴파일 작업을 최대 4개로 제한한다.

```bash
cd /home/kimhoyun/elevator_ws/src/Livox-SDK2
mkdir -p build
cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
cmake --build . --parallel 4
sudo cmake --install .
```

ROS 2 Humble용 드라이버 manifest를 활성화한다. Livox 저장소의 `package.xml`은 빌드 스크립트가 생성하는 파일이라 새 clone에는 없을 수 있다.

```bash
cd /home/kimhoyun/elevator_ws/src/livox_ros_driver2
cp package_ROS2.xml package.xml
```

그다음 ROS 환경을 불러오고 워크스페이스 의존성을 설치한다.

```bash
cd /home/kimhoyun/elevator_ws
source /opt/ros/humble/setup.bash

rosdep update
rosdep install --from-paths src --ignore-src -r -y
```

## 2. Livox 드라이버 빌드

### 이 워크스페이스에서 `build.sh humble`을 사용하지 않는 이유

`livox_ros_driver2/build.sh`는 드라이버만 빌드하지 않고 상위 워크스페이스 전체에 대해 `colcon build`를 실행한다. 또한 빌드 중 `ROS_VERSION`을 표준값 `2`가 아닌 `ROS2`로 설정한다. 이 때문에 같은 워크스페이스에 있는 Elevator-LIO가 다음 오류로 실패한다.

```text
Cannot determine ROS version. Source a ROS 1 or ROS 2 setup file first.
```

따라서 `build.sh humble` 대신 워크스페이스 루트에서 드라이버와 LIO를 나누어 빌드한다.

### 드라이버 및 SDK 빌드

아래 예시는 동시에 빌드하는 패키지를 1개로 제한하고, 각 패키지 내부 컴파일을 최대 4개 작업으로 제한한다.

```bash
cd /home/kimhoyun/elevator_ws
source /opt/ros/humble/setup.bash

export ROS_VERSION=2
export ROS_DISTRO=humble
export CMAKE_BUILD_PARALLEL_LEVEL=4

colcon build \
  --packages-select livox_ros_driver2 \
  --parallel-workers 1 \
  --symlink-install \
  --cmake-clean-cache \
  --cmake-args \
    -DROS_EDITION=ROS2 \
    -DDISTRO_ROS=humble \
    -DCMAKE_BUILD_TYPE=Release
```

`-DDISTRO_ROS=humble`을 생략하면 드라이버가 잘못된 메시지 생성 분기를 선택하여 다음 오류가 발생할 수 있다.

```text
LIVOX_INTERFACES_INCLUDE_DIRECTORIES-NOTFOUND
```

빌드에 성공하면 환경을 불러오고 패키지 검색 결과를 확인한다.

```bash
source /home/kimhoyun/elevator_ws/install/setup.bash
ros2 pkg prefix livox_ros_driver2
```

정상적인 경우 다음 경로가 출력된다.

```text
/home/kimhoyun/elevator_ws/install/livox_ros_driver2
```

메모리가 부족하면 `CMAKE_BUILD_PARALLEL_LEVEL=4`를 `2` 또는 `1`로 낮춘다.

## 3. Elevator-LIO 설정 확인

`yaml/root_config.yaml`에서 SOSLAB 센서 설정과 mapping runtime을 선택한다.

```yaml
sensor_config: "sensors/soslab.yaml"
runtime_config: "runtime/mapping.yaml"
logging_config: "logging/default.yaml"
```

`yaml/sensors/soslab.yaml`의 주요 설정은 다음과 같다.

```yaml
lidar_type: 2

offset:
  imu_t_lidar: [0.390654, 0.0, 0.107688]
  imu_R_lidar:
    - [0.974368445733107, 0.0, -0.224958067113962]
    - [0.0, 1.0, 0.0]
    - [0.224958067113962, 0.0, 0.974368445733107]
  lidar_t_body: [-0.405541089332131, 0.0, -0.019970125770968]
  lidar_R_body:
    - [0.974368445733107, 0.0, 0.224958067113962]
    - [0.0, 1.0, 0.0]
    - [-0.224958067113962, 0.0, 0.974368445733107]

topic_sub:
  lidar_topic_name: "/mlx/pointcloud"
  imu_topic_name: "/vectornav/imu"
  wheel_topic_name: "/odom"
  elevator_flag_topic_name: "/LIO/set_elevator_flag"
```

`lidar_type: 2` 파서는 `sensor_msgs/msg/PointCloud2`의 `x`, `y`, `z` 필드를 필수로 사용하고 `intensity`를 선택적으로 사용한다. SOSLAB 메시지에는 점별 `t`, `time`, `timestamp`가 없으므로 모든 점을 동일한 프레임 시각으로 처리한다.

현재 `wheel_topic_name: "/odom"`으로 되어 있지만 Elevator-LIO는 이 입력에서 `nav_msgs/msg/Odometry`가 아니라 `lio/msg/WheelInfo`를 기대한다. `runtime/mapping.yaml`의 `wheel.wheel_enable`이 `false`인 동안에는 추정에 사용되지 않는다. `/odom`을 휠 입력으로 사용하려면 별도 메시지 변환 또는 코드 수정이 필요하다.

## 4. Elevator-LIO 빌드

Livox 드라이버가 설치된 workspace overlay를 불러온 뒤 LIO만 빌드한다. 아래 명령은 LIO 내부 컴파일을 최대 4개 작업으로 제한한다.

```bash
cd /home/kimhoyun/elevator_ws

source /opt/ros/humble/setup.bash
source /home/kimhoyun/elevator_ws/install/setup.bash

export ROS_VERSION=2
export ROS_DISTRO=humble
export CMAKE_BUILD_PARALLEL_LEVEL=4

colcon build \
  --packages-select lio \
  --executor sequential \
  --symlink-install \
  --cmake-clean-cache \
  --cmake-args -DCMAKE_BUILD_TYPE=Release
```

빌드가 끝나면 새 터미널을 열 때마다 다음 환경을 불러온다.

```bash
source /opt/ros/humble/setup.bash
source /home/kimhoyun/elevator_ws/install/setup.bash
```

패키지가 정상적으로 설치되었는지 확인한다.

```bash
ros2 pkg prefix lio
```

## 5. 센서 입력 확인

LiDAR와 IMU 드라이버를 실행한 다음 토픽 타입과 주기를 확인한다.

```bash
ros2 topic info /mlx/pointcloud
ros2 topic info /vectornav/imu

ros2 topic hz /mlx/pointcloud
ros2 topic hz /vectornav/imu
```

필요한 메시지 타입은 다음과 같다.

```text
/mlx/pointcloud  -> sensor_msgs/msg/PointCloud2
/vectornav/imu   -> sensor_msgs/msg/Imu
```

각 메시지를 한 번 확인한다.

```bash
ros2 topic echo /mlx/pointcloud --once
ros2 topic echo /vectornav/imu --once
```

LiDAR와 IMU의 `header.stamp`는 반드시 같은 clock 기준이어야 한다.

```bash
ros2 topic echo /mlx/pointcloud --field header.stamp --once
ros2 topic echo /vectornav/imu --field header.stamp --once
```

두 timestamp의 기준이나 차이가 비정상적이면 LIO를 실행하기 전에 센서 드라이버의 시간 동기 설정을 수정한다.

## 6. 실행

초기 약 200개의 IMU 샘플로 바이어스와 중력 방향을 추정하므로, 시작할 때 플랫폼을 정지 상태로 유지한다.

RViz2와 함께 실행한다.

```bash
cd /home/kimhoyun/elevator_ws
source /opt/ros/humble/setup.bash
source install/setup.bash

ros2 launch lio start_ros2.launch.py
```

RViz2 없이 로그만 확인하려면 다음과 같이 실행한다.

```bash
ros2 launch lio start_ros2.launch.py use_rviz:=false
```

기본값이 아닌 root 설정을 명시하려면 다음 인자를 사용한다. 경로는 패키지의 `yaml/` 디렉터리를 기준으로 해석된다.

```bash
ros2 launch lio start_ros2.launch.py config_path:=root_config.yaml
```

## 7. 정상 동작 확인

```bash
ros2 node list
ros2 topic list | grep /LIO
ros2 topic hz /LIO/odom_imu
ros2 topic echo /LIO/odom_imu --once
ros2 run tf2_ros tf2_echo world base_link
```

주요 출력 토픽은 다음과 같다.

| 토픽 | 내용 |
| --- | --- |
| `/LIO/odom_imu` | IMU 중심의 추정 odometry |
| `/LIO/odom_vehicle` | `base_link` 기준 차량 odometry |
| `/LIO/clouds_lidar` | 현재 프레임의 처리된 점군 |
| `/LIO/global_map` | 누적 전체 점군 지도 |
| `/LIO/ikdtree` | scan matching에 사용하는 다운샘플된 내부 지도 |

RViz2의 Fixed Frame은 `world`로 설정한다.

## 8. 누적 전체 지도 표시

`yaml/runtime/mapping.yaml`에서 다음 옵션을 활성화한다.

```yaml
pcd_save:
  global_map_save_enable: true

pub:
  global_map_pub_enable: true
```

설정 변경 후 LIO를 재시작하고 RViz2에서 `PointCloud2` display를 추가하여 `/LIO/global_map`을 선택한다.

```bash
ros2 topic hz /LIO/global_map
ros2 topic echo /LIO/global_map --field width --once
```

전체 지도 발행은 포인트 수가 증가할수록 CPU, 메모리 및 RViz 렌더링 부하가 커진다. 실운용에서 시각화가 필요하지 않다면 `global_map_pub_enable`을 다시 `false`로 설정한다.

## 9. 현재 기능 범위

현재 Elevator-LIO에는 재방문 장소 검출, pose graph 또는 GTSAM/iSAM2 기반 전역 loop closure가 없다. 시작 지점으로 돌아오더라도 누적 drift를 전역 최적화하지 않는다.

`runtime/relocation.yaml`은 기존 PCD 지도 안에서 위치를 추정하는 모드이며 loop closure가 아니다. `elevator.exit_icp_z` 또한 엘리베이터에서 나온 직후 z축만 제한적으로 보정하므로 일반적인 6-DoF loop closure와 다르다.

## 10. 자주 발생하는 빌드 오류

### `livox_ros_driver2Config.cmake`를 찾지 못함

```text
Could not find livox_ros_driver2Config.cmake
```

드라이버가 아직 빌드되지 않았거나 현재 셸에서 overlay를 불러오지 않은 상태다.

```bash
source /opt/ros/humble/setup.bash
source /home/kimhoyun/elevator_ws/install/setup.bash
ros2 pkg prefix livox_ros_driver2
```

### ROS 버전을 결정하지 못함

```text
Cannot determine ROS version
```

ROS 환경이 없거나 `livox_ros_driver2/build.sh`가 `ROS_VERSION=ROS2`를 전달한 경우다.

```bash
source /opt/ros/humble/setup.bash
export ROS_VERSION=2
export ROS_DISTRO=humble
```

그 뒤 워크스페이스 루트에서 이 문서의 분리 빌드 명령을 사용한다.

### `LIVOX_INTERFACES_INCLUDE_DIRECTORIES-NOTFOUND`

Livox 드라이버 빌드에 Humble 배포판 인자가 전달되지 않은 경우다. 캐시를 지우면서 다음 CMake 인자를 전달한다.

```text
--cmake-clean-cache
-DROS_EDITION=ROS2
-DDISTRO_ROS=humble
```

### 컴파일 중 메모리 부족

각 패키지 내부 컴파일 작업 수를 낮춘다.

```bash
export CMAKE_BUILD_PARALLEL_LEVEL=2
```

여전히 부족하면 `1`로 낮추고 `--parallel-workers 1` 또는 `--executor sequential`을 유지한다.
