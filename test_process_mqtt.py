#!/usr/bin/env python3
"""
Test script to demonstrate MQTT process publishing
Creates sample process data and shows what will be published
"""

import json
from datetime import datetime

# Sample active processes data (what will be published)
active_processes_payload = {
    "count": 2,
    "processes": [
        {
            "pid": 12345,
            "name": "ollama",
            "memory_current": 6144,
            "memory_max": 8192,
            "memory_avg": 7000,
            "first_seen": "2026-02-23 09:30:15",
            "last_seen": "2026-02-23 10:20:45",
            "lifetime_seconds": 3030,
            "sample_count": 758,
            "status": "active"
        },
        {
            "pid": 67890,
            "name": "python3",
            "memory_current": 2048,
            "memory_max": 3072,
            "memory_avg": 2500,
            "first_seen": "2026-02-23 10:15:00",
            "last_seen": "2026-02-23 10:20:45",
            "lifetime_seconds": 345,
            "sample_count": 86,
            "status": "active"
        }
    ],
    "timestamp": datetime.now().strftime('%Y-%m-%d %H:%M:%S')
}

# Sample process history data (what will be published)
process_history_payload = {
    "total": 5,
    "history": [
        {
            "pid": 12345,
            "name": "ollama",
            "first_seen": "2026-02-23 09:30:15",
            "last_seen": "2026-02-23 10:20:45",
            "lifetime_seconds": 3030,
            "memory_max": 8192,
            "memory_avg": 7000,
            "sample_count": 758
        },
        {
            "pid": 67890,
            "name": "python3",
            "first_seen": "2026-02-23 10:15:00",
            "last_seen": "2026-02-23 10:20:45",
            "lifetime_seconds": 345,
            "memory_max": 3072,
            "memory_avg": 2500,
            "sample_count": 86
        },
        {
            "pid": 54321,
            "name": "ComfyUI",
            "first_seen": "2026-02-23 08:00:00",
            "last_seen": "2026-02-23 09:30:00",
            "lifetime_seconds": 5400,
            "memory_max": 12288,
            "memory_avg": 11000,
            "sample_count": 1350
        },
        {
            "pid": 98765,
            "name": "stable-diffusion",
            "first_seen": "2026-02-22 15:30:00",
            "last_seen": "2026-02-22 18:45:00",
            "lifetime_seconds": 11700,
            "memory_max": 16384,
            "memory_avg": 15000,
            "sample_count": 2925
        },
        {
            "pid": 11111,
            "name": "blender",
            "first_seen": "2026-02-22 10:00:00",
            "last_seen": "2026-02-22 14:30:00",
            "lifetime_seconds": 16200,
            "memory_max": 10240,
            "memory_avg": 9500,
            "sample_count": 4050
        }
    ],
    "timestamp": datetime.now().strftime('%Y-%m-%d %H:%M:%S')
}

print("="*80)
print("MQTT PROCESS PUBLISHING - SAMPLE DATA")
print("="*80)
print()

print("TOPIC: gpu_monitor/active_processes")
print("-"*80)
print(json.dumps(active_processes_payload, indent=2))
print()

print("="*80)
print()

print("TOPIC: gpu_monitor/process_history")
print("-"*80)
print(json.dumps(process_history_payload, indent=2))
print()

print("="*80)
print("IN HOME ASSISTANT")
print("="*80)
print()
print("Sensor: sensor.gpu_monitor_nvidia_geforce_rtx_5080_active_processes")
print(f"  State: {active_processes_payload['count']}")
print(f"  Attributes: {len(active_processes_payload['processes'])} processes with full details")
print()
print("Sensor: sensor.gpu_monitor_nvidia_geforce_rtx_5080_process_history")
print(f"  State: {process_history_payload['total']}")
print(f"  Attributes: {len(process_history_payload['history'])} historical processes")
print()

print("="*80)
print("ACCESS PROCESS DATA IN HOME ASSISTANT")
print("="*80)
print()
print("Get active process names:")
print("  {{ state_attr('sensor.gpu_monitor_nvidia_geforce_rtx_5080_active_processes', 'processes') | map(attribute='name') | list }}")
print()
print("Get process with highest memory:")
print("  {{ state_attr('sensor.gpu_monitor_nvidia_geforce_rtx_5080_active_processes', 'processes') | sort(attribute='memory_current', reverse=true) | first }}")
print()
print("Total memory used by processes:")
print("  {{ state_attr('sensor.gpu_monitor_nvidia_geforce_rtx_5080_active_processes', 'processes') | map(attribute='memory_current') | sum }}")
print()
