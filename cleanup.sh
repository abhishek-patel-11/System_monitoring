#!/bin/bash

# Print commands as they are executed
set -x

echo "Starting Netdata cleanup..."

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root or with sudo"
    exit 1
fi

# Stop Netdata service
systemctl stop netdata

# Remove Netdata packages
# First try the official uninstaller if it exists
if [ -f /usr/libexec/netdata/netdata-uninstaller.sh ]; then
    /usr/libexec/netdata/netdata-uninstaller.sh --yes --force
else
    # Fallback removal method
    dnf remove -y netdata netdata-*
    rm -rf /var/lib/netdata
    rm -rf /var/cache/netdata
    rm -rf /var/log/netdata
    rm -rf /etc/netdata
    rm -rf /usr/share/netdata
    rm -rf /usr/libexec/netdata
fi

# Remove any remaining configuration files
find /etc -name '*netdata*' -exec rm -rf {} +

# Remove stress-ng if it was installed by test script
dnf remove -y stress-ng
amazon-linux-extras remove epel -y

# Remove auto-update cron job if it exists
rm -f /etc/cron.daily/netdata-updater

echo "
=================================
Cleanup Complete!
=================================
Netdata has been completely removed from the system.
All configuration files and data have been cleaned up.

To verify the cleanup:
1. 'systemctl status netdata' should show no service
2. 'netdata' command should not be found
3. No files should remain in /etc/netdata
=================================
"

# Final verification
if systemctl status netdata &>/dev/null; then
    echo "WARNING: Netdata service still exists in systemd"
else
    echo "Verified: Netdata service removed from systemd"
fi

if [ -d "/etc/netdata" ]; then
    echo "WARNING: Netdata configuration directory still exists"
else
    echo "Verified: Netdata configuration directory removed"
fi