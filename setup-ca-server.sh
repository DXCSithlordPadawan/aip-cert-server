#!/bin/bash
##########################################################
# CA Server Setup Script (Runs inside container)
##########################################################
# Usage: ./setup-ca-server.sh
# Author: Iain Reid
# Created: 09 Jul 2025 
# Test Checked: 10 Jul 2015
##########################################################
# Amended Date  Amended By Who  Amended Reason
##########################################################
# 13 Jul 2025   Assistant       Fixed permissions, paths, PHP issues
#
##########################################################

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
apt-get update -y
apt-get upgrade -y

# Install required packages
echo -e "${YELLOW}Installing required packages...${NC}"
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl \
    openssl \
    apache2 \
    php \
    php-cli \
    php-json \
    libapache2-mod-php \
    ssl-cert \
    make \
    git \
    apache2-utils

apt-get clean

# Create CA directory structure
echo -e "${YELLOW}Creating CA directory structure...${NC}"
CA_ROOT="/mnt/ca-data"

# Ensure mount point exists and has correct permissions
if [ ! -d "${CA_ROOT}" ]; then
    mkdir -p ${CA_ROOT}
fi

# Create subdirectories
mkdir -p ${CA_ROOT}/{root,intermediate,requests,issued,web}
mkdir -p ${CA_ROOT}/root/{certs,crl,newcerts,private}
mkdir -p ${CA_ROOT}/intermediate/{certs,crl,csr,newcerts,private}

# Set permissions - make sure www-data can write to requests and issued
chmod 777 ${CA_ROOT}/root/private
chmod 777 ${CA_ROOT}/intermediate/private
chmod 777 ${CA_ROOT}/requests
chmod 777 ${CA_ROOT}/issued
chown -R www-data:www-data ${CA_ROOT}/intermediate
chown -R www-data:www-data ${CA_ROOT}/requests
chown -R www-data:www-data ${CA_ROOT}/issued

# Initialize index and serial files
touch ${CA_ROOT}/root/index.txt
touch ${CA_ROOT}/intermediate/index.txt
# Use hex format for serial numbers as OpenSSL expects
echo 01 > ${CA_ROOT}/root/serial
echo 1000 > ${CA_ROOT}/intermediate/serial
echo 1000 > ${CA_ROOT}/root/crlnumber
echo 1000 > ${CA_ROOT}/intermediate/crlnumber

# Create index attributes files to ensure serial increments
echo "unique_subject = no" > ${CA_ROOT}/root/index.txt.attr
echo "unique_subject = no" > ${CA_ROOT}/intermediate/index.txt.attr

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

[ client_cert ]
basicConstraints = CA:FALSE
nsCertType = client, email
nsComment = "OpenSSL Generated Client Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth, emailProtection

[ code_signing_cert ]
basicConstraints = CA:FALSE
nsComment = "OpenSSL Generated Code Signing Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning

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
sed -i 's|private/ca.key.pem|private/intermediate.key.pem|g' ${CA_ROOT}/intermediate/openssl.cnf
sed -i 's|certs/ca.cert.pem|certs/intermediate.cert.pem|g' ${CA_ROOT}/intermediate/openssl.cnf

# Copy v3.req file
cp /root/v3.req ${CA_ROOT}/v3.req

# Check if CA already exists
if [ -f "${CA_ROOT}/root/certs/ca.cert.pem" ]; then
    echo -e "${YELLOW}Root CA already exists, skipping CA generation...${NC}"
else
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
    chmod 777 ${CA_ROOT}/intermediate/private/intermediate.key.pem

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

    chmod 777 ${CA_ROOT}/intermediate/certs/intermediate.cert.pem

    # Create certificate chain
    cat ${CA_ROOT}/intermediate/certs/intermediate.cert.pem \
        ${CA_ROOT}/root/certs/ca.cert.pem > ${CA_ROOT}/intermediate/certs/ca-chain.cert.pem
fi

# Setup Apache for HTTPS GUI
echo -e "${YELLOW}Setting up Apache web server...${NC}"

# Create web directory
mkdir -p /var/www/ca-gui

# Copy web GUI files
if [ -d /root/ca-web-gui ]; then
    cp /root/ca-web-gui/*.php /var/www/ca-gui/ 2>/dev/null || true
    cp /root/ca-web-gui/*.css /var/www/ca-gui/ 2>/dev/null || true
    echo -e "${GREEN}Web GUI files copied${NC}"
else
    echo -e "${RED}Warning: Web GUI files not found in /root/ca-web-gui/${NC}"
fi

# Ensure PHP error log exists
mkdir -p /var/log/php
touch /var/log/php/errors.log
chown www-data:www-data /var/log/php/errors.log

# Configure PHP for debugging (we'll turn this off later)
cat > /etc/php/*/apache2/conf.d/99-ca-gui.ini << EOF
display_errors = On
error_reporting = E_ALL
log_errors = On
error_log = /var/log/php/errors.log
EOF

# Create Apache configuration
cat > /etc/apache2/sites-available/ca-gui.conf << EOF
<VirtualHost *:443>
    ServerName ${CONTAINER_NAME}.${DOMAIN_NAME}
    ServerAlias ${CONTAINER_IP%/*}
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
    
    # PHP settings
    php_value error_reporting -1
    php_value display_errors On
</VirtualHost>

<VirtualHost *:80>
    ServerName ${CONTAINER_NAME}.${DOMAIN_NAME}
    ServerAlias ${CONTAINER_IP%/*}
    Redirect permanent / https://${CONTAINER_NAME}.${DOMAIN_NAME}/
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

# Set final permissions
chown -R www-data:www-data /var/www/ca-gui
chmod -R 777 /var/www/ca-gui

# Ensure www-data can write to CA directories
chown -R www-data:www-data ${CA_ROOT}/intermediate
chown -R www-data:www-data ${CA_ROOT}/requests
chown -R www-data:www-data ${CA_ROOT}/issued
chown -R www-data:www-data ${CA_ROOT}/web
chmod -R 777 ${CA_ROOT}/intermediate
chmod -R 777 ${CA_ROOT}/requests
chmod -R 777 ${CA_ROOT}/issued
chmod -R 777 ${CA_ROOT}/web

# Allow www-data to run openssl commands for CA operations
echo "www-data ALL=(ALL) NOPASSWD: /usr/bin/openssl" >> /etc/sudoers

# Create a test script to verify permissions
cat > /var/www/ca-gui/test-permissions.php << 'EOF'
<?php
echo "<h2>Permission Test</h2>";
echo "<pre>";
echo "Current user: " . exec('whoami') . "\n";
echo "CA Root exists: " . (is_dir('/mnt/ca-data') ? 'Yes' : 'No') . "\n";
echo "Requests dir writable: " . (is_writable('/mnt/ca-data/requests') ? 'Yes' : 'No') . "\n";
echo "Issued dir writable: " . (is_writable('/mnt/ca-data/issued') ? 'Yes' : 'No') . "\n";
echo "\nDirectory permissions:\n";
system('ls -la /mnt/ca-data/');
echo "</pre>";
?>
EOF

# Restart Apache
systemctl restart apache2
systemctl enable apache2

# Create a simple systemd service to ensure permissions on boot
cat > /etc/systemd/system/ca-permissions.service << EOF
[Unit]
Description=Ensure CA directory permissions
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'chown -R www-data:www-data /mnt/ca-data/requests /mnt/ca-data/issued && chmod -R 777 /mnt/ca-data/requests /mnt/ca-data/issued'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl enable ca-permissions.service
systemctl start ca-permissions.service

echo -e "${GREEN}=== CA Server Setup Complete ===${NC}"
echo -e "${GREEN}Root CA Certificate: ${CA_ROOT}/root/certs/ca.cert.pem${NC}"
echo -e "${GREEN}Intermediate CA Certificate: ${CA_ROOT}/intermediate/certs/intermediate.cert.pem${NC}"
echo -e "${GREEN}Certificate Chain: ${CA_ROOT}/intermediate/certs/ca-chain.cert.pem${NC}"
echo -e "${YELLOW}Test permissions at: https://${CONTAINER_IP%/*}/test-permissions.php${NC}"