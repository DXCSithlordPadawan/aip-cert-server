#!/bin/bash
##########################################################
# Install Certificate API Components
##########################################################
# This script installs the API endpoint on the CA server
# and sets up the client on remote servers
##########################################################
# Usage: ./install-ca-api.sh [server|client]
# Author: Iain Reid / Assistant
# Created: 2025-08-06
##########################################################

source config.env

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

MODE="$1"

if [ "$MODE" != "server" ] && [ "$MODE" != "client" ]; then
    echo "Usage: $0 [server|client]"
    echo "  server: Install API endpoint on CA server"
    echo "  client: Install client tools on remote server"
    exit 1
fi

install_server() {
    echo -e "${GREEN}=== Installing CA API Server Components ===${NC}"
    
    # Check if running on Proxmox host
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}Please run as root on Proxmox host${NC}"
        exit 1
    fi
    
    # Check if container exists
    if ! pct status ${CONTAINER_ID} &>/dev/null; then
        echo -e "${RED}Container ${CONTAINER_ID} does not exist${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}Copying API files to container...${NC}"
    
    # Copy api.php to container
    pct push ${CONTAINER_ID} api.php /var/www/ca-gui/api.php
    
    # Set permissions
    pct exec ${CONTAINER_ID} -- chown www-data:www-data /var/www/ca-gui/api.php
    pct exec ${CONTAINER_ID} -- chmod 644 /var/www/ca-gui/api.php
    
    # Generate secure API key if not already set
    API_KEY=$(openssl rand -hex 32)
    
    # Create API configuration
    pct exec ${CONTAINER_ID} -- bash << EOF
# Create API configuration file
cat > /var/www/ca-gui/api-config.php << 'APICONFIG'
<?php
// API Configuration
return [
    'api_key' => '${API_KEY}',
    'allowed_networks' => [
        '192.168.0.0/16',
        '10.0.0.0/8',
        '172.16.0.0/12',
        '127.0.0.1/32'
    ],
    'auto_approve' => true,
    'max_cert_days' => 365,
    'rate_limit_per_hour' => 10
];
?>
APICONFIG

chown www-data:www-data /var/www/ca-gui/api-config.php
chmod 600 /var/www/ca-gui/api-config.php

# Create .htaccess to allow API access
cat >> /var/www/ca-gui/.htaccess << 'HTACCESS'

# Allow API access without basic auth for api.php
<Files "api.php">
    Satisfy Any
    Allow from all
</Files>
HTACCESS

# Restart Apache
systemctl restart apache2
EOF
    
    echo -e "${GREEN}API server installation complete${NC}"
    echo -e "${GREEN}API Key: ${API_KEY}${NC}"
    echo -e "${YELLOW}Save this API key securely - you'll need it for client configuration${NC}"
    echo -e "${GREEN}API Endpoint: https://${CONTAINER_IP%/*}/api.php${NC}"
    
    # Test API
    echo -e "${YELLOW}Testing API endpoint...${NC}"
    if pct exec ${CONTAINER_ID} -- curl -k -s -H "X-API-Key: ${API_KEY}" "https://localhost/api.php/download?type=root-ca" | grep -q "success"; then
        echo -e "${GREEN}✓ API endpoint is working${NC}"
    else
        echo -e "${RED}✗ API endpoint test failed${NC}"
    fi
}

install_client() {
    echo -e "${GREEN}=== Installing CA Client Components ===${NC}"
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}Please run as root${NC}"
        exit 1
    fi
    
    # Install dependencies
    echo -e "${YELLOW}Installing dependencies...${NC}"
    
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y curl jq openssl
    elif command -v yum >/dev/null 2>&1; then
        yum install -y curl jq openssl
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y curl jq openssl
    else
        echo -e "${RED}Unsupported package manager. Please install curl, jq, and openssl manually${NC}"
        exit 1
    fi
    
    # Copy client script
    echo -e "${YELLOW}Installing client script...${NC}"
    cp request-cert.sh /usr/local/bin/request-cert
    chmod 755 /usr/local/bin/request-cert
    
    # Create directories
    mkdir -p /etc/ssl/local-ca
    mkdir -p /etc/ssl/private
    
    # Create configuration file
    echo -e "${YELLOW}Creating configuration file...${NC}"
    
    read -p "Enter CA server URL [https://cert-server.aip.dxc.com]: " CA_SERVER_INPUT
    CA_SERVER_INPUT=${CA_SERVER_INPUT:-https://cert-server.aip.dxc.com}
    
    read -p "Enter API key: " API_KEY_INPUT
    
    if [ -z "$API_KEY_INPUT" ]; then
        echo -e "${RED}API key is required${NC}"
        exit 1
    fi
    
    cat > /etc/ssl/ca-client.conf << EOF
# Certificate Authority Client Configuration
CA_SERVER="$CA_SERVER_INPUT"
API_KEY="$API_KEY_INPUT"

# Default certificate paths
CERT_DIR="/etc/ssl/certs"
KEY_DIR="/etc/ssl/private"

# Default certificate parameters
ORGANIZATION="DXC Technology"
ORG_UNIT="EntServ D S"
COUNTRY="GB"
STATE="Hampshire"
LOCALITY="Farnborough"

# Default certificate type and key type
CERT_TYPE="server"
KEY_TYPE="ecdsa"

# Output directory for downloaded certificates
OUTPUT_DIR="/etc/ssl/local-ca"
EOF
    
    chmod 600 /etc/ssl/ca-client.conf
    
    echo -e "${GREEN}Client installation complete${NC}"
    echo -e "${GREEN}Client command: request-cert${NC}"
    echo -e "${GREEN}Configuration: /etc/ssl/ca-client.conf${NC}"
    
    # Download CA certificates
    echo -e "${YELLOW}Downloading CA certificates...${NC}"
    if /usr/local/bin/request-cert download-ca --output /usr/local/share/ca-certificates; then
        echo -e "${GREEN}✓ CA certificates downloaded${NC}"
        
        # Update CA certificates
        if command -v update-ca-certificates >/dev/null 2>&1; then
            update-ca-certificates
        elif command -v update-ca-trust >/dev/null 2>&1; then
            update-ca-trust
        fi
    else
        echo -e "${YELLOW}Could not download CA certificates. Check API key and server connectivity${NC}"
    fi
    
    # Create example service script
    cat > /usr/local/bin/auto-renew-cert << 'EOF'
#!/bin/bash
# Automatic certificate renewal script
# Add to cron: 0 2 * * 0 /usr/local/bin/auto-renew-cert

HOSTNAME=$(hostname -f)
EMAIL="admin@$(hostname -d)"

# Request certificate for this server
/usr/local/bin/request-cert request \
    --common-name "$HOSTNAME" \
    --email "$EMAIL" \
    --output /etc/ssl/local-ca

# Reload services that use certificates
systemctl reload apache2 2>/dev/null || true
systemctl reload nginx 2>/dev/null || true
systemctl reload postfix 2>/dev/null || true
EOF
    
    chmod 755 /usr/local/bin/auto-renew-cert
    
    echo -e "${GREEN}Created auto-renewal script: /usr/local/bin/auto-renew-cert${NC}"
    echo -e "${YELLOW}Add to cron for automatic renewal:${NC}"
    echo -e "  ${GREEN}0 2 * * 0 /usr/local/bin/auto-renew-cert${NC}"
}

# Main execution
case $MODE in
    server)
        install_server
        ;;
    client)
        install_client
        ;;
esac

echo -e "${GREEN}=== Installation Complete ===${NC}"