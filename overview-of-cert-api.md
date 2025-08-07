Now I'll create comprehensive documentation for the API system:I've created a comprehensive Certificate Authority API system with the following components:

## **Key Features:**

### **1. API Endpoint (api.php)**
- **RESTful API** with JSON responses
- **Authentication** via API keys
- **IP whitelisting** for network security
- **Rate limiting** to prevent abuse
- **Automatic approval** for trusted servers
- **Multiple certificate types** (server, client, code signing)

### **2. Client Script (request-cert.sh)**
- **Command-line tool** for easy integration
- **Automatic certificate requests** with key generation
- **CSR import support** for existing keys
- **Batch downloads** of certificate files
- **Configuration file support**
- **Verbose logging** and error handling

### **3. Installation System**
- **Automated setup** for both server and client
- **Dependency checking** and installation
- **Secure configuration** generation
- **Testing and validation**

## **Security Features:**

1. **Strong Authentication**: API key-based with secure generation
2. **Network Access Control**: CIDR-based IP whitelisting
3. **Rate Limiting**: Configurable per-IP limits
4. **File Permissions**: Proper certificate and key protection
5. **Audit Logging**: Comprehensive request logging

## **Usage Examples:**

### **Simple Certificate Request:**
```bash
request-cert request \
    --common-name web.example.com \
    --email admin@example.com \
    --san "www.example.com,api.example.com"
```

### **Automated Server Setup:**
```bash
# Install client
./install-ca-api.sh client

# Request certificate for this server
request-cert request \
    --common-name $(hostname -f) \
    --email admin@$(hostname -d) \
    --output /etc/ssl/local-ca
```

## **Installation Steps:**

1. **On CA Server:**
   ```bash
   # Add api.php to your existing CA web interface
   ./install-ca-api.sh server
   ```

2. **On Client Servers:**
   ```bash
   # Install client tools and configuration
   ./install-ca-api.sh client
   ```

## **Integration Benefits:**

- **Automatic Approval**: No manual intervention needed
- **Bulk Operations**: Request certificates for multiple servers
- **Service Integration**: Easy Apache/Nginx configuration
- **Automation Ready**: Cron jobs and systemd timers
- **Error Recovery**: Robust error handling and retries

The system is designed to work seamlessly with your existing CA infrastructure while providing enterprise-grade automation and security features. All certificates are automatically approved for servers within your trusted network ranges, making it perfect for internal infrastructure automation.