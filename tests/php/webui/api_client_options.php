<?php

// Regression test for HaveAPI client options passed by the web UI.

define('API_SSL_VERIFY', false);
define('API_OAUTH2_TRUSTED_ORIGINS', [
    'https://auth.vpsfree.cz',
    'https://auth.example.test:8443',
]);

require __DIR__ . '/../../../webui/lib/functions.lib.php';

function assert_same($expected, $actual, $message)
{
    if ($expected !== $actual) {
        fwrite(
            STDERR,
            sprintf(
                "%s\nExpected: %s\nActual:   %s\n",
                $message,
                var_export($expected, true),
                var_export($actual, true)
            )
        );
        exit(1);
    }
}

$options = getApiClientOptions();

assert_same(false, $options['verify'], 'API SSL verification option was not forwarded.');
assert_same(
    API_OAUTH2_TRUSTED_ORIGINS,
    $options['oauth2_trusted_origins'],
    'OAuth2 trusted origins were not forwarded to HaveAPI.'
);

echo "HaveAPI webui client options include OAuth2 trusted origins.\n";
