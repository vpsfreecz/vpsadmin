<?php

include '/etc/vpsadmin/config.php';

session_start();

include WEBUI_ROOT . 'lib/functions.lib.php';
include WEBUI_ROOT . 'lib/security.lib.php';
include WEBUI_ROOT . 'lib/login.lib.php';

header('Content-Type: application/json');

function session_time_zone_reply($status, $payload)
{
    http_response_code($status);
    echo json_encode($payload);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    session_time_zone_reply(405, ['message' => 'Method not allowed']);
}

if (!isLoggedIn()) {
    session_time_zone_reply(401, ['message' => 'Authentication required']);
}

try {
    csrf_check('session_time_zone');
} catch (CsrfTokenInvalid $e) {
    session_time_zone_reply(403, ['message' => 'Invalid CSRF token']);
}

$timeZone = $_POST['time_zone'] ?? null;

if ($timeZone === '') {
    $timeZone = null;
}

if (!valid_time_zone($timeZone)) {
    session_time_zone_reply(422, ['message' => 'Invalid time zone']);
}

$_SESSION['user']['time_zone'] = $timeZone;
set_request_time_zone($timeZone);

session_time_zone_reply(200, [
    'ok' => true,
    'time_zone' => $timeZone,
]);
