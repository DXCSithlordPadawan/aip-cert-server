# Proxmox Certificate Authority Server

This project creates a Certificate Authority (CA) server running in a Proxmox LXC container with the following features:

- **ECDSA P-384 Root and Intermediate certificates**
- **Web-based management interface**
- **Persistent storage on NFS**
- **Support for server, client, and code signing certificates**
- **Automatic certificate chain generation**

## Prerequisites

- Proxmox VE host
- NFS server accessible from Proxmox host
- Network connectivity to download Debian template

## File Structure

```
ca-server-setup/
├── config.env                 # Configuration parameters
├── create-ca-container.sh     # Main setup script
├── setup-ca-server.sh         # CA setup (runs in container)
├── v3.req                     # OpenSSL v3 extensions
├── ca-diagnostics.sh          # Diagnostic script
└── ca-web-gui/               
    ├── index.php             # Main web interface
    ├── ca-functions.php      # CA operations
    ├── download.php          # Certificate downloads
    └── style.css             # Web GUI styling
```

## Configuration

Edit `config.env` before running the setup:

```bash
# Container settings
CONTAINER_NAME="cert-server"          # Container hostname
CONTAINER_ID="200"                    # Proxmox container ID
CONTAINER_PASSWORD="BobTheBigRedBus-0" # Root password
CONTAINER_IP="192.168.0.122/24"       # Container IP address

# NFS storage
NFS_SERVER="192.168.0.106"            # NFS server IP
NFS_MOUNT_POINT="/mnt/pve/nfs-storage" # NFS mount on Proxmox

# Network
DNS_SERVER="192.168.0.110"            # DNS server
DOMAIN_NAME="aip.dxc.com"             # Domain name

# Certificate Authority
ROOT_CA_CN="AIP Root CA"              # Root CA common name
CA_COUNTRY="GB"                       # Country code
CA_STATE="Hampshire"                  # State/Province
CA_LOCALITY="Farnborough"             # City
CA_ORGANIZATION="DXC Technology"      # Organization
CA_ORG_UNIT="EntServ D S"            # Organizational unit

# Web interface
WEB_USER="admin"                      # Web GUI username
WEB_PASSWORD="CaAdmin2024!"           # Web GUI password
```

## Installation

1. **Prepare the files:**
   ```bash
   mkdir ca-server-setup
   cd ca-server-setup
   mkdir ca-web-gui
   
   # Copy all files to their respective locations
   chmod +x create-ca-container.sh
   chmod +x setup-ca-server.sh
   chmod +x ca-diagnostics.sh
   ```

2. **Run the setup:**
   ```bash
   sudo ./create-ca-container.sh
   ```

3. **Verify installation:**
   ```bash
   sudo ./ca-diagnostics.sh
   ```

## Usage

### Web Interface

Access the CA management interface:
- URL: `https://<CONTAINER_IP>`
- Username: `admin` (or configured value)
- Password: `CaAdmin2024!` (or configured value)

**Note:** The certificate is self-signed, so your browser will show a security warning.

### Features

1. **Submit Certificate Requests**
   - Server certificates (with SANs)
   - Client certificates
   - Code signing certificates
   - Choice of ECDSA or RSA keys

2. **Manage Requests**
   - View pending requests
   - Approve/reject requests
   - Download approved certificates

3. **Download CA Certificates**
   - Root CA certificate
   - Intermediate CA certificate
   - Complete certificate chain

### Container Access

SSH to container:
```bash
# From Proxmox host
pct enter 200

# Or via SSH (if enabled)
ssh root@192.168.0.122
```

### File Locations

Inside the container:
- CA root: `/mnt/ca-data/`
- Web files: `/var/www/ca-gui/`
- Apache config: `/etc/apache2/sites-available/ca-gui.conf`
- Logs: `/var/log/apache2/ca-gui-*.log`

## Troubleshooting

### Certificate requests not showing

1. Run diagnostics:
   ```bash
   sudo ./ca-diagnostics.sh
   ```

2. Check permissions:
   ```bash
   pct exec 200 -- ls -la /mnt/ca-data/requests/
   ```

3. View PHP errors:
   ```bash
   pct exec 200 -- tail -f /var/log/php/errors.log
   ```

### Common Issues

**Issue:** Web interface returns 500 error
- **Solution:** Check Apache error log and PHP permissions

**Issue:** Cannot approve certificates
- **Solution:** Verify www-data has sudo access for openssl

**Issue:** NFS mount not working
- **Solution:** Check NFS server is accessible and exports are correct

## Security Notes

1. The container runs **privileged** for NFS mount support
2. Default passwords should be changed immediately
3. The web interface uses basic authentication - consider adding additional security
4. All private keys are stored on the NFS mount - ensure it's properly secured

## Backup

Important files to backup:
- `/mnt/ca-data/root/` - Root CA keys and certificates
- `/mnt/ca-data/intermediate/` - Intermediate CA keys
- `/mnt/ca-data/issued/` - All issued certificates

## Certificate Types

### Server Certificates
- Includes `serverAuth` extended key usage
- Supports Subject Alternative Names (SANs)
- Common Name automatically added as SAN

### Client Certificates
- Includes `clientAuth` and `emailProtection`
- Suitable for user authentication

### Code Signing Certificates
- Includes `codeSigning` extended key usage
- For signing code and documents

## Advanced Configuration

### Custom v3.req

The `v3.req` file defines extensions for certificates. Modify the `[alt_names]` section for default SANs:

```ini
[ alt_names ]
DNS.1=server1.example.com
DNS.2=server2.example.com
IP.1=192.168.1.100
```

### Modifying CA Configuration

OpenSSL configurations are stored in:
- `/mnt/ca-data/root/openssl.cnf` - Root CA config
- `/mnt/ca-data/intermediate/openssl.cnf` - Intermediate CA config

## Support

For issues:
1. Run the diagnostics script
2. Check all log files
3. Verify NFS mount is working
4. Ensure all services are running