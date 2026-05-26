<?php

use PHPUnit\Framework\TestCase;

final class ApiClientOptionsTest extends TestCase
{
    public function testHaveApiClientOptionsIncludeOauth2TrustedOrigins(): void
    {
        define('API_SSL_VERIFY', false);
        define('API_OAUTH2_TRUSTED_ORIGINS', [
            'https://auth.vpsfree.cz',
            'https://auth.example.test:8443',
        ]);

        require_once dirname(__DIR__, 2) . '/lib/functions.lib.php';

        $options = getApiClientOptions();

        self::assertFalse($options['verify']);
        self::assertSame(API_OAUTH2_TRUSTED_ORIGINS, $options['oauth2_trusted_origins']);
    }
}
