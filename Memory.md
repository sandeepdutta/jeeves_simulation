# Jeeves Simulation — Project Memory
*Updated 2026-06-02*

---

## Project Overview

- **Location**: `~/jeeves_simulation/` (WSL2 Ubuntu 22.04 on Windows 11)
- **ROS 2**: Humble
- **Gazebo**: Harmonic (migrated from Fortress)
- **Robot**: `jeeves_production` — differential drive, two Orbbec Gemini 336 depth cameras, IMU, LiDAR
- **Main ROS package**: `jeeves_production_description`
- **Docker image**: `sandeepdutta/jeeves_humble_final:latest`

---

## Directory Structure (key paths)

```
~/jeeves_simulation/
├── docker/
│   ├── Dockerfile.base        # Base image definition
│   ├── Dockerfile.final       # Final image definition
│   ├── docker_run.sh          # Container launch script
│   ├── docker_build.sh        # Build script
│   └── entrypoint.sh
├── ros_ws/src/jeeves_production_description/
│   ├── urdf/                  # Robot URDF/xacro files
│   ├── launch/                # Launch files
│   └── config/                # EKF, world files
├── openrobotics/              # Fuel model downloads (Refrigerator, Oven, Armchair, DiningChair, DiningTable)
├── scripts/
│   └── fix_openrobotics_models.py   # Re-run after re-downloading models
└── aws-robomaker-small-house-world/ # Cloned but NOT used in current world
```

---

## Docker Setup

### Multi-platform support

Both `docker_run.sh` and `docker_build.sh` accept an optional platform argument:

```bash
# Build
./docker_build.sh           # auto-detects arch (arm64 on Apple Silicon, amd64 on x86)
./docker_build.sh amd64     # force AMD64 (Rosetta emulation on Apple Silicon)
./docker_build.sh arm64     # force ARM64

# Run
./docker_run.sh             # NVIDIA/WSL2 mode (default)
./docker_run.sh parallels   # Parallels VM / no-GPU mode
```

**Dockerfile does not change between platforms** — same image, different runtime flags.

**Apple Silicon note**: `gz-harmonic` and `ros-humble-moveit*` may lack ARM64 apt packages. If `arm64` build fails on those, use `./docker_build.sh amd64` (Rosetta 2 emulation — slower but fully compatible).

### Platform differences (`docker_run.sh`)

| Setting | NVIDIA/WSL2 | Parallels |
|---|---|---|
| Container name | `jeeves_simulation_humble` | `jeeves_simulation_humble_parallels` |
| `--gpus all` | ✓ | ✗ |
| `NVIDIA_DRIVER_CAPABILITIES` | `all` | — |
| `/usr/lib/wsl` mount | ✓ | ✗ |
| Vulkan ICD mount | ✓ | ✗ |
| `MESA_LOADER_DRIVER_OVERRIDE` | `d3d12` | — |
| `MESA_GL_VERSION_OVERRIDE` | `4.5COMPAT` | — |
| `LIBGL_ALWAYS_SOFTWARE` | — | `1` |

### `docker_run.sh` common flags (both platforms)
- `--env GZ_SIM_RESOURCE_PATH=/home/admin/openrobotics`
- X11 socket + xauth mounted for display
- `~/.gz` mounted for Gazebo cache persistence
- `mkdir -p "${HOME}/.gz/sim"` — prevents root-owned dir on first run

### `Dockerfile.base` key packages installed
- `gz-harmonic`, `ros-humble-ros-gzharmonic`
- `ros-humble-gz-ros2-control`
- `ros-humble-robot-localization` — EKF
- `vulkan-tools mesa-vulkan-drivers libvulkan1`
- `ros-humble-nav2-bringup`, `ros-humble-xacro`

### GPU rendering status (WSL2)
- **Works**: Mesa D3D12 (`GL_RENDERER = D3D12 (NVIDIA GeForce RTX 3080)`)
- **Broken**: PBR/HLMS PBS materials render transparent — D3D12 Mesa limitation
- **Workaround**: All models use `<ambient>/<diffuse>/<emissive>` (no `<pbr>`)
- `nvidia-smi` shows `ruby` (gz sim) using GPU — rendering IS GPU-accelerated
- To get full PBR: need native Linux or dual-boot (no VM on Windows 11 solves this)

---

## Gazebo Harmonic Migration (from Fortress)

### Renamed files (`_fortress` → `_harmonic`)
All plugin xacros and world/config files renamed. Key files:
- `jeeves_production_diff_drive_harmonic.xacro`
- `jeeves_production_camera_harmonic.xacro`
- `jeeves_production_imu_harmonic.xacro`
- `jeeves_production_lidar_harmonic.xacro`
- `jeeves_production_harmonic.gazebo`
- `config/jeeves_harmonic.world`

### Plugin name changes (Fortress → Harmonic)
- `ignition-gazebo-*-system` → `gz-sim-*-system`
- `ignition::gazebo::systems::*` → `gz::sim::systems::*`

### Bridge message types
- `ignition.msgs.*` → `gz.msgs.*`

### Environment variable
- `IGN_GAZEBO_RESOURCE_PATH` → `GZ_SIM_RESOURCE_PATH`

### `jeeves_production.xacro`
- Arg renamed: `use_fortress` → `use_harmonic`

---

## Robot Xacro Configuration

### `jeeves_production_diff_drive_harmonic.xacro`
```xml
<plugin filename="gz-sim-diff-drive-system" name="gz::sim::systems::DiffDrive">
  <left_joint>Left_wheel_joint</left_joint>   <!-- lowercase 'w' and 'j' — matches URDF -->
  <right_joint>Right_Wheel_Joint</right_joint>
  <topic>/cmd_vel</topic>                      <!-- absolute paths — required in Harmonic -->
  <odom_topic>/odom</odom_topic>
  <tf_topic>/gz/diff_drive_tf</tf_topic>       <!-- private — EKF publishes odom→base_link instead -->
  <wheel_separation>0.36850000000000194</wheel_separation>
  <wheel_radius>0.08565002820511592</wheel_radius>
</plugin>
<plugin filename="gz-sim-joint-state-publisher-system" name="gz::sim::systems::JointStatePublisher">
  <topic>/joint_states</topic>
</plugin>
```
**Important**: `Left_wheel_joint` is lowercase 'w' and 'j' — the URDF has inconsistent casing.

### `jeeves_production_camera_harmonic.xacro`
- Sensors attached to `Front_Camera_color_frame` / `Back_Camera_color_frame` (not optical frame — gz-sim cameras look along +X of the link, not +Z)
- `<optical_frame_id>Front_Camera_color_optical_frame</optical_frame_id>` sets published frame_id
- Resolution: 376×240 (matched to Gemini 336 H=90°, V≈65° FOV)
- Update rate: 5 Hz

### Camera FOV derivation
- Gemini 336: H=90° (π/2 rad), V=65°
- width/height = tan(45°)/tan(32.5°) = 1.5697 → 376×240

---

## Simulation Launch (`jeeves_sim.launch.py`)

### Key topic remappings (bridge)
| Gazebo topic | ROS topic | Direction |
|---|---|---|
| `/cmd_vel` | `/cmd_vel` | ROS→Gz |
| `/odom` | `/diffbot_base_controller/odom` | Gz→ROS |
| `/imu` | `/ob_front/camera/imu` | Gz→ROS |
| `/joint_states` | `/joint_states` | Gz→ROS |
| `/world/jeeves_world/clock` | `/clock` | Gz→ROS |

**Note**: `/tf` is NOT bridged — the diff drive uses `/gz/diff_drive_tf` (private). The EKF generates `odom→base_link` TF.

### `use_sim_time`
- `robot_state_publisher`: `True`
- EKF: `True` (via `offline_slam: 'true'`)
- This is required for RViz2 TF lookups to work

### EKF in simulation
```python
ekf = IncludeLaunchDescription(
    ekf.launch.py,
    launch_arguments={
        'publish_map_odom_tf':       'False',
        'publish_odom_base_link_tf': 'True',
        'offline_slam':              'true',   # → use_sim_time: true
    }
)
```

### GZ_SIM_RESOURCE_PATH (built in launch)
```python
gz_model_candidates = [os.path.join(home, 'openrobotics')]
```

---

## EKF Configuration (`config/ekf.yaml`)

- **Node**: `ekf_filter_odom_to_baselink_node`
- **odom0**: `/diffbot_base_controller/odom` — wheel odometry
- **imu0**: `/ob_front/camera/imu` — IMU (yaw rate + x-accel)
- `two_d_mode: true`, `odom0_relative: true`
- `publish_tf: true` — generates `odom→base_link`
- **Same config used on hardware and simulation** — topic names matched by remapping in sim

---

## World File (`config/jeeves_harmonic.world`)

### House layout
- 10m × 8m box-primitive house
- West half: living room
- East half: kitchen + dining

### Kitchen counter
- `counter_north_left`: x=1.1→2.47 (split to accommodate oven)
- `counter_north_right`: x=3.53→4.9
- Gap at x≈2.5→3.5 for the OpenRobotics Oven

### Models in world
All from `~/openrobotics/`:
| Model | URI | Location |
|---|---|---|
| Refrigerator | `model://Refrigerator` | x=0.5, y=3.7 — north wall, light blue |
| Oven | `model://Oven` | x=3.0, y=3.45 — counter gap |
| DiningTable | `model://DiningTable` | x=2.5, y=-0.5 |
| DiningChair ×4 | `model://DiningChair` | around dining table |
| Armchair ×3 | `model://Armchair` | living room |

### Lighting
- Directional sun: `diffuse 0.25`
- 5 point lights: living room north/south, corridor, kitchen north/south

---

## OpenRobotics Models (`~/openrobotics/`)

### Setup script
```bash
python3 ~/jeeves_simulation/scripts/fix_openrobotics_models.py
```
**Run this after every re-download.** It:
1. Strips COLLADA FFP material references → `_clean.dae`
2. Updates `model.sdf` to use `_clean.dae`
3. Replaces `<pbr>` with `<ambient>/<diffuse>/<emissive>` (PBR = transparent on D3D12)
4. Removes `<inertial>` blocks (cause Harmonic validation errors)
5. Removes `<meta>` tags (break SDF parsing)

### Model colors (defined in script `MODEL_COLORS`)
| Model | Color |
|---|---|
| Refrigerator | Light blue `0.6 0.78 0.9` |
| Oven | Grey `0.75 0.75 0.75` |
| Armchair | Warm brown `0.55 0.38 0.22` |
| DiningChair | Oak `0.71 0.52 0.32` |
| DiningTable | Oak `0.71 0.52 0.32` (wood) / dark `0.1 0.1 0.1` (legs) |

### Why PBR is broken
Ogre2 HLMS PBS materials render as transparent via D3D12 Mesa backend. The `<ambient>/<diffuse>` path uses a different (legacy) render path that does work.

---

## Hardware Launch (`jeeves_drive_hardware.launch.py`)

- EKF launched with `publish_odom_base_link_tf: True`, `publish_map_odom_tf: False`
- EKF config identical to simulation
- Odrive robot driver included
- micro-ROS agent for base ESP32 (`/dev/ttyUSB0`)
- M5Stick TCP bridge (port 8888)
- VL53L5CX ToF range sensor (8 zones, I2C adapter 7)
- `range_sensor` remaps `odom` → `odometry/filtered_local`

---

## Known Issues & Workarounds

| Issue | Workaround |
|---|---|
| PBR materials transparent (D3D12 Mesa) | Use `<ambient>/<diffuse>/<emissive>` only |
| AWS RoboMaker models use Ogre1 FFP | Strip materials with fix script → `_clean.dae` |
| Gazebo Fuel URI `app.gazebosim.org` not recognised by gz-fuel client | Download manually, place in `~/openrobotics/`, use `model://` |
| `Left_wheel_joint` casing | Must be lowercase — URDF inconsistency, diff drive plugin must match exactly |
| Inertia error on model load | Remove `<inertial>` from static models via fix script |
| `XDG_RUNTIME_DIR not set` | Harmless warning, ignore |
| ODE trimesh overflow | Harmless physics warning from mesh collisions, ignore |

---

## Useful Commands

```bash
# Launch simulation
ros2 launch jeeves_production_description jeeves_sim.launch.py

# Drive robot (keyboard)
ros2 run teleop_twist_keyboard teleop_twist_keyboard

# Check odom→base_link TF
ros2 run tf2_ros tf2_echo odom base_link

# View full TF tree
ros2 run tf2_tools view_frames

# Check GPU usage
watch -n1 nvidia-smi

# Fix OpenRobotics models after re-download
python3 ~/jeeves_simulation/scripts/fix_openrobotics_models.py

# Run RViz2 with sim time
rviz2 --ros-args -p use_sim_time:=true
```

---

## Computer Migration Checklist

### Common steps (all platforms)
- [ ] Copy `~/jeeves_simulation/` (entire directory)
- [ ] Copy `~/openrobotics/` (downloaded Fuel models)
- [ ] Install Docker
- [ ] Run `python3 ~/jeeves_simulation/scripts/fix_openrobotics_models.py` inside container (regenerates `_clean.dae`)
- [ ] Rebuild ROS workspace: `colcon build` in `~/jeeves_simulation/ros_ws/`

### Windows 11 + WSL2 + NVIDIA
- [ ] Install WSL2 + Ubuntu 22.04
- [ ] Install NVIDIA driver on Windows (includes WSL2 GPU support)
- [ ] Install Docker Desktop with WSL2 backend
- [ ] `./docker_build.sh` (auto-detects amd64) OR pull `sandeepdutta/jeeves_humble_final:latest`
- [ ] `./docker_run.sh` (NVIDIA mode)
- [ ] Verify GPU: inside container `glxinfo | grep renderer` → `D3D12 (NVIDIA GeForce RTX 3080)`

### Mac (Parallels VM)
- [ ] Install Parallels + Ubuntu 22.04 ARM VM
- [ ] Install Docker inside the VM
- [ ] `./docker_build.sh` (auto-detects arm64) — if packages fail, try `./docker_build.sh amd64`
- [ ] `./docker_run.sh parallels`
- [ ] Rendering will use software (llvmpipe) — Gazebo works but slower
- [ ] No PBR texture issues (already using ambient/diffuse fallback)
