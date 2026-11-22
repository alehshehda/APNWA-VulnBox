<?php
declare(strict_types=1);

/**
 * VulnBox Web Diagnostics & Log Inspection Portal (Port 8080)
 * Educational laboratory component for system configuration verification.
 */

header('Content-Type: text/plain; charset=utf-8');

if (isset($_GET['log']) && $_GET['log'] !== '') {
    $rawLog = (string)$_GET['log'];
    // Intentional single-pass path normalization weakness for educational analysis (CWE-22)
    $sanitizedLog = str_replace('../', '', $rawLog);
    $baseDir = '/var/log/webapp/';
    $targetPath = $baseDir . $sanitizedLog;

    echo "[VulnBox Log Viewer] Requested path: " . $targetPath . "\n\n";
    if (is_file($targetPath) && is_readable($targetPath)) {
        echo file_get_contents($targetPath);
    } else {
        http_response_code(404);
        echo "Error: Log file not found or not readable.\n";
    }
    exit(0);
}

if (isset($_GET['proxy_path']) && $_GET['proxy_path'] !== '') {
    $endpoint = '/' . ltrim((string)$_GET['proxy_path'], '/');
    $token = (string)($_GET['token'] ?? $_SERVER['HTTP_X_INTERNAL_TOKEN'] ?? '');
    $apiUrl = 'http://127.0.0.1:5000' . $endpoint;

    $headers = [
        'Accept: application/json',
    ];
    if ($token !== '') {
        $headers[] = 'X-Internal-Token: ' . $token;
    }

    $method = 'GET';
    $content = null;

    if (isset($_POST['ssh_key']) || isset($_GET['ssh_key'])) {
        $sshKey = (string)($_POST['ssh_key'] ?? $_GET['ssh_key']);
        $method = 'POST';
        $headers[] = 'Content-Type: application/json';
        $content = json_encode(['ssh_key' => $sshKey]);
    }

    $contextOptions = [
        'http' => [
            'method' => $method,
            'header' => implode("\r\n", $headers) . "\r\n",
            'timeout' => 3.0,
            'ignore_errors' => true,
        ],
    ];
    if ($content !== null) {
        $contextOptions['http']['content'] = $content;
    }

    $ctx = stream_context_create($contextOptions);
    $response = @file_get_contents($apiUrl, false, $ctx);

    if ($response === false) {
        http_response_code(502);
        echo "Error: Unable to reach internal management API at 127.0.0.1:5000.\n";
        exit(0);
    }

    echo $response . "\n";
    exit(0);
}

$module = $_GET['module'] ?? 'status';

if ($module === 'status') {
    echo "=== VulnBox Diagnostics Portal ===\n";
    echo "Service: vulnbox-web (Nginx + PHP-FPM)\n";
    echo "Status: ONLINE\n";
    echo "Base Log Directory: /var/log/webapp/\n";
    echo "Internal API Bridge: http://127.0.0.1:5000\n";
    echo "Usage:\n";
    echo "  ?module=status                     - Display service health summary\n";
    echo "  ?log=<filename>                    - View diagnostic log from /var/log/webapp/\n";
    echo "  ?proxy_path=<endpoint>&token=<tok> - Query local management API on 127.0.0.1:5000\n";
    exit(0);
}

echo "VulnBox Portal: Specify ?module=status, ?log=<file>, or ?proxy_path=<endpoint>\n";
