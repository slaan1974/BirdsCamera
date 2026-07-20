# PLAN — Ultralytics YOLO on Raspberry Pi 4

## Comprehensive Guide to Use Ultralytics YOLO on Raspberry Pi 4

---

## 1. Overview

This document covers everything needed to run [Ultralytics YOLO](https://github.com/ultralytics/ultralytics) — the latest YOLO26 models (and YOLOv8/YOLO11) — on a **Raspberry Pi 4**. The guide is based on the official Ultralytics documentation found in `docs/en/guides/raspberry-pi.md`, `docs/en/guides/coral-edge-tpu-on-raspberry-pi.md`, and supporting integration docs.

**Key facts:**

- The repo already has extensive Raspberry Pi support (detection via `is_raspberrypi()` in `ultralytics/utils/__init__.py:783`)
- An ARM64 Docker image exists at `ultralytics/ultralytics:latest-arm64`
- CI runs benchmarks on a self-hosted Pi runner
- **NCNN format is the #1 recommendation** for Pi 4 (best performance on ARM)

---

## 2. Raspberry Pi 4 Hardware Specifications

| Spec                  | Value                                                         |
| --------------------- | ------------------------------------------------------------- |
| CPU                   | Broadcom BCM2711, Cortex-A72 64-bit, 4 cores @ 1.8GHz         |
| GPU                   | VideoCore VI @ 500MHz                                         |
| RAM                   | 1GB / 2GB / 4GB / 8GB LPDDR4-3200                             |
| USB                   | 2× USB 3.0, 2× USB 2.0                                        |
| Camera                | MIPI CSI (22-pin connector, **different from Pi 5's 15-pin**) |
| Power                 | 3A@5V (USB-C)                                                 |
| **Recommended model** | **4GB or 8GB** for YOLO inference                             |

---

## 3. OS Setup

1. Flash **Raspberry Pi OS Bookworm (Debian 12) 64-bit Lite** (no desktop GUI saves RAM):
   - Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
   - Choose: Raspberry Pi OS (64-bit) Lite
   - **Important:** Pre-configure SSH, Wi-Fi, and user credentials in the Imager

2. Boot and initial setup:

   ```bash
   sudo apt update && sudo apt upgrade -y
   sudo apt install git curl wget -y
   ```

3. (Optional but recommended) **Use an SSD** instead of SD card:
   - Pi 4 can boot from USB 3.0 SSD for much better I/O performance
   - Critical for 24/7 operation (SD cards wear out)

---

## 4. Installation Methods

### Option A: Docker (Fastest — ~1 command)

```bash
t=ultralytics/ultralytics:latest-arm64
sudo docker pull $t && sudo docker run -it --ipc=host $t
```

Docker image is based on `arm64v8/ubuntu:24.04`, pre-installed with:

- Python 3, PyTorch (CPU), OpenCV
- All export dependencies (ONNX, OpenVINO, TensorFlow)
- Pre-downloaded YOLO26n model weights

### Option B: Manual Install (More Flexible)

```bash
# 1. System packages
sudo apt update
sudo apt install python3-pip python3-venv libgl1 libglib2.0-0 -y

# 2. Create virtual environment (recommended)
python3 -m venv ultralytics-env
source ultralytics-env/bin/activate

# 3. Upgrade pip and install CPU-only PyTorch (avoid Jetson CUDA builds on Pi)
pip install -U pip
pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu

# 4. Install Ultralytics with export dependencies
pip install ultralytics[export]
```

**Dependency notes** (from `pyproject.toml`):

- Core: `torch>=1.8.0`, `torchvision>=0.9.0`, `opencv-python`, `numpy`, `pillow`
- For export: `onnx`, `onnxruntime`, `openvino`, `tensorflow`, `tensorstore` (aarch64-specific)
- TensorFlow on aarch64 needs `tensorstore>=0.1.63` and avoids `h5py==3.11.0` (no aarch64 wheel)

**For inference-only (no export), install base package:**

```bash
pip install ultralytics
```

Then export models on a more powerful machine (see section 6).

---

## 5. Model Export Formats & Benchmarking

### 5.1 Export Formats Available on Pi

| Format        |  Export on Pi?  | Pi 4 Performance Estimate | Notes                        |
| ------------- | :-------------: | :-----------------------: | ---------------------------- |
| PyTorch       |     ✅ Yes      |     ~300ms (baseline)     | Default .pt format           |
| TorchScript   |     ✅ Yes      |          ~360ms           |                              |
| **ONNX**      |   **✅ Yes**    |        **~130ms**         | Good intermediate format     |
| **OpenVINO**  |   **✅ Yes**    |         **~71ms**         | Intel toolkit, works on ARM! |
| **NCNN**      |   **✅ Yes**    |         **~68ms**         | **RECOMMENDED — best on Pi** |
| **MNN**       |   **✅ Yes**    |         **~91ms**         | Strong competitor            |
| ExecuTorch    |     ✅ Yes      |          ~148ms           |                              |
| TF SavedModel |     ✅ Yes      |          ~214ms           |                              |
| TF GraphDef   |     ✅ Yes      |          ~214ms           |                              |
| TF Lite       | ⚠️ Yes (no NMS) |          ~251ms           | NMS export fails on ARM64    |
| Edge TPU      |      ❌ No      |      See Coral guide      | Must export on x86_64/Colab  |
| TF.js         |      ❌ No      |            N/A            | Unsupported on ARM64 Linux   |

**Pi 4 vs Pi 5 expectation:** Pi 4 runs ~30-40% slower than Pi 5 (based on Coral Edge TPU guide benchmarks showing Pi 5 is ~22% faster on standard mode and ~30% faster on high-frequency mode).

### 5.2 Pi 5 Benchmarks (Reference — Scale down ~30% for Pi 4)

**YOLO26n on Pi 5:**
| Format | Inference Time (ms) | Est. Pi 4 Time |
|--------|:------------------:|:--------------:|
| NCNN | 67.69 | ~90-100ms |
| OpenVINO | 70.74 | ~95-105ms |
| MNN | 90.89 | ~120-130ms |
| ONNX | 130.33 | ~170-185ms |
| PyTorch | 302.15 | ~400-420ms |

### 5.3 YOLO26 Size vs Performance

From ONNX benchmarks on Pi 5:
| Model | mAP50-95 | Inference Time (Pi 5) | Est. Pi 4 | Feasible? |
|-------|:-------:|:---------------------:|:---------:|:---------:|
| YOLO26n | 40.1 | 128ms | ~170ms | ✅ Real-time |
| YOLO26s | 47.8 | 353ms | ~480ms | ⚠️ ~2 FPS |
| YOLO26m | 52.5 | 994ms | ~1.3s | ❌ Too slow |
| YOLO26l | 54.4 | 1.26s | ~1.7s | ❌ |
| YOLO26x | 56.9 | 2.64s | ~3.5s | ❌ |

**Recommendation for Pi 4:** Use **YOLO26n** in **NCNN** format for best speed. YOLO26s may be usable at ~2 FPS.

### 5.4 Reproduce Benchmarks

```bash
yolo benchmark model=yolo26n.pt data=coco128.yaml imgsz=640
```

Or in Python:

```python
from ultralytics import YOLO

model = YOLO("yolo26n.pt")
results = model.benchmark(data="coco128.yaml", imgsz=640)
```

---

## 6. Running Inference

### 6.1 Basic Inference

```python
from ultralytics import YOLO

# Load model (auto-downloads if not present)
model = YOLO("yolo26n.pt")

# Run on image URL or file
results = model("https://ultralytics.com/images/bus.jpg")

# Run on local image
results = model("path/to/image.jpg")

# Run on video
results = model("path/to/video.mp4")
```

CLI equivalent:

```bash
yolo predict model=yolo26n.pt source='https://ultralytics.com/images/bus.jpg'
```

### 6.2 Using NCNN for Best Performance

```python
# Step 1: Export to NCNN (creates yolo26n_ncnn_model/ directory)
from ultralytics import YOLO

model = YOLO("yolo26n.pt")
model.export(format="ncnn")

# Step 2: Load and run NCNN model
ncnn_model = YOLO("yolo26n_ncnn_model")
results = ncnn_model("https://ultralytics.com/images/bus.jpg")
```

CLI:

```bash
yolo export model=yolo26n.pt format=ncnn
yolo predict model='yolo26n_ncnn_model' source='https://ultralytics.com/images/bus.jpg'
```

**Note:** First export may take several minutes on Pi 4 (PNNX conversion is CPU-intensive). After that, the NCNN model loads instantly.

### 6.3 Using OpenVINO (Alternative to NCNN)

```python
model.export(format="openvino")
ov_model = YOLO("yolo26n_openvino_model")
results = ov_model("image.jpg")
```

---

## 7. Camera Integration

### 7.1 Hardware — CSI Connector Note

**Pi 4 uses a 22-pin CSI connector** (Pi 5 uses 15-pin). Standard Raspberry Pi Camera modules work directly with Pi 4 without adapters.

Compatible cameras:

- Raspberry Pi Camera Module 3
- Raspberry Pi Camera Module 2
- Raspberry Pi HQ Camera

### 7.2 Method 1: picamera2 (Recommended)

```python
import cv2
from picamera2 import Picamera2

from ultralytics import YOLO

picam2 = Picamera2()
picam2.preview_configuration.main.size = (1280, 720)
picam2.preview_configuration.main.format = "RGB888"
picam2.preview_configuration.align()
picam2.configure("preview")
picam2.start()

model = YOLO("yolo26n_ncnn_model")  # Use NCNN for best FPS

while True:
    frame = picam2.capture_array()
    results = model(frame)
    annotated_frame = results[0].plot()
    cv2.imshow("Camera", annotated_frame)
    if cv2.waitKey(1) == ord("q"):
        break

cv2.destroyAllWindows()
```

### 7.3 Method 2: TCP Stream via rpicam-vid

Terminal 1 — start TCP stream:

```bash
rpicam-vid -n -t 0 --inline --listen -o tcp://127.0.0.1:8888
```

Terminal 2 — run YOLO on the stream:

```bash
yolo predict model=yolo26n_ncnn_model source="tcp://127.0.0.1:8888"
```

---

## 8. Performance Optimization

### 8.1 System-Level Optimizations

| Optimization                 |          Effect           | Instructions                                                                                                                               |
| ---------------------------- | :-----------------------: | ------------------------------------------------------------------------------------------------------------------------------------------ |
| Use Raspberry Pi OS Lite     |     Saves ~300MB RAM      | Flash OS without desktop                                                                                                                   |
| Use USB 3.0 SSD              |      Much faster I/O      | Boot from SSD instead of SD                                                                                                                |
| Overclock CPU to 2.0GHz      |        ~10% faster        | `arm_freq=2000` in `/boot/firmware/config.txt`                                                                                             |
| Overclock GPU to 600MHz      |        Helps NCNN         | `gpu_freq=600`                                                                                                                             |
| Increase GPU memory          |   128-256MB recommended   | `gpu_mem=256`                                                                                                                              |
| Disable unnecessary services |  More CPU for inference   | `sudo systemctl disable bluetooth` etc.                                                                                                    |
| Use swap (if low RAM)        | Avoid OOM on 1-2GB models | `sudo dphys-swapfile swapoff && edit CONF_SWAPSIZE=2048 in /etc/dphys-swapfile && sudo dphys-swapfile setup && sudo dphys-swapfile swapon` |

### 8.2 Overclocking Config

Edit `/boot/firmware/config.txt`:

```ini
arm_freq=2000
gpu_freq=600
force_turbo=1
over_voltage=2
gpu_mem=256
```

**Warning:** Ensure adequate cooling (heatsink + fan). Reduce if unstable.

### 8.3 YOLO Inference Optimizations

- Use `imgsz=320` instead of 640 for ~2-4× speedup (with accuracy loss)
- Use `half=True` if format supports FP16
- Use `max_det=10` to limit detections per image
- Use NCNN format (68ms on Pi 5 vs 302ms PyTorch = ~4.5× speedup)
- Batch inference: `model(["img1.jpg", "img2.jpg", ...])`

```python
# Optimized inference
results = model("image.jpg", imgsz=320, max_det=10, conf=0.25, iou=0.45)
```

---

## 9. Coral Edge TPU (Optional Hardware Accelerator)

### 9.1 What You Need

- Raspberry Pi 4 (2GB+ recommended)
- [Coral USB Accelerator](https://coral.ai/products/accelerator/)
- USB 3.0 port (for maximum throughput)
- A non-ARM machine to **export** the model (Edge TPU compiler not available on ARM)

### 9.2 Workflow

**Step 1 — Export on x86_64 machine or Colab:**

```python
from ultralytics import YOLO

model = YOLO("yolo26n.pt")
model.export(format="edgetpu")
# Produces: yolo26n_full_integer_quant_edgetpu.tflite
```

**Step 2 — Install Edge TPU runtime on Pi 4:**

```bash
# Download from https://github.com/feranick/libedgetpu/releases
# Choose the .deb for Bookworm 64-bit arm64
sudo dpkg -i libedgetpu1-max_*.bookworm_arm64.deb

# Uninstall full TensorFlow, use lightweight runtime
pip uninstall tensorflow tensorflow-aarchtf
pip install -U tflite-runtime
```

**Step 3 — Run on Pi 4:**

```python
from ultralytics import YOLO

model = YOLO("yolo26n_full_integer_quant_edgetpu.tflite")
results = model("image.jpg")
```

### 9.3 Edge TPU Performance on Pi 4 (YOLOv8n benchmarks)

| Image Size | Standard Mode | High-Frequency Mode |
| :--------: | :-----------: | :-----------------: |
|   320px    |    32.2ms     |       26.7ms        |
|   512px    |    73.5ms     |       60.7ms        |

**Edge TPU + Pi 4 delivers ~15-30 FPS** at 320px with YOLO26n — better than any CPU-only format.

---

## 10. Troubleshooting

| Problem                               | Cause                                           | Solution                                                                 |
| ------------------------------------- | ----------------------------------------------- | ------------------------------------------------------------------------ |
| `pip install` fails on aarch64        | Missing wheels for some packages                | Use `--extra-index-url https://download.pytorch.org/whl/cpu`             |
| TFLite NMS export fails               | ONNX NMS opset not supported on aarch64         | Export on x86_64, or use format="ncnn" instead                           |
| Model export is very slow             | PNNX/NCNN compilation is CPU-intensive          | Export once, reuse the NCNN model directory                              |
| OOM (Out of Memory) during inference  | YOLO26m/l/x too large for 4GB Pi                | Use YOLO26n, reduce `imgsz`, or get 8GB model                            |
| Camera not detected                   | CSI connector mismatch or disabled              | `sudo raspi-config` → Interface Options → Camera → Enable                |
| Poor FPS                              | Using PyTorch format (slowest)                  | Export to NCNN or OpenVINO                                               |
| `libedgetpu` fails to load            | Outdated runtime                                | Use community-maintained runtime from feranick/libertpu                  |
| High memory usage                     | OpenCV GUI + model + camera buffer              | Use `model.predict()` without `plot()`                                   |
| Swap file too small                   | 1GB Pi runs out of RAM                          | Increase swap to 2GB+                                                    |
| `UnicodeEncodeError` with Ultralytics | Pi OS locale is ISO-8859-15, can't encode emoji | Set `export PYTHONIOENCODING=utf-8 LC_ALL=C.UTF-8` before running Python |

---

## 11. Directory Layout Reference

Key files and directories in the repo relevant to Pi deployment:

```
ultralytics/
├── docker/Dockerfile-arm64              # ARM64 Docker image for Pi
├── docs/en/guides/
│   ├── raspberry-pi.md                  # 📘 Main Pi guide (533 lines)
│   ├── coral-edge-tpu-on-raspberry-pi.md  # Edge TPU + Pi guide
│   ├── model-deployment-options.md      # Export format comparison
│   └── docker-quickstart.md             # Docker setup on Pi
├── docs/en/integrations/
│   ├── ncnn.md                          # NCNN format docs
│   ├── tflite.md                        # TFLite format docs
│   ├── edge-tpu.md                      # Edge TPU format docs
│   └── openvino.md                      # OpenVINO on ARM docs
├── ultralytics/utils/__init__.py        # is_raspberrypi() detection (line 783)
├── ultralytics/engine/exporter.py       # Export engine (TFLite NMS blocked on ARM64)
├── examples/YOLOv8-TFLite-Python/       # Standalone TFLite inference example
├── pyproject.toml                       # Dependencies (aarch64-specific pins)
└── .github/workflows/ci.yml             # Pi CI job (self-hosted runner)
```

---

## 12. Quick Start Summary

```bash
# === EASIEST PATH: Docker ===
sudo docker pull ultralytics/ultralytics:latest-arm64
sudo docker run -it --ipc=host ultralytics/ultralytics:latest-arm64

# Inside container:
yolo predict model=yolo26n.pt source='https://ultralytics.com/images/bus.jpg'

# === MANUAL PATH ===
sudo apt update && sudo apt install python3-pip libgl1 -y
pip install -U pip
pip install ultralytics

# Export to NCNN and run
yolo export model=yolo26n.pt format=ncnn
yolo predict model='yolo26n_ncnn_model' source='https://ultralytics.com/images/bus.jpg'

# === WITH CAMERA ===
pip install picamera2 # Pre-installed on Pi OS
python -c "
from ultralytics import YOLO
from picamera2 import Picamera2
import cv2
picam2 = Picamera2()
picam2.configure('preview')
picam2.start()
model = YOLO('yolo26n_ncnn_model')
while True:
    frame = picam2.capture_array()
    results = model(frame)
    cv2.imshow('YOLO', results[0].plot())
    if cv2.waitKey(1) == ord('q'): break
cv2.destroyAllWindows()
"
```

### Expected FPS on Pi 4 (estimated):

| Setup            |   YOLO26n   |   YOLO26s   |
| ---------------- | :---------: | :---------: |
| PyTorch format   |  ~2.5 FPS   |   ~1 FPS    |
| ONNX format      |  ~5.5 FPS   |   ~2 FPS    |
| NCNN format      | **~10 FPS** |   ~4 FPS    |
| OpenVINO format  |  ~9.5 FPS   |   ~5 FPS    |
| Edge TPU (320px) | **~30 FPS** | **~25 FPS** |

---

## 13. References & Further Reading

| Resource             | URL                                                |
| -------------------- | -------------------------------------------------- |
| Official Pi Guide    | `docs/en/guides/raspberry-pi.md`                   |
| Edge TPU on Pi Guide | `docs/en/guides/coral-edge-tpu-on-raspberry-pi.md` |
| NCNN Integration     | `docs/en/integrations/ncnn.md`                     |
| TFLite Integration   | `docs/en/integrations/tflite.md`                   |
| MNN Integration      | `docs/en/integrations/mnn.md`                      |
| OpenVINO on ARM      | `docs/en/integrations/openvino.md`                 |
| Export Options       | `docs/en/guides/model-deployment-options.md`       |
| Full Documentation   | https://docs.ultralytics.com                       |
| GitHub Repository    | https://github.com/ultralytics/ultralytics         |
| Raspberry Pi Docs    | https://www.raspberrypi.com/documentation/         |

---

## 14. Docker Container Lifecycle — Reboot, Connect, Persist

### 14.1 Installing Docker on Raspberry Pi (If Not Already Installed)

```bash
# Install Docker using the convenience script
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add your user to the docker group (avoid sudo on every command)
sudo usermod -aG docker $USER
newgrp docker # or log out and back in

# Verify
docker --version
```

### 14.2 Create a Named Container (Recommended for Reboots)

Instead of using `docker run -it` (which creates a throwaway container), create a named, persistent container:

```bash
# First pull the image
docker pull ultralytics/ultralytics:latest-arm64

# Create a named container with auto-restart on reboot
docker run -d \
  --name ultralytics-pi \
  --restart unless-stopped \
  --ipc=host \
  -v /home/pi/ultralytics-data:/ultralytics/workspace \
  ultralytics/ultralytics:latest-arm64 \
  tail -f /dev/null
```

**Explanation of flags:**
| Flag | Purpose |
|------|---------|
| `-d` | Run in detached (background) mode |
| `--name ultralytics-pi` | Give the container a fixed name for easy reference |
| `--restart unless-stopped` | **Auto-start on reboot** (unless manually stopped) |
| `--ipc=host` | Shared memory for efficient PyTorch inference |
| `-v ...:/ultralytics/workspace` | Persistent data volume (models, images, results survive container removal) |
| `tail -f /dev/null` | Keeps container alive without running a specific command |

### 14.3 Starting the Container After Reboot

If you used `--restart unless-stopped`, the container starts **automatically** on every boot. To verify:

```bash
docker ps --filter name=ultralytics-pi
```

If it's running, you'll see it listed. If not (maybe you used `--restart no`), start it manually:

```bash
docker start ultralytics-pi
```

### 14.4 Connecting to the Running Container

**Option A — Interactive shell (most common):**

```bash
docker exec -it ultralytics-pi bash
```

You get a bash shell inside the container. Type `exit` to leave (container keeps running).

**Option B — Run a single command without entering:**

```bash
docker exec -it ultralytics-pi yolo predict model=yolo26n.pt source=workspace/test.jpg
```

**Option C — Attach to container's console:**

```bash
docker attach ultralytics-pi
```

(Only use if the container was started with `-it` and is running an interactive process. Detach with `Ctrl+P Ctrl+Q`.)

**Option D — If container exits and you want a fresh shell:**

```bash
docker start -ai ultralytics-pi
```

### 14.5 Stopping and Restarting

```bash
docker stop ultralytics-pi    # Graceful stop
docker restart ultralytics-pi # Restart
docker rm ultralytics-pi      # Remove container entirely (data in -v volume persists)
```

### 14.6 One-liner for Quick Interactive Use (No Named Container)

If you just want a quick session without persistence:

```bash
docker run -it --rm --ipc=host ultralytics/ultralytics:latest-arm64
```

(`--rm` auto-deletes the container when you exit — all data is lost.)

---

## 15. NCNN Conversion Inside the Docker Container

### 15.1 Why It Works

The `Dockerfile-arm64` runs `pip install -e ".[export]"`, which installs **all** export dependencies including ONNX, OpenVINO, and the toolchains needed for NCNN conversion (PNNX). Everything you need is already present.

### 15.2 Step-by-Step NCNN Conversion Inside Docker

```bash
# 1. Connect to the container
docker exec -it ultralytics-pi bash

# 2. You're now inside. The container has yolo26n.pt pre-downloaded.
ls -la yolo26n.pt # Should exist

# 3. Export to NCNN (this uses PNNX under the hood)
yolo export model=yolo26n.pt format=ncnn imgsz=640

# 4. Output is a directory: yolo26n_ncnn_model/
#    Contains: model.ncnn.param, model.ncnn.bin, metadata.yaml
ls -la yolo26n_ncnn_model/

# 5. Run inference with the NCNN model
yolo predict model=yolo26n_ncnn_model source='https://ultralytics.com/images/bus.jpg'
```

### 15.3 What Happens During NCNN Export

The export pipeline is:

```
yolo26n.pt (PyTorch)
    → torch.onnx.export() → yolo26n.onnx (intermediate)
    → pnnx yolo26n.onnx → yolo26n_ncnn_model/ (final NCNN artifacts)
```

The NCNN output directory contains:
| File | Description |
|------|-------------|
| `model.ncnn.param` | Network architecture definition (text format) |
| `model.ncnn.bin` | Learned weights (binary) |
| `metadata.yaml` | Ultralytics metadata (names, task type, imgsz, etc.) |

### 15.4 First Export Time & Persistence

- **First export on Pi 4:** ~5-15 minutes (PNNX is CPU-intensive, converting ONNX → NCNN)
- **Subsequent exports:** Faster if the ONNX file is cached
- **Best practice:** Export once, save the `_ncnn_model` directory to your volume mount:
  ```bash
  # Inside container
  cp -r yolo26n_ncnn_model /ultralytics/workspace/
  ```
  This survives container rebuilds.

### 15.5 Exporting Other Formats for Comparison

```bash
# Inside the container, all these work:
yolo export model=yolo26n.pt format=onnx     # ~2-5 min
yolo export model=yolo26n.pt format=openvino # ~2-5 min
yolo export model=yolo26n.pt format=mnn      # Requires MNN tools
```

---

## 16. Docker Logs and Troubleshooting

### 16.1 Container Logs

The container's stdout/stderr is captured by Docker:

```bash
# View logs
docker logs ultralytics-pi

# Follow logs in real-time (like tail -f)
docker logs -f ultralytics-pi

# Last 50 lines
docker logs --tail 50 ultralytics-pi

# Logs with timestamps
docker logs -t ultralytics-pi
```

### 16.2 Where YOLO Creates Logs Inside the Container

Inside the container, YOLO writes to:
| Path | Contents |
|------|----------|
| `/ultralytics/runs/` | All prediction/training outputs, including `predict/` subdirectories |
| `/ultralytics/runs/detect/predict/` | Annotated images, saved results |
| `/ultralytics/runs/detect/val/` | Validation metrics (if running benchmarks) |
| `yolo26n_ncnn_model/metadata.yaml` | NCNN model metadata (task, names, imgsz) |

To persist logs, mount a volume or copy results out:

```bash
# From host, copy results out of container
docker cp ultralytics-pi:/ultralytics/runs/detect/predict ./results

# Or mount a volume at creation time
docker run -d --name ultralytics-pi \
  --restart unless-stopped \
  --ipc=host \
  -v /home/pi/ultralytics-data:/ultralytics/workspace \
  -v /home/pi/ultralytics-runs:/ultralytics/runs \  # Persist ALL runs
ultralytics/ultralytics:latest-arm64 \
  tail -f /dev/null
```

### 16.3 Debugging Common Docker Issues

| Problem                                   | Check / Fix                                                                      |
| ----------------------------------------- | -------------------------------------------------------------------------------- |
| Container exits immediately after start   | Wrong entrypoint. Use `tail -f /dev/null` as the command                         |
| Can't pull the image                      | Check internet: `ping google.com`. Check ARM64: `uname -m`                       |
| Permission denied: `/var/run/docker.sock` | Add user to docker group: `sudo usermod -aG docker $USER`                        |
| OOM inside container                      | Check with `docker stats ultralytics-pi`. Add `--memory=4g` flag                 |
| Camera not accessible in container        | Need `--device /dev/video0:/dev/video0` or `--privileged` flag                   |
| NCNN export fails silently                | Run with more verbosity: `yolo export model=yolo26n.pt format=ncnn verbose=True` |
| Docker daemon not running after reboot    | `sudo systemctl enable docker && sudo systemctl start docker`                    |
| "Cannot connect to the Docker daemon"     | `sudo dockerd &` or check `sudo systemctl status docker`                         |

### 16.4 Checking Resource Usage

```bash
# Container resource stats (live)
docker stats ultralytics-pi

# Inspect full container config
docker inspect ultralytics-pi

# Check if restart policy is set correctly
docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' ultralytics-pi
# Should output: "unless-stopped"
```

---

## 17. Remote GUI Access

### 17.1 Architecture Overview

```
[Your Laptop/Desktop]  ←(network)→  [Raspberry Pi 4]
                                      ├── VNC Server (built-in Pi OS)
                                      ├── YOLO inference (Docker)
                                      └── Camera → picamera2 → CV2 display
```

### 17.2 Enable VNC on Raspberry Pi (Built-in)

Raspberry Pi OS (full desktop version, not Lite) includes RealVNC Server:

```bash
# 1. Enable VNC via raspi-config
sudo raspi-config
# → Interface Options → VNC → Enable

# 2. Or enable from the command line
sudo systemctl enable vncserver
sudo systemctl start vncserver

# 3. Find your Pi's IP address
hostname -I
# → e.g., 192.168.1.100
```

**Connecting:**

- **Windows/Mac/Linux:** Install [RealVNC Viewer](https://www.realvnc.com/en/connect/download/viewer/) and connect to `192.168.1.100:5900` (or whatever your Pi's IP is)
- **Linux alternative:** `vncviewer 192.168.1.100`

**If using Raspberry Pi OS Lite (no desktop):** Install a lightweight desktop + VNC:

```bash
sudo apt install raspberrypi-ui-mods x11vnc -y
x11vnc -storepasswd # Set a password
x11vnc -forever -usepw -display :0 &
```

### 17.3 Running YOLO with GUI Inside Docker + Displaying via VNC

**Step 1 — Start the container with X11 forwarding:**

```bash
# On the Pi (via SSH or terminal):
xhost +local:docker

docker run -d \
  --name ultralytics-pi \
  --restart unless-stopped \
  --ipc=host \
  --net=host \
  -e DISPLAY=$DISPLAY \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v ~/.Xauthority:/root/.Xauthority \
  -v /home/pi/ultralytics-data:/ultralytics/workspace \
  --device /dev/video0:/dev/video0 \
  ultralytics/ultralytics:latest-arm64 \
  tail -f /dev/null
```

**Key flags for GUI/camera:**
| Flag | Why |
|------|-----|
| `--net=host` | Container shares Pi's network (needed for X11 over VNC) |
| `-e DISPLAY=$DISPLAY` | Tells container which display to render to |
| `-v /tmp/.X11-unix:/tmp/.X11-unix` | Shares the X11 socket (GUI bridge) |
| `-v ~/.Xauthority:/root/.Xauthority` | Authentication for X11 |
| `--device /dev/video0:/dev/video0` | Passes camera device into container |

**Step 2 — Run YOLO with live camera preview:**

```bash
docker exec -it ultralytics-pi bash

# Inside container, run inference with live preview
yolo predict model=yolo26n_ncnn_model source=0 show=True
# The 'show=True' flag opens an OpenCV window — this appears on the Pi's display
# and is visible through VNC
```

**Step 3 — Full camera loop with display (Python script):**

```bash
docker exec -it ultralytics-pi python3 -c "
import cv2
from picamera2 import Picamera2
from ultralytics import YOLO
import time

picam2 = Picamera2()
picam2.preview_configuration.main.size = (640, 480)
picam2.preview_configuration.main.format = 'RGB888'
picam2.preview_configuration.align()
picam2.configure('preview')
picam2.start()
time.sleep(1)  # Let camera warm up

model = YOLO('yolo26n_ncnn_model')

while True:
    frame = picam2.capture_array()
    results = model(frame, imgsz=320)
    annotated = results[0].plot()
    cv2.imshow('YOLO Pi Camera', annotated)
    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

cv2.destroyAllWindows()
"
```

The `cv2.imshow()` window renders to the Pi's display, which is accessible remotely via VNC.

### 17.4 Alternative: Web-Based GUI (No VNC Required)

If you prefer a browser-based UI instead of VNC:

**Option A — Streamlit Dashboard (included in `ultralytics[solutions]`):**

```bash
# Install streamlit
docker exec ultralytics-pi pip install streamlit

# Run the Ultralytics Streamlit app
docker exec -it ultralytics-pi yolo streamlit-predict model=yolo26n_ncnn_model
# Access at: http://192.168.1.100:8501
```

**Option B — Flask Web Server:**

```python
# Save this as webcam.py and run inside container
import cv2
from flask import Flask, Response
from picamera2 import Picamera2

from ultralytics import YOLO

app = Flask(__name__)
model = YOLO("yolo26n_ncnn_model")
picam2 = Picamera2()
picam2.configure("preview")
picam2.start()


def generate():
    while True:
        frame = picam2.capture_array()
        results = model(frame, imgsz=320)
        annotated = results[0].plot()
        _, jpeg = cv2.imencode(".jpg", annotated)
        yield (b"--frame\r\nContent-Type: image/jpeg\r\n\r\n" + jpeg.tobytes() + b"\r\n")


@app.route("/video_feed")
def video_feed():
    return Response(generate(), mimetype="multipart/x-mixed-replace; boundary=frame")


@app.route("/")
def index():
    return '<html><body><img src="/video_feed"></body></html>'


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
```

Access at `http://192.168.1.100:5000` from any browser on your local network.

---

## 18. Pi Camera v2 Setup (Additional Detail)

Since you already have a **Raspberry Pi Camera Module v2** working, here's the full reference for completeness:

### 18.1 Hardware Connection

- Pi Camera v2 → ribbon cable → Pi 4 **22-pin CSI port** (marked "CAMERA")
- Pi 4 has a **22-pin connector** (Pi 5 uses 15-pin — different cable needed)
- The latch lifts up, insert ribbon cable with **metal contacts facing away from the Ethernet port**, press latch down

### 18.2 Enable the Camera Interface

```bash
# Method 1: raspi-config
sudo raspi-config
# → Interface Options → Camera → Enable → Reboot

# Method 2: Direct config.txt edit
echo "start_x=1" | sudo tee -a /boot/config.txt
sudo reboot
```

### 18.3 Verify Camera Detection

```bash
# Check if camera is detected by the system
rpicam-hello --list-cameras
# Expected output: Available cameras: imx219 [3280x2464] (/base/soc/i2c...)

# Quick test (5-second preview window)
rpicam-hello -t 5000
```

### 18.4 Camera Hardware Info (v2)

| Property   | Value                                  |
| ---------- | -------------------------------------- |
| Sensor     | Sony IMX219                            |
| Resolution | 3280 × 2464 (8 MP)                     |
| Focus      | Fixed                                  |
| FOV        | 62.2° × 48.8°                          |
| Connection | 22-pin ribbon cable to CSI             |
| Driver     | `libcamera` stack (native on Bookworm) |

### 18.5 Using picamera2 in Python

`picamera2` is pre-installed on Raspberry Pi OS Bookworm. The key API:

```python
from picamera2 import Picamera2

# Initialize
picam2 = Picamera2()

# Configure preview mode (lower res for faster inference)
config = picam2.create_preview_configuration(main={"size": (640, 480), "format": "RGB888"})
picam2.configure(config)
picam2.start()

# Capture a frame as numpy array (OpenCV-compatible)
frame = picam2.capture_array()  # shape: (480, 640, 3), dtype: uint8
```

**Camera Configuration Options:**

```python
# High quality (slower, good for stills)
config = picam2.create_still_configuration(main={"size": (3280, 2464), "format": "RGB888"})

# Low latency (faster, good for real-time)
config = picam2.create_preview_configuration(
    main={"size": (320, 240), "format": "RGB888"},
    lores={"size": (320, 240), "format": "RGB888"},
)
```

### 18.6 Camera + Docker Integration

To use the Pi camera from inside Docker, you need to pass the camera device:

```bash
# Find the camera device
ls -l /dev/video*
# Typically /dev/video0 for the main camera

# Pass it to Docker:
docker run -d --name ultralytics-picam \
  --restart unless-stopped \
  --ipc=host \
  --net=host \
  -e DISPLAY=$DISPLAY \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  --device /dev/video0:/dev/video0 \
  --device /dev/video1:/dev/video1 \
  --device /dev/video2:/dev/video2 \
  --device /dev/video3:/dev/video3 \
  -v /run/udev:/run/udev:ro \
  ultralytics/ultralytics:latest-arm64 \
  tail -f /dev/null
```

**Note:** The Pi's libcamera stack creates multiple `/dev/video*` nodes. Passing all of them (`video0` through `video3`) ensures full camera pipeline availability. For simpler setups, `--privileged` also works but has security implications.

```bash
# Simpler but less secure alternative:
docker run -d --name ultralytics-picam \
  --restart unless-stopped \
  --ipc=host \
  --privileged \
  ultralytics/ultralytics:latest-arm64 \
  tail -f /dev/null
```

### 18.7 Camera Troubleshooting

| Problem                            | Check / Fix                                                         |
| ---------------------------------- | ------------------------------------------------------------------- |
| `picamera2` not found              | Install: `pip install picamera2` (should be pre-installed on Pi OS) |
| `rpicam-hello` fails               | Ensure camera is enabled: `sudo raspi-config` → Interface           |
| "Failed to open camera"            | Check ribbon cable connection; try re-seating                       |
| No `/dev/video*` devices           | Camera not enabled in config.txt: `sudo raspi-config`               |
| Black/missing frames               | Wrong format string. Use `"RGB888"` not `"BGR888"`                  |
| `--device /dev/video0` still fails | Try `--privileged` flag or `-v /dev:/dev`                           |

---

## 19. Full Docker Lifecycle Quick Reference

```bash
# ===== FIRST TIME SETUP =====
# 1. Install Docker
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
# Log out and back in, or: newgrp docker

# 2. Pull the ARM64 image
docker pull ultralytics/ultralytics:latest-arm64

# 3. Create named container with all features
docker run -d \
  --name ultralytics-pi \
  --restart unless-stopped \
  --ipc=host \
  --net=host \
  -e DISPLAY=$DISPLAY \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v /home/pi/ultralytics-data:/ultralytics/workspace \
  -v /home/pi/ultralytics-runs:/ultralytics/runs \
  --device /dev/video0:/dev/video0 \
  --device /dev/video1:/dev/video1 \
  --device /dev/video2:/dev/video2 \
  --device /dev/video3:/dev/video3 \
  ultralytics/ultralytics:latest-arm64 \
  tail -f /dev/null

# ===== AFTER REBOOT =====
# Container starts automatically (unless-stopped). Verify:
docker ps | grep ultralytics-pi

# If it didn't start:
docker start ultralytics-pi

# ===== DAILY USE =====
# Drop into a shell:
docker exec -it ultralytics-pi bash

# Run a YOLO command directly:
docker exec ultralytics-pi yolo export model=yolo26n.pt format=ncnn

# Run NCNN inference:
docker exec ultralytics-pi yolo predict \
  model=yolo26n_ncnn_model \
  source=workspace/test.jpg

# Run live camera (if X11/VNC set up):
docker exec ultralytics-pi python3 /ultralytics/workspace/live_demo.py

# ===== MAINTENANCE =====
# View logs:
docker logs -f ultralytics-pi

# Check resources:
docker stats ultralytics-pi

# Update to latest image:
docker stop ultralytics-pi
docker rm ultralytics-pi
docker pull ultralytics/ultralytics:latest-arm64
# Then re-run the 'docker run' command from above

# ===== STOP/START =====
docker stop ultralytics-pi
docker start ultralytics-pi
docker restart ultralytics-pi
```

---

## 20. Team 1 — Docker Deployment with Camera v2 Auto-Start

### 20.1 Overview

**Goal:** Deploy YOLO inference inside Docker on a Pi 4 with Camera v2, auto-starting on every reboot with zero manual intervention.

**Architecture:**

```
[Boot] → systemd → Docker daemon → ultralytics container → inference script → camera→results
```

### 20.2 One-Shot Setup Script

Run this once on the Pi. It installs Docker, pulls the image, exports the NCNN model, creates the inference script, and installs the systemd service.

```bash
#!/usr/bin/env bash
set -euo pipefail

# ── 1. Install Docker ──
if ! command -v docker &> /dev/null; then
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "$USER"
  echo "=== Log out and back in, then re-run this script ==="
  exit 0
fi

# ── 2. Pull ARM64 image ──
docker pull ultralytics/ultralytics:latest-arm64

# ── 3. Export NCNN model (pre-build so first inference is fast) ──
docker run --rm --ipc=host \
  -v "$HOME/ultralytics-data:/ultralytics/workspace" \
  ultralytics/ultralytics:latest-arm64 \
  sh -c "yolo export model=yolo26n.pt format=ncnn imgsz=320 && \
         cp -r yolo26n_ncnn_model /ultralytics/workspace/"

# ── 4. Create inference runner script ──
cat > "$HOME/ultralytics-data/run_yolo.py" << 'PYEOF'
import cv2, time, os, json
from picamera2 import Picamera2
from ultralytics import YOLO

MODEL_PATH  = "/ultralytics/workspace/yolo26n_ncnn_model"
OUTPUT_DIR  = "/ultralytics/workspace/results"
os.makedirs(OUTPUT_DIR, exist_ok=True)

picam2 = Picamera2()
config = picam2.create_preview_configuration(
    main={"size": (640, 480), "format": "RGB888"}
)
picam2.configure(config)
picam2.start()
time.sleep(2)  # allow camera to stabilise

model = YOLO(MODEL_PATH)

frame_count = 0
while True:
    frame = picam2.capture_array()
    results = model(frame, imgsz=320, conf=0.25, iou=0.45, verbose=False)

    # Save annotated frame every 30 frames (~1/sec at 30 FPS)
    if frame_count % 30 == 0:
        annotated = results[0].plot()
        ts = time.strftime("%Y%m%d_%H%M%S")
        cv2.imwrite(f"{OUTPUT_DIR}/{ts}.jpg", annotated)

        # Log detections
        dets = results[0].boxes
        summary = {
            "timestamp": ts,
            "detections": len(dets) if dets else 0,
            "classes": [int(c) for c in dets.cls.tolist()] if dets is not None else [],
        }
        with open(f"{OUTPUT_DIR}/detections.jsonl", "a") as f:
            f.write(json.dumps(summary) + "\n")

    frame_count += 1
    time.sleep(0.03)  # throttle to ~30 FPS
PYEOF

# ── 5. Create systemd service ──
sudo tee /etc/systemd/system/ultralytics-docker.service > /dev/null << 'SVC'
[Unit]
Description=Ultralytics YOLO Docker Inference with Camera v2
After=docker.service
Requires=docker.service
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
Restart=always
RestartSec=10
User=pi
ExecStartPre=/usr/bin/docker start -a ultralytics-pi-cam
ExecStart=/usr/bin/docker exec ultralytics-pi-cam python3 /ultralytics/workspace/run_yolo.py
ExecStop=/usr/bin/docker stop ultralytics-pi-cam
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
SVC

# ── 6. Create and start the persistent container ──
docker rm -f ultralytics-pi-cam 2> /dev/null || true
docker run -d \
  --name ultralytics-pi-cam \
  --restart no \
  --ipc=host \
  --net=host \
  -v "$HOME/ultralytics-data:/ultralytics/workspace" \
  --device /dev/video0:/dev/video0 \
  --device /dev/video1:/dev/video1 \
  --device /dev/video2:/dev/video2 \
  --device /dev/video3:/dev/video3 \
  ultralytics/ultralytics:latest-arm64 \
  tail -f /dev/null

# ── 7. Enable the service ──
sudo systemctl daemon-reload
sudo systemctl enable ultralytics-docker.service
sudo systemctl start ultralytics-docker.service

echo "=== Deployment complete. Status: ==="
sudo systemctl status ultralytics-docker.service --no-pager
```

### 20.3 What Happens After Reboot

1. `systemd` starts the Docker daemon (`docker.service`)
2. After Docker is ready, `ultralytics-docker.service` starts
3. `ExecStartPre` ensures the container is running
4. `ExecStart` runs the inference script inside the container
5. If the script crashes, `Restart=always` re-launches it after 10 seconds
6. Annotated frames are saved to `~/ultralytics-data/results/`
7. Detection logs accumulate in `~/ultralytics-data/results/detections.jsonl`

### 20.4 Management Commands

| Action              | Command                                               |
| ------------------- | ----------------------------------------------------- |
| View service status | `sudo systemctl status ultralytics-docker.service`    |
| View live logs      | `sudo journalctl -fu ultralytics-docker.service`      |
| Stop inference      | `sudo systemctl stop ultralytics-docker.service`      |
| Start inference     | `sudo systemctl start ultralytics-docker.service`     |
| Disable auto-start  | `sudo systemctl disable ultralytics-docker.service`   |
| Tail detection logs | `tail -f ~/ultralytics-data/results/detections.jsonl` |
| Enter container     | `docker exec -it ultralytics-pi-cam bash`             |
| View container logs | `docker logs ultralytics-pi-cam`                      |

### 20.5 Camera Device Mapping

The `team1` script **dynamically discovers** available video devices at container creation time. Instead of hardcoding specific device nodes, it runs `ls /dev/video*` and only maps the nodes that actually exist on your system:

```bash
# The team1 script does this automatically:
VIDEO_DEVICES=$(ls /dev/video* 2> /dev/null || true)
for dev in ${VIDEO_DEVICES}; do
  DEVICE_FLAGS="${DEVICE_FLAGS} --device ${dev}:${dev}"
done
```

If your camera doesn't appear, verify it is enabled:

```bash
ls -l /dev/video*
sudo raspi-config → Interface Options → Camera → Enable → Reboot
```

Expected nodes on Raspberry Pi OS Bookworm:

```bash
# crw-rw---- 1 root video 81, 0 ... /dev/video0  (main)
# crw-rw---- 1 root video 81, 1 ... /dev/video1  (metadata)
# crw-rw---- 1 root video 81, 2 ... /dev/video2  (ISP)
# crw-rw---- 1 root video 81, 3 ... /dev/video3
```

### 20.6 Camera Usage & Image Capture

This section covers how Team 1 users interact with the camera, capture images manually, view detection results, and configure camera behavior.

#### 20.6.1 Verify Camera Inside Container

After setup, confirm the camera is accessible from within the Docker container:

```bash
# Enter the container
./team1 shell

# Check camera devices are passed through
ls /dev/video*

# Quick camera test (capture a single frame)
python3 -c "
from picamera2 import Picamera2
p = Picamera2()
p.start()
p.capture_file('/tmp/cam_test.jpg')
print('Camera OK — saved /tmp/cam_test.jpg')
"
```

Exit the container with `exit` or Ctrl+D.

#### 20.6.2 Manual Snapshot (One-Shot Capture)

Grab a single test frame without running the full inference pipeline:

```bash
docker exec ultralytics-pi-cam python3 -c "
from picamera2 import Picamera2
import cv2, time

p = Picamera2()
config = p.create_preview_configuration(
    main={'size': (640, 480), 'format': 'RGB888'}
)
p.configure(config)
p.start()
time.sleep(1)                     # Allow auto-exposure to settle
frame = p.capture_array()
cv2.imwrite('/ultralytics/data/snapshot.jpg', frame)
p.stop()
print('Snapshot saved to /ultralytics/data/snapshot.jpg')
"
```

View it on the host:

```bash
ls -l ~/ultralytics/data/snapshot.jpg
```

#### 20.6.3 Auto-Capture Workflow (How It Works)

The `run_yolo.py` inference script (created by `team1`) runs continuously inside the container:

```
Camera (picamera2) → capture_array() → YOLO inference → detections found?
                                                          ├── Yes → save annotated frame + log to JSONL
                                                          └── No  → skip (nothing saved)
```

**What gets saved when a detection occurs:**

| File            | Location                             | Example                                    |
| --------------- | ------------------------------------ | ------------------------------------------ |
| Annotated image | `/ultralytics/data/detect_{TS}.jpg`  | `detect_20260101_120000.jpg`               |
| Detection log   | `/ultralytics/data/detections.jsonl` | `{"timestamp":"...", "detections":2, ...}` |

**What does NOT get saved:**

- Frames with no detections (zero disk waste)
- Raw (unannotated) frames
- Video files

Each log line in `detections.jsonl` contains:

```json
{
  "timestamp": "20260101_120000",
  "frame": 42,
  "detections": 2,
  "classes": ["person", "dog"],
  "confidences": ["0.92", "0.87"]
}
```

#### 20.6.4 Camera Configuration

The inference script respects these environment variables (set them before starting the service):

| Parameter            | Default | Env Variable  | Effect                           |
| -------------------- | ------- | ------------- | -------------------------------- |
| Inference image size | 320     | `IMGSZ`       | Lower = faster but less accurate |
| Confidence threshold | 0.25    | `CONF_THRESH` | Raise to reduce false positives  |
| IoU threshold        | 0.45    | `IOU_THRESH`  | Raise for more overlapping boxes |
| Frame skip           | 1       | `FRAME_SKIP`  | 2 = process every other frame    |

**Example — run with higher confidence to reduce false alarms:**

```bash
sudo systemctl stop ultralytics-docker.service
docker exec ultralytics-pi-cam bash -c "CONF_THRESH=0.5 python3 /ultralytics/data/run_yolo.py" &
sudo systemctl start ultralytics-docker.service
```

**Change camera resolution** (edit the inference script):

```bash
docker exec ultralytics-pi-cam sed -i \
  's/("size": (640, 480)/("size": (1280, 720)/' \
  /ultralytics/data/run_yolo.py
sudo systemctl restart ultralytics-docker.service
```

#### 20.6.5 Web Gallery for Viewing Detections

A lightweight web server (Python stdlib, no Flask needed) serves all saved detection images in a browser-friendly gallery. It runs alongside the inference inside the same container.

**Start the gallery:**

```bash
./team1 gallery
```

**Access it:**
Open a browser on any device on the same network and go to `http://<pi-ip>:5000`.

**Features:**

- Shows all saved `detect_*.jpg` images in a **10-column grid**, newest first
- Auto-refreshes every 10 seconds
- Click any image for full-size view with **← Back to Gallery**, **< Prev** / **Next >** navigation links and **Escape** / **←** / **→** arrow key support
- Position indicator (e.g. "Image 3 of 25")
- Displays total detection count
- Zero configuration — just run the command
- **Prev / Next** navigation and **←** / **→** arrow keys on full-size image view

**Make it auto-start on boot** (one-time setup):

```bash
sudo systemctl stop ultralytics-docker.service
sudo sed -i '/^ExecStop=/i ExecStartPost=/usr/bin/docker exec -d ultralytics-pi-cam python3 /ultralytics/data/web_gallery.py' /etc/systemd/system/ultralytics-docker.service
sudo systemctl daemon-reload
sudo systemctl start ultralytics-docker.service
```

The gallery will now start automatically whenever the inference service starts.

#### 20.6.6 Alternative Ways to View Images

**Via scp (no browser needed):**

```bash
# From your laptop
scp slaan1974@ . < pi-ip > :~/ultralytics/data/detect_*.jpg
```

**Via VNC (graphical desktop):**

```bash
# On the Pi (if using Pi OS with desktop)
sudo systemctl enable vncserver
sudo systemctl start vncserver
# Connect via RealVNC Viewer, then browse ~/ultralytics/data/
```

**Via docker cp:**

```bash
docker cp ultralytics-pi-cam:/ultralytics/data/detect_20260101_120000.jpg .
```

**Monitor live log stream:**

```bash
./team1 logs
# Shows: "SAVED /ultralytics/data/detect_20260101_120000.jpg  (2 person, dog)"
```

#### 20.6.7 Camera Troubleshooting (Docker-Specific)

| Problem                                             | Likely Cause                                  | Check / Fix                                                                              |
| --------------------------------------------------- | --------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `No /dev/video*` devices                            | Camera not enabled in config                  | `sudo raspi-config` → Interface → Camera → Enable → Reboot                               |
| `Device not found` on container start               | Missing `--device` flag                       | Re-run `./team1` (dynamically maps all video nodes)                                      |
| `Picamera2` not available                           | Ubuntu container lacks libcamera              | Not required — inference script falls back to OpenCV V4L2 automatically                  |
| Black or green captured frames                      | Wrong pixel format                            | Ensure format is `"RGB888"`, not `"BGR888"` or `"YUYV"`                                  |
| Camera works but no detections saved                | Threshold too high or nothing in frame        | Lower `CONF_THRESH` (e.g. 0.1) temporarily to test; point camera at a person or object   |
| Camera works but detections are wrong               | Wrong model or poor lighting                  | Use `yolo26n.pt`; add more light or use `imgsz=640`                                      |
| Inference is very slow (>1s per frame)              | CPU throttling or wrong export format         | Verify NCNN model is loaded (not PyTorch); check `sudo raspi-config` → Performance → GPU |
| Web gallery not loading in browser                  | Port blocked or container not sharing network | Container uses `--net=host`; try `curl http://localhost:5000` on the Pi                  |
| Container keeps restarting                          | OOM or Python crash                           | `docker logs ultralytics-pi-cam` to see crash reason; check `free -h` for memory         |
| `libcamera` errors about camera not found           | Camera ribbon cable loose                     | Re-seat the camera cable; run `rpicam-hello -t 2000` on the Pi (not in container)        |
| Permission denied on `/dev/video*` inside container | `--device` flag missing                       | Re-run `./team1` to recreate container with correct device mapping                       |

### 20.7 Diagnostics: `support` Script

```bash
./support        # Full diagnostics (system, camera, docker, service, model, results, network)
./support quick  # Quick overview
./support camera # Detailed camera test (V4L2 capture inside container)
./support docker # Docker-specific diagnostics (image, container, daemon)
./support logs   # Show recent service + container + detection logs
./support fix    # Suggest fixes for any detected issues
```

**Commands:**

| Command                          | Description                                                                                                   |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `./support` (or `./support all`) | Full diagnostics — runs all checks and prints a summary                                                       |
| `./support quick`                | Quick system/service/camera/results overview (no detailed checks)                                             |
| `./support camera`               | Detailed camera diagnostics — checks video devices, V4L2 access inside container, and attempts a test capture |
| `./support docker`               | Docker-specific checks — daemon status, image pulled, container running, resource usage                       |
| `./support logs`                 | Show last 30 lines of service journal + last 20 lines of container logs + last 5 detection entries            |
| `./support fix`                  | Interactive fix suggestions — checks for common issues and prints step-by-step fix commands                   |
| `./support --help`               | Show usage and all available commands                                                                         |

---

## 21. Team 2 — Local (Non-Docker) Deployment with Camera v2 Auto-Start

### 21.1 Overview

**Goal:** Deploy YOLO inference natively on the Pi 4 OS (no Docker) with Camera v2, auto-starting on every reboot.

**Architecture:**

```
[Boot] → systemd → ultralytics-local.service → inference script → camera→results
```

### 21.2 Setup & Management: `team2` Script

A single executable script `team2` handles the entire lifecycle. Copy it to the Pi and run:

```bash
./team2 # Full setup: installs system deps, creates venv, exports NCNN model,
# creates inference script, installs and starts systemd service
```

**Commands:**

| Command                              | Description                                                                        |    Time    |
| ------------------------------------ | ---------------------------------------------------------------------------------- | :--------: |
| `./team2` (or `./team2 setup`)       | Full installation — run once on first deployment                                   |  ~30 min   |
| `./team2 setup --force`              | Full installation, redo all steps (ignore cached state)                            |  ~30 min   |
| `./team2 update`                     | **Fast re-write** — re-creates scripts and restarts services after editing `team2` | **~2 sec** |
| `./team2 status`                     | Show inference service + gallery service, model, results, and camera status        |   ~2 sec   |
| `./team2 logs`                       | Follow live inference log (`journalctl -fu`)                                       |     —      |
| `./team2 snapshot`                   | Capture test frame via `rpicam-jpeg` (works over SSH)                              |   ~3 sec   |
| `./team2 camera-test`                | Validate camera hardware via `rpicam-hello --nopreview`                            |   ~3 sec   |
| `./team2 gallery`                    | Start web gallery on port 5000 (Python stdlib)                                     |     —      |
| `./team2 stop` / `start` / `restart` | Manage _both_ inference + gallery services                                         |   ~2 sec   |
| `./team2 --help`                     | Show usage and all available commands                                              |     —      |

**After editing `team2`** (e.g., changing `FRAME_SKIP`, gallery CSS, etc.), run `./team2 update` instead of re-running full setup. It only re-writes the embedded scripts to disk and restarts the services — no apt, no pip, no model export. Takes ~2 seconds.

The gallery service (`ultralytics-gallery.service`) is created and enabled during `./team2 setup` alongside the inference service. Both auto-start on boot.

### 21.3 Diagnostics: `support2` Script

```bash
./support2        # Full diagnostics (system, camera, service, model, results, network)
./support2 quick  # Quick overview
./support2 camera # Detailed camera test (rpicam-jpeg capture)
./support2 logs   # Show recent service + detection logs
./support2 fix    # Suggest fixes for any detected issues
./support2 --help # Show usage and all available commands
```

### 21.4 What Happens After Reboot

1. `systemd` starts `ultralytics-local.service` (inference) and `ultralytics-gallery.service` (web gallery) after network is online
2. Inference service launches inference script via venv Python
3. Gallery service launches `web_gallery.py` on port 5000
4. Inference script initializes camera (picamera2 — native, libcamera available) and loads NCNN model
5. Annotated frames saved to `~/ultralytics-local/results/` (only on detection)
6. Detection logs written to `~/ultralytics-local/results/detections.jsonl`
7. If a script crashes, `Restart=always` re-launches after the configured delay (10s inference, 5s gallery)

### 21.5 File Layout

```
~/ultralytics-local/
├── venv/                         # Python virtual environment
├── models/
│   └── yolo26n_ncnn_model/      # NCNN model (model.ncnn.param + .bin + metadata.yaml)
├── results/
│   ├── detect_YYYYMMDD_HHMMSS.jpg   # Annotated detection images
│   └── detections.jsonl              # Detection log (JSON lines)
├── run_yolo.py                   # Inference script (uses picamera2 directly)
├── web_gallery.py                # Lightweight gallery server (port 5000)
│
├── /etc/systemd/system/ultralytics-local.service    # Inference service (auto-start)
└── /etc/systemd/system/ultralytics-gallery.service  # Gallery service (auto-start)
```

### 21.6 Switching Models / Updating Ultralytics

```bash
# Switch model
source ~/ultralytics-local/venv/bin/activate
sudo systemctl stop ultralytics-local.service
yolo export model=yolo26s.pt format=ncnn imgsz=320
mv yolo26s_ncnn_model ~/ultralytics-local/models/
sudo systemctl start ultralytics-local.service

# Update Ultralytics
sudo systemctl stop ultralytics-local.service
source ~/ultralytics-local/venv/bin/activate
pip install -U ultralytics
sudo systemctl start ultralytics-local.service
```

### 21.7 Configuration Environment Variables

The inference script reads these optional environment variables at startup:

| Parameter       | Default | Env Variable      | Effect                                             |
| --------------- | ------- | ----------------- | -------------------------------------------------- |
| Frame skip      | 10      | `FRAME_SKIP`      | Process every Nth frame (10 = ~3 inf/sec at 30fps) |
| Latest interval | 15      | `LATEST_INTERVAL` | Save `latest.jpg` every Nth processed frame        |
| Confidence      | 0.25    | `CONF_THRESH`     | Raise to reduce false positives                    |
| IoU threshold   | 0.45    | `IOU_THRESH`      | Raise for more overlapping boxes                   |
| Image size      | 320     | `IMGSZ`           | Lower = faster but less accurate                   |
| Max FIFO        | 1000    | `MAX_FIFO`        | Max detection images before oldest are deleted     |

**Override via systemd drop-in** (survives service restarts, no script edits):

```bash
sudo mkdir -p /etc/systemd/system/ultralytics-local.service.d
sudo tee /etc/systemd/system/ultralytics-local.service.d/frame_skip.conf << 'EOF'
[Service]
Environment=FRAME_SKIP=20
EOF
sudo systemctl daemon-reload
sudo systemctl restart ultralytics-local.service
```

**Override for a single manual run:**

```bash
FRAME_SKIP=5 ./team2
```

---

## 22. Team Comparison Summary

| Aspect               |              Team 1 — Docker              |                  Team 2 — Local                   |
| -------------------- | :---------------------------------------: | :-----------------------------------------------: |
| Isolation            |        ✅ Full container isolation        |                ❌ Runs on host OS                 |
| Setup time           |            ~5 min (pull image)            |               ~15 min (pip install)               |
| Disk usage           |              ~1.5 GB (image)              |                ~2 GB (venv + deps)                |
| Camera passthrough   |          `--device /dev/video*`           |                  Direct (native)                  |
| GPU access           |    VideoCore via NCNN inside container    |            VideoCore via NCNN natively            |
| Auto-start mechanism |    systemd wrapper around docker exec     |              Direct systemd service               |
| Overhead             |      Negligible (native performance)      |                       None                        |
| Update strategy      |          `docker pull` new image          |             `pip install -U` in venv              |
| Best for             | Teams wanting reproducibility & isolation | Teams wanting simplicity & direct hardware access |

---

## 23. Deployment Fixes & Status (June 2026)

### 23.1 Issue: picamera2 / libcamera Conflict

**Symptom:** `./team1 snapshot` fails with `ModuleNotFoundError: No module named 'libcamera'` because the Ubuntu container (`ultralytics/ultralytics:latest-arm64`) has `picamera2` installed in site-packages but lacks `libcamera` (which is a Raspberry Pi OS native library, not available in Ubuntu).

**Root cause:** The `ultralytics/ultralytics:latest-arm64` image is Ubuntu 24.04-based. `picamera2` is pre-installed in `/usr/local/lib/python3.12/dist-packages/` inside the image but its dependency `libcamera` is only available on Raspberry Pi OS.

**Fix applied 2026-06-22:**

| File            | Change                                                                                                                                        |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `team1:501-508` | `create_container` — changed picamera2 uninstall from silently suppressed (`> /dev/null 2>&1`) to **visible output** with pass/fail messaging |
| `team1:610-611` | `cmd_snapshot` — added `pip uninstall -y picamera2` before V4L2 capture so snapshot works even if picamera2 is still present                  |
| `support:684`   | `camera` diagnostic — replaced broken picamera2 test capture with same OpenCV V4L2 approach used by `./team1 snapshot`                        |

### 23.2 How Camera Access Works Now

All camera access inside the container uses **OpenCV V4L2** (`cv2.VideoCapture(path, cv2.CAP_V4L2)`):

```
run_yolo.py:      try picamera2 → ImportError? → use V4L2 (automatic fallback)
cmd_snapshot:     pip uninstall picamera2 → use V4L2 directly
support camera:   pip uninstall picamera2 → use V4L2 directly
```

The `run_yolo.py` inference script at `team1:128-132` already had a proper `try/except ImportError` fallback. Once `picamera2` is removed from the image's site-packages, it falls through to V4L2 automatically.

### 23.3 Issue: UnicodeEncodeError from Ultralytics Emoji Logging

**Symptom:** During `model.export()` in Team 2, Python crashes with `UnicodeEncodeError: 'charmap' codec can't encode character '\U0001f680'`. The export actually succeeds, but the heredoc's `print()` calls and `shutil.move()` after the export never execute because the Python process crashes first. Additionally, `pip` may show dependency conflict warnings (non-fatal).

**Root cause:** Raspberry Pi OS defaults to `ISO-8859-15` (latin9) locale, which only supports 256 characters. Ultralytics logging uses emoji (U+1F680 🚀, U+2705 ✅, U+26A0 ⚠️) and Unicode punctuation (U+2014 —). When Python's stdout is connected to a terminal with ISO-8859-15 encoding, any `print()` or `LOGGER.info()` containing these characters raises `UnicodeEncodeError` and terminates the process.

**Fix applied 2026-06-23:**

| File            | Change                                                                                                                                                                                                                    |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `team2:19-22`   | Added `export PYTHONIOENCODING=utf-8` and `export LC_ALL=C.UTF-8` globally at script start, before any Python invocations                                                                                                 |
| `team2:170-197` | Rewrote `export_model` heredoc — replaced em dash `—` with `-` in `print()`; changed `src` path from `~/$name` to `os.getcwd()/$name` (Ultralytics saves to CWD, not home); added fallback search for the model directory |

**Prevention:** The `PYTHONIOENCODING=utf-8` and `LC_ALL=C.UTF-8` exports force all Python subprocesses to use UTF-8 for stdout/stderr, avoiding encoding crashes regardless of the terminal's locale. These are set globally in `team2` so they apply to every Python call (install verification, export heredoc, inference script, gallery).

### 23.4 Issue: picamera2 Not Found in Venv (systemd Service Crash)

**Symptom:** The `ultralytics-local.service` fails immediately on startup with `ModuleNotFoundError: No module named 'picamera2'` (or after that was fixed: `No module named 'libcamera'`). The systemd journal shows the service restarting repeatedly with the same traceback at `run_yolo.py:23`.

**Root cause:** On Raspberry Pi OS, `picamera2` depends on `libcamera`, a C/C++ library with Python bindings (`python3-libcamera`) that is only available as an apt package — there is no pip package for it. Installing `picamera2` via `pip` inside an isolated venv works for `picamera2` itself, but the venv cannot see the system-installed `libcamera`, causing `import libcamera` to fail at runtime.

Additionally, `pip install picamera2` requires building `python-prctl` from source, which needs `libcap-dev` system headers.

**Fix applied 2026-06-23 (revised):**

| File            | Change                                                                                                                                            |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `team2:102`     | Added `libcap-dev` to the `apt install` list (build dependency for `python-prctl`)                                                                |
| `team2:110-113` | Changed venv creation to `python3 -m venv --system-site-packages "${VENV_DIR}"` so the venv inherits system-installed `libcamera` and `picamera2` |
| `team2:150-151` | **Removed** `pip install picamera2` — no longer needed since the system package is visible via `--system-site-packages`                           |

**Why `--system-site-packages` is safe here:** The flag makes the venv fall back to system site-packages only for packages not installed in the venv. All critical ML packages (PyTorch, Ultralytics, numpy, etc.) are installed via `pip` inside the venv and take priority. `libcamera` and `picamera2` are the only system packages used, and they don't conflict with any pip-installed packages.

### 23.5 Deployment Quick Reference

```bash
# ── After reboot, verify ──
./team1 status

# ── Common management ──
./team1 logs     # Live inference log (Ctrl+C to exit)
./team1 snapshot # Test camera capture
./team1 restart  # Restart service
./team1 shell    # Enter container bash

# ── If camera or inference fails ──
docker exec ultralytics-pi-cam pip uninstall -y picamera2
./team1 restart

# ── Run diagnostics ──
./support        # Full diagnostics (all checks)
./support quick  # Quick overview only
./support camera # Detailed camera diagnostics
./support docker # Docker-specific diagnostics
./support logs   # Show log tails (service + container + detections)
./support fix    # Suggested fixes

# ── Team 2 management (local deployment) ──
./team2 status   # Inference + gallery service status
./team2 stop     # Stop both services
./team2 start    # Start both services
./team2 restart  # Restart both services
./team2 logs     # Follow live inference log
./team2 snapshot # Capture test frame
./team2 gallery  # Start gallery standalone (port 5000)

# ── Team 2 diagnostics ──
./support2        # Full diagnostics (all checks)
./support2 quick  # Quick overview only
./support2 camera # Detailed camera diagnostics (rpicam-* tools)
./support2 logs   # Show log tails (service + detections)
./support2 fix    # Suggested fixes
```

---

## 24. Camera Testing with `rpicam-*` Tools (Team 2)

### 24.1 Overview

Raspberry Pi OS Bookworm renamed the camera tools from `libcamera-*` to `rpicam-*`. These CLI tools are built on `libcamera` and work without a desktop environment (critical for headless/SSH setups).

| Tool           | Purpose                                  | SSH-safe?        |
| -------------- | ---------------------------------------- | ---------------- |
| `rpicam-hello` | Quick camera detection test              | ✅ `--nopreview` |
| `rpicam-jpeg`  | Capture JPEG still images                | ✅ `--nopreview` |
| `rpicam-still` | Advanced still capture (raspistill-like) | ✅ `--nopreview` |
| `rpicam-vid`   | Video recording (H.264)                  | ✅ `--nopreview` |
| `rpicam-raw`   | Raw Bayer frame capture                  | ✅ `--nopreview` |

### 24.2 Local Testing (on the Pi)

```bash
# Quick hardware test (2 sec, no display needed)
rpicam-hello --nopreview --timeout 2000

# Capture a test JPEG (640x480, 2 sec timeout)
rpicam-jpeg --nopreview --timeout 2000 --width 640 --height 480 --output test.jpg

# Show camera sensor info
rpicam-hello --nopreview --timeout 500 --info-text "Sensor: %sensor  Resolution: %width x %height"

# Stream video over TCP (view from another machine)
rpicam-vid --nopreview -t 0 --inline --listen -o tcp://0.0.0.0:8888
```

### 24.3 Remote Camera Check (from Laptop)

These methods let you verify the Pi's camera works **without a monitor** attached to the Pi.

**Method A — SSH + rpicam-jpeg + SCP (recommended):**

```bash
# From your laptop — capture frame and copy back in one step
ssh pi@ < pi-ip > "rpicam-jpeg --nopreview --timeout 2000 --width 640 --height 480 -o /tmp/pi_check.jpg"
scp pi@ . < pi-ip > :/tmp/pi_check.jpg && open pi_check.jpg

# Or one-liner: pipe JPEG directly to stdout
ssh pi@ < pi-ip > "rpicam-jpeg --nopreview --timeout 1500 --width 640 --height 480 -o -" > pi_check.jpg
```

**Method B — SSH sensor info (no image needed):**

```bash
# Get camera info without capturing an image
ssh pi@ < pi-ip > "rpicam-hello --nopreview --timeout 1000 --info-text 'Sensor: %sensor (%width x %height)' 2>&1"
# Expected output: "Sensor: imx219 3280 x 2464" (or similar)
```

**Method C — Check video devices remotely:**

```bash
# Check camera appears in /dev/video*
ssh pi@ < pi-ip > "ls -la /dev/video*"

# Check camera is enabled in config
ssh pi@ < pi-ip > "grep -i 'camera\|start_x' /boot/config.txt 2>/dev/null || grep -i 'camera\|start_x' /boot/firmware/config.txt 2>/dev/null"
```

**Method D — Use `./team2 camera-test` (wraps rpicam-hello):**

```bash
ssh pi@ < pi-ip > "cd ~ && ./team2 camera-test"
# Returns: "Camera test PASSED — sensor detected and operational"
```

**Method E — Use `./team2 snapshot` (captures JPEG):**

```bash
ssh pi@ < pi-ip > "cd ~ && ./team2 snapshot"
scp pi@ . < pi-ip > :~/ultralytics-local/results/snapshot.jpg
```

### 24.4 Troubleshooting Camera Issues Remotely

| Symptom                         | Remote Check                                                       | Fix                                                        |
| ------------------------------- | ------------------------------------------------------------------ | ---------------------------------------------------------- |
| No `/dev/video*` devices        | `ssh pi@<pi-ip> "ls /dev/video*"`                                  | `sudo raspi-config` → Interface → Camera → Enable → Reboot |
| `rpicam-hello` exits with error | `ssh pi@<pi-ip> "rpicam-hello --nopreview --timeout 2000 2>&1"`    | Check ribbon cable; re-seat it                             |
| `picamera2` import fails        | `ssh pi@<pi-ip> "python3 -c 'from picamera2 import Picamera2'"`    | `sudo apt install python3-picamera2`                       |
| YOLO service not running        | `ssh pi@<pi-ip> "sudo systemctl status ultralytics-local.service"` | `ssh pi@<pi-ip> "./team2 restart"`                         |

---

## 25. Cleanup — Remove Docker & Team 1 Artifacts (Free Disk Space)

### 25.1 Overview

Before deploying Team 2 (local), reclaim disk space by removing all Docker resources and Team 1 data. The `cleanup.sh` script handles this automatically.

### 25.2 Script Usage

```bash
./cleanup.sh --status # Preview current Docker disk usage (no changes)
./cleanup.sh          # Show usage then prompt for confirmation
./cleanup.sh --force  # Skip confirmation, clean everything
```

### 25.3 What Gets Removed

| Resource             | Path / Identifier                      | Size (approx) |
| -------------------- | -------------------------------------- | :-----------: |
| Systemd service      | `ultralytics-docker.service`           |       —       |
| Docker container     | `ultralytics-pi-cam`                   |    ~100 MB    |
| Docker image         | `ultralytics/ultralytics:latest-arm64` |    ~1.5 GB    |
| All other containers | Any remaining containers               |    Varies     |
| Docker system cache  | Build cache, volumes, networks         |    ~500 MB    |
| Team 1 results       | `~/ultralytics/data/`                  |    Varies     |
| **Total freed**      |                                        | **~2.5 GB+**  |

### 25.4 Manual Cleanup (Without Script)

````bash
# Stop and remove service
sudo systemctl stop ultralytics-docker.service
sudo systemctl disable ultralytics-docker.service
sudo rm /etc/systemd/system/ultralytics-docker.service
sudo systemctl daemon-reload

# Remove container and image
docker stop ultralytics-pi-cam
docker rm ultralytics-pi-cam
docker rmi ultralytics/ultralytics:latest-arm64

# Full Docker cleanup
docker system prune -a -f --volumes

# Remove Team 1 data
rm -rf ~/ultralytics/data


## 26. Remote Camera Viewing — Web Gallery

### 26.1 Overview

The Team 2 inference script continuously saves the latest annotated camera frame to `latest.jpg` (every ~15 processed frames). The web gallery server (`web_gallery.py`) serves this as a live view, detection images with download links, and dedup counter badges.

Key features:
- **Live view** — latest annotated frame, auto-refreshes every 5 seconds
- **Dedup counter** — when the same single object appears consecutively, a counter (max 10) tracks repetitions instead of saving duplicate images
- **FIFO disk management** — keeps at most 1000 `detect_*.jpg` files; oldest auto-purged
- **Latest 1000 / Oldest 1000** — browse newest or oldest images from the gallery
- **Dedup-adjusted stats** — `./team2 status` shows both file count and the dedup-adjusted detection total

Everything runs **on the Pi** using Python stdlib only (no Flask, no Node.js). Access it from any browser on the same network.

### 26.2 Accessing the Gallery

The gallery auto-starts on boot via `ultralytics-gallery.service` (created by `./team2 setup`).
```bash
# Start/stop the gallery manually (manages both inference + gallery)
./team2 start
./team2 stop

# Or start standalone (foreground, for testing)
./team2 gallery
````

Then open a browser at:

```
http://<pi-ip>:5000
```

The Pi's IP address is shown at the top of the page and in the terminal when the gallery starts.

### 26.3 Page Layout

| Section                | Description                                                                                                                                   |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| **Live View**          | Latest annotated camera frame at 640x480 — auto-refreshes every 5 seconds. Shows whatever the camera sees with YOLO bounding boxes and labels |
| **Last 10 Detections** | Thumbnails of the 10 most recent detection images with **View** (full size) and **Download** links                                            |
| **Full Gallery**       | Click "Full Detection Gallery" to see all saved detection images (10-column grid, auto-refresh every 10s)                                     |

### 26.4 Downloading Images

Each detection thumbnail has a **Download** link that triggers a save dialog in your browser. Image files are named `detect_YYYYMMDD_HHMMSS.jpg`.

You can also download the images directly via command line:

```bash
# From your laptop — download all detection images
scp pi@ . < pi-ip > :~/ultralytics-local/results/detect_*.jpg

# Or via HTTP
curl -O http:// < pi-ip > :5000/download/detect_20260624_143201.jpg
```

### 26.5 Sharing the Gallery

Anyone on the same local network can access the gallery at `http://<pi-ip>:5000`.

**To make it accessible over the internet**, you would need to:

1. Set up port forwarding on your router (port 5000 → Pi's local IP)
2. Or use a tunnel service like `ngrok http 5000`
3. Or use Tailscale/ZeroTier for a secure VPN

### 26.6 How Live View Works

1. `run_yolo.py` runs YOLO inference on every Nth frame
2. It generates an annotated frame (with bounding boxes/labels) for every processed frame
3. Every 15 processed frames, it saves the annotated frame to `~/ultralytics-local/results/latest.jpg`
4. The web gallery serves `/latest` with `Cache-Control: no-cache` headers
5. The browser `<img>` tag includes a timestamp query parameter to force reload
6. The page auto-refreshes every 5 seconds via `<meta http-equiv="refresh">`

**Performance impact:** Negligible — the annotated frame is already generated for detection saving; `latest.jpg` is just an extra JPEG write every ~1.5 seconds.

### 26.7 Updating the Gallery

After updating the `team2` script (e.g., if you pulled changes), regenerate the gallery:

```bash
# Option A: Re-run full setup (regenerates both services)
./team2 stop
./team2
./team2 start

# Option B: Just copy the new gallery script
./team2 stop
# Copy the new web_gallery.py from the updated team2 repo
./team2 start

# Test the new version standalone
./team2 gallery
```

```

---

## 27. Wildlife Detection — Person, Cat, Bird

### 27.1 Overview

The **Team 2 (local)** deployment runs a dedicated wildlife detection mode. It captures a frame every **N seconds** (configurable, default 5), runs YOLO inference, and **only saves images** when one of the target classes is detected:

| Target | COCO Class ID |
|--------|:------------:|
| Person | 0 |
| Cat | 15 |
| Bird | 16 |

Frames without any of these targets are **silently discarded** — no disk waste. A `latest.jpg` is saved every capture cycle (regardless of detections) for the web gallery Live View.

### 27.2 How It Works

```

[Camera] → every Ns → YOLO inference → save latest.jpg → filter [0,15,16] → match?
→ YES → save detect_TS.jpg + JSONL + FIFO cleanup
→ NO → discard silently

````

Each saved image includes:
- **Timestamp overlay** on the image itself (`cv2.putText` — "2026-06-27 14:32:01" in green, bottom-left)
- **Timestamp in filename** (`detect_20260627_143201.jpg`)
- **JSONL log entry** with class names, confidences, and timestamp

### 27.3 Configuration

Settings are read from `~/ultralytics-local/results/config.json` (written by the web gallery settings panel), with environment variables taking priority over file values.

| Variable | Default | config.json key | Purpose |
|----------|---------|-----------------|---------|
| `CAPTURE_INTERVAL` | `5` | `capture_interval` | Seconds between capture+inference cycles |
| `CONF_THRESH` | `0.25` | — | Detection confidence threshold |
| `IOU_THRESH` | `0.45` | — | IoU threshold for NMS |
| `IMGSZ` | `320` | — | Inference image size (lower = faster) |
| `TARGET_CLASSES` | `0,15,16` | `target_classes` | Comma-separated COCO class IDs to keep |
| `MAX_FIFO` | `1000` | `max_fifo` | Max saved images before oldest auto-deleted |
| `MIN_FREE_SPACE_GB` | `1` | `min_free_space_gb` | Minimum free space (GB) to always keep on device |
| `CAMERA_RESOLUTION` | `1920x1080` | `camera_resolution` | Camera capture resolution — `1920x1080` (Full HD) or `3280x2464` (8MP Max) |
| `AUTO_REFRESH` | `10` | `auto_refresh` | Seconds between page auto-refresh — 1s, 5s, 10s, 30s, 60s, or 5min |

**Override for a test run:**

```bash
CAPTURE_INTERVAL=3 CONF_THRESH=0.5 ./team2 wildlife
````

**Override permanently (systemd drop-in):**

```bash
sudo mkdir -p /etc/systemd/system/ultralytics-wildlife.service.d
sudo tee /etc/systemd/system/ultralytics-wildlife.service.d/capture.conf << 'EOF'
[Service]
Environment=CAPTURE_INTERVAL=3
Environment=CONF_THRESH=0.5
EOF
sudo systemctl daemon-reload
sudo systemctl restart ultralytics-wildlife.service
```

### 27.4 Usage

**Run in foreground (for testing):**

```bash
./team2 wildlife
```

Press `Ctrl+C` to stop. All saved images go to `~/ultralytics-local/results/`.

**Run as a service (auto-start on boot):**

```bash
./team2 restart
```

**View saved detections in the browser:**

```bash
./team2 gallery
```

### 27.5 Web Gallery Features

The gallery runs on **port 5000** at `http://<pi-ip>:5000` and provides:

| Feature            | Description                                                                                                                    |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------ |
| **Live View**      | Latest camera frame (annotated, updates every capture cycle)                                                                   |
| **Class Filter**   | Dropdown to show only Person / Cat / Bird detections in the gallery                                                            |
| **Settings Panel** | Gear icon ⚙ opens a modal to change capture interval, max files, min free space, camera resolution, and auto-refresh interval |
| **Gallery**        | 10-column grid of all saved `detect_*.jpg` images with lightbox (prev/next via buttons or arrow keys) and download             |
| **FIFO Cleanup**   | Oldest files auto-deleted when max count exceeded or free space drops below threshold                                          |

#### 27.5.1 Settings Panel

Click the ⚙ gear icon in the top bar of any gallery page to open the settings modal:

| Setting               | Default             | Range                 | Description                                                               |
| --------------------- | ------------------- | --------------------- | ------------------------------------------------------------------------- |
| Capture Interval      | 5s                  | 1s – 5min             | Time between camera capture + inference cycles                            |
| Max Files             | 1000                | 10 – 1,000,000        | FIFO limit — oldest images deleted when exceeded                          |
| Min Free Space (GB)   | 1 GB                | 0 – 100 GB            | System always keeps at least this much disk free by deleting old images   |
| Camera Resolution     | 1920×1080 (Full HD) | 1920×1080 / 3280×2464 | Pi Camera v2 capture resolution — Full HD or 8MP Max                      |
| Auto-Refresh Interval | 10s                 | 1s – 5min             | How often the gallery page auto-refreshes — pauses while lightbox is open |

The modal also shows:

- **Current file count** — number of `detect_*.jpg` files saved
- **Disk usage** — used / free / total space on the results partition

When **Camera Resolution** is changed, the inference process detects it within ~5 iterations (~25s), stops the camera, and re-initialises it at the new resolution — no systemd restart needed.

Saving writes to `config.json` — the inference process picks up changes within ~5 iterations.

#### 27.5.2 Class Filter

The dropdown next to the gear icon filters the detection gallery to show only images matching the selected class. Available options:

- **All** — show every saved detection
- **Person** — only frames containing at least one person
- **Cat** — only frames containing at least one cat
- **Bird** — only frames containing at least one bird

The filter is persistent across Live View / Latest / Oldest gallery pages via the `?class=` query parameter.

#### 27.5.3 Gallery Endpoints

| Endpoint                    | Description                                                                                                                                                                                                          |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GET /`                     | Main page: Live View + last 10 detections (5s auto-refresh; pauses while lightbox is open)                                                                                                                           |
| `GET /?class=cat`           | Filtered main page                                                                                                                                                                                                   |
| `GET /gallery`              | Latest detection images (10s auto-refresh)                                                                                                                                                                           |
| `GET /gallery?view=oldest`  | Oldest detection images                                                                                                                                                                                              |
| `GET /gallery?class=person` | Filtered gallery                                                                                                                                                                                                     |
| `GET /config`               | Current settings as JSON (includes disk usage and file count)                                                                                                                                                        |
| `POST /config`              | Update settings via JSON body                                                                                                                                                                                        |
| `GET /latest`               | Annotated `latest.jpg` (no-cache for live feed)                                                                                                                                                                      |
| `GET /thumb/{name}`         | Raw JPEG bytes for gallery grid thumbnails (no `Content-Disposition`, so browser renders inline)                                                                                                                     |
| `GET /image/{name}`         | Full-size detection image in an HTML page with **← Live View**, **← Gallery**, **< Prev** / **Next >** navigation links, position indicator (e.g. "Image 3 of 25"), and **Escape** / **←** / **→** arrow key support |
| `GET /download/{name}`      | Detection image with download prompt                                                                                                                                                                                 |

#### 27.5.4 Image Navigation

Both the lightbox (click thumbnail) and full-page view (click **View**) support browsing through detection images:

| Action           | Lightbox                                                                      | Full-page (`/image/{name}`)                          |
| ---------------- | ----------------------------------------------------------------------------- | ---------------------------------------------------- |
| **Previous**     | Click ◀ button or press ←                                                    | Click **< Prev** link or press ←                     |
| **Next**         | Click ▶ button or press →                                                    | Click **Next >** link or press →                     |
| **Close / Back** | Click **✖ Close** button, click overlay, click **← Live View**, or press Esc | Click **← Live View** or **← Gallery**, or press Esc |

When the lightbox opens, the page's auto-refresh timer is **paused** (via `clearTimeout`) so the image stays on screen indefinitely. Auto-refresh resumes when the lightbox closes.

The full-page view also shows the current image position (e.g. "Image 3 of 25") in the navigation bar.

### 27.6 File Layout

```
~/ultralytics-local/
├── run_wildlife.py                # Wildlife detection inference script
├── web_gallery.py                 # Web gallery (HTTP server)
├── models/yolo26n_ncnn_model/     # NCNN model
├── results/
│   ├── config.json                 # Shared settings (written by gallery, read by inference)
│   ├── latest.jpg                  # Latest annotated frame (live view, overwritten every cycle)
│   ├── detect_20260627_143201.jpg  # Saved on target detection (timestamp in name)
│   ├── detect_20260627_143206.jpg  # ...
│   └── detections.jsonl            # JSONL log of all saved detections
└── venv/                          # Python venv (unchanged)
```

### 27.7 JSONL Log Format

```json
{
  "timestamp": "2026-06-27 14:32:01",
  "frame_file": "detect_20260627_143201.jpg",
  "targets": ["cat", "bird"],
  "confidences": ["0.92", "0.78"],
  "class_ids": [15, 16]
}
```

### 27.8 Performance Tips on Pi 4

| Setting               |  ~FPS   | Notes                                     |
| --------------------- | :-----: | ----------------------------------------- |
| Default (320px, NCNN) | ~10 FPS | 5s interval gives plenty of headroom      |
| `IMGSZ=224`           | ~15 FPS | Faster but less accurate on small targets |
| `IMGSZ=640`           | ~3 FPS  | Better detection of distant objects       |

The default 5-second capture interval leaves the CPU idle ~95% of the time, keeping thermals low for 24/7 operation. Longer intervals (30s–5min) reduce disk writes and CPU load further.

### 27.9 What Changed

| File      | Change                                                                                                                                                                                                                                                                      |
| --------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `team2`   | Replaced embedded inference script with `run_wildlife.py` (periodic class-filtered capture + `latest.jpg`)                                                                                                                                                                  |
| `team2`   | Added `load_config()` / `write_default_config()` for shared `config.json`                                                                                                                                                                                                   |
| `team2`   | Added free-space-aware FIFO cleanup (`min_free_space_gb`) via `os.statvfs`                                                                                                                                                                                                  |
| `team2`   | Added polling 1s sleep loop so capture interval changes take effect promptly                                                                                                                                                                                                |
| `team2`   | Added `/config` (GET/POST) endpoints to web gallery for runtime settings                                                                                                                                                                                                    |
| `team2`   | Added class filter (Person/Cat/Bird) dropdown in gallery live view and gallery pages                                                                                                                                                                                        |
| `team2`   | Added settings modal (gear icon) with capture interval, max files, min free space, and camera resolution inputs                                                                                                                                                             |
| `team2`   | Renamed `SERVICE_NAME` from `ultralytics-local.service` to `ultralytics-wildlife.service`                                                                                                                                                                                   |
| `team2`   | Updated INDEX_HTML and GALLERY_HTML templates with filter/settings/disk info                                                                                                                                                                                                |
| `team2`   | Changed gallery grids to `repeat(10, 1fr)` for 10-column layout                                                                                                                                                                                                             |
| `team2`   | Added prev/next buttons + arrow key navigation to lightbox in both INDEX_HTML and GALLERY_HTML                                                                                                                                                                              |
| `team2`   | Added **< Prev** / **Next >** links, position indicator, and **←** / **→** arrow keys to `send_image()` full-page view                                                                                                                                                      |
| `team2`   | Fixed unescaped `%` in Python `%`-formatted templates: JavaScript `% n` modulo and CSS `top:50%;transform:translateY(-50%)` (both caused "not enough arguments for format string" 503 error)                                                                                |
| `team2`   | Added `/thumb/{name}` endpoint returning raw JPEG bytes; thumbnails in grid changed from `/image/{name}` (full HTML page) to `/thumb/{name}` so browser renders them correctly                                                                                              |
| `team2`   | Lightbox JS selector updated from `[src^=\"/image/\"]` to `[src^=\"/thumb/\"]` to match new thumbnail src                                                                                                                                                                   |
| `team2`   | Added `.detection-grid` CSS to GALLERY_HTML — gallery page was missing grid styling for the `detection-grid` class used by `_detection_cards()`, causing cards to stack vertically instead of in a 10-column raster on `/gallery`                                           |
| `team2`   | Changed `.card img` from `object-fit: cover` to `object-fit: contain` in both INDEX_HTML and GALLERY_HTML — `cover` cropped thumbnails to a strip, `contain` shows the full image with letterboxing                                                                         |
| `team2`   | Changed gallery page grid from `repeat(10, 1fr)` to `repeat(auto-fill, minmax(220px, 1fr))` — each card at least 220px wide for viewable thumbnails; increased `.card img` height from 150px to 200px; removed redundant `.gallery` wrapper div                             |
| `team2`   | Lightbox auto-refresh fix: `clearTimeout(refreshTimer)` on lightbox open, `resetRefreshTimer()` on close — prevents lightbox image from disappearing on page reload; added `✖ Close` button and `← Live View` link to lightbox overlay in both INDEX_HTML and GALLERY_HTML |
| `team2`   | Camera resolution fix: removed `sensor_mode` kwarg from `create_still_configuration()`/`create_preview_configuration()` (picamera2 v0.5.2 doesn't support it)                                                                                                               |
| `team2`   | Camera resolution fix: close failed `Picamera2()` on each retry in `init_camera()` — prevents "Camera in Acquired state" lock on retries                                                                                                                                    |
| `team2`   | Camera resolution fix: `reconfig()` creates fresh `Picamera2` instead of reconfiguring (cleaner state); properly closes old camera before creating new one                                                                                                                  |
| `team2`   | Added `DIAG:` diagnostic logging in `reconfig()` and main loop (frame shape, plot result, latest.jpg write size)                                                                                                                                                            |
| `team2`   | Added `auto_refresh` to `CONFIG_DEFAULTS` and `load_gallery_config()` — saved to `config.json`, rendered into `REFRESH_MS` JS var and "auto-refresh every Ns" text in both INDEX_HTML and GALLERY_HTML                                                                      |
| `team2`   | Added `_sec_label()` helper — formats seconds as human label (e.g. 300→"5min")                                                                                                                                                                                              |
| `team2`   | Added Auto-Refresh Interval dropdown to settings modal in both INDEX_HTML and GALLERY_HTML — same options as capture interval (1s/5s/10s/30s/60s/5min)                                                                                                                      |
| `PLAN.md` | Updated this section; added Appendix A — Camera Resolution Troubleshooting                                                                                                                                                                                                  |

---

## 28. Data Drive — Windows-Compatible exFAT Partition

### 28.1 Overview

The Pi 4's SD card can host a dedicated **exFAT data partition** that is natively readable on Windows, macOS, and Linux without any special drivers. This partition stores all detection images (`detect_*.jpg`) and logs (`detections.jsonl`) from both Team 1 (Docker) and Team 2 (local) deployments.

**Why exFAT?**

- **Windows** — plug the SD card into any Windows PC; detection images appear as a regular drive
- **macOS** — native read/write support
- **Linux** — exFAT supported in kernel 5.4+
- No driver installation needed on any platform
- File size limit of 16 EB (practical for 24/7 time-lapse detection)

### 28.2 Architecture

```
SD Card Layout (32GB example):
┌─────────────────────────────────────┐
│ /dev/mmcblk0p1  (vfat, ~500MB)     │  Boot partition (config.txt, kernel)
├─────────────────────────────────────┤
│ /dev/mmcblk0p2  (ext4, ~23GB)      │  Root filesystem (Pi OS)
├─────────────────────────────────────┤
│ /dev/mmcblk0p3  (exFAT, ~6GB)      │  Data partition — label "WILDLIFE_DATA"
│   ├── .wildlife_data_sentinel       │  Sentinel file (idempotency check)
│   ├── team1/                        │  Team 1 results (detect_*.jpg, JSONL)
│   └── team2/                        │  Team 2 results (detect_*.jpg, JSONL)
└─────────────────────────────────────┘

Mount point: /mnt/wildlife-data
Symlinks:
  ~/ultralytics/data        → /mnt/wildlife-data/team1   (Team 1)
  ~/ultralytics-local/results → /mnt/wildlife-data/team2 (Team 2)
```

### 28.3 Setup Script

A single script `setup-data-drive.sh` handles the entire lifecycle:

```bash
# Set up SD card data partition (shrinks root, creates exFAT, reboots)
./setup-data-drive.sh sd

# Check status
./setup-data-drive.sh status

# Flush buffers and show Windows-safe unmount instructions
./setup-data-drive.sh sync

# Copy PLAN.md and TEST.md to the data drive for Windows access
./setup-data-drive.sh docs

# Remove data partition (teardown)
./setup-data-drive.sh remove
```

Read the full documentation at the top of `setup-data-drive.sh` for initramfs details, idempotency logic, and manual recovery steps.

### 28.4 How It Works

The setup has two phases:

**Phase 1 — Boot-time resize (initramfs):**

1. The script builds a gzipped cpio initramfs containing `e2fsck`, `resize2fs`, `fdisk`, `parted`, `mkfs.exfat`, `blkid`, and busybox
2. It adds `initramfs wildlife-initrd.img` to `config.txt`
3. On next boot, the initramfs `/init` runs before the root is mounted:
   - Mounts boot partition
   - Runs `e2fsck -f` on root partition
   - Runs `resize2fs -M` (shrinks to minimum)
   - Calculates target size (minimum + 2GB margin)
   - Runs `resize2fs` to that target
   - Runs `parted resizepart` to shrink partition 2
   - Creates partition 3 as exFAT
   - Formats as exFAT with label `WILDLIFE_DATA`
   - Writes sentinel file
   - Restores original config.txt
   - `switch_root` to real root filesystem

**Phase 2 — Post-reboot mount and symlinks:**

1. Mounts exFAT partition at `/mnt/wildlife-data`
2. Creates team1/ and team2/ subdirectories
3. Adds fstab entry for auto-mount
4. Migrates any existing detection images to the data partition
5. Sets up symlinks:
   - `~/ultralytics/data` → `/mnt/wildlife-data/team1`
   - `~/ultralytics-local/results` → `/mnt/wildlife-data/team2`

**Idempotency:** If the data partition already exists with a sentinel file, the script skips Phase 1 entirely. It only runs Phase 2 (mount + symlinks).

### 28.5 Usage with Team 1 and Team 2

After `setup-data-drive.sh sd` has been run and the Pi has rebooted, enable data drive mode for each team:

```bash
# Team 1 (Docker) — redirects RESULTS_DIR to /mnt/wildlife-data/team1
DATA_DRIVE=true ./team1 setup

# Team 2 (local) — redirects RESULTS_DIR to /mnt/wildlife-data/team2
DATA_DRIVE=true ./team2 setup

# Or set the env var permanently via systemd drop-in:
sudo mkdir -p /etc/systemd/system/ultralytics-docker.service.d
sudo tee /etc/systemd/system/ultralytics-docker.service.d/datadrive.conf << 'EOF'
[Service]
Environment=DATA_DRIVE=true
EOF
sudo systemctl daemon-reload
sudo systemctl restart ultralytics-docker.service
```

When `DATA_DRIVE=true` is set and the exFAT partition is mounted, the scripts:

1. Check that `/mnt/wildlife-data` is mounted
2. Verify the sentinel file `.wildlife_data_sentinel` exists
3. Create the team subdirectory if needed
4. Redirect `RESULTS_DIR` to the data drive path
5. Fall back gracefully with a warning if the drive is not available

### 28.6 Accessing Detection Images on Windows

1. **Shut down the Pi:** `sudo shutdown -h now`
2. **Remove the SD card** from the Pi
3. **Insert into a Windows PC** (use a USB SD card reader if needed)
4. **Open the `WILDLIFE_DATA` drive** in File Explorer — it appears as a normal drive with the label `WILDLIFE_DATA`
5. Browse to:
   - `WILDLIFE_DATA:\team1\` for Team 1 detection images
   - `WILDLIFE_DATA:\team2\` for Team 2 detection images
6. Copy images directly — no software installation needed

**Alternative — access over the network (without removing the SD card):**

```bash
# From Windows, use SCP (e.g. WinSCP) or:
# Map a network drive to \\<pi-ip>\mnt\wildlife-data
# Or use the web gallery at http://<pi-ip>:5000
```

### 28.7 Diagnostics

Both `support` and `support2` scripts include a `datadrive` command:

```bash
./support datadrive  # Check data drive health (Team 1 context)
./support2 datadrive # Check data drive health (Team 2 context)
```

Checks performed:

- Is `/mnt/wildlife-data` mounted?
- Filesystem type (should be exFAT)
- Free space remaining
- Sentinel file present?
- Symlinks pointing to the correct paths?
- fstab entry present?

The data drive health check is also included in the full diagnostics run (`./support` / `./support2`).

### 28.8 Troubleshooting

| Problem                                         | Cause                              | Fix                                                                                                                      |
| ----------------------------------------------- | ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `DATA_DRIVE=true` but results go to default dir | Data drive not mounted             | `./setup-data-drive.sh status` → if not mounted, run `./setup-data-drive.sh sd` again or `sudo mount /mnt/wildlife-data` |
| exFAT partition not visible on Windows          | Unclean unmount                    | Run `./setup-data-drive.sh sync` on the Pi before shutting down; or use "Safely Remove Hardware" on Windows              |
| "No space left on device"                       | exFAT partition full (6GB default) | Delete old images from Windows File Explorer; or increase `TARGET_SIZE_GB` in `setup-data-drive.sh` and re-run           |
| Root partition resize failed                    | Not enough free space              | Check `df -h` on the Pi — need at least ~2GB free on root before running `sd` command                                    |
| Boot hangs after `sd` command                   | Initramfs issue                    | Reflash SD card from backup; see recovery instructions in `setup-data-drive.sh` header                                   |
| Symlink broken after removal                    | Data drive removed without cleanup | Re-run `./setup-data-drive.sh remove` to clean up, or manually remove symlinks + fstab entry                             |

### 28.9 What Changed

| File                  | Change                                                                                                                                                |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `setup-data-drive.sh` | New script — initramfs-based boot-time resize, exFAT creation, mount/symlink setup, status/sync/remove commands                                       |
| `team1`               | Added `DATA_DRIVE` env var awareness: redirects `RESULTS_DIR` to `/mnt/wildlife-data/team1` when set                                                  |
| `team2`               | Added `DATA_DRIVE` env var awareness: redirects `RESULTS_DIR` to `/mnt/wildlife-data/team2` when set                                                  |
| `support`             | Added `check_data_drive()` function (mount, FS type, free space, sentinel, symlinks, fstab); new `datadrive` subcommand; included in full diagnostics |
| `support2`            | Added `check_data_drive()` function (same checks, Team 2 context); new `datadrive` subcommand; included in full diagnostics                           |
| `setup-data-drive.sh` | Added `docs` subcommand — copies `PLAN.md` and `TEST.md` to the exFAT partition root                                                                  |
| `PLAN.md`             | Added this section; added `docs` subcommand reference in 28.3                                                                                         |
| `TEST.md`             | Updated with full test plan covering static, unit, and integration test levels                                                                        |

---

## Appendix A — Camera Resolution Troubleshooting

If the live view timestamp freezes after changing camera resolution, run these commands on the Pi to diagnose:

### A.1 Quick Checks

```bash
# Is the inference process running?
sudo systemctl status ultralytics-wildlife.service

# Recent logs (look for DIAG: lines)
sudo journalctl -u ultralytics-wildlife.service -n 80 --no-pager

# Is latest.jpg being updated?
ls -la ~/ultralytics-local/results/latest.jpg
# Check mtime — if it stays the same for >30s, nothing is writing

# What's in the config?
cat ~/ultralytics-local/results/config.json
```

### A.2 Standalone Camera Test

Test if picamera2 can loop-capture at 3280×2464:

```bash
python3 -c "
from picamera2 import Picamera2
import time
p = Picamera2()
cfg = p.create_still_configuration(main={'size': (3280,2464), 'format':'RGB888'}, sensor_mode=1)
p.configure(cfg)
p.start()
time.sleep(2)
for i in range(3):
    f = p.capture_array()
    print('Frame %d: shape=%s' % (i, f.shape))
    time.sleep(1)
p.stop()
p.close()
print('OK')
"
```

### A.3 DIAG Log Reference

After adding diagnostic logging (see `team2`), the log will contain `DIAG:` lines showing:

| Prefix                                    | What it means                               |
| ----------------------------------------- | ------------------------------------------- |
| `DIAG: resolution change detected`        | `reconfig()` triggered                      |
| `DIAG: reconfig — stopping camera`        | About to call `cam.stop()`                  |
| `DIAG: reconfig — building config`        | About to build new camera config            |
| `DIAG: reconfig — configuring camera`     | About to call `cam.configure()`             |
| `DIAG: reconfig — starting camera`        | About to call `cam.start()`                 |
| `DIAG: reconfig — warm-up capture`        | Discarding first frame after reconfig       |
| `DIAG: reconfig — FAILED`                 | Reconfiguration raised an exception         |
| `DIAG: loop — frame shape=`               | Frame captured successfully with dimensions |
| `DIAG: loop — plot() OK`                  | Annotation rendering succeeded              |
| `DIAG: loop — wrote latest.jpg`           | File written to disk with byte size         |
| `DIAG: loop — FAILED to write latest.jpg` | `cv2.imwrite` returned false                |
| `DIAG: loop — captured failed`            | `capture_array()` raised exception          |

To watch logs live while testing:

```bash
sudo journalctl -u ultralytics-wildlife.service -f
```
