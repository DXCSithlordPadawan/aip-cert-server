#!/bin/bash
##########################################################
# CA Server Diagnostics Script
##########################################################
# This script checks the CA server installation and helps
# diagnose common issues
##########################################################
# Usage: ./ca-diagnostis.sh
# Author: Iain Reid
# Created: 13 Jul 2025 
# Test Checked: 14 Jul 2015
##########################################################
# Amended Date  Amended By Who  Amended Reason
##########################################################
# 14 Jul 2025   Assistant       Fixed PHP issues, improved error handling
#
##########################################################

source config.env

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== CA Server Diagnostics ===${NC}"
echo

# Check if container exists and is running
echo -e "${YELLOW}Checking container status...${NC}"
if pct status ${CONTAINER_ID} &>/dev/null; then
    STATUS=$(pct status ${CONTAINER_ID} | grep -oP 'status: \K\w+')
    echo -e "Container ${CONTAINER_ID} status: ${GREEN}${STATUS}${NC}"
else
    echo -e "${RED}Container ${CONTAINER_ID} does not exist${NC}"
    exit 1
fi

# Run diagnostics inside container
echo -e "\n${YELLOW}Running diagnostics inside container...${NC}"

pct exec ${CONTAINER_ID} -- bash << 'EOF'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "\n${YELLOW}1. Checking CA directory structure:${NC}"
if [ -d "/mnt/ca-data" ]; then
    echo -e "${GREEN}✓ CA root directory exists${NC}"
    echo "Directory contents:"
    ls -la /mnt/ca-data/
else
    echo -e "${RED}✗ CA root directory missing${NC}"
fi

echo -e "\n${YELLOW}2. Checking directory permissions:${NC}"
for dir in requests issued root intermediate; do
    if [ -d "/mnt/ca-data/$dir" ]; then
        PERMS=$(stat -c "%a %U:%G" /mnt/ca-data/$dir)
        echo -e "${GREEN}✓${NC} /mnt/ca-data/$dir: $PERMS"
    else
        echo -e "${RED}✗${NC} /mnt/ca-data/$dir: missing"
    fi
done

echo -e "\n${YELLOW}3. Checking CA certificates:${NC}"
if [ -f "/mnt/ca-data/root/certs/ca.cert.pem" ]; then
    echo -e "${GREEN}✓ Root CA exists${NC}"
    openssl x509 -in /mnt/ca-data/root/certs/ca.cert.pem -noout -subject | sed 's/^/  /'
else
    echo -e "${RED}✗ Root CA missing${NC}"
fi

if [ -f "/mnt/ca-data/intermediate/certs/intermediate.cert.pem" ]; then
    echo -e "${GREEN}✓ Intermediate CA exists${NC}"
    openssl x509 -in /mnt/ca-data/intermediate/certs/intermediate.cert.pem -noout -subject | sed 's/^/  /'
else
    echo -e "${RED}✗ Intermediate CA missing${NC}"
fi

echo -e "\n${YELLOW}4. Checking web server:${NC}"
if systemctl is-active --quiet apache2; then
    echo -e "${GREEN}✓ Apache is running${NC}"
else
    echo -e "${RED}✗ Apache is not running${NC}"
    systemctl status apache2 --no-pager | head -10
fi

echo -e "\n${YELLOW}5. Checking PHP configuration:${NC}"
if [ -f "/var/www/ca-gui/index.php" ]; then
    echo -e "${GREEN}✓ Web GUI files installed${NC}"
    echo "PHP version: $(php -v | head -1)"
else
    echo -e "${RED}✗ Web GUI files missing${NC}"
fi

echo -e "\n${YELLOW}6. Checking pending requests:${NC}"
if [ -d "/mnt/ca-data/requests" ]; then
    COUNT=$(find /mnt/ca-data/requests -name "request.json" 2>/dev/null | wc -l)
    echo "Found $COUNT certificate requests"
    if [ $COUNT -gt 0 ]; then
        echo "Recent requests:"
        find /mnt/ca-data/requests -name "request.json" -exec grep -H "common_name\|status\|submitted" {} \; | head -20
    fi
fi

echo -e "\n${YELLOW}7. Checking Apache error log:${NC}"
if [ -f "/var/log/apache2/ca-gui-error.log" ]; then
    echo "Last 10 Apache errors:"
    tail -10 /var/log/apache2/ca-gui-error.log | sed 's/^/  /'
else
    echo "No Apache error log found"
fi

echo -e "\n${YELLOW}8. Checking PHP error log:${NC}"
if [ -f "/var/log/php/errors.log" ]; then
    echo "Last 10 PHP errors:"
    tail -10 /var/log/php/errors.log | sed 's/^/  /'
else
    echo "No PHP error log found"
fi

echo -e "\n${YELLOW}9. Testing web server connectivity:${NC}"
curl -k -s -o /dev/null -w "HTTPS response code: %{http_code}\n" https://localhost/ || echo "Failed to connect"

echo -e "\n${YELLOW}10. Checking sudoers for www-data:${NC}"
if grep -q "www-data.*openssl" /etc/sudoers; then
    echo -e "${GREEN}✓ www-data has sudo access for openssl${NC}"
else
    echo -e "${RED}✗ www-data missing sudo access for openssl${NC}"
fi

EOF

echo -e "\n${GREEN}=== Diagnostics Complete ===${NC}"
echo -e "\nTo access the CA web interface:"
echo -e "  URL: ${GREEN}https://${CONTAINER_IP%/*}${NC}"
echo -e "  Username: ${GREEN}${WEB_USER}${NC}"
echo -e "  Password: ${GREEN}${WEB_PASSWORD}${NC}"
echo -e "\nTo test permissions directly:"
echo -e "  ${GREEN}https://${CONTAINER_IP%/*}/test-permissions.php${NC}"