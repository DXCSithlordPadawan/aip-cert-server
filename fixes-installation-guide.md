# Certificate Authority Server - Complete Installation Guide

## Overview

This guide covers the installation of a Certificate Authority server on Proxmox with:
- ECDSA P-384 Root and Intermediate certificates
- Web GUI for certificate management
- Support for importing BASE64 PEM format CSRs
- Persistent storage on NFS
- Automatic serial number incrementing

## Files Required

Create the following directory structure:
```
ca-server-setup/
├── config.env
├── create-ca-container.sh
├── setup-ca-server.sh
├── ca-diagnostics.sh
├── fix-serial-numbers.sh
├── v3.req
└── ca-web-gui/
    ├── index.php
    ├── ca-functions.php
    ├── download.php
    ├── view-request.php
    └── style.css
```

## Installation Steps

### 1. Prepare Files

```bash
# Create directories
mkdir -p ca-server-setup/ca-web-gui
cd ca-server-setup

# Make scripts executable
chmod +x create-ca-container.sh
chmod +x setup-ca-server.sh
chmod +x ca-diagnostics.sh
chmod +x fix-serial-numbers.sh
```

### 2. Configure Settings

Edit `config.env` to match your environment:
```bash
# Key settings to verify/change:
CONTAINER_IP="192.168.0.122/24"    # Your desired IP
NFS_SERVER="192.168.0.106"          # Your NFS server
DNS_SERVER="192.168.0.110"          # Your DNS server
DOMAIN_NAME="aip.dxc.com"           # Your domain
ROOT_CA_CN="AIP Root CA"            # Your CA name
```

### 3. Run Installation

```bash
sudo ./create-ca-container.sh
```

### 4. Verify Installation

```bash
# Run diagnostics
sudo ./ca-diagnostics.sh

# Test web interface
curl -k https://192.168.0.122/test-permissions.php
```

### 5. Fix Serial Numbers (if needed)

If serial numbers are stuck at 1000:
```bash
sudo ./fix-serial-numbers.sh
```

## Using the CA Server

### Web Interface Access

1. Navigate to: `https://192.168.0.122` (or your configured IP)
2. Accept the self-signed certificate warning
3. Login with:
   - Username: `admin`
   - Password: `CaAdmin2024!`

### Certificate Request Methods

#### Method 1: Web Form
1. Click "Submit Request"
2. Fill in certificate details
3. Choose key type (ECDSA or RSA)
4. Add Subject Alternative Names if needed
5. Submit request

#### Method 2: Import CSR (BASE64 PEM)
1. Click "Import CSR"
2. Paste your CSR in PEM format:
   ```
   -----BEGIN CERTIFICATE REQUEST-----
   MIICvDCCAaQCAQAwdzELMAkGA1UEBhMCVVMxDTALBgNVBAgMBFV0YWgxDzAN...
   -----END CERTIFICATE REQUEST-----
   ```
3. Select certificate type
4. Submit

### Managing Requests

1. View pending requests in the "Pending Requests" section
2. Click "View" to see full request details
3. Click "Approve" to sign the certificate
4. Click "Reject" to deny the request

### Downloading Certificates

#### For Approved Certificates:
- **Download**: Gets the certificate only
- **Chain**: Gets the certificate with CA chain

#### CA Certificates:
- Root CA Certificate
- Intermediate CA Certificate  
- Complete CA Chain

## Troubleshooting

### Issue: Requests not appearing

```bash
# Check permissions
pct exec 200 -- ls -la /mnt/ca-data/requests/

# View PHP errors
pct exec 200 -- tail -f /var/log/php/errors.log
```

### Issue: Serial numbers stuck at 1000

```bash
# Run the fix script
sudo ./fix-serial-numbers.sh

# Manually check serial
pct exec 200 -- cat /mnt/ca-data/intermediate/serial
```

### Issue: Cannot approve certificates

```bash
# Check sudo permissions
pct exec 200 -- sudo -l -U www-data

# Check OpenSSL CA config
pct exec 200 -- openssl ca -config /mnt/ca-data/intermediate/openssl.cnf -help
```

### Issue: View button returns 404

Ensure `view-request.php` was copied:
```bash
pct exec 200 -- ls -la /var/www/ca-gui/view-request.php
```

## Security Considerations

1. **Change default passwords immediately**
   - Container root password
   - Web GUI admin password

2. **Secure the NFS mount**
   - Limit access to CA server only
   - Use NFSv4 with Kerberos if possible

3. **Protect private keys**
   - Root CA key: `/mnt/ca-data/root/private/ca.key.pem`
   - Intermediate CA key: `/mnt/ca-data/intermediate/private/intermediate.key.pem`

4. **Regular backups**
   ```bash
   # Backup CA data
   tar -czf ca-backup-$(date +%Y%m%d).tar.gz /mnt/ca-data/
   ```

## Advanced Usage

### Custom Certificate Extensions

Edit `/mnt/ca-data/intermediate/openssl.cnf` to add custom extensions.

### Batch Certificate Processing

Use the CSR import feature with a script:
```bash
#!/bin/bash
CSR_FILE="request.csr"
CSR_CONTENT=$(cat $CSR_FILE)

curl -k -u admin:CaAdmin2024! \
  -X POST https://192.168.0.122/ \
  -d "action=submit_csr" \
  -d "cert_type=server" \
  --data-urlencode "csr_pem=$CSR_CONTENT"
```

### Certificate Revocation

Currently not implemented in the web GUI. Use command line:
```bash
pct exec 200 -- openssl ca -config /mnt/ca-data/intermediate/openssl.cnf \
  -revoke /mnt/ca-data/issued/[SERIAL]/certificate.crt
```

## Maintenance

### View CA statistics
```bash
pct exec 200 -- bash -c '
echo "Certificates issued: $(wc -l < /mnt/ca-data/intermediate/index.txt)"
echo "Next serial: $(cat /mnt/ca-data/intermediate/serial)"
echo "Pending requests: $(find /mnt/ca-data/requests -name "*.json" | wc -l)"
'
```

### Clean old requests
```bash
pct exec 200 -- find /mnt/ca-data/requests -name "*.json" -mtime +30 -delete
```

## Files Summary

The fixed implementation includes:
1. **create-ca-container.sh** - Creates the container with proper NFS mount
2. **setup-ca-server.sh** - Configures CA with serial number fix
3. **ca-functions.php** - Handles all CA operations including CSR import
4. **index.php** - Main web interface with CSR import form
5. **view-request.php** - Request details viewer
6. **download.php** - Handles all certificate downloads
7. **style.css** - Complete styling for all pages
8. **ca-diagnostics.sh** - Troubleshooting tool
9. **fix-serial-numbers.sh** - Fixes serial increment issue