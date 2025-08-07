I've created a comprehensive set of scripts for setting up a Proxmox LXC container as a Certificate Authority server with ECDSA certificates and a web-based GUI. Here's what the solution provides:

## Key Features:

1. **Automated Container Creation**:
   - Creates a privileged Debian 12 LXC container
   - Configures persistent NFS storage
   - Tests for existing NFS storage and reuses if available
   - All parameters configurable via external `config.env` file

2. **Certificate Authority Setup**:
   - ECDSA P-384 Root CA certificate
   - ECDSA P-384 Intermediate CA certificate
   - Supports the v3.req extensions file you mentioned
   - 20-year validity for Root CA, 10-year for Intermediate

3. **Web-Based GUI** (HTTPS on port 443):
   - Submit certificate requests (server, client, code signing)
   - Approve/reject pending requests
   - Download issued certificates
   - Download Root CA, Intermediate CA, and certificate chains
   - Basic authentication protection

4. **Configuration Parameters** (all amendable in config.env):
   - Container name, ID, password
   - NFS server (default: 192.168.0.106)
   - Certificate server IP (default: 192.168.0.122)
   - Domain name (default: aip.dxc.com)
   - Root CA CN (default: "AIP Root CA")
   - DNS server (default: 192.168.0.110)
   - Container password (default: BobTheBigRedBus-0)


ca-server-setup/
├── config.env                 # Configuration file
├── create-ca-container.sh     # Main container creation script
├── setup-ca-server.sh         # CA server setup script (runs inside container)
├── v3.req                     # OpenSSL v3 extensions file
└── ca-web-gui/               # Web GUI files
    ├── index.php
    ├── style.css
    └── ca-functions.php

## To Use:

1. Create a directory and save all the files as shown
2. Make the scripts executable: `chmod +x *.sh`
3. Adjust parameters in `config.env` as needed
4. Run as root: `sudo ./create-ca-container.sh`

The system will automatically:
- Check/create NFS storage
- Download the Debian template if needed
- Create and configure the container
- Install and configure the CA
- Set up the web interface with HTTPS

The web GUI provides all the certificate management features you requested, including request submission, approval workflow, and certificate downloads.

I see you've provided the actual v3.req file. I'll update the scripts to incorporate this specific v3.req configuration and ensure all the default values match your requirements.Now I'll add support for using the provided v3.req file in certificate generation and update the web GUI to properly use it:Now let me add better organization field handling and update the form to include organization field:Now let me add the generation of a self-signed certificate for the CA web interface using the same defaults:Now let me update the completion messages to show the correct hostname:Perfect! I've updated the scripts to match your exact requirements:

## Key Updates Made:

1. **Updated config.env** with your specific defaults:
   - Container name: `cert-server` (matching the CN in v3.req)
   - Country: GB
   - State: Hampshire
   - Locality: Farnborough  
   - Organization: DXC Technology
   - Organizational Unit: EntServ D S

2. **Incorporated your v3.req file** exactly as provided with:
   - All the DNS entries (bastion.aip, ibs.aip.dxc.com, etc.)
   - IP address 192.168.0.110
   - Proper certificate extensions

3. **Updated the Web GUI**:
   - Pre-fills forms with your organization defaults
   - Uses the v3.req file for server certificate generation
   - Properly handles the provided SANs

4. **Container hostname** now includes the domain: `cert-server.aip.dxc.com`

## Usage:

1. Create the directory structure:
```bash
mkdir ca-server-setup
cd ca-server-setup
mkdir ca-web-gui
```

2. Create all the files as shown in the artifact, including your specific v3.req file

3. Make scripts executable:
```bash
chmod +x create-ca-container.sh
chmod +x setup-ca-server.sh
```

4. Run the setup:
```bash
sudo ./create-ca-container.sh
```

The system will create a Certificate Authority that:
- Uses ECDSA P-384 for both Root and Intermediate CAs
- Incorporates your v3.req file for certificate requests
- Provides HTTPS web interface at https://192.168.0.122
- Stores all data persistently on NFS storage
- Uses all your specified defaults (GB, Hampshire, Farnborough, DXC Technology, etc.)

All parameters can still be modified by editing the `config.env` file before running the setup script.

Now let me fix the CA functions to handle imported CSRs properly when approving:Now let me update the create-ca-container.sh to ensure all PHP files are copied:Let me create a script to fix the serial number issue on an already running container:Now let me create an updated download.php that handles missing private keys for imported CSRs:Let me create a comprehensive installation guide with all the fixes:## Summary of Fixes

I've addressed all the issues you mentioned:

1. **Serial Number Stuck at 1000**:
   - Added `index.txt.attr` files with `unique_subject = no` to allow serial incrementing
   - Created `fix-serial-numbers.sh` script to fix existing installations
   - Modified the OpenSSL configuration to properly track serial numbers

2. **Missing view-request.php**:
   - Created complete `view-request.php` that shows:
     - Full request details
     - CSR content and parsed details
     - Approve/Reject buttons
     - Copy CSR functionality

3. **BASE64 PEM CSR Import**:
   - Added `submitCSRRequest()` function to ca-functions.php
   - Added CSR import form to index.php
   - Extracts subject information from imported CSRs
   - Handles imported CSRs differently (no private key)

4. **Additional Improvements**:
   - Better error handling and logging throughout
   - Updated download.php to handle certificates without private keys
   - Added diagnostic tools for troubleshooting
   - Improved permission handling
   - Added comprehensive documentation

The system now supports:
- Manual certificate request creation with automatic key generation
- Importing existing CSRs in BASE64 PEM format
- Proper serial number incrementing
- Complete request lifecycle management
- Secure web-based administration

All files are ready to use and include proper error handling, logging, and security measures.