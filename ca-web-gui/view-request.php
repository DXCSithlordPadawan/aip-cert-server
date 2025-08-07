<?php
session_start();
require_once 'ca-functions.php';

$ca = new CertificateAuthority('/mnt/ca-data');

// Get request ID from URL
$requestId = $_GET['id'] ?? '';

if (empty($requestId)) {
    header('Location: index.php');
    exit;
}

// Get request details
$requestDetails = $ca->getRequestDetails($requestId);

if (!$requestDetails) {
    $error = "Request not found";
}
?>

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>View Certificate Request - <?php echo htmlspecialchars($requestId); ?></title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <div class="container">
        <header>
            <h1>Tenant Certificate Request Details</h1>
            <nav>
                <ul>
                    <li><a href="index.php">← Back to Dashboard</a></li>
                </ul>
            </nav>
        </header>

        <?php if (isset($error)): ?>
            <div class="message error">
                <?php echo htmlspecialchars($error); ?>
            </div>
        <?php else: ?>
            <section class="card">
                <h2>Request Information</h2>
                <table class="detail-table">
                    <tr>
                        <th>Request ID:</th>
                        <td><?php echo htmlspecialchars($requestDetails['id']); ?></td>
                    </tr>
                    <tr>
                        <th>Status:</th>
                        <td>
                            <span class="status-badge status-<?php echo $requestDetails['status']; ?>">
                                <?php echo ucfirst($requestDetails['status']); ?>
                            </span>
                        </td>
                    </tr>
                    <tr>
                        <th>Type:</th>
                        <td><?php echo htmlspecialchars(ucfirst(str_replace('_', ' ', $requestDetails['type']))); ?></td>
                    </tr>
                    <tr>
                        <th>Submitted:</th>
                        <td><?php echo htmlspecialchars($requestDetails['submitted']); ?></td>
                    </tr>
                    <tr>
                        <th>Common Name:</th>
                        <td><?php echo htmlspecialchars($requestDetails['common_name']); ?></td>
                    </tr>
                    <tr>
                        <th>Organization:</th>
                        <td><?php echo htmlspecialchars($requestDetails['organization']); ?></td>
                    </tr>
                    <tr>
                        <th>Organizational Unit:</th>
                        <td><?php echo htmlspecialchars($requestDetails['org_unit'] ?: 'N/A'); ?></td>
                    </tr>
                    <tr>
                        <th>Country:</th>
                        <td><?php echo htmlspecialchars($requestDetails['country']); ?></td>
                    </tr>
                    <tr>
                        <th>State/Province:</th>
                        <td><?php echo htmlspecialchars($requestDetails['state']); ?></td>
                    </tr>
                    <tr>
                        <th>City:</th>
                        <td><?php echo htmlspecialchars($requestDetails['locality']); ?></td>
                    </tr>
                    <tr>
                        <th>Email:</th>
                        <td><?php echo htmlspecialchars($requestDetails['email']); ?></td>
                    </tr>
                    <tr>
                        <th>Key Type:</th>
                        <td><?php echo htmlspecialchars(strtoupper($requestDetails['key_type'])); ?></td>
                    </tr>
                    <?php if (!empty($requestDetails['san'])): ?>
                    <tr>
                        <th>Subject Alternative Names:</th>
                        <td><?php echo htmlspecialchars($requestDetails['san']); ?></td>
                    </tr>
                    <?php endif; ?>
                </table>
            </section>

            <?php if (isset($requestDetails['csr_content'])): ?>
            <section class="card">
                <h2>Tenant Certificate Signing Request (CSR)</h2>
                <div class="csr-display">
                    <pre><?php echo htmlspecialchars($requestDetails['csr_content']); ?></pre>
                    <button onclick="copyCsr()" class="btn btn-primary btn-sm">Copy CSR</button>
                </div>
            </section>
            <?php endif; ?>

            <?php if (isset($requestDetails['csr_details'])): ?>
            <section class="card">
                <h2>CSR Details</h2>
                <pre><?php echo htmlspecialchars($requestDetails['csr_details']); ?></pre>
            </section>
            <?php endif; ?>

            <?php if ($requestDetails['status'] === 'pending'): ?>
            <section class="card">
                <h2>Actions</h2>
                <form method="POST" action="index.php" style="display: inline;">
                    <input type="hidden" name="action" value="approve_request">
                    <input type="hidden" name="request_id" value="<?php echo $requestDetails['id']; ?>">
                    <button type="submit" class="btn btn-success">Approve Request</button>
                </form>
                <form method="POST" action="index.php" style="display: inline;">
                    <input type="hidden" name="action" value="reject_request">
                    <input type="hidden" name="request_id" value="<?php echo $requestDetails['id']; ?>">
                    <button type="submit" class="btn btn-danger">Reject Request</button>
                </form>
            </section>
            <?php endif; ?>
        <?php endif; ?>
    </div>

    <script>
    function copyCsr() {
        const csr = document.querySelector('.csr-display pre').textContent;
        navigator.clipboard.writeText(csr).then(() => {
            alert('CSR copied to clipboard!');
        });
    }
    </script>
</body>
</html>