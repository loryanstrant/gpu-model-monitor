# MQTT Process Information Publishing

The GPU Model Monitor now publishes detailed GPU process information to MQTT.

## New MQTT Topics

### 1. Active Processes Topic
**Topic:** `gpu_monitor/active_processes`

**State Value:** Count of active processes

**Attributes (JSON):**
```json
{
  "count": 2,
  "processes": [
    {
      "pid": 12345,
      "name": "python",
      "memory_current": 1024,
      "memory_max": 2048,
      "memory_avg": 1536,
      "first_seen": "2026-02-23 10:00:00",
      "last_seen": "2026-02-23 10:15:30",
      "lifetime_seconds": 930,
      "sample_count": 233,
      "status": "active"
    },
    {
      "pid": 67890,
      "name": "ollama",
      "memory_current": 4096,
      "memory_max": 5120,
      "memory_avg": 4500,
      "first_seen": "2026-02-23 09:45:00",
      "last_seen": "2026-02-23 10:15:30",
      "lifetime_seconds": 1830,
      "sample_count": 458,
      "status": "active"
    }
  ],
  "timestamp": "2026-02-23 10:15:30"
}
```

**Field Descriptions:**
- `pid`: Process ID
- `name`: Process name/command
- `memory_current`: Current GPU memory usage in MiB
- `memory_max`: Maximum GPU memory usage observed in MiB
- `memory_avg`: Average GPU memory usage in MiB
- `first_seen`: When process was first detected
- `last_seen`: Most recent detection time
- `lifetime_seconds`: How long the process has been running
- `sample_count`: Number of monitoring samples collected
- `status`: Always "active" for current processes

### 2. Process History Topic
**Topic:** `gpu_monitor/process_history`

**State Value:** Total number of historical processes (last 50)

**Attributes (JSON):**
```json
{
  "total": 50,
  "history": [
    {
      "pid": 12345,
      "name": "python",
      "first_seen": "2026-02-23 10:00:00",
      "last_seen": "2026-02-23 10:15:30",
      "lifetime_seconds": 930,
      "memory_max": 2048,
      "memory_avg": 1536,
      "sample_count": 233
    },
    {
      "pid": 67890,
      "name": "ollama",
      "first_seen": "2026-02-23 09:45:00",
      "last_seen": "2026-02-23 10:15:30",
      "lifetime_seconds": 1830,
      "memory_max": 5120,
      "memory_avg": 4500,
      "sample_count": 458
    }
  ],
  "timestamp": "2026-02-23 10:15:30"
}
```

## Home Assistant Sensors

### GPU Active Processes Sensor
- **Entity ID:** `sensor.gpu_monitor_nvidia_geforce_rtx_5080_active_processes`
- **State:** Number of active processes
- **Attributes:** Full array of process details (see above)

### GPU Process History Sensor
- **Entity ID:** `sensor.gpu_monitor_nvidia_geforce_rtx_5080_process_history`
- **State:** Total number of historical processes
- **Attributes:** Array of last 50 processes with their history

## Usage in Home Assistant

### Display Active Process Count
```yaml
type: entity
entity: sensor.gpu_monitor_nvidia_geforce_rtx_5080_active_processes
name: Active GPU Processes
```

### Display Process Details in a Table
```yaml
type: markdown
content: |
  {% set processes = state_attr('sensor.gpu_monitor_nvidia_geforce_rtx_5080_active_processes', 'processes') %}
  {% if processes %}
  | PID | Process | Memory | Lifetime |
  |-----|---------|--------|----------|
  {% for proc in processes %}
  | {{ proc.pid }} | {{ proc.name }} | {{ proc.memory_current }} MiB | {{ (proc.lifetime_seconds / 60) | round(0) }} min |
  {% endfor %}
  {% else %}
  No active GPU processes
  {% endif %}
```

### Automation Example: Alert on High Memory Process
```yaml
automation:
  - alias: "Alert on High GPU Memory Process"
    trigger:
      - platform: state
        entity_id: sensor.gpu_monitor_nvidia_geforce_rtx_5080_active_processes
    condition:
      - condition: template
        value_template: >
          {% set processes = state_attr('sensor.gpu_monitor_nvidia_geforce_rtx_5080_active_processes', 'processes') %}
          {{ processes | selectattr('memory_current', '>', 8000) | list | length > 0 }}
    action:
      - service: notify.mobile_app
        data:
          title: "High GPU Memory Usage"
          message: >
            {% set processes = state_attr('sensor.gpu_monitor_nvidia_geforce_rtx_5080_active_processes', 'processes') %}
            {% set high_mem_procs = processes | selectattr('memory_current', '>', 8000) | list %}
            Process {{ high_mem_procs[0].name }} (PID {{ high_mem_procs[0].pid }}) is using {{ high_mem_procs[0].memory_current }} MiB
```

## Testing

To test MQTT publishing with process details:

```bash
# View current stats (including processes if any)
sudo docker exec GPU-Model-Monitor-DEV cat /app/gpu_current_stats.json | python3 -m json.tool

# Manually trigger MQTT publish
sudo docker exec GPU-Model-Monitor-DEV python3 /app/mqtt_publisher.py /app/gpu_current_stats.json

# Check container logs
sudo docker logs GPU-Model-Monitor-DEV | grep -i process
```

## Subscribe to MQTT Topics

You can monitor the MQTT messages using mosquitto_sub:

```bash
# Subscribe to all gpu_monitor topics
mosquitto_sub -h mqtt.strant.casa -u mqtt -P mqtt -t "gpu_monitor/#" -v

# Subscribe only to active processes
mosquitto_sub -h mqtt.strant.casa -u mqtt -P mqtt -t "gpu_monitor/active_processes" -v

# Subscribe only to process history
mosquitto_sub -h mqtt.strant.casa -u mqtt -P mqtt -t "gpu_monitor/process_history" -v
```

## Update Frequency

- Active processes: Published every 4 seconds (with each metrics update)
- Process history: Published every 4 seconds (last 50 processes from database)

## Notes

- Process history is limited to the last 50 processes to keep MQTT message sizes reasonable
- Empty arrays are published when no processes are active
- History includes both currently active and recently completed processes
- The history sensor maintains data across process restarts (stored in SQLite database)
