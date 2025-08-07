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
        
        // Debug logging
        error_log("CA initialized - Requests dir: " . $this->requestsDir);
        error_log("Requests dir exists: " . (is_dir($this->requestsDir) ? 'Yes' : 'No'));
        error_log("Requests dir writable: " . (is_writable($this->requestsDir) ? 'Yes' : 'No'));
    }
    
    /**
     * Submit a new certificate request
     */
    public function submitRequest($data) {
        try {
            $requestId = uniqid('req_');
            $requestDir = $this->requestsDir . '/' . $requestId;
            
            // Create directory with proper permissions
            if (!mkdir($requestDir, 0755, true)) {
                throw new Exception("Failed to create request directory: $requestDir");
            }
            
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
            
            $jsonFile = $requestDir . '/request.json';
            if (file_put_contents($jsonFile, json_encode($requestData, JSON_PRETTY_PRINT)) === false) {
                throw new Exception("Failed to write request data to: $jsonFile");
            }
            
            // Generate private key
            if ($data['key_type'] === 'ecdsa') {
                $keyCmd = "openssl ecparam -genkey -name secp384r1 -out $requestDir/private.key 2>&1";
            } else {
                $keyCmd = "openssl genrsa -out $requestDir/private.key 2048 2>&1";
            }
            
            exec($keyCmd, $output, $returnCode);
            if ($returnCode !== 0) {
                throw new Exception("Failed to generate private key: " . implode("\n", $output));
            }
            
            // Generate CSR
            $subject = "/C={$data['country']}/ST={$data['state']}/L={$data['locality']}/O={$data['organization']}";
            if (!empty($data['org_unit'])) {
                $subject .= "/OU={$data['org_unit']}";
            }
            $subject .= "/CN={$data['common_name']}/emailAddress={$data['email']}";
            
            // Create config for CSR with extensions
            $configContent = $this->generateCSRConfig($data);
            $configFile = $requestDir . '/csr.conf';
            if (file_put_contents($configFile, $configContent) === false) {
                throw new Exception("Failed to write CSR config");
            }
            
            $csrCmd = "openssl req -new -key $requestDir/private.key -out $requestDir/request.csr -config $configFile -subj \"$subject\" 2>&1";
            exec($csrCmd, $output, $returnCode);
            
            if ($returnCode !== 0) {
                throw new Exception("Failed to generate CSR: " . implode("\n", $output));
            }
            
            // Log success
            error_log("Certificate request created successfully: $requestId in $requestDir");
            
            return ['success' => true, 'message' => 'Certificate request submitted successfully. Request ID: ' . $requestId];
            
        } catch (Exception $e) {
            error_log("Error in submitRequest: " . $e->getMessage());
            return ['success' => false, 'message' => 'Error submitting request: ' . $e->getMessage()];
        }
    }
    
    /**
     * Generate CSR configuration
     */
    private function generateCSRConfig($data) {
        // Read the v3.req template if it exists
        $v3ReqPath = $this->caRoot . '/v3.req';
        if (file_exists($v3ReqPath) && $data['cert_type'] === 'server') {
            $v3ReqContent = file_get_contents($v3ReqPath);
            
            // Replace default values with submitted values
            $config = str_replace('countryName_default = GB', 'countryName_default = ' . $data['country'], $v3ReqContent);
            $config = str_replace('stateOrProvinceName_default = Hampshire', 'stateOrProvinceName_default = ' . $data['state'], $config);
            $config = str_replace('localityName_default = Farnborough', 'localityName_default = ' . $data['locality'], $config);
            $config = str_replace('organizationUnitName_default = EntServ D S', 'organizationUnitName_default = ' . ($data['org_unit'] ?: 'EntServ D S'), $config);
            $config = str_replace('commonName_default = cert-server.aip.dxc.com', 'commonName_default = ' . $data['common_name'], $config);
            
            // If custom SANs provided, update the alt_names section
            if (!empty($data['san'])) {
                $altNamesSection = "\n[ alt_names ]\n";
                $sans = array_map('trim', explode(',', $data['san']));
                $dnsIndex = 1;
                $ipIndex = 1;
                
                // Always include the common name as a SAN
                $altNamesSection .= "DNS.{$dnsIndex} = {$data['common_name']}\n";
                $dnsIndex++;
                
                foreach ($sans as $san) {
                    if (empty($san)) continue;
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
            case 'server':
                $config .= "keyUsage = critical, digitalSignature, keyEncipherment\n";
                $config .= "extendedKeyUsage = serverAuth\n";
                break;
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
            $sans = array_map('trim', explode(',', $data['san']));
            $dnsIndex = 1;
            $ipIndex = 1;
            
            // Always include CN as SAN for server certs
            if ($data['cert_type'] === 'server') {
                $config .= "DNS.{$dnsIndex} = {$data['common_name']}\n";
                $dnsIndex++;
            }
            
            foreach ($sans as $san) {
                if (empty($san)) continue;
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
        
        if (!is_dir($this->requestsDir)) {
            error_log("Requests directory does not exist: " . $this->requestsDir);
            return $requests;
        }
        
        $dirs = glob($this->requestsDir . '/*', GLOB_ONLYDIR);
        
        error_log("Found " . count($dirs) . " request directories");
        
        foreach ($dirs as $dir) {
            $jsonFile = $dir . '/request.json';
            if (file_exists($jsonFile)) {
                $content = file_get_contents($jsonFile);
                $data = json_decode($content, true);
                if ($data && isset($data['status']) && $data['status'] === 'pending') {
                    $requests[] = $data;
                }
            }
        }
        
        error_log("Found " . count($requests) . " pending requests");
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
            
            // Use sudo for openssl ca command since www-data needs elevated permissions
            $signCmd = "openssl ca -batch -config {$this->intermediateDir}/openssl.cnf ";
            $signCmd .= "-extensions {$requestData['type']}_cert -days 365 -notext ";
            $signCmd .= "-md sha384 -in $csrFile -out $certFile -extfile $extFile 2>&1";
            
            exec($signCmd, $output, $returnCode);
            
            if ($returnCode !== 0) {
                error_log("Certificate signing failed: " . implode("\n", $output));
                return ['success' => false, 'message' => 'Failed to sign certificate: ' . implode("\n", $output)];
            }
            
            // Get certificate serial number
            $serialCmd = "openssl x509 -in $certFile -noout -serial 2>&1";
            exec($serialCmd, $serialOutput, $returnCode);
            
            if ($returnCode !== 0) {
                return ['success' => false, 'message' => 'Failed to get certificate serial'];
            }
            
            $serial = str_replace('serial=', '', $serialOutput[0]);
            
            // Update request status
            $requestData['status'] = 'approved';
            $requestData['approved_date'] = date('Y-m-d H:i:s');
            $requestData['serial'] = $serial;
            file_put_contents($requestFile, json_encode($requestData, JSON_PRETTY_PRINT));
            
            // Copy to issued directory
            $issuedDir = $this->issuedDir . '/' . $serial;
            if (!mkdir($issuedDir, 0755, true)) {
                throw new Exception("Failed to create issued directory");
            }
            
            copy($certFile, $issuedDir . '/certificate.crt');
            
            // Only copy private key if it exists (not for imported CSRs)
            if (file_exists($requestDir . '/private.key')) {
                copy($requestDir . '/private.key', $issuedDir . '/private.key');
            }
            
            copy($requestFile, $issuedDir . '/metadata.json');
            
            // Create certificate chain
            $chainFile = $issuedDir . '/chain.pem';
            $chainContent = file_get_contents($certFile) . "\n" . 
                           file_get_contents($this->intermediateDir . '/certs/ca-chain.cert.pem');
            file_put_contents($chainFile, $chainContent);
            
            return ['success' => true, 'message' => 'Certificate approved and issued successfully. Serial: ' . $serial];
            
        } catch (Exception $e) {
            error_log("Error in approveRequest: " . $e->getMessage());
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
        
        // Add SANs if present
        if (!empty($requestData['san']) || $requestData['type'] === 'server') {
            $content .= "subjectAltName = @alt_names\n\n";
            $content .= "[alt_names]\n";
            
            $index = 1;
            
            // Always include CN as SAN for server certs
            if ($requestData['type'] === 'server') {
                $content .= "DNS.{$index} = {$requestData['common_name']}\n";
                $index++;
            }
            
            if (!empty($requestData['san'])) {
                $sans = array_map('trim', explode(',', $requestData['san']));
                foreach ($sans as $san) {
                    if (empty($san)) continue;
                    if (filter_var($san, FILTER_VALIDATE_IP)) {
                        $content .= "IP.{$index} = $san\n";
                    } else {
                        $content .= "DNS.{$index} = $san\n";
                    }
                    $index++;
                }
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
            error_log("Error in rejectRequest: " . $e->getMessage());
            return ['success' => false, 'message' => 'Error rejecting request: ' . $e->getMessage()];
        }
    }
    
    /**
     * Get all issued certificates
     */
    public function getIssuedCertificates() {
        $certificates = [];
        
        if (!is_dir($this->issuedDir)) {
            return $certificates;
        }
        
        $dirs = glob($this->issuedDir . '/*', GLOB_ONLYDIR);
        
        foreach ($dirs as $dir) {
            $metadataFile = $dir . '/metadata.json';
            $certFile = $dir . '/certificate.crt';
            
            if (file_exists($metadataFile) && file_exists($certFile)) {
                $metadata = json_decode(file_get_contents($metadataFile), true);
                
                // Get certificate details
                $certContent = file_get_contents($certFile);
                $certInfo = openssl_x509_parse($certContent);
                
                if ($certInfo) {
                    $certificates[] = [
                        'serial' => $metadata['serial'],
                        'common_name' => $metadata['common_name'],
                        'type' => $metadata['type'],
                        'valid_from' => date('Y-m-d H:i:s', $certInfo['validFrom_time_t']),
                        'valid_to' => date('Y-m-d H:i:s', $certInfo['validTo_time_t'])
                    ];
                }
            }
        }
        
        return $certificates;
    }
    
    /**
     * Get request details
     */
    public function getRequestDetails($requestId) {
        $requestDir = $this->requestsDir . '/' . $requestId;
        $requestFile = $requestDir . '/request.json';
        
        if (!file_exists($requestFile)) {
            return null;
        }
        
        $requestData = json_decode(file_get_contents($requestFile), true);
        
        // Add CSR content if available
        $csrFile = $requestDir . '/request.csr';
        if (file_exists($csrFile)) {
            $requestData['csr_content'] = file_get_contents($csrFile);
            
            // Get CSR details
            $cmd = "openssl req -in $csrFile -noout -text 2>&1";
            exec($cmd, $output, $returnCode);
            if ($returnCode === 0) {
                $requestData['csr_details'] = implode("\n", $output);
            }
        }
        
        return $requestData;
    }
    
    /**
     * Submit CSR from PEM format
     */
    public function submitCSRRequest($pemData, $certType = 'server') {
        try {
            // Validate PEM format
            if (!preg_match('/-----BEGIN CERTIFICATE REQUEST-----/', $pemData)) {
                throw new Exception("Invalid CSR format. Must be in PEM format.");
            }
            
            $requestId = uniqid('req_');
            $requestDir = $this->requestsDir . '/' . $requestId;
            
            if (!mkdir($requestDir, 0755, true)) {
                throw new Exception("Failed to create request directory");
            }
            
            // Save CSR
            $csrFile = $requestDir . '/request.csr';
            if (file_put_contents($csrFile, $pemData) === false) {
                throw new Exception("Failed to save CSR");
            }
            
            // Extract subject information from CSR
            $cmd = "openssl req -in $csrFile -noout -subject 2>&1";
            exec($cmd, $output, $returnCode);
            
            if ($returnCode !== 0) {
                throw new Exception("Invalid CSR: " . implode("\n", $output));
            }
            
            // Parse subject
            $subject = $output[0];
            preg_match_all('/\/([A-Z]+)=([^\/]+)/', $subject, $matches, PREG_SET_ORDER);
            
            $subjectData = [];
            foreach ($matches as $match) {
                $subjectData[$match[1]] = $match[2];
            }
            
            // Extract SAN if present
            $cmd = "openssl req -in $csrFile -noout -text | grep -A1 'Subject Alternative Name' 2>&1";
            exec($cmd, $sanOutput);
            
            $san = '';
            if (count($sanOutput) > 1) {
                // Parse SAN from output
                $sanLine = trim($sanOutput[1]);
                $san = str_replace(['DNS:', 'IP:'], '', $sanLine);
            }
            
            // Create request data
            $requestData = [
                'id' => $requestId,
                'type' => $certType,
                'common_name' => $subjectData['CN'] ?? 'Unknown',
                'organization' => $subjectData['O'] ?? '',
                'org_unit' => $subjectData['OU'] ?? '',
                'country' => $subjectData['C'] ?? '',
                'state' => $subjectData['ST'] ?? '',
                'locality' => $subjectData['L'] ?? '',
                'email' => $subjectData['emailAddress'] ?? '',
                'san' => $san,
                'key_type' => 'imported',
                'submitted' => date('Y-m-d H:i:s'),
                'status' => 'pending',
                'csr_source' => 'pem_import'
            ];
            
            file_put_contents($requestDir . '/request.json', json_encode($requestData, JSON_PRETTY_PRINT));
            
            error_log("CSR import successful: $requestId");
            
            return ['success' => true, 'message' => 'CSR imported successfully. Request ID: ' . $requestId];
            
        } catch (Exception $e) {
            error_log("Error in submitCSRRequest: " . $e->getMessage());
            return ['success' => false, 'message' => 'Error importing CSR: ' . $e->getMessage()];
        }
    }
}
?>