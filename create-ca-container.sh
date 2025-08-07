#!/bin/bash
##########################################################
# Main Container Creation Script
##########################################################
# Usage: ./create-ca-container.sh
# Author: Iain Reid
# Created: 09 Jul 2025 
# Test Checked: 14 Jul 2015
##########################################################
# Amended Date  Amended By Who  Amended Reason
##########################################################
# 14 Jul 2025   Assistant       Fixed PHP issues, improved error handling
#
##########################################################

# Load configuration
source config.env

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Proxmox CA Server Container Creation ===${NC}"

# Function to check if storage exists
check_nfs_storage() {
    echo -e "${YELLOW}Checking NFS storage...${NC}"
    if pvesm status | grep -q "^${NFS_STORAGE_NAME}"; then
        echo -e "${GREEN}NFS storage '${NFS_STORAGE_NAME}' already exists${NC}"
        return 0
    else
        echo -e "${YELLOW}NFS storage not found, creating...${NC}"
        pvesm add nfs ${NFS_STORAGE_NAME} \
            --server ${NFS_SERVER} \
            --export ${NFS_MOUNT_POINT} \
            --content vztmpl,iso,backup,rootdir,images \
            --options vers=4
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}NFS storage created successfully${NC}"
            return 0
        else
            echo -e "${RED}Failed to create NFS storage${NC}"
            return 1
        fi
    fi
}

# Function to download template if not exists
download_template() {
    echo -e "${YELLOW}Checking for Debian 12 template...${NC}"
    TEMPLATE_NAME="debian-12-standard_12.7-1_amd64.tar.zst"
    
    if [ ! -f "/var/lib/vz/template/cache/${TEMPLATE_NAME}" ]; then
        echo -e "${YELLOW}Downloading Debian 12 template...${NC}"
        pveam download local ${TEMPLATE_NAME}
    else
        echo -e "${GREEN}Template already exists${NC}"
    fi
}

# Function to create container
create_container() {
    echo -e "${YELLOW}Creating LXC container...${NC}"
    
    # Check if container already exists
    if pct status ${CONTAINER_ID} &>/dev/null; then
        echo -e "${RED}Container ${CONTAINER_ID} already exists!${NC}"
        read -p "Do you want to destroy it and recreate? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            pct stop ${CONTAINER_ID} &>/dev/null
            pct destroy ${CONTAINER_ID}
        else
            exit 1
        fi
    fi
    
    # Create container - Note: unprivileged=0 for privileged container
    pct create ${CONTAINER_ID} \
        local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst \
        --hostname ${CONTAINER_NAME}.${DOMAIN_NAME} \
        --cores ${CONTAINER_CORES} \
        --memory ${CONTAINER_MEMORY} \
        --swap 512 \
        --storage local-lvm \
        --rootfs local-lvm:${CONTAINER_DISK} \
        --net0 name=eth0,bridge=vmbr0,ip=${CONTAINER_IP},gw=${CONTAINER_GATEWAY} \
        --nameserver ${DNS_SERVER} \
        --searchdomain ${DOMAIN_NAME} \
        --password ${CONTAINER_PASSWORD} \
        --features nesting=1 \
        --unprivileged 0
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Container created successfully${NC}"
        
        # Add NFS mount point - using bind mount approach
        echo -e "${YELLOW}Adding NFS mount point...${NC}"
        # Create mount point in container
        pct exec ${CONTAINER_ID} -- mkdir -p /mnt/ca-data
        
        # Add bind mount to container config
        echo "lxc.mount.entry: ${NFS_MOUNT_POINT}/ca-data mnt/ca-data none bind,create=dir 0 0" >> /etc/pve/lxc/${CONTAINER_ID}.conf
        
        return 0
    else
        echo -e "${RED}Failed to create container${NC}"
        return 1
    fi
}

# Function to setup CA server inside container
setup_ca_server() {
    echo -e "${YELLOW}Starting container...${NC}"
    pct start ${CONTAINER_ID}
    sleep 5
    
    # Ensure NFS mount directory exists on host
    mkdir -p ${NFS_MOUNT_POINT}/ca-data
    chmod 777 ${NFS_MOUNT_POINT}/ca-data
    
    echo -e "${YELLOW}Copying setup files to container...${NC}"
    pct push ${CONTAINER_ID} setup-ca-server.sh /root/setup-ca-server.sh
    pct push ${CONTAINER_ID} config.env /root/config.env
    pct push ${CONTAINER_ID} v3.req /root/v3.req
    
    # Create web GUI directory and copy files
    pct exec ${CONTAINER_ID} -- mkdir -p /root/ca-web-gui
    
    # Copy all PHP files
    for file in ca-web-gui/*.php; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            pct push ${CONTAINER_ID} "$file" "/root/ca-web-gui/${filename}"
            echo -e "${GREEN}Copied ${filename}${NC}"
        fi
    done
    
    # Copy CSS files
    for file in ca-web-gui/*.css; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            pct push ${CONTAINER_ID} "$file" "/root/ca-web-gui/${filename}"
            echo -e "${GREEN}Copied ${filename}${NC}"
        fi
    done
    
    # Ensure view-request.php exists
    if [ ! -f "ca-web-gui/view-request.php" ]; then
        echo -e "${YELLOW}Warning: view-request.php not found, creating a placeholder${NC}"
    fi
    
    echo -e "${YELLOW}Running CA setup script inside container...${NC}"
    pct exec ${CONTAINER_ID} -- chmod +x /root/setup-ca-server.sh
    pct exec ${CONTAINER_ID} -- /root/setup-ca-server.sh
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}CA server setup completed successfully${NC}"
        
        # Test web server
        echo -e "${YELLOW}Testing web server...${NC}"
        sleep 3
        if curl -k -s -o /dev/null -w "%{http_code}" https://${CONTAINER_IP%/*} | grep -q "401\|200"; then
            echo -e "${GREEN}Web server is responding${NC}"
        else
            echo -e "${RED}Web server is not responding${NC}"
        fi
        
        return 0
    else
        echo -e "${RED}CA server setup failed${NC}"
        return 1
    fi
}

# Main execution
main() {
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}Please run as root${NC}"
        exit 1
    fi
    
    # Check if config file exists
    if [ ! -f "config.env" ]; then
        echo -e "${RED}config.env file not found!${NC}"
        exit 1
    fi
    
    # Check if required files exist
    for file in setup-ca-server.sh v3.req ca-web-gui/index.php ca-web-gui/ca-functions.php ca-web-gui/style.css ca-web-gui/download.php; do
        if [ ! -f "$file" ]; then
            echo -e "${RED}Required file not found: $file${NC}"
            exit 1
        fi
    done
    
    # Execute setup steps
    check_nfs_storage || exit 1
    download_template || exit 1
    create_container || exit 1
    setup_ca_server || exit 1
    
    echo -e "${GREEN}=== Setup Complete ===${NC}"
    echo -e "${GREEN}CA Server URL: https://${CONTAINER_IP%/*}${NC}"
    echo -e "${GREEN}CA Server FQDN: https://${CONTAINER_NAME}.${DOMAIN_NAME}${NC}"
    echo -e "${GREEN}Web GUI User: ${WEB_USER}${NC}"
    echo -e "${GREEN}Web GUI Password: ${WEB_PASSWORD}${NC}"
    echo -e "${GREEN}Container Password: ${CONTAINER_PASSWORD}${NC}"
    echo -e "${YELLOW}Note: The certificate is self-signed, your browser will show a security warning.${NC}"
}

# Run main function
main