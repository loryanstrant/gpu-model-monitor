#!/usr/bin/env python3
"""
MQTT Publisher for GPU Model Monitor
Publishes GPU metrics and process data to an MQTT broker for Home Assistant integration
"""

import json
import os
import sys
import logging
from datetime import datetime
import paho.mqtt.client as mqtt
import time
import psutil

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger('mqtt-publisher')

class GPUMQTTPublisher:
    def __init__(self):
        # Read configuration from environment variables
        self.mqtt_host = os.getenv('MQTT_HOST', '').strip()
        self.mqtt_port = int(os.getenv('MQTT_PORT', '1883'))
        self.mqtt_username = os.getenv('MQTT_USERNAME', '').strip()
        self.mqtt_password = os.getenv('MQTT_PASSWORD', '').strip()
        self.mqtt_ssl = os.getenv('MQTT_SSL', 'false').lower() == 'true'
        self.mqtt_topic_prefix = os.getenv('MQTT_TOPIC_PREFIX', 'gpu_monitor').strip()
        self.mqtt_enabled = os.getenv('MQTT_ENABLED', 'false').lower() == 'true'
        
        # GPU configuration
        self.gpu_name = None
        self.driver_version = None
        self.cuda_version = None
        
        self.client = None
        self.connected = False
        
        # Check if MQTT is enabled
        if not self.mqtt_enabled:
            logger.info("MQTT publishing is disabled via MQTT_ENABLED=false")
            return
            
        # Validate required configuration
        if not self.mqtt_host:
            logger.warning("MQTT_HOST not configured, MQTT publishing disabled")
            self.mqtt_enabled = False
            return
        
        logger.info(f"MQTT Publisher initialized for broker: {self.mqtt_host}:{self.mqtt_port}")
        logger.info(f"Topic prefix: {self.mqtt_topic_prefix}")
        logger.info(f"SSL enabled: {self.mqtt_ssl}")
    
    def get_process_start_time(self, pid):
        """Get the actual start time of a process from the system"""
        try:
            proc = psutil.Process(pid)
            # Get process creation time as Unix timestamp
            create_time = proc.create_time()
            # Convert to datetime string
            start_datetime = datetime.fromtimestamp(create_time)
            return start_datetime.strftime('%Y-%m-%d %H:%M:%S'), create_time
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess, Exception):
            return None, None
    
    def format_lifetime(self, seconds):
        """Format lifetime in human-readable format"""
        if seconds < 60:
            return f"{seconds}s"
        elif seconds < 3600:
            minutes = seconds // 60
            remaining_seconds = seconds % 60
            return f"{minutes}m {remaining_seconds}s"
        elif seconds < 86400:
            hours = seconds // 3600
            remaining_minutes = (seconds % 3600) // 60
            return f"{hours}h {remaining_minutes}m"
        else:
            days = seconds // 86400
            remaining_hours = (seconds % 86400) // 3600
            return f"{days}d {remaining_hours}h"
    
    def load_gpu_config(self):
        """Load GPU configuration from config file"""
        config_file = "/app/gpu_config.json"
        try:
            if os.path.exists(config_file):
                with open(config_file, 'r') as f:
                    config = json.load(f)
                    self.gpu_name = config.get('gpu_name', 'GPU')
                    self.driver_version = config.get('driver_version', 'Unknown')
                    self.cuda_version = config.get('cuda_version', 'Unknown')
                    logger.info(f"GPU Config loaded: {self.gpu_name}")
        except Exception as e:
            logger.error(f"Failed to load GPU config: {e}")
            self.gpu_name = "GPU"
            self.driver_version = "Unknown"
            self.cuda_version = "Unknown"
    
    def on_connect(self, client, userdata, flags, rc):
        """Callback when connected to MQTT broker"""
        if rc == 0:
            self.connected = True
            logger.info("Successfully connected to MQTT broker")
            # Publish Home Assistant discovery messages
            self.publish_discovery()
        else:
            self.connected = False
            logger.error(f"Failed to connect to MQTT broker, return code: {rc}")
    
    def on_disconnect(self, client, userdata, rc):
        """Callback when disconnected from MQTT broker"""
        self.connected = False
        if rc != 0:
            logger.warning(f"Unexpected MQTT disconnection, return code: {rc}")
    
    def connect(self):
        """Connect to MQTT broker"""
        if not self.mqtt_enabled:
            return False
        
        try:
            self.client = mqtt.Client(client_id="gpu_model_monitor")
            self.client.on_connect = self.on_connect
            self.client.on_disconnect = self.on_disconnect
            
            # Set username and password if provided
            if self.mqtt_username and self.mqtt_password:
                self.client.username_pw_set(self.mqtt_username, self.mqtt_password)
            
            # Enable SSL/TLS if configured
            if self.mqtt_ssl:
                import ssl
                self.client.tls_set(cert_reqs=ssl.CERT_NONE)
                self.client.tls_insecure_set(True)
            
            # Connect to broker
            self.client.connect(self.mqtt_host, self.mqtt_port, 60)
            self.client.loop_start()
            
            # Wait for connection
            timeout = 5
            start_time = time.time()
            while not self.connected and (time.time() - start_time) < timeout:
                time.sleep(0.1)
            
            return self.connected
            
        except Exception as e:
            logger.error(f"Failed to connect to MQTT broker: {e}")
            return False
    
    def publish_discovery(self):
        """Publish Home Assistant MQTT discovery messages"""
        if not self.connected or not self.gpu_name:
            return
        
        # Sanitize device name for use in topic
        device_id = self.gpu_name.lower().replace(' ', '_').replace('-', '_')
        
        # Device information
        device_info = {
            "identifiers": [f"gpu_monitor_{device_id}"],
            "name": f"GPU Monitor - {self.gpu_name}",
            "model": self.gpu_name,
            "manufacturer": "NVIDIA",
            "sw_version": f"Driver {self.driver_version}, CUDA {self.cuda_version}",
            "configuration_url": "https://github.com/loryanstrant/gpu-model-monitor"
        }
        
        # Define sensors for Home Assistant
        sensors = [
            {
                "name": "GPU Temperature",
                "state_topic": f"{self.mqtt_topic_prefix}/temperature",
                "unit_of_measurement": "°C",
                "device_class": "temperature",
                "state_class": "measurement",
                "unique_id": f"{device_id}_temperature",
                "icon": "mdi:thermometer"
            },
            {
                "name": "GPU Utilization",
                "state_topic": f"{self.mqtt_topic_prefix}/utilization",
                "unit_of_measurement": "%",
                "state_class": "measurement",
                "unique_id": f"{device_id}_utilization",
                "icon": "mdi:chip"
            },
            {
                "name": "GPU Memory Used",
                "state_topic": f"{self.mqtt_topic_prefix}/memory",
                "unit_of_measurement": "MiB",
                "state_class": "measurement",
                "unique_id": f"{device_id}_memory",
                "icon": "mdi:memory"
            },
            {
                "name": "GPU Memory Total",
                "state_topic": f"{self.mqtt_topic_prefix}/memory_total",
                "unit_of_measurement": "MiB",
                "state_class": "measurement",
                "unique_id": f"{device_id}_memory_total",
                "icon": "mdi:memory"
            },
            {
                "name": "GPU Memory Utilization",
                "state_topic": f"{self.mqtt_topic_prefix}/memory_percent",
                "unit_of_measurement": "%",
                "state_class": "measurement",
                "unique_id": f"{device_id}_memory_percent",
                "icon": "mdi:memory"
            },
            {
                "name": "GPU Power Draw",
                "state_topic": f"{self.mqtt_topic_prefix}/power",
                "unit_of_measurement": "W",
                "device_class": "power",
                "state_class": "measurement",
                "unique_id": f"{device_id}_power",
                "icon": "mdi:flash"
            },
            {
                "name": "GPU Process Count",
                "state_topic": f"{self.mqtt_topic_prefix}/process_count",
                "state_class": "measurement",
                "unique_id": f"{device_id}_process_count",
                "icon": "mdi:application-cog"
            },
            {
                "name": "GPU Active Processes",
                "state_topic": f"{self.mqtt_topic_prefix}/active_processes",
                "json_attributes_topic": f"{self.mqtt_topic_prefix}/active_processes",
                "unique_id": f"{device_id}_active_processes",
                "icon": "mdi:application-brackets",
                "value_template": "{{ value_json.count }}"
            },
            {
                "name": "GPU Process History",
                "state_topic": f"{self.mqtt_topic_prefix}/process_history",
                "json_attributes_topic": f"{self.mqtt_topic_prefix}/process_history",
                "unique_id": f"{device_id}_process_history",
                "icon": "mdi:history",
                "value_template": "{{ value_json.total }}"
            }
        ]
        
        # Publish discovery messages for each sensor
        for sensor in sensors:
            sensor["device"] = device_info
            discovery_topic = f"homeassistant/sensor/{device_id}/{sensor['unique_id']}/config"
            payload = json.dumps(sensor)
            
            result = self.client.publish(discovery_topic, payload, retain=True)
            if result.rc == mqtt.MQTT_ERR_SUCCESS:
                logger.debug(f"Published discovery for: {sensor['name']}")
            else:
                logger.error(f"Failed to publish discovery for: {sensor['name']}")
        
        logger.info("Home Assistant discovery messages published")
    
    def publish_active_processes(self, processes):
        """Publish detailed information about active GPU processes"""
        if not self.connected:
            return False
        
        try:
            # Parse processes if it's a string
            if isinstance(processes, str):
                try:
                    processes = json.loads(processes)
                except:
                    processes = []
            
            if not isinstance(processes, list):
                processes = []
            
            # Format process data for publishing with actual start times
            formatted_processes = []
            current_time = time.time()
            
            for proc in processes:
                pid = proc.get("pid")
                
                # Get actual process start time from the OS
                start_time_str, start_time_unix = self.get_process_start_time(pid)
                
                # Calculate actual lifetime
                if start_time_unix:
                    actual_lifetime = int(current_time - start_time_unix)
                    lifetime_formatted = self.format_lifetime(actual_lifetime)
                else:
                    # Fallback to first_seen based calculation if process info not available
                    actual_lifetime = proc.get("lifetime_seconds", 0)
                    lifetime_formatted = self.format_lifetime(actual_lifetime)
                    start_time_str = proc.get("first_seen", "unknown")
                
                formatted_proc = {
                    "pid": pid,
                    "name": proc.get("process_name", "unknown"),
                    "memory_current": proc.get("memory", 0),
                    "memory_max": proc.get("max_memory", 0),
                    "memory_avg": proc.get("avg_memory", 0),
                    "memory_percent": proc.get("memory_percent", 0),
                    "process_start_time": start_time_str,
                    "first_seen_by_container": proc.get("first_seen", "unknown"),
                    "last_seen": proc.get("last_seen", "unknown"),
                    "lifetime_seconds": actual_lifetime,
                    "lifetime_formatted": lifetime_formatted,
                    "sample_count": proc.get("sample_count", 0),
                    "status": "active"
                }
                formatted_processes.append(formatted_proc)
            
            # Create payload with count and process details
            payload = {
                "count": len(formatted_processes),
                "processes": formatted_processes,
                "timestamp": datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            }
            
            # Publish to active_processes topic
            topic = f"{self.mqtt_topic_prefix}/active_processes"
            self.client.publish(topic, json.dumps(payload), retain=False)
            
            logger.debug(f"Published {len(formatted_processes)} active processes")
            return True
            
        except Exception as e:
            logger.error(f"Failed to publish active processes: {e}")
            return False
    
    def publish_process_history(self):
        """Publish GPU process history from database"""
        if not self.connected:
            return False
        
        try:
            # Get current GPU memory total for percentage calculation
            mem_total = 0
            try:
                with open('/app/gpu_current_stats.json', 'r') as f:
                    current_stats = json.load(f)
                    mem_total = current_stats.get('memory_total', 0)
            except:
                logger.debug("Could not load memory_total from current stats")
            
            # Read process history from database via script
            import subprocess
            
            # Build SQL query with memory percentage calculation
            sql_query = f'''SELECT 
                pid,
                process_name,
                datetime(first_seen, 'unixepoch', 'localtime') as first_seen,
                datetime(last_seen, 'unixepoch', 'localtime') as last_seen,
                (last_seen - first_seen) as lifetime_seconds,
                max_memory,
                avg_memory,
                CASE 
                    WHEN {mem_total} > 0 THEN ROUND((avg_memory / {mem_total}) * 100, 2)
                    ELSE 0 
                END as avg_memory_percent,
                CASE 
                    WHEN {mem_total} > 0 THEN ROUND((max_memory / {mem_total}) * 100, 2)
                    ELSE 0 
                END as max_memory_percent,
                sample_count
            FROM gpu_processes
            ORDER BY last_seen DESC
            LIMIT 50;'''
            
            result = subprocess.run(
                ['sqlite3', '-json', '/app/history/gpu_metrics.db', sql_query],
                capture_output=True,
                text=True,
                timeout=5
            )
            
            if result.returncode == 0 and result.stdout:
                history = json.loads(result.stdout)
                
                # Format history data
                formatted_history = []
                for proc in history:
                    formatted_proc = {
                        "pid": proc.get("pid"),
                        "name": proc.get("process_name", "unknown"),
                        "first_seen": proc.get("first_seen", "unknown"),
                        "last_seen": proc.get("last_seen", "unknown"),
                        "lifetime_seconds": proc.get("lifetime_seconds", 0),
                        "memory_max": proc.get("max_memory", 0),
                        "memory_max_percent": proc.get("max_memory_percent", 0),
                        "memory_avg": proc.get("avg_memory", 0),
                        "memory_avg_percent": proc.get("avg_memory_percent", 0),
                        "sample_count": proc.get("sample_count", 0)
                    }
                    formatted_history.append(formatted_proc)
                
                # Create payload
                payload = {
                    "total": len(formatted_history),
                    "history": formatted_history,
                    "timestamp": datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                }
                
                # Publish to process_history topic
                topic = f"{self.mqtt_topic_prefix}/process_history"
                self.client.publish(topic, json.dumps(payload), retain=False)
                
                logger.debug(f"Published process history with {len(formatted_history)} entries")
                return True
            else:
                logger.debug("No process history available")
                # Publish empty history
                payload = {
                    "total": 0,
                    "history": [],
                    "timestamp": datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                }
                topic = f"{self.mqtt_topic_prefix}/process_history"
                self.client.publish(topic, json.dumps(payload), retain=False)
                return True
                
        except Exception as e:
            logger.error(f"Failed to publish process history: {e}")
            return False
    
    def publish_metrics(self, metrics_data):
        """Publish GPU metrics to MQTT"""
        if not self.connected:
            logger.warning("Not connected to MQTT broker, skipping publish")
            return False
        
        try:
            # Extract metrics
            temperature = metrics_data.get('temperature', 0)
            utilization = metrics_data.get('utilization', 0)
            memory = metrics_data.get('memory', 0)
            memory_total = metrics_data.get('memory_total', 0)
            memory_percent = metrics_data.get('memory_percent', 0)
            power = metrics_data.get('power', 0)
            
            # Count current processes
            current_processes = metrics_data.get('current_processes', [])
            # Handle both JSON string and parsed list
            if isinstance(current_processes, str):
                try:
                    current_processes = json.loads(current_processes)
                except:
                    current_processes = []
            process_count = len(current_processes) if isinstance(current_processes, list) else 0
            
            # Publish individual metrics
            metrics = {
                'temperature': temperature,
                'utilization': utilization,
                'memory': memory,
                'memory_total': memory_total,
                'memory_percent': memory_percent,
                'power': power,
                'process_count': process_count
            }
            
            for metric_name, value in metrics.items():
                topic = f"{self.mqtt_topic_prefix}/{metric_name}"
                self.client.publish(topic, str(value), retain=False)
            
            # Publish full state as JSON
            state_topic = f"{self.mqtt_topic_prefix}/state"
            state_payload = {
                "timestamp": metrics_data.get('timestamp'),
                "temperature": temperature,
                "utilization": utilization,
                "memory": memory,
                "memory_total": memory_total,
                "memory_percent": memory_percent,
                "power": power,
                "process_count": process_count
            }
            self.client.publish(state_topic, json.dumps(state_payload), retain=False)
            
            # Publish active processes with details
            self.publish_active_processes(current_processes)
            
            # Publish process history (every publish cycle to keep history updated)
            self.publish_process_history()
            
            logger.debug(f"Published metrics - Temp: {temperature}°C, Util: {utilization}%, Mem: {memory}MiB, Power: {power}W, Processes: {process_count}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to publish metrics: {e}")
            return False
    
    def disconnect(self):
        """Disconnect from MQTT broker"""
        if self.client:
            self.client.loop_stop()
            self.client.disconnect()
            logger.info("Disconnected from MQTT broker")


def main():
    """Main function for command-line usage"""
    if len(sys.argv) < 2:
        logger.error("Usage: mqtt_publisher.py <json_file>")
        sys.exit(1)
    
    json_file = sys.argv[1]
    
    # Initialize publisher
    publisher = GPUMQTTPublisher()
    
    if not publisher.mqtt_enabled:
        logger.info("MQTT is disabled, exiting")
        sys.exit(0)
    
    # Load GPU configuration
    publisher.load_gpu_config()
    
    # Connect to broker
    if not publisher.connect():
        logger.error("Failed to connect to MQTT broker")
        sys.exit(1)
    
    # Read metrics from JSON file
    try:
        with open(json_file, 'r') as f:
            metrics = json.load(f)
        
        # Publish metrics
        if publisher.publish_metrics(metrics):
            logger.info("Successfully published metrics to MQTT")
        else:
            logger.error("Failed to publish metrics to MQTT")
            sys.exit(1)
    
    except Exception as e:
        logger.error(f"Error reading metrics file: {e}")
        sys.exit(1)
    
    finally:
        publisher.disconnect()


if __name__ == "__main__":
    main()
