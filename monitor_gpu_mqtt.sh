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
        log_debug "MQTT: $line"
    done &
}

###############################################################################
# Get GPU name, driver version, and CUDA version
###############################################################################
GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || echo "GPU")
DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || echo "Unknown")
CUDA_VERSION=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || echo "Unknown")

# Get CUDA version from nvidia-smi output
CUDA_VERSION_FULL=$(nvidia-smi | grep "CUDA Version" | sed 's/.*CUDA Version: \([0-9.]*\).*/\1/' || echo "Unknown")

CONFIG_FILE="$BASE_DIR/gpu_config.json"

# Create config JSON with GPU info
cat > "$CONFIG_FILE" << EOF
{
    "gpu_name": "${GPU_NAME}",
    "driver_version": "${DRIVER_VERSION}",
    "cuda_version": "${CUDA_VERSION_FULL}"
}
EOF

###############################################################################
# initialize_database: Creates and initializes the SQLite database
###############################################################################
function initialize_database() {
    log_debug "Initializing SQLite database at $DB_FILE"
    
    if [ ! -f "$DB_FILE" ]; then
        log_debug "Creating new database file"
        touch "$DB_FILE"
        chmod 666 "$DB_FILE"
    fi
    
    # Create SQLite tables and indexes
    sqlite3 "$DB_FILE" << EOF
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
        log_error "Failed to initialize SQLite database"
        return 1
    fi
    
    log_debug "Database initialized successfully"
    return 0
}

###############################################################################
# update_process_tracking: Track GPU processes
###############################################################################

# Helper function to validate PID
is_valid_pid() {
    local pid="$1"
    [ -n "$pid" ] && [ "$pid" != "N/A" ] && [ "$pid" != "-" ] && [[ "$pid" =~ ^[0-9]+$ ]]
}

function update_process_tracking() {
    local current_time=$(date +%s)
    local process_count=0
    
    # Cache nvidia-smi outputs to avoid repeated calls
    local smi_output=$(nvidia-smi 2>/dev/null)
    local compute_apps=$(nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader,nounits 2>/dev/null)
    
    log_debug "Starting process tracking at timestamp: $current_time"
    
    # Get current processes using GPU from pmon (captures ALL processes, not just compute apps)
    local pmon_raw=$(nvidia-smi pmon -c 1 2>/dev/null)
    local pmon_output=$(echo "$pmon_raw" | grep -v "^#" | awk 'NF')
    
    log_debug "pmon raw output line count: $(echo "$pmon_raw" | wc -l)"
    log_debug "pmon filtered output: $pmon_output"
    
    if [ -z "$pmon_output" ]; then
        log_debug "No GPU processes currently running (pmon empty)"
        
        # Fallback: Try parsing standard nvidia-smi output for processes
        if echo "$smi_output" | grep -q "No running processes found"; then
            log_debug "No GPU processes found (nvidia-smi reports none)"
            return 0
        fi
        
        local process_lines=$(echo "$smi_output" | awk '/Processes:/,/^$/' | grep -E "^\|.*[0-9]+.*MiB.*\|" | grep -v "Processes")
        
        if [ -z "$process_lines" ]; then
            log_debug "No processes found in nvidia-smi table output"
            return 0
        fi
        
        log_debug "Found process lines in nvidia-smi output, parsing..."
        
        while IFS='|' read -r _ content _; do
            [ -z "$content" ] && continue
            
            local gpu=$(echo "$content" | awk '{print $1}')
            local pid=$(echo "$content" | awk '{print $4}')
            local ptype=$(echo "$content" | awk '{print $5}')
            local process_name=$(echo "$content" | awk '{if (NF > 6) {for(i=6;i<=NF-1;i++) printf "%s ", $i; printf "\n"} else {print $6}}' | sed 's/[[:space:]]*$//')
            local memory=$(echo "$content" | awk '{print $NF}' | sed 's/MiB//')
            
            pid=$(echo "$pid" | tr -d ' ')
            memory=$(echo "$memory" | tr -d ' ')
            
            log_debug "Parsed nvidia-smi: PID=$pid, Name=$process_name, Mem=$memory"
            
            if ! is_valid_pid "$pid"; then
                log_debug "Invalid PID: $pid, skipping"
                continue
            fi
            
            if ! [[ "$memory" =~ ^[0-9]+$ ]]; then
                log_debug "Invalid memory value: $memory, defaulting to 0"
                memory="0"
            fi
            
            process_name=$(echo "$process_name" | sed "s/'/''/g")
            
            if sql_result=$(sqlite3 "$DB_FILE" 2>&1 <<SQL
INSERT INTO process_snapshots (timestamp_epoch, pid, process_name, memory_usage)
VALUES ($current_time, $pid, '$process_name', $memory);

INSERT INTO gpu_processes (pid, process_name, first_seen, last_seen, max_memory, avg_memory, sample_count)
VALUES ($pid, '$process_name', $current_time, $current_time, $memory, $memory, 1)
ON CONFLICT(pid) DO UPDATE SET
    last_seen = $current_time,
    max_memory = MAX(max_memory, $memory),
    avg_memory = ((avg_memory * sample_count) + $memory) / (sample_count + 1),
    sample_count = sample_count + 1;
SQL
); then
                process_count=$((process_count + 1))
                log_debug "Successfully inserted/updated process PID=$pid"
            else
                log_error "Failed to insert process PID=$pid: $sql_result"
            fi
        done < <(echo "$process_lines")
        
        log_debug "Processed $process_count processes from nvidia-smi output"
        return 0
    fi
    
    log_debug "Found pmon output, processing..."
    
    while read -r gpu_id pid ptype sm mem_util enc dec command rest; do
        [ -z "$pid" ] && continue
        
        log_debug "Parsed pmon: GPU=$gpu_id, PID=$pid, Type=$ptype, Command=$command"
        
        if ! is_valid_pid "$pid"; then
            log_debug "Invalid PID from pmon: $pid, skipping"
            continue
        fi
        
        local process_info=$(echo "$compute_apps" | grep -E "^[[:space:]]*${pid}[[:space:]]*,|^${pid}[[:space:]]*,")
        
        if [ -n "$process_info" ]; then
            local proc_pid=$(echo "$process_info" | cut -d',' -f1 | tr -d ' ')
            local proc_name=$(echo "$process_info" | cut -d',' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            local proc_mem=$(echo "$process_info" | cut -d',' -f3 | tr -d ' ')
            log_debug "Found in compute_apps: PID=$proc_pid, Name=$proc_name, Mem=$proc_mem"
        else
            local proc_pid="$pid"
            local proc_name="$command"
            local smi_mem=$(echo "$smi_output" | grep -E "^\|.*[[:space:]]${pid}[[:space:]].*MiB" | sed 's/.*[[:space:]]\([0-9]\+\)MiB.*/\1/')
            local proc_mem="${smi_mem:-0}"
            log_debug "Not in compute_apps, using pmon: PID=$proc_pid, Name=$proc_name, Mem=$proc_mem"
        fi
        
        if ! is_valid_pid "$proc_pid"; then
            log_debug "Invalid processed PID: $proc_pid, skipping"
            continue
        fi
        
        if ! [[ "$proc_mem" =~ ^[0-9]+$ ]]; then
            log_debug "Invalid memory value: $proc_mem, defaulting to 0"
            proc_mem="0"
        fi
        
        proc_name=$(echo "$proc_name" | sed "s/'/''/g")
        
        if sql_result=$(sqlite3 "$DB_FILE" 2>&1 <<SQL
INSERT INTO process_snapshots (timestamp_epoch, pid, process_name, memory_usage)
VALUES ($current_time, $proc_pid, '$proc_name', $proc_mem);

INSERT INTO gpu_processes (pid, process_name, first_seen, last_seen, max_memory, avg_memory, sample_count)
VALUES ($proc_pid, '$proc_name', $current_time, $current_time, $proc_mem, $proc_mem, 1)
ON CONFLICT(pid) DO UPDATE SET
    last_seen = $current_time,
    max_memory = MAX(max_memory, $proc_mem),
    avg_memory = ((avg_memory * sample_count) + $proc_mem) / (sample_count + 1),
    sample_count = sample_count + 1;
SQL
); then
            process_count=$((process_count + 1))
            log_debug "Successfully inserted/updated process PID=$proc_pid"
        else
            log_error "Failed to insert process PID=$proc_pid: $sql_result"
        fi
    done < <(echo "$pmon_output")
    
    log_debug "Processed $process_count processes from pmon output"
}

###############################################################################
# get_current_processes: Get current GPU processes as JSON
###############################################################################
function get_current_processes() {
    local mem_total="${1:-0}"
    local current_time=$(date +%s)
    local cutoff_time=$((current_time - 10))
    
    log_debug "Getting current processes with cutoff_time=$cutoff_time, total_memory=$mem_total"
    
    if result=$(sqlite3 -json "$DB_FILE" 2>&1 <<SQL
    SELECT 
        p.pid,
        p.process_name,
        datetime(p.first_seen, 'unixepoch', 'localtime') as first_seen,
        datetime(p.last_seen, 'unixepoch', 'localtime') as last_seen,
        (p.last_seen - p.first_seen) as lifetime_seconds,
        COALESCE(s.memory_usage, p.max_memory) as memory,
        p.max_memory,
        p.avg_memory,
        p.sample_count
    FROM gpu_processes p
    LEFT JOIN (
        SELECT pid, memory_usage
        FROM process_snapshots
        WHERE (pid, timestamp_epoch) IN (
            SELECT pid, MAX(timestamp_epoch)
            FROM process_snapshots
            GROUP BY pid
        )
    ) s ON p.pid = s.pid
    WHERE p.last_seen > $cutoff_time
    ORDER BY p.last_seen DESC;
SQL
); then
        log_debug "Current processes query returned: ${result:0:200}..."
        # Enrich with actual OS process start times and memory percentages
        if [ -f "$BASE_DIR/enrich_processes.py" ] && command -v python3 &> /dev/null; then
            result=$(echo "$result" | GPU_MEMORY_TOTAL="$mem_total" python3 "$BASE_DIR/enrich_processes.py" 2>&1)
            if [ $? -ne 0 ]; then
                log_warning "Failed to enrich process data with actual start times"
            fi
        fi
        echo "$result"
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
        [ -f "$backup" ] && rm "$backup"
        return 0
    else
        log_error "Failed to write to temp file: $temp"
        [ -f "$backup" ] && mv "$backup" "$file"
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
    local cutoff_time=$(( $(date +%s) - 259200 ))  # 3 days
    
    local history_data=$(sqlite3 -json "$DB_FILE" <<SQL
    SELECT 
        timestamp,
        temperature,
        utilization,
        memory,
        power
    FROM gpu_metrics
    WHERE timestamp_epoch > $cutoff_time
    ORDER BY timestamp_epoch ASC;
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
    
    local process_history=$(sqlite3 -json "$DB_FILE" <<SQL
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
