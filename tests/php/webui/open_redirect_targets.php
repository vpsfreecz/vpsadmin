<?php

// Regression tests for redirect target sanitization used by login and
// language-switch flows.

require __DIR__ . '/../../../webui/lib/functions.lib.php';
require __DIR__ . '/../../../webui/lib/vps.lib.php';
require __DIR__ . '/../../../webui/lib/xtemplate.lib.php';

function assert_same($expected, $actual, $message)
{
    if ($expected !== $actual) {
        fwrite(
            STDERR,
            sprintf("%s\nExpected: %s\nActual:   %s\n", $message, $expected, $actual)
        );
        exit(1);
    }
}

$fallbackCases = [
    'https://attacker.example/path',
    '//attacker.example/path',
    '///attacker.example/path',
    '\\attacker.example\\path',
    'javascript:alert(1)',
    "?page=login\r\nLocation: https://attacker.example/",
    '',
    null,
];

foreach ($fallbackCases as $target) {
    assert_same('?page=', local_redirect_target($target), 'Unsafe redirect target was accepted.');
}

$localCases = [
    '?page=cluster' => '?page=cluster',
    './index.php?page=cluster' => './index.php?page=cluster',
    '/index.php?page=cluster' => '/index.php?page=cluster',
    'index.php?page=cluster' => 'index.php?page=cluster',
];

foreach ($localCases as $target => $expected) {
    assert_same($expected, local_redirect_target($target), 'Local redirect target was rejected.');
}

$xtpl = new XTemplate('', '', null, 'main', false);

$_GET = ['prev_url' => base64_encode('https://attacker.example/')];
assert_same('./index.php', $xtpl->get_prev_url(), 'External prev_url was accepted.');

$_GET = ['prev_url' => '%%%'];
assert_same('./index.php', $xtpl->get_prev_url(), 'Invalid prev_url was accepted.');

$_GET = ['prev_url' => base64_encode('?page=cluster')];
assert_same('?page=cluster', $xtpl->get_prev_url(), 'Local prev_url was rejected.');

$_GET = [];
assert_same('./index.php', $xtpl->get_prev_url(), 'Missing prev_url did not fall back.');

$_SERVER['HTTP_HOST'] = 'admin.example';

$_GET = ['action' => 'info'];
$_SERVER['REQUEST_URI'] = '/?page=adminvps&action=info&run=restart&veid=101&t=csrf';
$_SERVER['HTTP_REFERER'] = 'https://admin.example/?page=adminvps&action=info&veid=101';
assert_same(
    '/?page=adminvps&action=info&veid=101',
    vps_run_redirect_path(101),
    'Same-origin VPS detail referrer was not preserved.'
);

$_GET = [];
$_SERVER['REQUEST_URI'] = '/?page=adminvps&run=stop&veid=101&t=csrf';
$_SERVER['HTTP_REFERER'] = 'https://admin.example/?page=adminvps&action=list&from_id=100&limit=1';
assert_same(
    '/?page=adminvps&action=list&from_id=100&limit=1',
    vps_run_redirect_path(101),
    'Same-origin VPS list referrer was not preserved.'
);

$_GET = ['action' => 'info'];
$_SERVER['REQUEST_URI'] = '/?page=adminvps&action=info&run=restart&veid=101&t=csrf';
$_SERVER['HTTP_REFERER'] = 'https://admin.example/?page=adminvps&action=info&run=restart&veid=101&t=csrf';
assert_same(
    '?page=adminvps&action=info&veid=101',
    vps_run_redirect_path(101),
    'Current VPS action URL should fall back to VPS details.'
);

$_SERVER['HTTP_REFERER'] = 'https://attacker.example/?page=adminvps&action=info&veid=101';
assert_same(
    '?page=adminvps&action=info&veid=101',
    vps_run_redirect_path(101),
    'External VPS action referrer was accepted.'
);

echo "Redirect targets are restricted to local URLs.\n";
