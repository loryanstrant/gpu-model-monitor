# GPU Model Monitor with MQTT Support

This is an extended version of GPU Model Monitor that adds MQTT publishing functionality for integration with Home Assistant and other MQTT-based systems.

## New Features

- **MQTT Publishing**: Publishes GPU metrics to an MQTT broker
- **Home Assistant Discovery**: Automatically registers sensors in Home Assistant
- **Configurable Topics**: Customizable MQTT topic prefix
- **SSL/TLS Support**: Optional encrypted MQTT connections

## MQTT Configuration

The MQTT functionality is configured through environment variables in the docker-compose.yml file:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `MQTT_ENABLED` | Enable/disable MQTT publishing | `false` | Yes |
| `MQTT_HOST` | MQTT broker hostname or IP address | - | Yes (if enabled) |
| `MQTT_PORT` | MQTT broker port | `1883` | No |
| `MQTT_SSL` | Enable SSL/TLS encryption | `false` | No |
| `MQTT_USERNAME` | MQTT broker username | - | No |
| `MQTT_PASSWORD` | MQTT broker password | - | No |
| `MQTT_TOPIC_PREFIX` | Prefix for all MQTT topics | `gpu_monitor` | No |

## Published MQTT Topics

When enabled, the following topics are published:

- `{prefix}/temperature` - GPU temperature in °C
- `{prefix}/utilization` - GPU utilization percentage
- `{prefix}/memory` - GPU memory used in MiB
- `{prefix}/memory_total` - Total GPU memory in MiB
- `{prefix}/memory_percent` - GPU memory usage percentage
- `{prefix}/power` - GPU power draw in Watts
- `{prefix}/process_count` - Number of processes using the GPU
- `{prefix}/active_processes` - JSON array of active GPU processes with detailed metrics
- `{prefix}/state` - Complete state as JSON

## Home Assistant Integration

The monitor automatically publishes MQTT discovery messages for Home Assistant. Once running, sensors will appear automatically in Home Assistant under:

**Device**: GPU Monitor - {Your GPU Name}

**Sensors**:
- GPU Temperature
- GPU Utilization
- GPU Memory Used
- GPU Memory Total
- GPU Memory Percentage
- GPU Power Draw
- GPU Process Count
- Active Processes (with detailed attributes including per-process memory percentages)

### Process Attributes

The `Active Processes` sensor includes detailed attributes for each GPU process:
- Process ID (PID)
- Process name
- Current memory usage (MB)
- Memory percentage (% of total GPU memory)
- Maximum memory usage
- Average memory usage
- Process start time
- Process lifetime

## Installation

### 1. Create the directory structure

```bash
sudo mkdir -p /home/docker/GPUModelMonitorDEV/{history,logs}
sudo chown -R $USER:$USER /home/docker/GPUModelMonitorDEV
```

### 2. Copy files to the server

Copy the following files to `/home/docker/GPUModelMonitorDEV/`:
- `Dockerfile`
- `docker-compose.yml`
- `monitor_gpu_mqtt.sh`
- `mqtt_publisher.py`
- `server.py`
- `gpu-stats.html`

### 3. Configure MQTT settings

Edit `docker-compose.yml` and update the MQTT environment variables:

```yaml
environment:
  - MQTT_ENABLED=true
  - MQTT_HOST=your-mqtt-broker-ip
  - MQTT_PORT=1883
  - MQTT_USERNAME=your_username
  - MQTT_PASSWORD=your_password
```

### 4. Build and run

You can either:

**Option A: Build locally**
```bash
cd /home/docker/GPUModelMonitorDEV
docker-compose build
docker-compose up -d
```

**Option B: Use with Portainer**
1. In Portainer, navigate to Stacks
2. Add a new stack named "GPUModelMonitorDEV"
3. Use the Web editor and paste the docker-compose.yml content
4. Deploy the stack

### 5. Verify operation

Check the logs to ensure MQTT is working:

```bash
docker logs GPU-Model-Monitor-DEV
```

You should see messages like:
```
MQTT Publisher initialized for broker: your-broker-ip:1883
Successfully connected to MQTT broker
Home Assistant discovery messages published
```

## Testing

### Test MQTT Connection

You can test the MQTT connection using mosquitto_sub:

```bash
mosquitto_sub -h your-mqtt-broker-ip -u your_username -P your_password -t "gpu_monitor/#" -v
```

### Disable MQTT

To disable MQTT publishing without rebuilding, set:

```yaml
environment:
  - MQTT_ENABLED=false
```

## Troubleshooting

### MQTT not connecting

1. Check MQTT broker is reachable from the Docker container
2. Verify username/password are correct
3. Check firewall rules allow MQTT port (default 1883)
4. Review logs: `docker logs GPU-Model-Monitor-DEV | grep MQTT`

### Home Assistant not discovering sensors

1. Ensure MQTT integration is configured in Home Assistant
2. Check MQTT broker logs for incoming messages
3. Verify discovery prefix matches Home Assistant configuration (default: `homeassistant`)
4. Restart Home Assistant after first container start

### SSL/TLS issues

If using SSL:
- Set `MQTT_SSL=true`
- Ensure broker uses valid certificate
- Port is usually 8883 for SSL/TLS

## Differences from Production Version

This DEV version:
- Uses port 8083 instead of 8082
- Has separate history and logs directories
- Includes MQTT functionality
- Container named `GPU-Model-Monitor-DEV`

## Web Interface

Access the monitoring dashboard at: `http://your-server-ip:8083`

## Original Project

This is based on: https://github.com/loryanstrant/gpu-model-monitor
