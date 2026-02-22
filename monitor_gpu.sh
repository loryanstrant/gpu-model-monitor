#!/bin/bash
###############################################################################
# GPU Model Monitor - Backend Process (with MQTT Support)
# 
# This script monitors NVIDIA GPU metrics with enhanced process tracking and MQTT publishing.
# Features:
# - Real-time GPU metrics collection
# - Driver and CUDA version tracking
# - Process monitoring with PID, name, and memory usage
# - Process lifetime tracking with actual OS process start times
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

# Remaining functions omitted for brevity - full file in repository
# This includes: initialize_database, update_process_tracking, get_current_processes,
# get_process_history, safe_write_json, update_stats, export_history_json,
# export_process_history_json, cleanup_old_data, and main execution loop
