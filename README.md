# GPU Model Monitor

A comprehensive Docker-based NVIDIA GPU monitoring solution with enhanced process tracking capabilities. This tool monitors GPU metrics in real-time and tracks model/process usage over time, providing insights into GPU utilization, memory consumption, and process lifetimes.

![Docker support](https://img.shields.io/badge/docker-supported-blue)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Features

- **Real-time GPU Metrics Monitoring**
  - Temperature, utilization, memory, and power usage
  - Live updating dashboard with interactive charts
  
- **Enhanced Process Tracking**
  - Track all GPU processes with PID, process name, and memory usage
  - Monitor process lifetimes to see how long models were loaded
  - Historical process data with max/average memory consumption
  - Sortable and filterable process tables
  
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


## Screenshot
<img width="1204" height="1370" alt="image" src="https://github.com/user-attachments/assets/e00bfd4e-c24e-435d-b52c-1ab57e16dc9b" />



## Quick Start

### Using Pre-built Image from GHCR

```bash
docker run -d \
  --name gpu-model-monitor \
  --pid=host \
  -p 8081:8081 \
  -e TZ=America/Los_Angeles \
  -v ./history:/app/history:rw \
  -v ./logs:/app/logs:rw \
  --gpus all \
  --restart unless-stopped \
  ghcr.io/loryanstrant/gpu-model-monitor:latest
```

**Note:** The `--pid=host` flag is required for the container to see GPU processes running on the host and in other containers. Without this flag, only processes within the container itself will be visible.

### Using Docker Compose

1. Clone the repository:
```bash
git clone https://github.com/loryanstrant/gpu-model-monitor.git
cd gpu-model-monitor
```

2. Start the container:
```bash
docker-compose up -d
```

3. Access the dashboard at: [http://localhost:8081](http://localhost:8081)

## Prerequisites

- Docker
- NVIDIA GPU
- NVIDIA Container Toolkit
- NVIDIA drivers installed on host

### Installing NVIDIA Container Toolkit

#### Ubuntu / Debian / WSL

```bash
# Add NVIDIA package repositories
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
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
docker run -d \
  --name gpu-model-monitor \
  -p 8081:8081 \
  -e TZ=America/Los_Angeles \
  -v ./history:/app/history:rw \
  -v ./logs:/app/logs:rw \
  --gpus all \
  --restart unless-stopped \
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
- Lifetime tracking to see how long each process has been running
- Filter and sort capabilities for easy analysis

### Process History
- Complete history of all GPU processes (last 100)
- Track when processes started and stopped
- View maximum and average memory consumption
- Number of samples collected for each process

## Configuration

### Environment Variables

- `TZ`: Timezone (default: America/Los_Angeles)

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
- Verify nvidia-smi can list processes: `nvidia-smi pmon`
- Check database permissions in history directory
- Review logs in `./logs/error.log`

## Architecture

- **Backend**: Bash script with Python web server
- **Database**: SQLite3 for efficient data storage
- **Frontend**: Vanilla JavaScript with Chart.js
- **Web Server**: aiohttp (Python async web framework)

## Development Approach
<img width="256" height="256" alt="image" src="https://github.com/user-attachments/assets/9bdff80e-30d2-4c30-acb2-37154d7748e1" />


## License

MIT License - see [LICENSE](LICENSE) file for details

## Acknowledgments

Based on the concept from [bigsk1/gpu-monitor](https://github.com/bigsk1/gpu-monitor) with enhanced process tracking capabilities.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
