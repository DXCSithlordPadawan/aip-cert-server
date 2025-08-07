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
        $contentType = 'application/x-x509-ca-cert';
        break;
        
    case 'intermediate-ca':
        $file = $caRoot . '/intermediate/certs/intermediate.cert.pem';
        $filename = 'intermediate-ca.crt';
        $contentType = 'application/x-x509-ca-cert';
        break;
        
    case 'ca-chain':
        $file = $caRoot . '/intermediate/certs/ca-chain.cert.pem';
        $filename = 'ca-chain.pem';
        $contentType = 'application/x-pem-file';
        break;
        
    case 'cert':
        if (empty($serial)) {
            die('Serial number required');
        }
        $file = $caRoot . '/issued/' . $serial . '/certificate.crt';
        $filename = $serial . '.crt';
        $contentType = 'application/x-x509-cert';
        break;
        
    case 'chain':
        if (empty($serial)) {
            die('Serial number required');
        }
        $file = $caRoot . '/issued/' . $serial . '/chain.pem';
        $filename = $serial . '-chain.pem';
        $contentType = 'application/x-pem-file';
        break;
        
    case 'bundle':
        // Download certificate + private key bundle (if private key exists)
        if (empty($serial)) {
            die('Serial number required');
        }
        $certFile = $caRoot . '/issued/' . $serial . '/certificate.crt';
        $keyFile = $caRoot . '/issued/' . $serial . '/private.key';
        $chainFile = $caRoot . '/issued/' . $serial . '/chain.pem';
        
        if (!file_exists($certFile)) {
            die('Certificate not found');
        }
        
        // Check if private key exists (won't for imported CSRs)
        if (file_exists($keyFile)) {
            // Create bundle with cert + key + chain
            $bundle = file_get_contents($certFile) . "\n";
            $bundle .= file_get_contents($keyFile) . "\n";
            if (file_exists($chainFile)) {
                $bundle .= file_get_contents($chainFile);
            }
            $filename = $serial . '-bundle.pem';
        } else {
            // Just provide the certificate for imported CSRs
            $bundle = file_get_contents($certFile);
            $filename = $serial . '-cert-only.pem';
        }
        
        header('Content-Type: application/x-pem-file');
        header('Content-Disposition: attachment; filename="' . $filename . '"');
        header('Content-Length: ' . strlen($bundle));
        echo $bundle;
        exit;
        
    default:
        die('Invalid download type');
}

if (!file_exists($file)) {
    die('File not found');
}

// Send file
header('Content-Type: ' . $contentType);
header('Content-Disposition: attachment; filename="' . $filename . '"');
header('Content-Length: ' . filesize($file));
readfile($file);