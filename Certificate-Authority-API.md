# Certificate Authority API Documentation

## Overview

The Certificate Authority API provides automated certificate request and download capabilities for servers within your domain. It includes automatic approval for trusted servers and comprehensive security controls.

## Components

### 1. API Endpoint (`api.php`)
- RESTful API for certificate operations
- Authentication via API key
- IP address whitelisting
- Rate limiting
- Automatic certificate approval

### 2. Client Script (`request-cert.sh`)
- Command-line tool for remote servers
- Certificate request and download
- CSR submission support
- Configuration file support

### 3. Installation Script (`install-ca-api.sh`)
- Automated setup for server and client components
- Dependency installation
- Security configuration

## Installation

### On CA Server (Proxmox Host)

```bash
# Copy the API files to your CA project directory
# Run the installation script
./install-ca-api.sh server
```

This will:
- Install the API endpoint in the container
- Generate a secure API key
- Configure Apache for API access
- Test the endpoint

### On Client Servers

```bash
# Copy the client files to the target server
./install-ca-api.sh client
```

This will:
- Install dependencies (curl, jq, openssl)
- Install the client script as `request-cert`
- Create configuration file
- Download CA certificates
- Set up auto-renewal script

## API Endpoints

### POST /api.php/submit
Submit a new certificate request with automatic generation.

**Request Body:**
```json
{
    "common_name": "web.example.com",
    "organization": "DXC Technology",
    "org_unit": "EntServ D S",
    "country": "GB",
    "state": "Hampshire",
    "locality": "Farnborough",
    "email": "admin@example.com",
    "san": "www.example.com,api.example.com",
    "cert_type": "server",
    "key_type": "ecdsa"
}
```

**Response:**
```json
{
    "success": true,
    "message": "Certificate request submitted successfully. Request ID: req_abc123",
    "request_id": "req_abc123",
    "auto_approved": true,
    "serial": "1A2B3C4D",
    "downloads": {
        "certificate": "https://ca-server/api.php/download?type=cert&serial=1A2B3C4D",
        "chain": "https://ca-server/api.php/download?type=chain&serial=1A2B3C4D",
        "private_key": "https://ca-server/api.php/download?type=key&serial=1A2B3C4D"
    }
}
```

### POST /api.php/submit-csr
Submit an existing Certificate Signing Request.

**Request Body:**
```json
{
    "csr_pem": "-----BEGIN CERTIFICATE REQUEST-----\nMIIC...\n-----END CERTIFICATE REQUEST-----",
    "cert_type": "server"
}
```

### GET /api.php/download
Download certificate files.

**Parameters:**
- `type`: cert, chain, key, bundle, root-ca, intermediate-ca, ca-chain
- `serial`: Certificate serial number (for cert-specific downloads)

**Response:**
```json
{
    "success": true,
    "filename": "1A2B3C4D.crt",
    "content_type": "application/x-x509-cert",
    "content": "LS0tLS1CRUdJTi...",
    "size": 1234
}
```

### GET /api.php/status
Check request status.

**Parameters:**
- `request_id`: Request ID to check

## Client Usage

### Basic Certificate Request

```bash
# Request certificate for current server
request-cert request \
    --common-name $(hostname -f) \
    --email admin@$(hostname -d) \
    --output /etc/ssl/local-ca
```

### Submit Existing CSR

```bash
# Submit pre-generated CSR
request-cert submit-csr \
    --csr-file /path/to/request.csr \
    --type server \
    --output /etc/ssl/local-ca
```

### Download Certificate Files

```bash
# Download specific certificate by serial
request-cert download \
    --serial 1A2B3C4D \
    --output /etc/ssl/local-ca
```

### Download CA Certificates

```bash
# Download root and intermediate CA certificates
request-cert download-ca \
    --output /usr/local/share/ca-certificates
```

### Check Request Status

```bash
# Check status of submitted request
request-cert status --request-id req_abc123
```

## Configuration

### Server Configuration

Edit the API configuration in the container:

```php
// /var/www/ca-gui/api-config.php
return [
    'api_key' => 'your-secure-api-key',
    'allowed_networks' => [
        '192.168.0.0/16',
        '10.0.0.0/8',
        '172.16.0.0/12'
    ],
    'auto_approve' => true,
    'max_cert_days' => 365,
    'rate_limit_per_hour' => 10
];
```

### Client Configuration

Edit `/etc/ssl/ca-client.conf`:

```bash
# CA Server Configuration
CA_SERVER="https://cert-server.aip.dxc.com"
API_KEY="your-secure-api-key"

# Default paths
CERT_DIR="/etc/ssl/certs"
KEY_DIR="/etc/ssl/private"
OUTPUT_DIR="/etc/ssl/local-ca"

# Default certificate parameters
ORGANIZATION="DXC Technology"
ORG_UNIT="EntServ D S"
COUNTRY="GB"
STATE="Hampshire"
LOCALITY="Farnborough"
CERT_TYPE="server"
KEY_TYPE="ecdsa"
```

## Security Features

### Authentication
- API key-based authentication
- Keys transmitted in HTTP headers
- Secure key generation during installation

### Authorization
- IP address whitelisting with CIDR support
- Network-based access control
- Configurable allowed networks

### Rate Limiting
- Per-IP request limits
- Configurable hourly limits
- Automatic cleanup of old requests

### Certificate Validation
- Subject validation
- SAN (Subject Alternative Name) support
- Certificate type restrictions
- Key type validation

## Automation Examples

### Cron Job for Auto-Renewal

```bash
# Add to crontab for weekly certificate check
0 2 * * 0 /usr/local/bin/auto-renew-cert
```

### Systemd Service Integration

```bash
# Create systemd service for certificate management
cat > /etc/systemd/system/cert-renewal.service << EOF
[Unit]
Description=Certificate Renewal Service
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/auto-renew-cert
User=root

[Install]
WantedBy=multi-user.target
EOF

# Create timer for weekly execution
cat > /etc/systemd/system/cert-renewal.timer << EOF
[Unit]
Description=Certificate Renewal Timer
Requires=cert-renewal.service

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl enable cert-renewal.timer
systemctl start cert-renewal.timer
```

### Integration with Web Servers

#### Apache Integration

```bash
# Request certificate
request-cert request \
    --common-name $(hostname -f) \
    --email admin@$(hostname -d) \
    --san "www.$(hostname -d),api.$(hostname -d)" \
    --output /etc/ssl/local-ca

# Update Apache configuration
cat > /etc/apache2/sites-available/ssl-site.conf << EOF
<VirtualHost *:443>
    ServerName $(hostname -f)
    
    SSLEngine on
    SSLCertificateFile /etc/ssl/local-ca/$(hostname -f).crt
    SSLCertificateKeyFile /etc/ssl/local-ca/$(hostname -f).key
    SSLCertificateChainFile /etc/ssl/local-ca/$(hostname -f)-chain.pem
    
    # Your site configuration
</VirtualHost>
EOF

systemctl reload apache2
```

#### Nginx Integration

```bash
# Update Nginx configuration
cat > /etc/nginx/sites-available/ssl-site << EOF
server {
    listen 443 ssl;
    server_name $(hostname -f);
    
    ssl_certificate /etc/ssl/local-ca/$(hostname -f).crt;
    ssl_certificate_key /etc/ssl/local-ca/$(hostname -f).key;
    ssl_trusted_certificate /etc/ssl/local-ca/ca-chain.pem;
    
    # Your site configuration
}
EOF

systemctl reload nginx
```

## Troubleshooting

### API Issues

1. **Authentication failures**
   ```bash
   # Check API key in configuration
   grep API_KEY /etc/ssl/ca-client.conf
   
   # Test API connectivity
   curl -H "X-API-Key: your-key" https://ca-server/api.php/download?type=root-ca
   ```

2. **Network access denied**
   ```bash
   # Check client IP is in allowed networks
   # Update server configuration if needed
   ```

3. **Rate limiting**
   ```bash
   # Check rate limits in server config
   # Wait for limit reset or increase limits
   ```

### Certificate Issues

1. **Invalid CSR format**
   ```bash
   # Verify CSR format
   openssl req -in request.csr -noout -text
   ```

2. **Subject validation errors**
   ```bash
   # Check required subject fields are present
   # Verify organization and country match CA policy
   ```

### Client Issues

1. **Missing dependencies**
   ```bash
   # Install required tools
   apt-get install curl jq openssl  # Debian/Ubuntu
   yum install curl jq openssl      # RHEL/CentOS
   ```

2. **Configuration file not found**
   ```bash
   # Create configuration file
   cp ca-client.conf /etc/ssl/ca-client.conf
   chmod 600 /etc/ssl/ca-client.conf
   ```

## API Response Codes

- `200 OK`: Request successful
- `400 Bad Request`: Invalid request data
- `401 Unauthorized`: Authentication failed
- `404 Not Found`: Resource not found
- `429 Too Many Requests`: Rate limit exceeded
- `500 Internal Server Error`: Server error

## Security Considerations

1. **Secure API Keys**: Use strong, randomly generated API keys
2. **Network Security**: Limit API access to trusted networks only
3. **Certificate Storage**: Protect private keys with appropriate file permissions
4. **Regular Updates**: Keep CA server and client tools updated
5. **Monitoring**: Log API access and certificate issuance
6. **Backup**: Regular backup of CA data and configuration files

## Support and Maintenance

### Log Files
- API logs: `/var/log/apache2/ca-gui-error.log`
- PHP errors: `/var/log/php/errors.log`
- System logs: `/var/log/syslog`

### Monitoring
```bash
# Check API health
curl -H "X-API-Key: your-key" https://ca-server/api.php/download?type=root-ca

# Monitor certificate expiry
openssl x509 -in certificate.crt -noout -dates

# Check CA server status
systemctl status apache2
```

### Backup Procedures
```bash
# Backup CA data
tar -czf ca-backup-$(date +%Y%m%d).tar.gz /mnt/pve/nfs-storage/ca-data

# Backup configuration
cp /etc/ssl/ca-client.conf ca-client-backup.conf
```