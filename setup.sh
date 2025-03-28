#!/bin/bash

# Print commands and their arguments as they are executed
set -x

echo "Starting Netdata installation and setup..."

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root or with sudo"
    exit 1
fi

# Check if required commands are available
for cmd in curl wget; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: $cmd is not installed. Please install it manually."
        exit 1
    fi
done

# Install Netdata using the official one-line installation script
wget -O /tmp/netdata-kickstart.sh https://my-netdata.io/kickstart.sh
sh /tmp/netdata-kickstart.sh --non-interactive

# Explicitly start the Netdata service
echo "Starting Netdata service..."
systemctl daemon-reload
systemctl enable netdata
systemctl start netdata

# Wait a bit for the service to fully start
sleep 5

# Check service status with more detailed output
if ! systemctl is-active --quiet netdata; then
    echo "Netdata service failed to start. Checking status..."
    systemctl status netdata
    journalctl -u netdata --no-pager -n 50
    exit 1
fi

echo "Netdata service is running successfully!"

# Configure basic alert for CPU usage
mkdir -p /etc/netdata/health.d
cat > /etc/netdata/health.d/cpu_usage.conf << EOF
alarm: cpu_usage
on: system.cpu
lookup: average -3s percentage
every: 10s
warn: \$this > 80
crit: \$this > 90
info: CPU usage is high
EOF

# Restart Netdata to apply new configuration
systemctl restart netdata

# Wait a bit for the service to restart
sleep 5

# Verify service is still running after restart
if ! systemctl is-active --quiet netdata; then
    echo "Netdata service failed to restart after configuration changes. Checking status..."
    systemctl status netdata
    journalctl -u netdata --no-pager -n 50
    exit 1
fi

# Configure custom process monitoring
echo "Setting up custom process monitoring..."
mkdir -p /etc/netdata/python.d
mkdir -p /etc/netdata/custom-charts.d

# Copy configuration files
cp configs/apps_groups.conf /etc/netdata/apps_groups.conf
cp configs/python.d/apps.conf /etc/netdata/python.d/apps.conf

# Set proper permissions
chown -R netdata:netdata /etc/netdata/python.d
chown -R netdata:netdata /etc/netdata/custom-charts.d
chmod 755 /etc/netdata/python.d
chmod 644 /etc/netdata/python.d/apps.conf
chmod 644 /etc/netdata/apps_groups.conf

# Restart Netdata to apply changes
systemctl restart netdata

# Wait for service to restart
sleep 5

# Verify service status
if ! systemctl is-active --quiet netdata; then
    echo "Netdata service failed to restart. Checking status..."
    systemctl status netdata
    journalctl -u netdata --no-pager -n 50
    exit 1
fi

echo "Custom process monitoring has been configured successfully!"
echo "Access your Netdata dashboard at http://localhost:19999"

# Print access instructions and status
echo "
=================================
Installation Complete!
=================================
Netdata Status: $(systemctl status netdata --no-pager | grep Active)

You can access the Netdata dashboard at:
http://localhost:19999

To access from another machine, replace 'localhost' 
with this server's IP address.

CPU usage alerts have been configured for:
- Warning: > 80%
- Critical: > 90%

To view Netdata logs, use:
journalctl -u netdata --no-pager -n 50
=================================
"

# Clean up installation files
rm -f /tmp/netdata-kickstart.sh