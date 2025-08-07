<?php
/**
 * Certificate Authority API Endpoint
 * Allows automated certificate requests and downloads from trusted servers
 * 
 * Usage: curl -X POST https://cert-server/api.php -H "Content-Type: application/json" -d '{...}'
 * Author: Iain Reid / Assistant
 * Created: 2025-08-06
 */

// Disable output buffering for streaming responses
while (ob_get_level()) {
    ob_end_clean();
}

// Set headers for JSON responses
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-API-Key');

// Handle preflight requests
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require_once 'ca-functions.php';

class CertificateAPI {
    private $ca;
    private $config;
    
    public function __construct() {
        $this->ca = new CertificateAuthority('/mnt/ca-data');
        $this->loadConfig();
    }
    
    private function loadConfig() {
        // Load configuration from environment or config file
        $this->config = [
            // API key for authentication - change this to a strong random value
            'api_key' => getenv('CA_API_KEY') ?: 'changeme-secure-api-key-here',
            
            // Allowed IP ranges (CIDR notation)
            'allowed_networks' => [
                '192.168.0.0/16',    // Internal network
                '10.0.0.0/8',        // Private network
                '172.16.0.0/12',     // Private network
                '127.0.0.1/32'       // Localhost
            ],
            
            // Auto-approval settings
            'auto_approve' => true,
            'max_cert_days' => 365,
            
            // Rate limiting
            'rate_limit_per_hour' => 10
        ];
    }
    
    public function handleRequest() {
        try {
            // Validate authentication and authorization
            if (!$this->validateAuth()) {
                return $this->errorResponse('Unauthorized', 401);
            }
            
            // Rate limiting check
            if (!$this->checkRateLimit()) {
                return $this->errorResponse('Rate limit exceeded', 429);
            }
            
            $method = $_SERVER['REQUEST_METHOD'];
            $path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
            
            // Route requests
            switch ($method) {
                case 'POST':
                    if (strpos($path, '/submit') !== false) {
                        return $this->submitCertificateRequest();
                    } elseif (strpos($path, '/submit-csr') !== false) {
                        return $this->submitCSRRequest();
                    }
                    break;
                    
                case 'GET':
                    if (strpos($path, '/download') !== false) {
                        return $this->downloadCertificate();
                    } elseif (strpos($path, '/status') !== false) {
                        return $this->getRequestStatus();
                    }
                    break;
            }
            
            return $this->errorResponse('Endpoint not found', 404);
            
        } catch (Exception $e) {
            error_log("API Error: " . $e->getMessage());
            return $this->errorResponse('Internal server error', 500);
        }
    }
    
    private function validateAuth() {
        // Check API key
        $apiKey = $_SERVER['HTTP_X_API_KEY'] ?? $_SERVER['HTTP_AUTHORIZATION'] ?? '';
        if (strpos($apiKey, 'Bearer ') === 0) {
            $apiKey = substr($apiKey, 7);
        }
        
        if ($apiKey !== $this->config['api_key']) {
            error_log("Invalid API key attempt from " . $_SERVER['REMOTE_ADDR']);
            return false;
        }
        
        // Check IP whitelist
        $clientIP = $_SERVER['REMOTE_ADDR'];
        $allowed = false;
        
        foreach ($this->config['allowed_networks'] as $network) {
            if ($this->ipInRange($clientIP, $network)) {
                $allowed = true;
                break;
            }
        }
        
        if (!$allowed) {
            error_log("Unauthorized IP attempt: " . $clientIP);
            return false;
        }
        
        return true;
    }
    
    private function ipInRange($ip, $range) {
        if (strpos($range, '/') === false) {
            return $ip === $range;
        }
        
        list($subnet, $bits) = explode('/', $range);
        $ip = ip2long($ip);
        $subnet = ip2long($subnet);
        $mask = -1 << (32 - $bits);
        $subnet &= $mask;
        
        return ($ip & $mask) === $subnet;
    }
    
    private function checkRateLimit() {
        $clientIP = $_SERVER['REMOTE_ADDR'];
        $cacheFile = '/tmp/ca_rate_limit_' . md5($clientIP);
        $maxRequests = $this->config['rate_limit_per_hour'];
        
        $requests = [];
        if (file_exists($cacheFile)) {
            $requests = json_decode(file_get_contents($cacheFile), true) ?: [];
        }
        
        $currentTime = time();
        $oneHourAgo = $currentTime - 3600;
        
        // Clean old requests
        $requests = array_filter($requests, function($timestamp) use ($oneHourAgo) {
            return $timestamp > $oneHourAgo;
        });
        
        if (count($requests) >= $maxRequests) {
            return false;
        }
        
        // Add current request
        $requests[] = $currentTime;
        file_put_contents($cacheFile, json_encode($requests));
        
        return true;
    }
    
    private function submitCertificateRequest() {
        $input = json_decode(file_get_contents('php://input'), true);
        
        if (!$input) {
            return $this->errorResponse('Invalid JSON input', 400);
        }
        
        // Validate required fields
        $required = ['common_name', 'organization', 'country', 'state', 'locality', 'email'];
        foreach ($required as $field) {
            if (empty($input[$field])) {
                return $this->errorResponse("Missing required field: $field", 400);
            }
        }
        
        // Set defaults
        $requestData = array_merge([
            'cert_type' => 'server',
            'org_unit' => 'EntServ D S',
            'san' => '',
            'key_type' => 'ecdsa'
        ], $input);
        
        // Submit request
        $result = $this->ca->submitRequest($requestData);
        
        if (!$result['success']) {
            return $this->errorResponse($result['message'], 400);
        }
        
        // Extract request ID from message
        preg_match('/Request ID: ([a-f0-9_]+)/', $result['message'], $matches);
        $requestId = $matches[1] ?? null;
        
        $response = [
            'success' => true,
            'message' => $result['message'],
            'request_id' => $requestId
        ];
        
        // Auto-approve if configured
        if ($this->config['auto_approve'] && $requestId) {
            $approveResult = $this->ca->approveRequest($requestId);
            
            if ($approveResult['success']) {
                // Extract serial number
                preg_match('/Serial: ([A-F0-9]+)/', $approveResult['message'], $serialMatches);
                $serial = $serialMatches[1] ?? null;
                
                $response['auto_approved'] = true;
                $response['serial'] = $serial;
                $response['message'] .= ' Certificate automatically approved.';
                
                // Add download URLs
                if ($serial) {
                    $baseUrl = $this->getBaseUrl();
                    $response['downloads'] = [
                        'certificate' => $baseUrl . '/api.php/download?type=cert&serial=' . $serial,
                        'chain' => $baseUrl . '/api.php/download?type=chain&serial=' . $serial,
                        'bundle' => $baseUrl . '/api.php/download?type=bundle&serial=' . $serial,
                        'private_key' => $baseUrl . '/api.php/download?type=key&serial=' . $serial
                    ];
                }
            } else {
                $response['auto_approve_error'] = $approveResult['message'];
            }
        }
        
        return $this->jsonResponse($response);
    }
    
    private function submitCSRRequest() {
        $input = json_decode(file_get_contents('php://input'), true);
        
        if (!$input || empty($input['csr_pem'])) {
            return $this->errorResponse('CSR PEM data required', 400);
        }
        
        $certType = $input['cert_type'] ?? 'server';
        
        $result = $this->ca->submitCSRRequest($input['csr_pem'], $certType);
        
        if (!$result['success']) {
            return $this->errorResponse($result['message'], 400);
        }
        
        // Extract request ID
        preg_match('/Request ID: ([a-f0-9_]+)/', $result['message'], $matches);
        $requestId = $matches[1] ?? null;
        
        $response = [
            'success' => true,
            'message' => $result['message'],
            'request_id' => $requestId
        ];
        
        // Auto-approve if configured
        if ($this->config['auto_approve'] && $requestId) {
            $approveResult = $this->ca->approveRequest($requestId);
            
            if ($approveResult['success']) {
                preg_match('/Serial: ([A-F0-9]+)/', $approveResult['message'], $serialMatches);
                $serial = $serialMatches[1] ?? null;
                
                $response['auto_approved'] = true;
                $response['serial'] = $serial;
                $response['message'] .= ' Certificate automatically approved.';
                
                if ($serial) {
                    $baseUrl = $this->getBaseUrl();
                    $response['downloads'] = [
                        'certificate' => $baseUrl . '/api.php/download?type=cert&serial=' . $serial,
                        'chain' => $baseUrl . '/api.php/download?type=chain&serial=' . $serial
                        // Note: No private key for imported CSRs
                    ];
                }
            }
        }
        
        return $this->jsonResponse($response);
    }
    
    private function downloadCertificate() {
        $type = $_GET['type'] ?? '';
        $serial = $_GET['serial'] ?? '';
        
        $caRoot = '/mnt/ca-data';
        
        switch ($type) {
            case 'root-ca':
                return $this->downloadFile(
                    $caRoot . '/root/certs/ca.cert.pem',
                    'root-ca.crt',
                    'application/x-x509-ca-cert'
                );
                
            case 'intermediate-ca':
                return $this->downloadFile(
                    $caRoot . '/intermediate/certs/intermediate.cert.pem',
                    'intermediate-ca.crt',
                    'application/x-x509-ca-cert'
                );
                
            case 'ca-chain':
                return $this->downloadFile(
                    $caRoot . '/intermediate/certs/ca-chain.cert.pem',
                    'ca-chain.pem',
                    'application/x-pem-file'
                );
                
            case 'cert':
                if (empty($serial)) {
                    return $this->errorResponse('Serial number required', 400);
                }
                return $this->downloadFile(
                    $caRoot . '/issued/' . $serial . '/certificate.crt',
                    $serial . '.crt',
                    'application/x-x509-cert'
                );
                
            case 'chain':
                if (empty($serial)) {
                    return $this->errorResponse('Serial number required', 400);
                }
                return $this->downloadFile(
                    $caRoot . '/issued/' . $serial . '/chain.pem',
                    $serial . '-chain.pem',
                    'application/x-pem-file'
                );
                
            case 'key':
                if (empty($serial)) {
                    return $this->errorResponse('Serial number required', 400);
                }
                return $this->downloadFile(
                    $caRoot . '/issued/' . $serial . '/private.key',
                    $serial . '.key',
                    'application/x-pem-file'
                );
                
            case 'bundle':
                if (empty($serial)) {
                    return $this->errorResponse('Serial number required', 400);
                }
                return $this->downloadBundle($caRoot, $serial);
                
            default:
                return $this->errorResponse('Invalid download type', 400);
        }
    }
    
    private function downloadFile($filePath, $filename, $contentType) {
        if (!file_exists($filePath)) {
            return $this->errorResponse('File not found', 404);
        }
        
        // For API downloads, return as JSON with base64 content
        $content = file_get_contents($filePath);
        
        return $this->jsonResponse([
            'success' => true,
            'filename' => $filename,
            'content_type' => $contentType,
            'content' => base64_encode($content),
            'size' => strlen($content)
        ]);
    }
    
    private function downloadBundle($caRoot, $serial) {
        $certFile = $caRoot . '/issued/' . $serial . '/certificate.crt';
        $keyFile = $caRoot . '/issued/' . $serial . '/private.key';
        $chainFile = $caRoot . '/issued/' . $serial . '/chain.pem';
        
        if (!file_exists($certFile)) {
            return $this->errorResponse('Certificate not found', 404);
        }
        
        $bundle = file_get_contents($certFile) . "\n";
        
        if (file_exists($keyFile)) {
            $bundle .= file_get_contents($keyFile) . "\n";
            $filename = $serial . '-bundle.pem';
        } else {
            $filename = $serial . '-cert-only.pem';
        }
        
        if (file_exists($chainFile)) {
            $bundle .= file_get_contents($chainFile);
        }
        
        return $this->jsonResponse([
            'success' => true,
            'filename' => $filename,
            'content_type' => 'application/x-pem-file',
            'content' => base64_encode($bundle),
            'size' => strlen($bundle)
        ]);
    }
    
    private function getRequestStatus() {
        $requestId = $_GET['request_id'] ?? '';
        
        if (empty($requestId)) {
            return $this->errorResponse('Request ID required', 400);
        }
        
        $details = $this->ca->getRequestDetails($requestId);
        
        if (!$details) {
            return $this->errorResponse('Request not found', 404);
        }
        
        // Remove sensitive information for API response
        unset($details['csr_content']);
        unset($details['csr_details']);
        
        return $this->jsonResponse([
            'success' => true,
            'request' => $details
        ]);
    }
    
    private function getBaseUrl() {
        $protocol = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
        $host = $_SERVER['HTTP_HOST'];
        return $protocol . '://' . $host;
    }
    
    private function jsonResponse($data, $code = 200) {
        http_response_code($code);
        echo json_encode($data, JSON_PRETTY_PRINT);
        exit;
    }
    
    private function errorResponse($message, $code = 400) {
        return $this->jsonResponse([
            'success' => false,
            'error' => $message
        ], $code);
    }
}

// Initialize and handle request
$api = new CertificateAPI();
$api->handleRequest();
?>