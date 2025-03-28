#!/bin/bash

# Print commands as they are executed
set -x

echo "Starting dashboard testing..."

# Function to check if Netdata is running
check_netdata() {
    if ! systemctl is-active --quiet netdata; then
        echo "ERROR: Netdata is not running!"
        systemctl status netdata
        exit 1
    fi
}

# Function to generate CPU load
generate_cpu_load() {
    echo "Generating CPU load..."
    for i in $(seq 1 $(nproc)); do
        yes > /dev/null &
    done
    sleep 30
    killall yes
}

# Function to generate disk I/O
generate_disk_load() {
    echo "Generating disk I/O..."
    dd if=/dev/zero of=/tmp/test.file bs=1M count=1024 conv=fdatasync
    rm /tmp/test.file
}

# Function to generate memory usage
generate_memory_load() {
    echo "Generating memory load..."
    stress-ng --vm 2 --vm-bytes 75% --timeout 30s
}

# Main test sequence
main() {
    # Check if stress-ng is installed
    if ! command -v stress-ng &> /dev/null; then
        echo "Installing stress-ng..."
        amazon-linux-extras install epel -y
        yum install -y stress-ng
    fi

    # Check if Netdata is running
    check_netdata

    # Run tests
    echo "Starting system load tests..."
    
    echo "Test 1: CPU Load"
    generate_cpu_load
    
    echo "Test 2: Disk I/O"
    generate_disk_load
    
    echo "Test 3: Memory Usage"
    generate_memory_load
    
    echo "All tests completed successfully!"
    
    # Check metrics in Netdata
    echo "Checking Netdata metrics..."
    curl -s http://localhost:19999/api/v1/alarms > /tmp/alarms.json
    echo "Recent alarms:"
    cat /tmp/alarms.json
    rm /tmp/alarms.json
    
    # Verify Netdata is still running after tests
    check_netdata
}

# Run main test sequence
main

echo "
=================================
Testing Complete!
=================================
Please check the Netdata dashboard at:
http://localhost:19999

Key areas to verify:
1. System Overview > CPU (should show spike)
2. System Overview > Memory (should show usage spike)
3. Disk > Disk I/O (should show activity spike)
4. Alarms > Log (check for any triggered alerts)
=================================
"