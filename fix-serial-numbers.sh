#!/bin/bash
##########################################################
# Fix Serial Number Increment Issue
##########################################################
# This script fixes the serial number not incrementing issue
# Run this on the Proxmox host
##########################################################
# Usage: ./fix-serial-numbers.sh
# Author: Iain Reid
# Created: 14 Jul 2025 
# Test Checked: 14 Jul 2015
##########################################################
# Amended Date  Amended By Who  Amended Reason
##########################################################
# 14 Jul 2025   Assistant       Fixed permissions, paths, PHP issues
#
##########################################################
source config.env

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Fixing Serial Number Issue ===${NC}"

# Check if container exists
if ! pct status ${CONTAINER_ID} &>/dev/null; then
    echo -e "${RED}Container ${CONTAINER_ID} does not exist${NC}"
    exit 1
fi

# Fix serial numbers inside container
pct exec ${CONTAINER_ID} -- bash << 'EOF'
CA_ROOT="/mnt/ca-data"

echo "Fixing serial number files..."

# Create index attributes files to ensure serial increments
echo "unique_subject = no" > ${CA_ROOT}/root/index.txt.attr
echo "unique_subject = no" > ${CA_ROOT}/intermediate/index.txt.attr

# Check current serial numbers
if [ -f "${CA_ROOT}/intermediate/serial" ]; then
    CURRENT_SERIAL=$(cat ${CA_ROOT}/intermediate/serial)
    echo "Current intermediate serial: $CURRENT_SERIAL"
    
    # If serial is stuck at 1000, check if any certs have been issued
    if [ "$CURRENT_SERIAL" = "1000" ]; then
        # Count entries in index.txt
        if [ -f "${CA_ROOT}/intermediate/index.txt" ]; then
            CERT_COUNT=$(wc -l < ${CA_ROOT}/intermediate/index.txt)
            if [ $CERT_COUNT -gt 0 ]; then
                # Calculate next serial
                NEXT_SERIAL=$(printf "%04X" $((0x1000 + $CERT_COUNT)))
                echo $NEXT_SERIAL > ${CA_ROOT}/intermediate/serial
                echo "Fixed serial to: $NEXT_SERIAL"
            fi
        fi
    fi
fi

# Set proper permissions
chown -R www-data:www-data ${CA_ROOT}/requests
chown -R www-data:www-data ${CA_ROOT}/issued
chmod 644 ${CA_ROOT}/intermediate/serial
chmod 644 ${CA_ROOT}/intermediate/index.txt
chmod 644 ${CA_ROOT}/intermediate/index.txt.attr

echo "Serial number fix complete"
EOF

echo -e "${GREEN}=== Fix Complete ===${NC}"
echo -e "${YELLOW}Try approving a certificate request now to test if serial increments${NC}"