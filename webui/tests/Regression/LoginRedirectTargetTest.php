<?php

use PHPUnit\Framework\TestCase;

require_once dirname(__DIR__, 2) . '/lib/functions.lib.php';
require_once dirname(__DIR__, 2) . '/lib/login.lib.php';

final class LoginRedirectTargetTest extends TestCase
{
    public function testPostLoginRedirectTargetRejectsAuthAndLanguageEndpoints(): void
    {
        $rejected = [
            '?page=lang&newlang=cs_CZ.utf8',
            './index.php?page=lang&newlang=cs_CZ.utf8',
            '/?page=login&action=login',
            '?page=jumpto&search=test',
            'https://attacker.example/?page=cluster',
            "?page=cluster\r\nLocation: https://attacker.example/",
            '',
            null,
        ];

        foreach ($rejected as $target) {
            self::assertNull(post_login_redirect_target($target));
        }
    }

    public function testPostLoginRedirectTargetKeepsSafeLocalPages(): void
    {
        self::assertSame('?page=about', post_login_redirect_target('?page=about'));
        self::assertSame('/?page=cluster', post_login_redirect_target('/?page=cluster'));
        self::assertSame(
            './index.php?page=adminvps&action=list',
            post_login_redirect_target('./index.php?page=adminvps&action=list')
        );
    }
}
