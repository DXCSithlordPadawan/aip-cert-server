# Proxmox Certificate Authority Server Setup

This setup consists of multiple scripts to create a Proxmox LXC container running a Certificate Authority with ECDSA certificates and a web-based GUI.

## File Structure

```
ca-server-setup/
├── config.env                 # Configuration file
├── create-ca-container.sh     # Main container creation script
├── setup-ca-server.sh         # CA server setup script (runs inside container)
├── v3.req                     # OpenSSL v3 extensions file
└── ca-web-gui/               # Web GUI files
    ├── index.php
    ├── style.css
    └── ca-functions.php
```

## 1. Configuration File (config.env)

```bash
# Container Configuration
CONTAINER_NAME="cert-server"
CONTAINER_ID="200"
CONTAINER_PASSWORD="BobTheBigRedBus-0"
CONTAINER_CORES="2"
CONTAINER_MEMORY="2048"
CONTAINER_DISK="8"
CONTAINER_IP="192.168.0.122/24"
CONTAINER_GATEWAY="192.168.0.1"

# NFS Storage Configuration
NFS_SERVER="192.168.0.106"
NFS_MOUNT_POINT="/mnt/pve/nfs-storage"
NFS_STORAGE_NAME="nfs-storage"

# Network Configuration
DNS_SERVER="192.168.0.110"
DOMAIN_NAME="aip.dxc.com"

# Certificate Configuration
ROOT_CA_CN="AIP Root CA"
ROOT_CA_DAYS="7300"  # 20 years
INTERMEDIATE_CA_DAYS="3650"  # 10 years
CA_COUNTRY="GB"
CA_STATE="Hampshire"
CA_LOCALITY="Farnborough"
CA_ORGANIZATION="DXC Technology"
CA_ORG_UNIT="EntServ D S"
CA_EMAIL="ca@aip.dxc.com"

# Web GUI Configuration
WEB_PORT="443"
WEB_USER="admin"
WEB_PASSWORD="CaAdmin2024!"
```

## 2. Main Container Creation Script (create-ca-container.sh)

```bash
#!/bin/bash

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
    
    # Create container
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
        
        # Add NFS mount point
        echo -e "${YELLOW}Adding NFS mount point...${NC}"
        pct set ${CONTAINER_ID} -mp0 ${NFS_STORAGE_NAME}:${CONTAINER_DISK},mp=/mnt/ca-data
        
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
    
    echo -e "${YELLOW}Copying setup files to container...${NC}"
    pct push ${CONTAINER_ID} setup-ca-server.sh /root/setup-ca-server.sh
    pct push ${CONTAINER_ID} config.env /root/config.env
    pct push ${CONTAINER_ID} v3.req /root/v3.req
    
    # Create web GUI directory and copy files
    pct exec ${CONTAINER_ID} -- mkdir -p /root/ca-web-gui
    for file in ca-web-gui/*; do
        if [ -f "$file" ]; then
            pct push ${CONTAINER_ID} "$file" "/root/$(basename $file)"
        fi
    done
    
    echo -e "${YELLOW}Running CA setup script inside container...${NC}"
    pct exec ${CONTAINER_ID} -- chmod +x /root/setup-ca-server.sh
    pct exec ${CONTAINER_ID} -- /root/setup-ca-server.sh
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}CA server setup completed successfully${NC}"
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
}

# Run main function
main
```

## 3. CA Server Setup Script (setup-ca-server.sh)

```bash
#!/bin/bash

# This script runs inside the container
source /root/config.env

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Setting up Certificate Authority Server ===${NC}"

# Update system
echo -e "${YELLOW}Updating system packages...${NC}"
apt-get update && apt-get upgrade -y

# Install required packages
echo -e "${YELLOW}Installing required packages...${NC}"
apt-get install -y \
    openssl \
    apache2 \
    php \
    php-cli \
    php-openssl \
    php-json \
    libapache2-mod-php \
    ssl-cert \
    make \
    git

# Create CA directory structure
echo -e "${YELLOW}Creating CA directory structure...${NC}"
CA_ROOT="/mnt/ca-data"
mkdir -p ${CA_ROOT}/{root,intermediate,requests,issued,web}
mkdir -p ${CA_ROOT}/root/{certs,crl,newcerts,private}
mkdir -p ${CA_ROOT}/intermediate/{certs,crl,csr,newcerts,private}

# Set permissions
chmod 700 ${CA_ROOT}/root/private
chmod 700 ${CA_ROOT}/intermediate/private

# Initialize index and serial files
touch ${CA_ROOT}/root/index.txt
touch ${CA_ROOT}/intermediate/index.txt
echo 1000 > ${CA_ROOT}/root/serial
echo 1000 > ${CA_ROOT}/intermediate/serial
echo 1000 > ${CA_ROOT}/root/crlnumber
echo 1000 > ${CA_ROOT}/intermediate/crlnumber

# Create OpenSSL configuration for Root CA
cat > ${CA_ROOT}/root/openssl.cnf << 'EOF'
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = /mnt/ca-data/root
certs             = $dir/certs
crl_dir           = $dir/crl
new_certs_dir     = $dir/newcerts
database          = $dir/index.txt
serial            = $dir/serial
RANDFILE          = $dir/private/.rand
private_key       = $dir/private/ca.key.pem
certificate       = $dir/certs/ca.cert.pem
crlnumber         = $dir/crlnumber
crl               = $dir/crl/ca.crl.pem
crl_extensions    = crl_ext
default_crl_days  = 30
default_md        = sha256
name_opt          = ca_default
cert_opt          = ca_default
default_days      = 375
preserve          = no
policy            = policy_strict

[ policy_strict ]
countryName             = match
stateOrProvinceName     = match
organizationName        = match
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ policy_loose ]
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ req ]
default_bits        = 384
distinguished_name  = req_distinguished_name
string_mask         = utf8only
default_md          = sha256
x509_extensions     = v3_ca

[ req_distinguished_name ]
countryName                     = Country Name (2 letter code)
stateOrProvinceName             = State or Province Name
localityName                    = Locality Name
0.organizationName              = Organization Name
organizationalUnitName          = Organizational Unit Name
commonName                      = Common Name
emailAddress                    = Email Address

[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ v3_intermediate_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ usr_cert ]
basicConstraints = CA:FALSE
nsCertType = client, email
nsComment = "OpenSSL Generated Client Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth, emailProtection

[ server_cert ]
basicConstraints = CA:FALSE
nsCertType = server
nsComment = "OpenSSL Generated Server Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth

[ crl_ext ]
authorityKeyIdentifier=keyid:always

[ ocsp ]
basicConstraints = CA:FALSE
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, OCSPSigning
EOF

# Create OpenSSL configuration for Intermediate CA
cp ${CA_ROOT}/root/openssl.cnf ${CA_ROOT}/intermediate/openssl.cnf
sed -i 's|/mnt/ca-data/root|/mnt/ca-data/intermediate|g' ${CA_ROOT}/intermediate/openssl.cnf

# Copy v3.req file
cp /root/v3.req ${CA_ROOT}/v3.req

# Generate Root CA private key (ECDSA P-384)
echo -e "${YELLOW}Generating Root CA private key...${NC}"
openssl ecparam -genkey -name secp384r1 -out ${CA_ROOT}/root/private/ca.key.pem
chmod 400 ${CA_ROOT}/root/private/ca.key.pem

# Generate Root CA certificate
echo -e "${YELLOW}Generating Root CA certificate...${NC}"
openssl req -config ${CA_ROOT}/root/openssl.cnf \
    -key ${CA_ROOT}/root/private/ca.key.pem \
    -new -x509 -days ${ROOT_CA_DAYS} -sha384 -extensions v3_ca \
    -out ${CA_ROOT}/root/certs/ca.cert.pem \
    -subj "/C=${CA_COUNTRY}/ST=${CA_STATE}/L=${CA_LOCALITY}/O=${CA_ORGANIZATION}/OU=${CA_ORG_UNIT}/CN=${ROOT_CA_CN}/emailAddress=${CA_EMAIL}"

# Verify Root CA
echo -e "${YELLOW}Verifying Root CA certificate...${NC}"
openssl x509 -noout -text -in ${CA_ROOT}/root/certs/ca.cert.pem

# Generate Intermediate CA private key (ECDSA P-384)
echo -e "${YELLOW}Generating Intermediate CA private key...${NC}"
openssl ecparam -genkey -name secp384r1 -out ${CA_ROOT}/intermediate/private/intermediate.key.pem
chmod 400 ${CA_ROOT}/intermediate/private/intermediate.key.pem

# Generate Intermediate CA CSR
echo -e "${YELLOW}Generating Intermediate CA CSR...${NC}"
openssl req -config ${CA_ROOT}/intermediate/openssl.cnf -new -sha384 \
    -key ${CA_ROOT}/intermediate/private/intermediate.key.pem \
    -out ${CA_ROOT}/intermediate/csr/intermediate.csr.pem \
    -subj "/C=${CA_COUNTRY}/ST=${CA_STATE}/L=${CA_LOCALITY}/O=${CA_ORGANIZATION}/OU=${CA_ORG_UNIT}/CN=${ROOT_CA_CN} Intermediate CA/emailAddress=${CA_EMAIL}"

# Sign Intermediate CA certificate
echo -e "${YELLOW}Signing Intermediate CA certificate...${NC}"
openssl ca -batch -config ${CA_ROOT}/root/openssl.cnf -extensions v3_intermediate_ca \
    -days ${INTERMEDIATE_CA_DAYS} -notext -md sha384 \
    -in ${CA_ROOT}/intermediate/csr/intermediate.csr.pem \
    -out ${CA_ROOT}/intermediate/certs/intermediate.cert.pem

chmod 444 ${CA_ROOT}/intermediate/certs/intermediate.cert.pem

# Create certificate chain
cat ${CA_ROOT}/intermediate/certs/intermediate.cert.pem \
    ${CA_ROOT}/root/certs/ca.cert.pem > ${CA_ROOT}/intermediate/certs/ca-chain.cert.pem

# Setup Apache for HTTPS GUI
echo -e "${YELLOW}Setting up Apache web server...${NC}"

# Create web directory
mkdir -p /var/www/ca-gui
cp /root/*.php /var/www/ca-gui/
cp /root/*.css /var/www/ca-gui/ 2>/dev/null || true

# Create Apache configuration
cat > /etc/apache2/sites-available/ca-gui.conf << EOF
<VirtualHost *:443>
    ServerName ${CONTAINER_NAME}.${DOMAIN_NAME}
    DocumentRoot /var/www/ca-gui
    
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/ca-gui.crt
    SSLCertificateKeyFile /etc/ssl/private/ca-gui.key
    
    <Directory /var/www/ca-gui>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/ca-gui-error.log
    CustomLog \${APACHE_LOG_DIR}/ca-gui-access.log combined
</VirtualHost>
EOF

# Generate self-signed certificate for web GUI
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/ca-gui.key \
    -out /etc/ssl/certs/ca-gui.crt \
    -subj "/C=${CA_COUNTRY}/ST=${CA_STATE}/L=${CA_LOCALITY}/O=${CA_ORGANIZATION}/OU=${CA_ORG_UNIT}/CN=${CONTAINER_NAME}.${DOMAIN_NAME}"

# Enable Apache modules and site
a2enmod ssl
a2enmod rewrite
a2enmod php*
a2dissite 000-default
a2ensite ca-gui

# Create .htaccess for basic authentication
htpasswd -bc /var/www/ca-gui/.htpasswd ${WEB_USER} ${WEB_PASSWORD}

cat > /var/www/ca-gui/.htaccess << EOF
AuthType Basic
AuthName "Certificate Authority Administration"
AuthUserFile /var/www/ca-gui/.htpasswd
Require valid-user
EOF

# Set permissions
chown -R www-data:www-data /var/www/ca-gui
chmod -R 755 /var/www/ca-gui
chown -R www-data:www-data ${CA_ROOT}/web
chmod -R 755 ${CA_ROOT}/web

# Create systemd service for CA operations
cat > /etc/systemd/system/ca-processor.service << EOF
[Unit]
Description=Certificate Authority Request Processor
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/php /var/www/ca-gui/ca-processor.php
Restart=always
User=www-data
Group=www-data

[Install]
WantedBy=multi-user.target
EOF

# Restart Apache
systemctl restart apache2
systemctl enable apache2

echo -e "${GREEN}=== CA Server Setup Complete ===${NC}"
echo -e "${GREEN}Root CA Certificate: ${CA_ROOT}/root/certs/ca.cert.pem${NC}"
echo -e "${GREEN}Intermediate CA Certificate: ${CA_ROOT}/intermediate/certs/intermediate.cert.pem${NC}"
echo -e "${GREEN}Certificate Chain: ${CA_ROOT}/intermediate/certs/ca-chain.cert.pem${NC}"
```

## 4. OpenSSL v3 Extensions File (v3.req)

```ini
[ req ]

distinguished_name=req_distinguished_name
req_extensions=v3_req

[ req_distinguished_name ]
countryName = Country Name 
countryName_default = GB
stateOrProvinceName = State name
stateOrProvinceName_default = Hampshire
localityName = City
localityName_default = Farnborough
organizationUnitName = OU Name
organizationUnitName_default = EntServ D S
commonName = Common Name
commonName_default = cert-server.aip.dxc.com

[ v3_req ]
#authorityKeyIdentifier=keyid:always,issuer:always
basicConstraints=CA:FALSE
keyUsage=digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage=serverAuth
subjectAltName = @alt_names

[ alt_names ]
DNS.1=bastion.aip
DNS.2=ibs.aip.dxc.com
DNS.3=quay.aip.dxc.com
DNS.4=bastion.aip.dxc.com
DNS.5=dc1
IP.1=192.168.0.110
```

## 5. Web GUI - Main Page (ca-web-gui/index.php)

```php
<?php
session_start();
require_once 'ca-functions.php';

$ca = new CertificateAuthority('/mnt/ca-data');
$message = '';
$messageType = '';

// Handle form submissions
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (isset($_POST['action'])) {
        switch ($_POST['action']) {
            case 'submit_request':
                $result = $ca->submitRequest($_POST);
                $message = $result['message'];
                $messageType = $result['success'] ? 'success' : 'error';
                break;
            
            case 'approve_request':
                $result = $ca->approveRequest($_POST['request_id']);
                $message = $result['message'];
                $messageType = $result['success'] ? 'success' : 'error';
                break;
            
            case 'reject_request':
                $result = $ca->rejectRequest($_POST['request_id']);
                $message = $result['message'];
                $messageType = $result['success'] ? 'success' : 'error';
                break;
        }
    }
}

// Get pending requests
$pendingRequests = $ca->getPendingRequests();
$issuedCertificates = $ca->getIssuedCertificates();
?>

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Certificate Authority Management</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <div class="container">
        <header>
            <h1>Certificate Authority Management System</h1>
            <nav>
                <ul>
                    <li><a href="#request">Submit Request</a></li>
                    <li><a href="#pending">Pending Requests</a></li>
                    <li><a href="#issued">Issued Certificates</a></li>
                    <li><a href="#download">Download CA Certificates</a></li>
                </ul>
            </nav>
        </header>

        <?php if ($message): ?>
            <div class="message <?php echo $messageType; ?>">
                <?php echo htmlspecialchars($message); ?>
            </div>
        <?php endif; ?>

        <!-- Certificate Request Form -->
        <section id="request" class="card">
            <h2>Submit Certificate Request</h2>
            <form method="POST" action="">
                <input type="hidden" name="action" value="submit_request">
                
                <div class="form-group">
                    <label>Certificate Type:</label>
                    <select name="cert_type" required>
                        <option value="server">Server Certificate</option>
                        <option value="client">Client Certificate</option>
                        <option value="code_signing">Code Signing Certificate</option>
                    </select>
                </div>

                <div class="form-group">
                    <label>Common Name (CN):</label>
                    <input type="text" name="common_name" required 
                           placeholder="e.g., server.example.com or John Doe">
                </div>

                <div class="form-group">
                    <label>Organization (O):</label>
                    <input type="text" name="organization" required value="DXC Technology">
                </div>

                <div class="form-group">
                    <label>Organizational Unit (OU):</label>
                    <input type="text" name="org_unit" value="EntServ D S">
                </div>

                <div class="form-group">
                    <label>Country (C):</label>
                    <input type="text" name="country" maxlength="2" required value="GB"
                           placeholder="e.g., US">
                </div>

                <div class="form-group">
                    <label>State/Province (ST):</label>
                    <input type="text" name="state" required value="Hampshire">
                </div>

                <div class="form-group">
                    <label>Locality/City (L):</label>
                    <input type="text" name="locality" required value="Farnborough">
                </div>

                <div class="form-group">
                    <label>Email Address:</label>
                    <input type="email" name="email" required>
                </div>

                <div class="form-group">
                    <label>Subject Alternative Names (comma-separated):</label>
                    <input type="text" name="san" 
                           placeholder="e.g., www.example.com, mail.example.com">
                </div>

                <div class="form-group">
                    <label>Key Type:</label>
                    <select name="key_type" required>
                        <option value="ecdsa">ECDSA (P-384)</option>
                        <option value="rsa">RSA (2048-bit)</option>
                    </select>
                </div>

                <button type="submit" class="btn btn-primary">Submit Request</button>
            </form>
        </section>

        <!-- Pending Requests -->
        <section id="pending" class="card">
            <h2>Pending Certificate Requests</h2>
            <?php if (empty($pendingRequests)): ?>
                <p>No pending requests.</p>
            <?php else: ?>
                <table>
                    <thead>
                        <tr>
                            <th>Request ID</th>
                            <th>Common Name</th>
                            <th>Type</th>
                            <th>Submitted</th>
                            <th>Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($pendingRequests as $request): ?>
                            <tr>
                                <td><?php echo htmlspecialchars($request['id']); ?></td>
                                <td><?php echo htmlspecialchars($request['common_name']); ?></td>
                                <td><?php echo htmlspecialchars($request['type']); ?></td>
                                <td><?php echo htmlspecialchars($request['submitted']); ?></td>
                                <td>
                                    <form method="POST" style="display: inline;">
                                        <input type="hidden" name="action" value="approve_request">
                                        <input type="hidden" name="request_id" 
                                               value="<?php echo $request['id']; ?>">
                                        <button type="submit" class="btn btn-success btn-sm">
                                            Approve
                                        </button>
                                    </form>
                                    <form method="POST" style="display: inline;">
                                        <input type="hidden" name="action" value="reject_request">
                                        <input type="hidden" name="request_id" 
                                               value="<?php echo $request['id']; ?>">
                                        <button type="submit" class="btn btn-danger btn-sm">
                                            Reject
                                        </button>
                                    </form>
                                    <a href="view-request.php?id=<?php echo $request['id']; ?>" 
                                       class="btn btn-info btn-sm">View</a>
                                </td>
                            </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            <?php endif; ?>
        </section>

        <!-- Issued Certificates -->
        <section id="issued" class="card">
            <h2>Issued Certificates</h2>
            <?php if (empty($issuedCertificates)): ?>
                <p>No certificates issued yet.</p>
            <?php else: ?>
                <table>
                    <thead>
                        <tr>
                            <th>Serial Number</th>
                            <th>Common Name</th>
                            <th>Type</th>
                            <th>Valid From</th>
                            <th>Valid To</th>
                            <th>Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($issuedCertificates as $cert): ?>
                            <tr>
                                <td><?php echo htmlspecialchars($cert['serial']); ?></td>
                                <td><?php echo htmlspecialchars($cert['common_name']); ?></td>
                                <td><?php echo htmlspecialchars($cert['type']); ?></td>
                                <td><?php echo htmlspecialchars($cert['valid_from']); ?></td>
                                <td><?php echo htmlspecialchars($cert['valid_to']); ?></td>
                                <td>
                                    <a href="download.php?type=cert&serial=<?php echo $cert['serial']; ?>" 
                                       class="btn btn-primary btn-sm">Download</a>
                                    <a href="download.php?type=chain&serial=<?php echo $cert['serial']; ?>" 
                                       class="btn btn-info btn-sm">Chain</a>
                                </td>
                            </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            <?php endif; ?>
        </section>

        <!-- Download CA Certificates -->
        <section id="download" class="card">
            <h2>Download CA Certificates</h2>
            <div class="download-grid">
                <div class="download-item">
                    <h3>Root CA Certificate</h3>
                    <p>The root certificate of the Certificate Authority</p>
                    <a href="download.php?type=root-ca" class="btn btn-primary">
                        Download Root CA
                    </a>
                </div>
                <div class="download-item">
                    <h3>Intermediate CA Certificate</h3>
                    <p>The intermediate certificate used for signing</p>
                    <a href="download.php?type=intermediate-ca" class="btn btn-primary">
                        Download Intermediate CA
                    </a>
                </div>
                <div class="download-item">
                    <h3>CA Certificate Chain</h3>
                    <p>Complete certificate chain (Root + Intermediate)</p>
                    <a href="download.php?type=ca-chain" class="btn btn-primary">
                        Download CA Chain
                    </a>
                </div>
            </div>
        </section>
    </div>
</body>
</html>
```

## 6. Web GUI - Style Sheet (ca-web-gui/style.css)

```css
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
    background-color: #f5f5f5;
    color: #333;
    line-height: 1.6;
}

.container {
    max-width: 1200px;
    margin: 0 auto;
    padding: 20px;
}

header {
    background-color: #2c3e50;
    color: white;
    padding: 20px;
    margin-bottom: 30px;
    border-radius: 8px;
}

header h1 {
    margin-bottom: 15px;
}

nav ul {
    list-style: none;
    display: flex;
    gap: 20px;
}

nav a {
    color: white;
    text-decoration: none;
    padding: 5px 10px;
    border-radius: 4px;
    transition: background-color 0.3s;
}

nav a:hover {
    background-color: rgba(255, 255, 255, 0.1);
}

.card {
    background: white;
    border-radius: 8px;
    padding: 30px;
    margin-bottom: 30px;
    box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
}

.card h2 {
    margin-bottom: 20px;
    color: #2c3e50;
    border-bottom: 2px solid #ecf0f1;
    padding-bottom: 10px;
}

.message {
    padding: 15px;
    margin-bottom: 20px;
    border-radius: 4px;
    font-weight: 500;
}

.message.success {
    background-color: #d4edda;
    color: #155724;
    border: 1px solid #c3e6cb;
}

.message.error {
    background-color: #f8d7da;
    color: #721c24;
    border: 1px solid #f5c6cb;
}

.form-group {
    margin-bottom: 20px;
}

.form-group label {
    display: block;
    margin-bottom: 5px;
    font-weight: 600;
    color: #555;
}

.form-group input,
.form-group select,
.form-group textarea {
    width: 100%;
    padding: 10px;
    border: 1px solid #ddd;
    border-radius: 4px;
    font-size: 16px;
    transition: border-color 0.3s;
}

.form-group input:focus,
.form-group select:focus,
.form-group textarea:focus {
    outline: none;
    border-color: #3498db;
}

.btn {
    display: inline-block;
    padding: 10px 20px;
    border: none;
    border-radius: 4px;
    font-size: 16px;
    font-weight: 500;
    text-decoration: none;
    cursor: pointer;
    transition: all 0.3s;
    text-align: center;
}

.btn-primary {
    background-color: #3498db;
    color: white;
}

.btn-primary:hover {
    background-color: #2980b9;
}

.btn-success {
    background-color: #27ae60;
    color: white;
}

.btn-success:hover {
    background-color: #229954;
}

.btn-danger {
    background-color: #e74c3c;
    color: white;
}

.btn-danger:hover {
    background-color: #c0392b;
}

.btn-info {
    background-color: #16a085;
    color: white;
}

.btn-info:hover {
    background-color: #138d75;
}

.btn-sm {
    padding: 5px 10px;
    font-size: 14px;
}

table {
    width: 100%;
    border-collapse: collapse;
    margin-top: 20px;
}

table th,
table td {
    padding: 12px;
    text-align: left;
    border-bottom: 1px solid #ecf0f1;
}

table th {
    background-color: #f8f9fa;
    font-weight: 600;
    color: #2c3e50;
}

table tr:hover {
    background-color: #f8f9fa;
}

.download-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
    gap: 20px;
    margin-top: 20px;
}

.download-item {
    padding: 20px;
    background-color: #f8f9fa;
    border-radius: 8px;
    text-align: center;
}

.download-item h3 {
    margin-bottom: 10px;
    color: #2c3e50;
}

.download-item p {
    margin-bottom: 15px;
    color: #666;
}

@media (max-width: 768px) {
    nav ul {
        flex-direction: column;
        gap: 10px;
    }
    
    .download-grid {
        grid-template-columns: 1fr;
    }
}
```

## 7. Web GUI - CA Functions (ca-web-gui/ca-functions.php)

```php
<?php
class CertificateAuthority {
    private $caRoot;
    private $rootDir;
    private $intermediateDir;
    private $requestsDir;
    private $issuedDir;
    
    public function __construct($caRoot) {
        $this->caRoot = $caRoot;
        $this->rootDir = $caRoot . '/root';
        $this->intermediateDir = $caRoot . '/intermediate';
        $this->requestsDir = $caRoot . '/requests';
        $this->issuedDir = $caRoot . '/issued';
        
        // Create directories if they don't exist
        foreach ([$this->requestsDir, $this->issuedDir] as $dir) {
            if (!is_dir($dir)) {
                mkdir($dir, 0755, true);
            }
        }
    }
    
    /**
     * Submit a new certificate request
     */
    public function submitRequest($data) {
        try {
            $requestId = uniqid('req_');
            $requestDir = $this->requestsDir . '/' . $requestId;
            mkdir($requestDir, 0755);
            
            // Save request data
            $requestData = [
                'id' => $requestId,
                'type' => $data['cert_type'],
                'common_name' => $data['common_name'],
                'organization' => $data['organization'],
                'org_unit' => $data['org_unit'] ?? '',
                'country' => $data['country'],
                'state' => $data['state'],
                'locality' => $data['locality'],
                'email' => $data['email'],
                'san' => $data['san'] ?? '',
                'key_type' => $data['key_type'],
                'submitted' => date('Y-m-d H:i:s'),
                'status' => 'pending'
            ];
            
            file_put_contents($requestDir . '/request.json', json_encode($requestData, JSON_PRETTY_PRINT));
            
            // Generate private key
            if ($data['key_type'] === 'ecdsa') {
                $keyCmd = "openssl ecparam -genkey -name secp384r1 -out $requestDir/private.key";
            } else {
                $keyCmd = "openssl genrsa -out $requestDir/private.key 2048";
            }
            exec($keyCmd);
            
            // Generate CSR
            $subject = "/C={$data['country']}/ST={$data['state']}/L={$data['locality']}/O={$data['organization']}";
            if (!empty($data['org_unit'])) {
                $subject .= "/OU={$data['org_unit']}";
            }
            $subject .= "/CN={$data['common_name']}/emailAddress={$data['email']}";
            
            // Create config for CSR with extensions
            $configContent = $this->generateCSRConfig($data);
            file_put_contents($requestDir . '/csr.conf', $configContent);
            
            $csrCmd = "openssl req -new -key $requestDir/private.key -out $requestDir/request.csr -config $requestDir/csr.conf -subj \"$subject\"";
            exec($csrCmd);
            
            return ['success' => true, 'message' => 'Certificate request submitted successfully. Request ID: ' . $requestId];
            
        } catch (Exception $e) {
            return ['success' => false, 'message' => 'Error submitting request: ' . $e->getMessage()];
        }
    }
    
    /**
     * Generate CSR configuration
     */
    private function generateCSRConfig($data) {
        global $caRoot;
        
        // Read the v3.req template
        $v3ReqContent = file_get_contents($this->caRoot . '/v3.req');
        
        // For server certificates, use the v3.req as base
        if ($data['cert_type'] === 'server') {
            // Replace default values with submitted values
            $config = str_replace('countryName_default = GB', 'countryName_default = ' . $data['country'], $v3ReqContent);
            $config = str_replace('stateOrProvinceName_default = Hampshire', 'stateOrProvinceName_default = ' . $data['state'], $config);
            $config = str_replace('localityName_default = Farnborough', 'localityName_default = ' . $data['locality'], $config);
            $config = str_replace('organizationUnitName_default = EntServ D S', 'organizationUnitName_default = ' . ($data['org_unit'] ?: 'EntServ D S'), $config);
            $config = str_replace('commonName_default = cert-server.aip.dxc.com', 'commonName_default = ' . $data['common_name'], $config);
            
            // If custom SANs provided, update the alt_names section
            if (!empty($data['san'])) {
                $altNamesSection = "[alt_names]\n";
                $sans = explode(',', $data['san']);
                $dnsIndex = 1;
                $ipIndex = 1;
                foreach ($sans as $san) {
                    $san = trim($san);
                    if (filter_var($san, FILTER_VALIDATE_IP)) {
                        $altNamesSection .= "IP.{$ipIndex} = $san\n";
                        $ipIndex++;
                    } else {
                        $altNamesSection .= "DNS.{$dnsIndex} = $san\n";
                        $dnsIndex++;
                    }
                }
                // Replace the alt_names section
                $config = preg_replace('/\[ alt_names \].*$/s', trim($altNamesSection), $config);
            }
            
            return $config;
        }
        
        // For client and code signing certificates, generate custom config
        $config = "[req]\n";
        $config .= "distinguished_name = req_distinguished_name\n";
        $config .= "req_extensions = v3_req\n";
        $config .= "prompt = no\n\n";
        
        $config .= "[req_distinguished_name]\n";
        $config .= "C = {$data['country']}\n";
        $config .= "ST = {$data['state']}\n";
        $config .= "L = {$data['locality']}\n";
        $config .= "O = {$data['organization']}\n";
        if (!empty($data['org_unit'])) {
            $config .= "OU = {$data['org_unit']}\n";
        }
        $config .= "CN = {$data['common_name']}\n";
        $config .= "emailAddress = {$data['email']}\n\n";
        
        $config .= "[v3_req]\n";
        $config .= "basicConstraints = CA:FALSE\n";
        
        switch ($data['cert_type']) {
            case 'client':
                $config .= "keyUsage = critical, nonRepudiation, digitalSignature, keyEncipherment\n";
                $config .= "extendedKeyUsage = clientAuth, emailProtection\n";
                break;
            case 'code_signing':
                $config .= "keyUsage = critical, digitalSignature\n";
                $config .= "extendedKeyUsage = critical, codeSigning\n";
                break;
        }
        
        if (!empty($data['san'])) {
            $config .= "subjectAltName = @alt_names\n\n";
            $config .= "[alt_names]\n";
            $sans = explode(',', $data['san']);
            $dnsIndex = 1;
            $ipIndex = 1;
            foreach ($sans as $san) {
                $san = trim($san);
                if (filter_var($san, FILTER_VALIDATE_IP)) {
                    $config .= "IP.{$ipIndex} = $san\n";
                    $ipIndex++;
                } else {
                    $config .= "DNS.{$dnsIndex} = $san\n";
                    $dnsIndex++;
                }
            }
        }
        
        return $config;
    }
    
    /**
     * Get all pending requests
     */
    public function getPendingRequests() {
        $requests = [];
        $dirs = glob($this->requestsDir . '/*', GLOB_ONLYDIR);
        
        foreach ($dirs as $dir) {
            $jsonFile = $dir . '/request.json';
            if (file_exists($jsonFile)) {
                $data = json_decode(file_get_contents($jsonFile), true);
                if ($data['status'] === 'pending') {
                    $requests[] = $data;
                }
            }
        }
        
        return $requests;
    }
    
    /**
     * Approve a certificate request
     */
    public function approveRequest($requestId) {
        try {
            $requestDir = $this->requestsDir . '/' . $requestId;
            $requestFile = $requestDir . '/request.json';
            
            if (!file_exists($requestFile)) {
                return ['success' => false, 'message' => 'Request not found'];
            }
            
            $requestData = json_decode(file_get_contents($requestFile), true);
            
            // Sign the certificate
            $csrFile = $requestDir . '/request.csr';
            $certFile = $requestDir . '/certificate.crt';
            
            // Create extensions file for signing
            $extFile = $requestDir . '/extensions.conf';
            $this->createExtensionsFile($extFile, $requestData);
            
            $signCmd = "openssl ca -batch -config {$this->intermediateDir}/openssl.cnf ";
            $signCmd .= "-extensions {$requestData['type']}_cert -days 365 -notext ";
            $signCmd .= "-md sha384 -in $csrFile -out $certFile -extfile $extFile";
            
            exec($signCmd . " 2>&1", $output, $returnCode);
            
            if ($returnCode !== 0) {
                return ['success' => false, 'message' => 'Failed to sign certificate: ' . implode("\n", $output)];
            }
            
            // Get certificate serial number
            $serialCmd = "openssl x509 -in $certFile -noout -serial";
            exec($serialCmd, $serialOutput);
            $serial = str_replace('serial=', '', $serialOutput[0]);
            
            // Update request status
            $requestData['status'] = 'approved';
            $requestData['approved_date'] = date('Y-m-d H:i:s');
            $requestData['serial'] = $serial;
            file_put_contents($requestFile, json_encode($requestData, JSON_PRETTY_PRINT));
            
            // Copy to issued directory
            $issuedDir = $this->issuedDir . '/' . $serial;
            mkdir($issuedDir, 0755);
            copy($certFile, $issuedDir . '/certificate.crt');
            copy($requestDir . '/private.key', $issuedDir . '/private.key');
            copy($requestFile, $issuedDir . '/metadata.json');
            
            // Create certificate chain
            $chainFile = $issuedDir . '/chain.pem';
            $chainContent = file_get_contents($certFile) . "\n" . 
                           file_get_contents($this->intermediateDir . '/certs/ca-chain.cert.pem');
            file_put_contents($chainFile, $chainContent);
            
            return ['success' => true, 'message' => 'Certificate approved and issued successfully'];
            
        } catch (Exception $e) {
            return ['success' => false, 'message' => 'Error approving request: ' . $e->getMessage()];
        }
    }
    
    /**
     * Create extensions file for certificate signing
     */
    private function createExtensionsFile($filename, $requestData) {
        $content = "[{$requestData['type']}_cert]\n";
        $content .= "basicConstraints = CA:FALSE\n";
        
        switch ($requestData['type']) {
            case 'server':
                $content .= "nsCertType = server\n";
                $content .= "keyUsage = critical, digitalSignature, keyEncipherment\n";
                $content .= "extendedKeyUsage = serverAuth\n";
                break;
            case 'client':
                $content .= "nsCertType = client, email\n";
                $content .= "keyUsage = critical, nonRepudiation, digitalSignature, keyEncipherment\n";
                $content .= "extendedKeyUsage = clientAuth, emailProtection\n";
                break;
            case 'code_signing':
                $content .= "keyUsage = critical, digitalSignature\n";
                $content .= "extendedKeyUsage = critical, codeSigning\n";
                break;
        }
        
        $content .= "subjectKeyIdentifier = hash\n";
        $content .= "authorityKeyIdentifier = keyid,issuer\n";
        
        if (!empty($requestData['san'])) {
            $content .= "subjectAltName = @alt_names\n\n";
            $content .= "[alt_names]\n";
            $sans = explode(',', $requestData['san']);
            $index = 1;
            foreach ($sans as $san) {
                $san = trim($san);
                if (filter_var($san, FILTER_VALIDATE_IP)) {
                    $content .= "IP.{$index} = $san\n";
                } else {
                    $content .= "DNS.{$index} = $san\n";
                }
                $index++;
            }
        }
        
        file_put_contents($filename, $content);
    }
    
    /**
     * Reject a certificate request
     */
    public function rejectRequest($requestId) {
        try {
            $requestDir = $this->requestsDir . '/' . $requestId;
            $requestFile = $requestDir . '/request.json';
            
            if (!file_exists($requestFile)) {
                return ['success' => false, 'message' => 'Request not found'];
            }
            
            $requestData = json_decode(file_get_contents($requestFile), true);
            $requestData['status'] = 'rejected';
            $requestData['rejected_date'] = date('Y-m-d H:i:s');
            file_put_contents($requestFile, json_encode($requestData, JSON_PRETTY_PRINT));
            
            return ['success' => true, 'message' => 'Certificate request rejected'];
            
        } catch (Exception $e) {
            return ['success' => false, 'message' => 'Error rejecting request: ' . $e->getMessage()];
        }
    }
    
    /**
     * Get all issued certificates
     */
    public function getIssuedCertificates() {
        $certificates = [];
        $dirs = glob($this->issuedDir . '/*', GLOB_ONLYDIR);
        
        foreach ($dirs as $dir) {
            $metadataFile = $dir . '/metadata.json';
            $certFile = $dir . '/certificate.crt';
            
            if (file_exists($metadataFile) && file_exists($certFile)) {
                $metadata = json_decode(file_get_contents($metadataFile), true);
                
                // Get certificate details
                $certInfo = openssl_x509_parse(file_get_contents($certFile));
                
                $certificates[] = [
                    'serial' => $metadata['serial'],
                    'common_name' => $metadata['common_name'],
                    'type' => $metadata['type'],
                    'valid_from' => date('Y-m-d H:i:s', $certInfo['validFrom_time_t']),
                    'valid_to' => date('Y-m-d H:i:s', $certInfo['validTo_time_t'])
                ];
            }
        }
        
        return $certificates;
    }
}
?>
```

## 8. Download Handler (ca-web-gui/download.php)

```php
<?php
session_start();

$caRoot = '/mnt/ca-data';

// Get download type
$type = $_GET['type'] ?? '';
$serial = $_GET['serial'] ?? '';

switch ($type) {
    case 'root-ca':
        $file = $caRoot . '/root/certs/ca.cert.pem';
        $filename = 'root-ca.crt';
        break;
        
    case 'intermediate-ca':
        $file = $caRoot . '/intermediate/certs/intermediate.cert.pem';
        $filename = 'intermediate-ca.crt';
        break;
        
    case 'ca-chain':
        $file = $caRoot . '/intermediate/certs/ca-chain.cert.pem';
        $filename = 'ca-chain.pem';
        break;
        
    case 'cert':
        if (empty($serial)) {
            die('Serial number required');
        }
        $file = $caRoot . '/issued/' . $serial . '/certificate.crt';
        $filename = $serial . '.crt';
        break;
        
    case 'chain':
        if (empty($serial)) {
            die('Serial number required');
        }
        $file = $caRoot . '/issued/' . $serial . '/chain.pem';
        $filename = $serial . '-chain.pem';
        break;
        
    default:
        die('Invalid download type');
}

if (!file_exists($file)) {
    die('File not found');
}

// Send file
header('Content-Type: application/x-pem-file');
header('Content-Disposition: attachment; filename="' . $filename . '"');
header('Content-Length: ' . filesize($file));
readfile($file);
```

## Usage Instructions

1. **Prepare the files**:
   ```bash
   mkdir ca-server-setup
   cd ca-server-setup
   mkdir ca-web-gui
   
   # Create all the files as shown above
   chmod +x create-ca-container.sh
   chmod +x setup-ca-server.sh
   ```

2. **Configure settings**:
   Edit `config.env` to adjust any parameters as needed.

3. **Run the setup**:
   ```bash
   sudo ./create-ca-container.sh
   ```

4. **Access the CA Web GUI**:
   - URL: `https://192.168.0.122` (or your configured IP)
   - Username: `admin`
   - Password: `CaAdmin2024!`

5. **Container SSH access**:
   - SSH to Proxmox host
   - Enter container: `pct enter 200` (or your configured ID)
   - Or SSH directly with password: `BobTheBigRedBus-0`

The system will create a fully functional Certificate Authority with:
- ECDSA P-384 Root and Intermediate certificates
- Web-based certificate request and management interface
- Support for server, client, and code signing certificates
- Automatic certificate chain generation
- Persistent storage on NFS

All certificates and data are stored on the NFS mount for persistence across container restarts.