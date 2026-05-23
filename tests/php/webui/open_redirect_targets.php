<?php

// Regression tests for redirect target sanitization used by login and
// language-switch flows.

require __DIR__ . '/../../../webui/lib/functions.lib.php';
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

echo "Redirect targets are restricted to local URLs.\n";
