<?php

use PHPUnit\Framework\TestCase;

final class MultiFactorAuthStatusLabelTest extends TestCase
{
    public function testStatusLabelUsesOnAndOff(): void
    {
        require_once dirname(__DIR__, 2) . '/lib/functions.lib.php';

        self::assertSame('On', multi_factor_auth_status_label(true));
        self::assertSame(
            'On, no authentication device is enabled',
            multi_factor_auth_status_label(true, false)
        );
        self::assertSame('Off', multi_factor_auth_status_label(false));
    }
}
