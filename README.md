# GPU Model Monitor

A comprehensive Docker-based NVIDIA GPU monitoring solution with enhanced process tracking capabilities and **Home Assistant integration via MQTT**. This tool monitors GPU metrics in real-time and tracks model/process usage over time, providing insights into GPU utilization, memory consumption, and process lifetimes.

![Docker support](https://img.shields.io/badge/docker-supported-blue)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Features

- **Real-time GPU Metrics Monitoring**
  - Temperature, utilization, memory, and power usage
  - Live updating dashboard with interactive charts
  
- **Enhanced Process Tracking**
  - Track all GPU processes with PID, process name, and memory usage
  - Monitor process lifetimes with **actual OS process start times** (not container-relative)
  - Historical process data with max/average memory consumption
  - Sortable and filterable process tables
  
- **Home Assistant Integration** ✨ NEW
  - MQTT publishing with auto-discovery
  - Real-time GPU metrics as sensors
  - Active processes with detailed attributes
  - Process history tracking
  - Easy integration with Home Assistant automations
  
- **System Information**
  - NVIDIA driver version
  - CUDA version
  - GPU model name
  
- **Data Persistence**
  - SQLite database for efficient storage
  - Historical data tracking (up to 3 days)
  - Process history with detailed metrics
  
- **Web Dashboard**
  - Responsive design for desktop and mobile
  - Real-time metrics updates
  - Interactive charts and gauges
  - Process filtering and sorting
  - Timezone-aware timestamps


## Screenshot
<img width=\"1204\" height=\"1370\" alt=\"image\" src=\"https://github.com/user-attachments/assets/e00bfd4e-c24e-435d-b52c-1ab57e16dc9b\"  />



## Quick Start

### Using Pre-built Image from GHCR

```bash
docker run -d \\
  --name gpu-model-monitor \\
  --pid=host \\
  -p 8081:8081 \\
  -e TZ=America/Los_Angeles \\
  -v ./history:/app/history:rw \\
  -v ./logs:/app/logs:rw \\
  --gpus all \\
  --restart unless-stopped \\
  ghcr.io/loryanstrant/gpu-model-monitor:latest
```

**Note:** The `--pid=host` flag is required for the container to see GPU processes running on the host and in other containers. Without this flag, only processes within the container itself will be visible.

### Using Docker Compose

1. Clone the repository:
```bash
git clone https://github.com/loryanstrant/gpu-model-monitor.git
cd gpu-model-monitor
```

2. (Optional) Configure MQTT for Home Assistant integration:
```bash
# Edit docker-compose.yml and set MQTT variables:
MQTT_ENABLED=true
MQTT_HOST=your-mqtt-broker.local
MQTT_PORT=1883
MQTT_USERNAME=your_username
MQTT_PASSWORD=your_password
```

3. Start the container:
```bash
docker-compose up -d
```

4. Access the dashboard at: [http://localhost:8081](http://localhost:8081)

## Prerequisites

- Docker
- NVIDIA GPU
- NVIDIA Container Toolkit
- NVIDIA drivers installed on host
- (Optional) MQTT broker for Home Assistant integration

### Installing NVIDIA Container Toolkit

#### Ubuntu / Debian / WSL

```bash
# Add NVIDIA package repositories
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \\
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \\
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \\
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
```

```bash
# Install nvidia container toolkit
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
```

```bash
# Configure Docker with toolkit
sudo nvidia-ctk runtime configure --runtime=docker
```

```bash
# Restart Docker daemon
sudo systemctl restart docker
```

```bash
# Test installation
sudo docker run --rm --runtime=nvidia --gpus all ubuntu nvidia-smi
```

For other distributions, check the [official documentation](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html).

## Building from Source

```bash
# Clone the repository
git clone https://github.com/loryanstrant/gpu-model-monitor.git
cd gpu-model-monitor

# Build the image
docker build -t gpu-model-monitor .

# Run the container
docker run -d \\
  --name gpu-model-monitor \\
  --pid=host \\
  -p 8081:8081 \\
  -e TZ=America/Los_Angeles \\
  -v ./history:/app/history:rw \\
  -v ./logs:/app/logs:rw \\
  --gpus all \\
  --restart unless-stopped \\
  gpu-model-monitor
```

## Dashboard Features

### Current Metrics
- Real-time GPU temperature, utilization, memory, and power usage
- Color-coded gauges for quick status assessment

### Performance History
- Historical chart showing temperature, GPU usage, and memory over time
- Up to 3 days of historical data

### Active GPU Processes
- Live view of all processes currently using the GPU
- Shows PID, process name, current/max/average memory usage
- **Actual OS process start times** - accurate even across container restarts
- Lifetime tracking to see how long each process has been running
- Filter and sort capabilities for easy analysis

### Process History
- Complete history of all GPU processes (last 100)
- Track when processes started and stopped (in your local timezone)
- View maximum and average memory consumption
- Number of samples collected for each process

## Home Assistant Integration

### Setting Up MQTT

1. **Configure Environment Variables** in `docker-compose.yml`:
   ```yaml
   environment:
     - TZ=Your/Timezone  # e.g., America/Los_Angeles
     - MQTT_ENABLED=true
     - MQTT_HOST=mqtt.example.com  # Your MQTT broker
     - MQTT_PORT=1883
     - MQTT_SSL=false  # Set to true if using SSL/TLS
     - MQTT_USERNAME=your_username
     - MQTT_PASSWORD=your_password
     - MQTT_TOPIC_PREFIX=gpu_monitor  # Default topic prefix
   ```

2. **Restart the container**:
   ```bash
   docker-compose down && docker-compose up -d
   ```

3. **Auto-Discovery**: The integration automatically creates Home Assistant sensors using MQTT Discovery. No manual configuration needed!

### Available Sensors

The following sensors are automatically created in Home Assistant:

- **GPU Temperature** - Real-time temperature in °C
- **GPU Utilization** - GPU usage percentage
- **GPU Memory Used** - Memory usage in MiB
- **GPU Power Draw** - Power consumption in Watts
- **GPU Process Count** - Number of active GPU processes
- **GPU Active Processes** - Detailed process information with attributes:
  - PID
  - Process name
  - Current/Max/Average memory usage
  - **Actual OS process start time**
  - Process lifetime (formatted)
  - Status
- **GPU Process History** - Historical process data

### Example Home Assistant Automation

```yaml
automation:
  - alias: \"Notify on High GPU Temperature\"
    trigger:
      - platform: numeric_state
        entity_id: sensor.gpu_monitor_nvidia_geforce_rtx_5080_temperature
        above: 80
    action:
      - service: notify.mobile_app
        data:
          message: \"GPU temperature is {{ states('sensor.gpu_monitor_nvidia_geforce_rtx_5080_temperature') }}°C!\"
```

## Configuration

### Environment Variables

#### Basic Configuration
- `TZ`: Timezone (default: America/Los_Angeles) - affects timestamp display in web interface and MQTT

#### MQTT Configuration (Optional)
- `MQTT_ENABLED`: Enable/disable MQTT publishing (default: false)
- `MQTT_HOST`: MQTT broker hostname or IP address
- `MQTT_PORT`: MQTT broker port (default: 1883)
- `MQTT_SSL`: Enable SSL/TLS for MQTT (default: false)
- `MQTT_USERNAME`: MQTT authentication username
- `MQTT_PASSWORD`: MQTT authentication password
- `MQTT_TOPIC_PREFIX`: Topic prefix for MQTT messages (default: gpu_monitor)

### Volumes

- `./history:/app/history:rw` - Persists SQLite database and historical data
- `./logs:/app/logs:rw` - Persists application logs

### Ports

- `8081` - Web dashboard (default)

To change the port, modify the docker-compose.yml file or the `-p` parameter in the docker run command.

## Data Persistence

All data is stored in SQLite database located in the `history` directory:
- `gpu_metrics.db` - Main database containing:
  - GPU metrics (temperature, utilization, memory, power)
  - Process tracking data
  - Process snapshots

Data retention:
- GPU metrics: 3 days
- Process history: 3 days
- Automatic cleanup runs hourly

## Troubleshooting

### NVIDIA SMI not found
- Ensure NVIDIA drivers are installed on the host
- Verify NVIDIA Container Toolkit installation
- Test with: `sudo docker run --rm --runtime=nvidia --gpus all ubuntu nvidia-smi`

### Container fails to start
- Check Docker logs: `docker logs gpu-model-monitor`
- Verify GPU access: `nvidia-smi`
- Ensure proper permissions on volume directories

### Dashboard not accessible
- Verify container is running: `docker ps`
- Check container logs: `docker logs gpu-model-monitor`
- Ensure port 8081 is not in use

### Process tracking not working
- **Verify PID host mode is enabled**: `--pid=host` or `pid: \"host\"` in docker-compose.yml
- Verify nvidia-smi can list processes: `nvidia-smi pmon`
- Check database permissions in history directory
- Review logs in `./logs/error.log`

### Process lifetimes resetting
- Ensure `--pid=host` is set - this allows the container to query actual OS process start times
- Without host PID mode, lifetimes will be relative to container start time

### MQTT not connecting
- Verify MQTT broker is accessible from container
- Check MQTT credentials
- Review logs: `docker logs gpu-model-monitor | grep MQTT`
- Test MQTT broker: `mosquitto_sub -h your-broker -p 1883 -u user -P pass -t '#'`

### Home Assistant sensors not appearing
- Ensure MQTT integration is configured in Home Assistant
- Check Home Assistant MQTT logs
- Wait 30-60 seconds for auto-discovery
- Check MQTT topic: `homeassistant/sensor/+/+/config`

## Architecture

- **Backend**: Bash script with Python web server and MQTT publisher
- **Database**: SQLite3 for efficient data storage
- **Frontend**: Vanilla JavaScript with Chart.js
- **Web Server**: aiohttp (Python async web framework)
- **MQTT Client**: paho-mqtt (Python MQTT library)
- **Process Info**: psutil (Python system utilities library)

## Development Approach
<img width=\"256\" height=\"256\" alt=\"image\" src=\"https://github.com/user-attachments/assets/9bdff80e-30d2-4c30-acb2-37154d7748e1\" />


## License

MIT License - see [LICENSE](LICENSE) file for details

## Acknowledgments

Based on the concept from [bigsk1/gpu-monitor](https://github.com/bigsk1/gpu-monitor) with enhanced process tracking capabilities and Home Assistant integration.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
