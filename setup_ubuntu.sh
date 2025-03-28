#!/bin/bash

# Print commands and their arguments as they are executed
set -x

echo "Starting Netdata installation and setup for Ubuntu 24.04.2 LTS..."

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root or with sudo"
    exit 1
fi

# Update package lists and install prerequisites
echo "Updating package lists and installing prerequisites..."
apt update
apt install -y curl wget apt-transport-https ca-certificates gnupg lsb-release

# Check for and remove existing Netdata installation
echo "Checking for existing Netdata installation..."
if dpkg -l | grep -q netdata; then
    echo "Existing Netdata installation found. Removing..."
    apt remove -y netdata
    apt purge -y netdata
    apt autoremove -y
    # Clean up any leftover files
    rm -rf /var/lib/netdata
    rm -rf /etc/netdata
    rm -rf /var/cache/netdata
    rm -rf /var/log/netdata
    rm -rf /usr/lib/netdata
    rm -rf /usr/share/netdata
fi

# Check if required commands are available
for cmd in curl wget; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: $cmd is not installed. Installation attempt failed."
        exit 1
    fi
done

# Install stress-ng for testing (optional)
apt install -y stress-ng

# Install Netdata using the official repository method (more reliable for Ubuntu)
echo "Installing Netdata using official repository method..."

# Add the Netdata repository
curl -fsSL https://packagecloud.io/netdata/netdata/gpgkey | gpg --dearmor -o /usr/share/keyrings/netdata-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/netdata-keyring.gpg] https://packagecloud.io/netdata/netdata/ubuntu/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/netdata.list

# Install Netdata
apt update
apt install -y netdata

# Verify Netdata installation
if ! command -v netdata &> /dev/null; then
    echo "Netdata installation failed. Please check the installation logs."
    exit 1
fi

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
    
    echo "Attempting to fix common issues..."
    # Fix permissions on netdata directories
    chown -R netdata:netdata /var/lib/netdata
    chown -R netdata:netdata /var/cache/netdata
    chmod 755 /var/cache/netdata
    
    # Restart the service
    systemctl restart netdata
    sleep 5
    
    # Check again
    if ! systemctl is-active --quiet netdata; then
        echo "Netdata service still failed to start. Manual intervention may be required."
        systemctl status netdata
        exit 1
    fi
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

# Configure firewall to allow Netdata web interface access
echo "Configuring UFW firewall to allow Netdata access..."
if command -v ufw &> /dev/null; then
    ufw allow 19999/tcp comment "Netdata web interface"
    echo "UFW firewall configured to allow Netdata web interface access."
else
    echo "UFW not installed. Please manually configure your firewall to allow port 19999/tcp."
fi

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

# Get server IP address for connecting from other machines
SERVER_IP=$(hostname -I | awk '{print $1}')

echo "
=================================
Installation Complete!
=================================
Netdata Status: $(systemctl status netdata --no-pager | grep Active)

You can access the Netdata dashboard at:
http://localhost:19999
Or from another machine:
http://${SERVER_IP}:19999

CPU usage alerts have been configured for:
- Warning: > 80%
- Critical: > 90%

To view Netdata logs, use:
journalctl -u netdata --no-pager -n 50

To test your monitoring dashboard, run:
chmod +x test_dashboard.sh
sudo ./test_dashboard.sh
=================================
"