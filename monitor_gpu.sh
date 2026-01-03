#!/bin/bash
###############################################################################
# GPU Model Monitor - Backend Process
# 
# This script monitors NVIDIA GPU metrics with enhanced process tracking.
# Features:
# - Real-time GPU metrics collection
# - Driver and CUDA version tracking
# - Process monitoring with PID, name, and memory usage
# - Process lifetime tracking
# - Historical data management
# - SQLite database for persistence
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
function update_process_tracking() {
    local current_time=$(date +%s)
    
    # Get current processes using GPU
    local process_data=$(nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader,nounits 2>/dev/null)
    
    if [ -z "$process_data" ]; then
        log_debug "No GPU processes currently running"
        return 0
    fi
    
    # Process each running process
    echo "$process_data" | while IFS=',' read -r pid process_name memory; do
        # Clean up whitespace
        pid=$(echo "$pid" | tr -d ' ')
        process_name=$(echo "$process_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        memory=$(echo "$memory" | tr -d ' ')
        
        if [ -z "$pid" ] || [ "$pid" = "N/A" ]; then
            continue
        fi
        
        # Insert snapshot
        sqlite3 "$DB_FILE" <<SQL
        INSERT INTO process_snapshots (timestamp_epoch, pid, process_name, memory_usage)
        VALUES ($current_time, $pid, '$process_name', $memory);
        
        -- Update or insert into gpu_processes
        INSERT INTO gpu_processes (pid, process_name, first_seen, last_seen, max_memory, avg_memory, sample_count)
        VALUES ($pid, '$process_name', $current_time, $current_time, $memory, $memory, 1)
        ON CONFLICT(pid) DO UPDATE SET
            last_seen = $current_time,
            max_memory = MAX(max_memory, $memory),
            avg_memory = ((avg_memory * sample_count) + $memory) / (sample_count + 1),
            sample_count = sample_count + 1;
SQL
    done
}

###############################################################################
# get_current_processes: Get current GPU processes as JSON
###############################################################################
function get_current_processes() {
    local current_time=$(date +%s)
    
    # Get processes that were seen in the last 10 seconds (still active)
    local cutoff_time=$((current_time - 10))
    
    sqlite3 -json "$DB_FILE" <<SQL
    SELECT 
        pid,
        process_name,
        datetime(first_seen, 'unixepoch') as first_seen,
        datetime(last_seen, 'unixepoch') as last_seen,
        (last_seen - first_seen) as lifetime_seconds,
        max_memory,
        avg_memory,
        sample_count
    FROM gpu_processes
    WHERE last_seen > $cutoff_time
    ORDER BY last_seen DESC;
SQL
}

###############################################################################
# get_process_history: Get historical process data as JSON
###############################################################################
function get_process_history() {
    # Get all processes with their history
    sqlite3 -json "$DB_FILE" <<SQL
    SELECT 
        pid,
        process_name,
        datetime(first_seen, 'unixepoch') as first_seen,
        datetime(last_seen, 'unixepoch') as last_seen,
        (last_seen - first_seen) as lifetime_seconds,
        max_memory,
        avg_memory,
        sample_count
    FROM gpu_processes
    ORDER BY last_seen DESC
    LIMIT 100;
SQL
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
    local gpu_stats=$(nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,memory.used,power.draw \
                     --format=csv,noheader,nounits 2>/dev/null)
    
    if [[ -n "$gpu_stats" ]]; then
        local temp=$(echo "$gpu_stats" | cut -d',' -f1 | tr -d ' ')
        local util=$(echo "$gpu_stats" | cut -d',' -f2 | tr -d ' ')
        local mem=$(echo "$gpu_stats" | cut -d',' -f3 | tr -d ' ')
        local power=$(echo "$gpu_stats" | cut -d',' -f4 | tr -d ' []')

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
        
        # Get current processes for display
        local current_processes=$(get_current_processes)
        
        # Create JSON content with processes
        local json_content=$(cat << EOF
{
    "timestamp": "$timestamp",
    "temperature": $temp,
    "utilization": $util,
    "memory": $mem,
    "power": $power,
    "current_processes": $current_processes
}
EOF
)
        
        # Write JSON safely
        safe_write_json "$JSON_FILE" "$json_content"
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
    
    sqlite3 -json "$DB_FILE" <<SQL > "$output_file"
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
    
    chmod 666 "$output_file" 2>/dev/null
}

###############################################################################
# export_process_history: Export process history to JSON
###############################################################################
function export_process_history() {
    local output_file="$HISTORY_DIR/process_history.json"
    local process_history=$(get_process_history)
    
    safe_write_json "$output_file" "$process_history"
    chmod 666 "$output_file" 2>/dev/null
}

###############################################################################
# clean_old_data: Purges old data from SQLite database
###############################################################################
function clean_old_data() {
    log_debug "Cleaning old data from SQLite database"
    
    local cutoff_time=$(( $(date +%s) - 259200 ))  # 3 days
    
    sqlite3 "$DB_FILE" <<EOF
    DELETE FROM gpu_metrics WHERE timestamp_epoch < $cutoff_time;
    DELETE FROM process_snapshots WHERE timestamp_epoch < $cutoff_time;
    DELETE FROM gpu_processes WHERE last_seen < $cutoff_time;
    VACUUM;
EOF
    
    if [ $? -ne 0 ]; then
        log_error "Failed to clean old data from database"
        return 1
    fi
    
    log_debug "Old data cleaned successfully"
    return 0
}

# Initialize the SQLite database before starting monitoring
initialize_database

# Export initial history files
export_history_json
export_process_history

# Start web server in background using Python server
cd /app && python3 server.py &

###############################################################################
# Main Process Loop
###############################################################################
update_counter=0
while true; do
    update_stats
    
    # Export history every 15 updates (every minute)
    update_counter=$((update_counter + 1))
    if [ $((update_counter % 15)) -eq 0 ]; then
        export_history_json
        export_process_history
    fi
    
    # Clean old data once per hour
    if [ $(date +%M) -eq 0 ] && [ $(date +%S) -lt 10 ]; then
        clean_old_data
    fi
    
    sleep $INTERVAL
done
