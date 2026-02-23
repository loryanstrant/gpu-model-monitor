FROM python:3.13.3-slim-bookworm

# Install required packages
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip install --no-cache-dir aiohttp paho-mqtt psutil

# Create app directory
WORKDIR /app

# Create necessary directories
RUN mkdir -p /app/history /app/logs

# Copy application files
COPY gpu-stats.html /app/
COPY monitor_gpu_mqtt.sh /app/monitor_gpu.sh
COPY mqtt_publisher.py /app/
COPY enrich_processes.py /app/
COPY server.py /app/

# Make scripts executable
RUN chmod +x /app/monitor_gpu.sh /app/mqtt_publisher.py /app/enrich_processes.py

# Expose port for web server
EXPOSE 8081

# Start the application
CMD ["./monitor_gpu.sh"]
