#!/bin/bash
###############################################################################
# GPU Model Monitor - Backend Process (with MQTT Support)
# 
# This script monitors NVIDIA GPU metrics with enhanced process tracking and MQTT publishing.
# Features:
# - Real-time GPU metrics collection
# - Driver and CUDA version tracking
# - Process monitoring with PID, name, and memory usage
# - Process lifetime tracking
# - Historical data management
# - SQLite database for persistence
# - MQTT publishing for Home Assistant integration
###############################################################################

BASE_DIR="/app"
LOG_FILE="$BASE_DIR/gpu_stats.log"
JSON_FILE="$BASE_DIR/gpu_current_stats.json"
HISTORY_DIR="$BASE_DIR/history"
LOG_DIR="$BASE_DIR/logs"
ERROR_LOG="$LOG_DIR/error.log"
WARNING_LOG="$LOG_DIR/warning.log"
DEBUG_LOG="$LOG_DIR/debug.log"
DB_FILE="$HISTORY_DIR/gpu_metrics.db"
MQTT_PUBLISHER="$BASE_DIR/mqtt_publisher.py"
INTERVAL=4  # Time between GPU checks (seconds)
GPU_MEMORY_TOTAL=0  # Total GPU memory in MB (updated during monitoring)

# Create required directories with proper permissions
mkdir -p "$LOG_DIR"
chmod 755 "$LOG_DIR"
mkdir -p "$HISTORY_DIR"
chmod 755 "$HISTORY_DIR"

###############################################################################
# Logging Functions
###############################################################################

log_error() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] ERROR: $1" | tee -a "$ERROR_LOG"
}

log_warning() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] WARNING: $1" | tee -a "$WARNING_LOG"
}

log_debug() {
    if [ "${DEBUG:-}" = "true" ]; then
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[$timestamp] DEBUG: $1" >> "$DEBUG_LOG"
    fi
}

log_info() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] INFO: $1"
}

###############################################################################
# MQTT Publishing Functions
###############################################################################

# Initialize MQTT publisher (connect and send discovery messages)
mqtt_publisher_init=false

function publish_to_mqtt() {
    local json_file="$1"
    
    # Check if MQTT is enabled
    if [ "${MQTT_ENABLED:-false}" != "true" ]; then
        return 0
    fi
    
    # Check if MQTT publisher exists
    if [ ! -f "$MQTT_PUBLISHER" ]; then
        if [ "$mqtt_publisher_init" = "false" ]; then
            log_warning "MQTT publisher script not found at $MQTT_PUBLISHER"
            mqtt_publisher_init=true
        fi
        return 1
    fi
    
    # Check if Python3 is available
    if ! command -v python3 &> /dev/null; then
        if [ "$mqtt_publisher_init" = "false" ]; then
            log_error "Python3 not found, cannot publish to MQTT"
            mqtt_publisher_init=true
        fi
        return 1
    fi
    
    # Log initialization message once
    if [ "$mqtt_publisher_init" = "false" ]; then
        log_info "MQTT publishing enabled - broker: ${MQTT_HOST:-not_set}:${MQTT_PORT:-1883}"
        mqtt_publisher_init=true
    fi
    
    # Publish metrics to MQTT (run in background to not block monitoring)
    python3 "$MQTT_PUBLISHER" "$json_file" 2>&1 | while read line; do
        # Filter out debug messages unless debug is enabled  
        if [[ "$line" == *"ERROR"* ]] || [[ "$line" == *"WARNING"* ]] || [[ "${DEBUG:-}" = "true" ]]; then
            echo "[MQTT] $line"
        fi
    done &
}

###############################################################################
# GPU Configuration
###############################################################################

GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1)
DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1)
CUDA_VERSION=$(nvcc --version 2>/dev/null | grep -oP 'release \K[0-9.]+' | head -n1)
CUDA_VERSION_FULL=$(nvidia-smi 2>/dev/null | grep "CUDA Version" | awk '{print $9}')

if [ -z "$CUDA_VERSION" ] && [ -n "$CUDA_VERSION_FULL" ]; then
    CUDA_VERSION="$CUDA_VERSION_FULL"
fi

if [ -z "$GPU_NAME" ]; then
    echo "ERROR: Could not detect NVIDIA GPU. Make sure nvidia-smi is available."
    exit 1
fi

# Save GPU configuration to JSON for web interface
cat > "$BASE_DIR/gpu_config.json" <<EOF
{
    "gpu_name": "$GPU_NAME",
    "driver_version": "$DRIVER_VERSION",
    "cuda_version": "$CUDA_VERSION"
}
EOF

###############################################################################
# Database Initialization
###############################################################################

function initialize_database() {
    log_info "Initializing database: $DB_FILE"
    
    sqlite3 "$DB_FILE" <<EOF
    -- Table for GPU metrics history
    CREATE TABLE IF NOT EXISTS gpu_metrics (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        timestamp_epoch INTEGER NOT NULL,
        temperature REAL NOT NULL,
        utilization REAL NOT NULL,
        memory REAL NOT NULL,
        power REAL NOT NULL
    );
    
    CREATE INDEX IF NOT EXISTS idx_gpu_metrics_timestamp_epoch ON gpu_metrics(timestamp_epoch);
    
    -- Table for tracking processes
    CREATE TABLE IF NOT EXISTS gpu_processes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pid INTEGER NOT NULL UNIQUE,
        process_name TEXT NOT NULL,
        first_seen INTEGER NOT NULL,
        last_seen INTEGER NOT NULL,
        max_memory REAL NOT NULL,
        avg_memory REAL NOT NULL,
        sample_count INTEGER NOT NULL DEFAULT 1
    );
    
    CREATE INDEX IF NOT EXISTS idx_gpu_processes_pid ON gpu_processes(pid);
    CREATE INDEX IF NOT EXISTS idx_gpu_processes_last_seen ON gpu_processes(last_seen);
    
    -- Table for process snapshots
    CREATE TABLE IF NOT EXISTS process_snapshots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp_epoch INTEGER NOT NULL,
        pid INTEGER NOT NULL,
        process_name TEXT NOT NULL,
        memory_usage REAL NOT NULL
    );
    
    CREATE INDEX IF NOT EXISTS idx_process_snapshots_timestamp ON process_snapshots(timestamp_epoch);
    CREATE INDEX IF NOT EXISTS idx_process_snapshots_pid ON process_snapshots(pid);
EOF
    
    if [ $? -ne 0 ]; then
        log_error "Failed to initialize database"
        exit 1
    fi
    
    log_info "Database initialized successfully"
}

###############################################################################
# Process Tracking Functions
###############################################################################

function get_gpu_processes() {
    nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader,nounits 2>/dev/null
}

function update_process_tracking() {
    local current_time=$(date +%s)
    local gpu_processes=$(get_gpu_processes)
    
    if [ -z "$gpu_processes" ]; then
        log_debug "No GPU processes currently running"
        return 0
    fi
    
    while IFS=',' read -r pid name memory; do
        # Clean up values
        pid=$(echo "$pid" | tr -d ' ')
        name=$(echo "$name" | tr -d ' ' | sed 's/[^a-zA-Z0-9._-]/_/g')
        memory=$(echo "$memory" | tr -d ' ' | sed 's/[^0-9.]//g')
        
        if [ -z "$pid" ] || [ -z "$memory" ]; then
            continue
        fi
        
        # Insert snapshot
        sqlite3 "$DB_FILE" <<SQL
        INSERT INTO process_snapshots (timestamp_epoch, pid, process_name, memory_usage)
        VALUES ($current_time, $pid, '$name', $memory);
SQL
        
        # Update or insert process tracking
        sqlite3 "$DB_FILE" <<SQL
        INSERT INTO gpu_processes (pid, process_name, first_seen, last_seen, max_memory, avg_memory, sample_count)
        VALUES (
            $pid, 
            '$name', 
            $current_time, 
            $current_time, 
            $memory, 
            $memory,
            1
        )
        ON CONFLICT(pid) DO UPDATE SET
            last_seen = $current_time,
            max_memory = MAX(max_memory, $memory),
            avg_memory = ((avg_memory * sample_count) + $memory) / (sample_count + 1),
            sample_count = sample_count + 1;
SQL
        
    done <<< "$gpu_processes"
}

###############################################################################
# Current Process Query with Enrichment
###############################################################################

function get_current_processes() {
    local mem_total="$1"
    log_debug "Getting current processes"
    
    if result=$(sqlite3 -json "$DB_FILE" 2>&1 <<SQL
    SELECT DISTINCT
        ps.pid,
        ps.process_name,
        ps.memory_usage as memory,
        gp.max_memory,
        gp.avg_memory,
        gp.sample_count,
        datetime(gp.first_seen, 'unixepoch', 'localtime') as first_seen,
        datetime(gp.last_seen, 'unixepoch', 'localtime') as last_seen,
        (gp.last_seen - gp.first_seen) as lifetime_seconds
    FROM (
        SELECT pid, process_name, memory_usage,
               ROW_NUMBER() OVER (PARTITION BY pid ORDER BY timestamp_epoch DESC) as rn
        FROM process_snapshots
        WHERE timestamp_epoch > (strftime('%s', 'now') - 30)
    ) ps
    JOIN gpu_processes gp ON ps.pid = gp.pid
    WHERE ps.rn = 1
    ORDER BY ps.memory_usage DESC;
SQL
); then
        # Enrich with actual process start times and memory percentages from Python
        if [ -n "$result" ] && [ "$result" != "[]" ]; then
            result=$(echo "$result" | GPU_MEMORY_TOTAL="$mem_total" python3 "$BASE_DIR/enrich_processes.py" 2>&1)
            if [ $? -eq 0 ]; then
                log_debug "Enriched process data: ${result:0:200}..."
                echo "$result"
            else
                log_error "Failed to enrich process data: $result"
                echo "[]"
                return 1
            fi
        else
            echo "[]"
        fi
    else
        log_error "Failed to query current processes: $result"
        echo "[]"
        return 1
    fi
}

###############################################################################
# get_process_history: Get historical process data as JSON
###############################################################################
function get_process_history() {
    log_debug "Getting process history"
    
    if result=$(sqlite3 -json "$DB_FILE" 2>&1 <<SQL
    SELECT 
        pid,
        process_name,
        datetime(first_seen, 'unixepoch', 'localtime') as first_seen,
        datetime(last_seen, 'unixepoch', 'localtime') as last_seen,
        (last_seen - first_seen) as lifetime_seconds,
        max_memory,
        avg_memory,
        sample_count
    FROM gpu_processes
    ORDER BY last_seen DESC
    LIMIT 100;
SQL
); then
        log_debug "Process history query returned: ${result:0:200}..."
        echo "$result"
    else
        log_error "Failed to query process history: $result"
        echo "[]"
        return 1
    fi
}

###############################################################################
# safe_write_json: Safely writes JSON data to prevent corruption
###############################################################################
function safe_write_json() {
    local file="$1"
    local content="$2"
    local temp="${file}.tmp"
    local backup="${file}.bak"
    
    echo "$content" > "$temp"
    
    if [ -s "$temp" ]; then
        [ -f "$file" ] && cp "$file" "$backup"
        mv "$temp" "$file"
        log_debug "Safely wrote to $file"
    else
        log_error "Temporary JSON file is empty, not updating $file"
        rm -f "$temp"
        return 1
    fi
}

###############################################################################
# update_stats: Core function for GPU metrics collection and processing
###############################################################################
update_stats() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local timestamp_epoch=$(date +%s)
    local gpu_stats=$(nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,memory.used,memory.total,power.draw \
                     --format=csv,noheader,nounits 2>/dev/null)
    
    if [[ -n "$gpu_stats" ]]; then
        local temp=$(echo "$gpu_stats" | cut -d',' -f1 | tr -d ' ')
        local util=$(echo "$gpu_stats" | cut -d',' -f2 | tr -d ' ')
        local mem=$(echo "$gpu_stats" | cut -d',' -f3 | tr -d ' ')
        local mem_total=$(echo "$gpu_stats" | cut -d',' -f4 | tr -d ' ')
        local power=$(echo "$gpu_stats" | cut -d',' -f5 | tr -d ' []')
        
        # Update global GPU_MEMORY_TOTAL
        GPU_MEMORY_TOTAL="$mem_total"
        
        # Calculate memory percentage
        local mem_percent=0
        if [[ -n "$mem_total" && "$mem_total" -gt 0 ]]; then
            mem_percent=$(awk "BEGIN {printf \"%.1f\", ($mem / $mem_total) * 100}")
        fi

        # Handle N/A power value
        if [[ "$power" == "N/A" || -z "$power" || "$power" == "[N/A]" ]]; then
            power="0"
        fi
        
        # Insert into database
        sqlite3 "$DB_FILE" <<SQL
        INSERT INTO gpu_metrics (timestamp, timestamp_epoch, temperature, utilization, memory, power)
        VALUES ('$timestamp', $timestamp_epoch, $temp, $util, $mem, $power);
SQL
        
        # Update process tracking
        update_process_tracking
        
        # Get current processes for display (pass total memory for percentage calculation)
        local current_processes=$(get_current_processes "$mem_total")
        
        # Ensure current_processes is valid JSON (empty array if no output)
        if [ -z "$current_processes" ] || [ "$current_processes" = "[]" ]; then
            current_processes="[]"
        fi
        
        # Create JSON content with processes
        local json_content=$(cat << EOF
{
    "timestamp": "$timestamp",
    "temperature": $temp,
    "utilization": $util,
    "memory": $mem,
    "memory_total": $mem_total,
    "memory_percent": $mem_percent,
    "power": $power,
    "current_processes": $current_processes
}
EOF
)
        
        # Write JSON safely
        safe_write_json "$JSON_FILE" "$json_content"
        
        # Publish to MQTT if enabled
        publish_to_mqtt "$JSON_FILE"
    else
        log_error "Failed to get GPU stats output"
    fi
}

###############################################################################
# export_history_json: Export history to JSON for web display
###############################################################################
function export_history_json() {
    local output_file="$HISTORY_DIR/history.json"
    
    local history_data=$(sqlite3 -json "$DB_FILE" <<SQL
    SELECT 
        timestamp,
        temperature,
        utilization,
        memory,
        power
    FROM gpu_metrics
    ORDER BY timestamp_epoch DESC
    LIMIT 1000;
SQL
)
    
    if [ -n "$history_data" ]; then
        echo "$history_data" > "$output_file"
    fi
}

###############################################################################
# export_process_history_json: Export process history to JSON for web display
###############################################################################
function export_process_history_json() {
    local output_file="$HISTORY_DIR/process_history.json"
    
    # Use global GPU_MEMORY_TOTAL for percentage calculation
    local mem_total="${GPU_MEMORY_TOTAL:-0}"
    
    local process_history=$(sqlite3 -json "$DB_FILE" <<SQL
    SELECT 
        pid,
        process_name,
        datetime(first_seen, 'unixepoch', 'localtime') as first_seen,
        datetime(last_seen, 'unixepoch', 'localtime') as last_seen,
        (last_seen - first_seen) as lifetime_seconds,
        max_memory,
        avg_memory,
        CASE 
            WHEN $mem_total > 0 THEN ROUND((avg_memory / $mem_total) * 100, 2)
            ELSE 0 
        END as avg_memory_percent,
        CASE 
            WHEN $mem_total > 0 THEN ROUND((max_memory / $mem_total) * 100, 2)
            ELSE 0 
        END as max_memory_percent,
        sample_count
    FROM gpu_processes
    ORDER BY last_seen DESC
    LIMIT 100;
SQL
)
    
    if [ -n "$process_history" ]; then
        echo "$process_history" > "$output_file"
    else
        echo "[]" > "$output_file"
    fi
}

###############################################################################
# cleanup_old_data: Clean up old database records
###############################################################################
function cleanup_old_data() {
    local cutoff_time=$(( $(date +%s) - 259200 ))  # 3 days
    
    sqlite3 "$DB_FILE" <<SQL
    DELETE FROM gpu_metrics WHERE timestamp_epoch < $cutoff_time;
    DELETE FROM process_snapshots WHERE timestamp_epoch < $cutoff_time;
    DELETE FROM gpu_processes WHERE last_seen < $cutoff_time;
    VACUUM;
SQL
}

###############################################################################
# Main execution
###############################################################################

echo "========================================="
echo "GPU Model Monitor (with MQTT)"
echo "========================================="
echo "GPU: $GPU_NAME"
echo "Driver: $DRIVER_VERSION"
echo "CUDA: $CUDA_VERSION_FULL"
echo "========================================="

# Initialize database
initialize_database

# Start Python web server in background
python3 "$BASE_DIR/server.py" &
SERVER_PID=$!

# Counter for periodic tasks
export_counter=0
cleanup_counter=0

# Main monitoring loop
while true; do
    update_stats
    
    # Export history every 15 iterations (60 seconds)
    export_counter=$((export_counter + 1))
    if [ $export_counter -ge 15 ]; then
        export_history_json
        export_process_history_json
        export_counter=0
    fi
    
    # Cleanup old data every 900 iterations (1 hour)
    cleanup_counter=$((cleanup_counter + 1))
    if [ $cleanup_counter -ge 900 ]; then
        cleanup_old_data
        cleanup_counter=0
    fi
    
    sleep $INTERVAL
done
