Now let me create an improved configuration file with all the amendable parameters:Now let me create a debug/diagnostic script to help troubleshoot issues:Now let me create a README file to document the setup and usage:## Summary

I've analyzed your scripts and identified the main issue: **The PHP scripts are failing to create certificate requests due to file permission and path issues**. Here are the key fixes I've implemented:

### Main Issues Fixed:

1. **Permission Problems**: 
   - Added proper ownership (`www-data`) for the requests and issued directories
   - Added sudo permissions for www-data to run OpenSSL CA commands
   - Created a systemd service to ensure permissions persist after reboot

2. **PHP Script Issues**:
   - Added error logging throughout the CA functions
   - Fixed the CSR configuration generation
   - Ensured proper error handling and return messages
   - Added directory existence checks before operations
   
3. **Container Configuration**:
   - Ensured privileged container creation (`--unprivileged 0`)
   - Fixed NFS mount using bind mount approach in container config
   - Added proper error checking for NFS storage

4. **Web Server Setup**:
   - Added PHP error logging configuration
   - Created test-permissions.php for diagnostics
   - Ensured Apache has proper SSL configuration
   - Added better error handling in the setup process

5. **CA Operations**:
   - Fixed the OpenSSL configuration files for all certificate types
   - Added proper extensions handling for server, client, and code signing certificates
   - Ensured certificate chains are created correctly
   - Added sudo prefix for CA signing operations

### Key Improvements:

1. **Better Error Handling**: All scripts now have comprehensive error checking and logging
2. **Diagnostics Tool**: Created `ca-diagnostics.sh` to help troubleshoot issues
3. **Persistent Storage**: Properly configured NFS mount with bind mount in container
4. **Security**: Added sudo configuration for www-data to run necessary OpenSSL commands

### How to Use the Fixed Scripts:

1. **Setup Process**:
   ```bash
   # Create directory structure
   mkdir -p ca-server-setup/ca-web-gui
   
   # Place all files in correct locations
   # Make scripts executable
   chmod +x create-ca-container.sh setup-ca-server.sh ca-diagnostics.sh
   
   # Run the setup
   sudo ./create-ca-container.sh
   ```

2. **Verify Installation**:
   ```bash
   # Run diagnostics
   sudo ./ca-diagnostics.sh
   
   # Check web interface
   curl -k https://192.168.0.122/test-permissions.php
   ```

3. **Access Web Interface**:
   - Navigate to: `https://192.168.0.122`
   - Login with: admin / CaAdmin2024!
   - Submit a test certificate request

### What the Fixed Scripts Do:

1. **create-ca-container.sh**:
   - Checks for existing NFS storage before creating
   - Creates privileged container with proper network settings
   - Sets up bind mount for persistent storage
   - Copies all files and runs setup inside container

2. **setup-ca-server.sh**:
   - Installs all required packages
   - Creates CA directory structure with correct permissions
   - Generates ECDSA Root and Intermediate CAs
   - Configures Apache with HTTPS
   - Sets up PHP with error logging
   - Creates systemd service for permission persistence

3. **ca-functions.php**:
   - Properly creates request directories
   - Generates CSR with correct configuration
   - Handles certificate signing with sudo
   - Manages request lifecycle (pending → approved/rejected)
   - Creates certificate chains automatically

4. **ca-diagnostics.sh**:
   - Checks container status
   - Verifies directory structure and permissions
   - Tests CA certificates
   - Shows pending requests
   - Displays recent errors from logs

### Testing the Fix:

After installation, test that certificate requests work:

1. Access `https://192.168.0.122/test-permissions.php` to verify permissions
2. Submit a test certificate request through the web interface
3. Check that the request appears in the pending list
4. Approve the request and verify certificate generation

### If Issues Persist:

1. Check the diagnostic output:
   ```bash
   sudo ./ca-diagnostics.sh
   ```

2. Monitor PHP errors in real-time:
   ```bash
   pct exec 200 -- tail -f /var/log/php/errors.log
   ```

3. Check Apache errors:
   ```bash
   pct exec 200 -- tail -f /var/log/apache2/ca-gui-error.log
   ```

4. Verify NFS mount is working:
   ```bash
   pct exec 200 -- df -h /mnt/ca-data
   pct exec 200 -- touch /mnt/ca-data/test.txt
   ```

The scripts should now properly handle certificate requests with persistent storage on NFS. The main issue was that the web server user (www-data) didn't have proper permissions to create directories and run OpenSSL CA commands, which has been fixed in these updated scripts.