<?php

// Regression tests for shared escaping/URL helpers used by the web UI XSS fixes.

require __DIR__ . '/../../../webui/lib/functions.lib.php';
require __DIR__ . '/../../../webui/lib/xtemplate.lib.php';
require __DIR__ . '/../../../webui/lib/login.lib.php';

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

function assert_contains($needle, $haystack, $message)
{
    if (!str_contains($haystack, $needle)) {
        fwrite(STDERR, $message . "\nMissing: " . $needle . "\nIn: " . $haystack . "\n");
        exit(1);
    }
}

function assert_not_contains($needle, $haystack, $message)
{
    if (str_contains($haystack, $needle)) {
        fwrite(STDERR, $message . "\nFound: " . $needle . "\nIn: " . $haystack . "\n");
        exit(1);
    }
}

$payload = '" onclick="alert(1)"><script>alert(2)</script>';
assert_same(
    '&quot; onclick=&quot;alert(1)&quot;&gt;&lt;script&gt;alert(2)&lt;/script&gt;',
    h($payload),
    'h() must escape quotes and HTML markup.'
);

assert_same('?page=', local_redirect_target($payload), 'Attribute-breaking return target was accepted.');
assert_same('?page=cluster', local_redirect_target('?page=cluster'), 'Local return target was rejected.');

$xtpl = new XTemplate('', '', null, 'main', false);
$xtpl->sbar_add('Back', $payload);
assert_same('?page=', $xtpl->vars['SBI_LINK'], 'Sidebar link did not fall back for unsafe target.');

$xtpl->sbar_add('Back', '?page=history&list=1');
assert_same('?page=history&amp;list=1', $xtpl->vars['SBI_LINK'], 'Sidebar href was not HTML-escaped.');

$xtpl->sbar_add_trusted('Console action', "javascript:vps_do('start');");
assert_same(
    'javascript:vps_do(&#039;start&#039;);',
    $xtpl->vars['SBI_LINK'],
    'Trusted sidebar href was not escaped without local URL validation.'
);

$xtpl->form_create('?page=cluster&type=' . $payload, 'post" autofocus="autofocus', 'x"><script>', false);
$form = $xtpl->vars['TABLE_FORM_BEGIN'];
assert_contains('&quot;', $form, 'Form attributes were not escaped.');
assert_not_contains('<script>', $form, 'Form opening tag contains raw script markup.');
assert_not_contains('autofocus="autofocus"', $form, 'Form method broke out of its attribute.');

$_SERVER = [
    'HTTP_X_FORWARDED_HOST' => 'victim.example"+alert(1)+"',
    'HTTP_HOST' => 'webui.example.test',
    'SERVER_NAME' => 'fallback.example.test',
    'SERVER_PORT' => '80',
];
assert_same('http://webui.example.test', getSelfUri(), 'Invalid forwarded host was trusted.');

$_SERVER = [
    'HTTP_X_FORWARDED_HOST' => 'proxy.example.test:8443',
    'HTTP_HOST' => 'webui.example.test',
    'HTTP_X_FORWARDED_PROTO' => 'https',
    'SERVER_NAME' => 'fallback.example.test',
    'SERVER_PORT' => '80',
];
assert_same('https://proxy.example.test:8443', getSelfUri(), 'Valid forwarded host was rejected.');

echo "Shared XSS helpers escape attributes and host-derived URLs.\n";
