#!/bin/bash
###############################################################################
# Quick Configuration Script for MQTT Settings
# Run this to update MQTT settings in docker-compose.yml
###############################################################################

echo "========================================="
echo "GPU Model Monitor - MQTT Configuration"
echo "========================================="
echo ""

# Prompt for MQTT settings
read -p "MQTT Broker IP/Hostname: " MQTT_HOST
read -p "MQTT Port [1883]: " MQTT_PORT
MQTT_PORT=${MQTT_PORT:-1883}
read -p "Use SSL/TLS? (true/false) [false]: " MQTT_SSL
MQTT_SSL=${MQTT_SSL:-false}
read -p "MQTT Username: " MQTT_USERNAME
read -sp "MQTT Password: " MQTT_PASSWORD
echo ""
read -p "MQTT Topic Prefix [gpu_monitor]: " MQTT_TOPIC_PREFIX
MQTT_TOPIC_PREFIX=${MQTT_TOPIC_PREFIX:-gpu_monitor}

echo ""
echo "========================================="
echo "Configuration Summary:"
echo "========================================="
echo "MQTT Host: $MQTT_HOST"
echo "MQTT Port: $MQTT_PORT"
echo "SSL/TLS: $MQTT_SSL"
echo "Username: $MQTT_USERNAME"
echo "Password: ********"
echo "Topic Prefix: $MQTT_TOPIC_PREFIX"
echo "========================================="
echo ""
read -p "Apply this configuration? (y/n): " CONFIRM

if [ "$CONFIRM" != "y" ]; then
    echo "Configuration cancelled."
    exit 0
fi

# Update docker-compose.yml
cd /home/docker/GPUModelMonitorDEV

# Create backup
cp docker-compose.yml docker-compose.yml.backup

# Update the file using sed
sed -i "s|MQTT_HOST=.*|MQTT_HOST=$MQTT_HOST|g" docker-compose.yml
sed -i "s|MQTT_PORT=.*|MQTT_PORT=$MQTT_PORT|g" docker-compose.yml
sed -i "s|MQTT_SSL=.*|MQTT_SSL=$MQTT_SSL|g" docker-compose.yml
sed -i "s|MQTT_USERNAME=.*|MQTT_USERNAME=$MQTT_USERNAME|g" docker-compose.yml
sed -i "s|MQTT_PASSWORD=.*|MQTT_PASSWORD=$MQTT_PASSWORD|g" docker-compose.yml
sed -i "s|MQTT_TOPIC_PREFIX=.*|MQTT_TOPIC_PREFIX=$MQTT_TOPIC_PREFIX|g" docker-compose.yml

echo ""
echo "✓ Configuration updated!"
echo "✓ Backup saved as docker-compose.yml.backup"
echo ""
echo "Next steps:"
echo "1. Review the configuration:"
echo "   cat docker-compose.yml"
echo ""
echo "2. Build and start the container:"
echo "   docker-compose build"
echo "   docker-compose up -d"
echo ""
echo "3. Monitor the logs:"
echo "   docker logs -f GPU-Model-Monitor-DEV"
echo ""
