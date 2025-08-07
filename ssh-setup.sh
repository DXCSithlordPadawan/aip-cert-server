#!/usr/bin/env bash

# SSH Setup Script for Cert-Server Container (ID: 200)
# Container IP: 192.168.0.122/24
# Proxmox Host IP: 192.168.0.106
# Author: Based on tteck's script structure
# License: MIT

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing SSH Server"
$STD apt-get update
$STD apt-get install -y openssh-server
msg_ok "Installed SSH Server"

msg_info "Configuring SSH Service"
# Enable and start SSH service
systemctl enable ssh
systemctl start ssh

# Create SSH directory for root user
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# Configure SSH daemon for security
cat > /etc/ssh/sshd_config.d/custom.conf << 'EOF'
# Custom SSH configuration for container access
Port 22
PermitRootLogin yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

msg_ok "Configured SSH Service"

msg_info "Setting up Firewall Rules"
# Install and configure UFW if not present
if ! command -v ufw &> /dev/null; then
    $STD apt-get install -y ufw
fi

# Reset UFW to defaults
ufw --force reset

# Allow SSH from Proxmox host specifically
ufw allow from 192.168.0.106 to any port 22 comment 'SSH from Proxmox host'

# Allow SSH from local network (optional - remove if too permissive)
ufw allow from 192.168.0.0/24 to any port 22 comment 'SSH from local network'

# Enable UFW
ufw --force enable

msg_ok "Configured Firewall Rules"

msg_info "Generating SSH Key Pair"
# Generate SSH key pair if it doesn't exist
if [ ! -f /root/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N "" -C "root@cert-server-$(date +%Y%m%d)"
    chmod 600 /root/.ssh/id_rsa
    chmod 644 /root/.ssh/id_rsa.pub
fi

# Copy public key to authorized_keys for local access
cat /root/.ssh/id_rsa.pub > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

msg_ok "Generated SSH Key Pair"

msg_info "Configuring Network"
# Ensure the container has the correct IP configuration
cat > /etc/netplan/01-netcfg.yaml << 'EOF'
network:
  version: 2
  ethernets:
    eth0:
      addresses:
        - 192.168.0.122/24
      gateway4: 192.168.0.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 1.1.1.1
EOF

# Apply network configuration
netplan apply

msg_ok "Configured Network"

msg_info "Restarting SSH Service"
systemctl restart ssh
systemctl status ssh --no-pager -l
msg_ok "SSH Service Restarted"

msg_info "Setting up SSH Connection Test"
# Create a test script for the Proxmox host
cat > /tmp/test_ssh_connection.sh << 'EOF'
#!/bin/bash
# Test SSH connection from Proxmox host (192.168.0.106) to cert-server (192.168.0.122)

echo "Testing SSH connection to cert-server..."
echo "Run this script on the Proxmox host (192.168.0.106)"
echo ""

# Test basic connectivity
echo "1. Testing network connectivity:"
ping -c 3 192.168.0.122

echo ""
echo "2. Testing SSH port accessibility:"
nc -zv 192.168.0.122 22

echo ""
echo "3. Attempting SSH connection:"
echo "   You can now SSH to the cert-server using:"
echo "   ssh root@192.168.0.122"
echo ""
echo "4. If you want key-based authentication, copy the public key:"
echo "   ssh-copy-id root@192.168.0.122"
echo ""
EOF

chmod +x /tmp/test_ssh_connection.sh
msg_ok "Created SSH Connection Test Script"

motd_ssh
customize

msg_info "Displaying Connection Information"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "SSH Setup Complete!"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Container Details:"
echo "  - Container ID: 200"
echo "  - Container IP: 192.168.0.122"
echo "  - SSH Port: 22"
echo ""
echo "From Proxmox host (192.168.0.106), you can now connect using:"
echo "  ssh root@192.168.0.122"
echo ""
echo "SSH Key Details:"
echo "  - Private key: /root/.ssh/id_rsa"
echo "  - Public key: /root/.ssh/id_rsa.pub"
echo ""
echo "Firewall Status:"
ufw status numbered
echo ""
echo "Test script created: /tmp/test_ssh_connection.sh"
echo "Copy this script to your Proxmox host to test the connection."
echo ""
echo "═══════════════════════════════════════════════════════════════"

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

echo ""
echo "SSH setup completed successfully!"
echo "You can now SSH from the Proxmox host to this container."