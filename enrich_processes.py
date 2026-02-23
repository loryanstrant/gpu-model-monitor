#!/usr/bin/env python3
"""
Helper script to enrich process data with actual OS start times and memory percentages.
Reads JSON from stdin and outputs enriched JSON to stdout.
Total GPU memory can be passed via GPU_MEMORY_TOTAL environment variable.
"""
import json
import sys
import os
import psutil
from datetime import datetime

def get_process_start_time(pid):
    """Get the actual OS start time of a process"""
    try:
        proc = psutil.Process(pid)
        start_time_unix = proc.create_time()
        start_time_str = datetime.fromtimestamp(start_time_unix).strftime('%Y-%m-%d %H:%M:%S')
        return start_time_str, start_time_unix
    except (psutil.NoSuchProcess, psutil.AccessDenied, PermissionError):
        return None, None

def format_lifetime(seconds):
    """Format lifetime in human-readable format"""
    if seconds <= 0:
        return "0s"
    
    days = int(seconds // 86400)
    hours = int((seconds % 86400) // 3600)
    minutes = int((seconds % 3600) // 60)
    secs = int(seconds % 60)
    
    if days > 0:
        return f"{days}d {hours}h"
    elif hours > 0:
        return f"{hours}h {minutes}m"
    elif minutes > 0:
        return f"{minutes}m {secs}s"
    else:
        return f"{secs}s"

def enrich_processes(processes_json, gpu_memory_total):
    """Enrich process data with actual OS start times and memory percentages"""
    try:
        processes = json.loads(processes_json)
        if not isinstance(processes, list):
            return processes_json
        
        current_time = datetime.now().timestamp()
        
        for process in processes:
            pid = process.get('pid')
            if pid:
                start_time_str, start_time_unix = get_process_start_time(pid)
                if start_time_str:
                    process['process_start_time'] = start_time_str
                    actual_lifetime = int(current_time - start_time_unix)
                    process['actual_lifetime_seconds'] = actual_lifetime
                    process['lifetime_formatted'] = format_lifetime(actual_lifetime)
                else:
                    # Keep existing lifetime if we can't get actual start time
                    process['process_start_time'] = None
                    process['actual_lifetime_seconds'] = process.get('lifetime_seconds', 0)
                    process['lifetime_formatted'] = format_lifetime(process.get('lifetime_seconds', 0))
            
            # Calculate memory percentage if total GPU memory is provided
            if gpu_memory_total > 0:
                process_memory = process.get('memory', 0) or 0
                memory_percent = round((process_memory / gpu_memory_total) * 100, 2)
                process['memory_percent'] = memory_percent
        
        return json.dumps(processes)
    except Exception as e:
        print(f"Error enriching processes: {e}", file=sys.stderr)
        return processes_json

if __name__ == '__main__':
    # Read total GPU memory from environment variable
    gpu_memory_total = float(os.getenv('GPU_MEMORY_TOTAL', '0'))
    
    # Read JSON from stdin
    input_json = sys.stdin.read()
    
    # Enrich and output
    enriched_json = enrich_processes(input_json, gpu_memory_total)
    print(enriched_json)

