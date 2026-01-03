# GPU Model Monitor - Features Documentation

## Overview

GPU Model Monitor is a comprehensive Docker-based solution for monitoring NVIDIA GPUs with enhanced process tracking capabilities. This document details all features and their implementation.

## Core Features

### 1. Real-time GPU Metrics

The monitor collects and displays the following metrics every 4 seconds:

- **Temperature**: GPU temperature in Celsius
- **Utilization**: GPU utilization percentage
- **Memory**: GPU memory usage in MiB
- **Power**: Power consumption in Watts

All metrics are stored in a SQLite database for historical analysis.

### 2. System Information

Automatically detects and displays:

- **GPU Model**: Full GPU name (e.g., NVIDIA GeForce RTX 3090)
- **Driver Version**: NVIDIA driver version
- **CUDA Version**: CUDA toolkit version

This information is displayed prominently in the dashboard header.

### 3. Process Tracking

#### Active Process Monitoring

Tracks all processes currently using the GPU with:

- **PID**: Process identifier
- **Process Name**: Executable name
- **Current Memory**: Real-time GPU memory usage
- **Max Memory**: Maximum memory used during lifetime
- **Average Memory**: Average memory consumption
- **Lifetime**: How long the process has been running
- **Status**: Active/Inactive indicator

#### Process History

Maintains a complete history of all GPU processes including:

- First seen timestamp
- Last seen timestamp
- Total lifetime
- Memory usage statistics
- Number of samples collected

This enables tracking of how long models were loaded and their memory footprint over time.

### 4. Interactive Dashboard

#### Metrics Display

- **Gauges**: Color-coded progress bars for each metric
  - Green: Normal operation
  - Yellow: Warning threshold
  - Red: Critical threshold

- **Charts**: Interactive time-series graphs using Chart.js
  - Temperature trends
  - GPU utilization patterns
  - Memory usage over time
  - Configurable time ranges

#### Process Tables

**Active Processes Table:**
- Sortable columns (click headers to sort)
- Real-time filtering (search by PID or name)
- Auto-refresh every 5 seconds

**Process History Table:**
- Sortable columns for historical analysis
- Filter by process name or PID
- Shows up to last 100 processes

#### Filtering and Sorting

All tables support:
- **Click-to-sort**: Click column headers to sort ascending/descending
- **Live filtering**: Type-as-you-search filtering
- **Visual feedback**: Arrow indicators show current sort direction

### 5. Data Management

#### SQLite Database

Three main tables:

1. **gpu_metrics**: GPU performance metrics
   - Timestamp and epoch time
   - Temperature, utilization, memory, power
   - Indexed by timestamp for fast queries

2. **gpu_processes**: Process tracking data
   - PID, process name
   - First/last seen timestamps
   - Memory statistics (max, avg)
   - Sample count

3. **process_snapshots**: Point-in-time process data
   - Timestamp for each observation
   - PID, name, memory usage
   - Enables lifetime tracking

#### Data Retention

- **Historical Data**: 3 days
- **Automatic Cleanup**: Runs hourly
- **Efficient Storage**: VACUUM operation optimizes database
- **Export**: JSON files for web dashboard access

### 6. Web Server

- **Technology**: Python aiohttp (async web framework)
- **Port**: 8081 (configurable)
- **Static File Serving**: HTML, JSON, images
- **Low Overhead**: Async I/O for efficiency

### 7. Docker Integration

#### Dockerfile

- Based on Python 3.13 slim image
- Minimal dependencies (curl, jq, sqlite3)
- Proper volume mounts for persistence
- NVIDIA runtime support

#### Docker Compose

- Simple one-command deployment
- Volume persistence
- GPU device mapping
- Timezone configuration
- Auto-restart policy

### 8. GitHub Actions Integration

Automatic building and publishing to GHCR:

- Triggered on push to main/master
- Tag-based versioning (v1.0.0)
- Latest tag for main branch
- Build caching for speed
- Multi-platform support ready

## Technical Architecture

### Backend (monitor_gpu.sh)

**Main Loop:**
```
1. Query nvidia-smi for metrics
2. Parse and validate data
3. Insert into SQLite database
4. Track active processes
5. Update JSON files for web
6. Sleep 4 seconds
7. Repeat
```

**Process Tracking:**
```
1. Query nvidia-smi for compute apps
2. Extract PID, name, memory
3. Check if PID exists in database
4. Update existing or insert new
5. Calculate statistics (max, avg)
6. Mark last_seen timestamp
```

**Data Export:**
```
Every 15 updates (1 minute):
- Export GPU metrics to JSON
- Export process history to JSON
- Make files readable by web server
```

**Cleanup:**
```
Every hour at :00:
- Delete data older than 3 days
- VACUUM database
- Rotate log files
```

### Frontend (gpu-stats.html)

**Update Cycles:**

- **Metrics**: Every 5 seconds
  - Fetch current stats JSON
  - Update gauge values and colors
  - Refresh process table

- **Charts**: Every 30 seconds
  - Fetch history JSON
  - Update Chart.js graphs
  - Process history refresh

**Interactive Features:**

- Click gauge cards to toggle graph lines
- Click table headers to sort
- Type in filter boxes to search
- Responsive layout adapts to screen size

## Usage Patterns

### Model Training Tracking

1. Start training job
2. Monitor appears in Active Processes
3. Track memory usage in real-time
4. View lifetime counter
5. After completion, process moves to History
6. Analyze max/avg memory used

### Multi-Process Analysis

1. Filter by process name
2. Sort by memory usage
3. Compare different model sizes
4. Identify memory-hungry processes

### Performance Debugging

1. Check temperature trends
2. Correlate with GPU utilization
3. Identify thermal throttling
4. Optimize workload timing

### Historical Analysis

1. View process history
2. Filter by date range (implicit via 3-day retention)
3. Compare memory usage patterns
4. Plan resource allocation

## Security Features

- No external database connections
- Local file system only
- Read-only volume mounts for system files
- Explicit permissions on created directories
- SRI hash verification for CDN resources
- No sensitive data exposure

## Performance Characteristics

- **CPU Usage**: Minimal (~1-2%)
- **Memory Usage**: ~50-100 MB
- **Disk I/O**: Low (SQLite writes every 4 seconds)
- **Network**: Only for web dashboard access
- **GPU Overhead**: Negligible (nvidia-smi queries)

## Extensibility

The modular design allows for:

- Additional metrics from nvidia-smi
- Custom alerting thresholds
- Export to external monitoring systems
- Integration with other tools
- Custom visualizations

## Browser Compatibility

Tested and supported on:
- Chrome/Edge (latest)
- Firefox (latest)
- Safari (latest)
- Mobile browsers (iOS Safari, Chrome Mobile)

## Future Enhancements

Potential additions:
- Email/webhook alerts
- Multi-GPU support
- Prometheus exporter
- REST API
- Process kill functionality
- Memory limit enforcement
- Custom metric collection
