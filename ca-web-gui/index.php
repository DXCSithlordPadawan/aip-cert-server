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
                
            case 'submit_csr':
                $result = $ca->submitCSRRequest($_POST['csr_pem'], $_POST['cert_type']);
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
    <title>Munroe Certificate Authority Management</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <div class="container">
        <header>
            <h1>Tenant Certificate Authority Management System</h1>
            <nav>
                <ul>
                    <li><a href="#request">Submit Request</a></li>
                    <li><a href="#import">Import CSR</a></li>
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
                           placeholder="e.g., GB">
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

        <!-- Import CSR Section -->
        <section id="import" class="card">
            <h2>Import Tenant Certificate Signing Request (CSR)</h2>
            <p>Import an existing CSR in BASE64 PEM format</p>
            <form method="POST" action="">
                <input type="hidden" name="action" value="submit_csr">
                
                <div class="form-group">
                    <label>Certificate Type:</label>
                    <select name="cert_type" required>
                        <option value="server">Server Certificate</option>
                        <option value="client">Client Certificate</option>
                        <option value="code_signing">Code Signing Certificate</option>
                    </select>
                </div>
                
                <div class="form-group">
                    <label>CSR (PEM format):</label>
                    <textarea name="csr_pem" rows="15" required 
                              placeholder="-----BEGIN CERTIFICATE REQUEST-----
MIICvDCCAaQCAQAwdzELMAkGA1UEBhMCVVMxDTALBgNVBAgMBFV0YWgxDzANBgNV
...
-----END CERTIFICATE REQUEST-----"></textarea>
                </div>
                
                <button type="submit" class="btn btn-primary">Import CSR</button>
            </form>
        </section>

        <!-- Pending Requests -->
        <section id="pending" class="card">
            <h2>Pending Tenant Certificate Requests</h2>
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
                            <th>Source</th>
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
                                <td><?php echo isset($request['csr_source']) && $request['csr_source'] === 'pem_import' ? 'Imported' : 'Generated'; ?></td>
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
            <h2>Issued Tenant Certificates</h2>
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