<?php

use PHPUnit\Framework\TestCase;

final class OpenRedirectTargetsTest extends TestCase
{
    public function testRedirectTargetsAreRestrictedToLocalUrls(): void
    {
        require_once dirname(__DIR__, 2) . '/lib/functions.lib.php';
        require_once dirname(__DIR__, 2) . '/lib/vps.lib.php';
        require_once dirname(__DIR__, 2) . '/lib/xtemplate.lib.php';

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
            self::assertSame('?page=', local_redirect_target($target));
        }

        $localCases = [
            '?page=cluster' => '?page=cluster',
            './index.php?page=cluster' => './index.php?page=cluster',
            '/index.php?page=cluster' => '/index.php?page=cluster',
            'index.php?page=cluster' => 'index.php?page=cluster',
        ];

        foreach ($localCases as $target => $expected) {
            self::assertSame($expected, local_redirect_target($target));
        }

        $xtpl = new XTemplate('', '', null, 'main', false);

        $_GET = ['prev_url' => base64_encode('https://attacker.example/')];
        self::assertSame('./index.php', $xtpl->get_prev_url());

        $_GET = ['prev_url' => '%%%'];
        self::assertSame('./index.php', $xtpl->get_prev_url());

        $_GET = ['prev_url' => base64_encode('?page=cluster')];
        self::assertSame('?page=cluster', $xtpl->get_prev_url());

        $_GET = [];
        self::assertSame('./index.php', $xtpl->get_prev_url());

        $_SERVER['HTTP_HOST'] = 'admin.example';

        $_GET = ['action' => 'info'];
        $_SERVER['REQUEST_URI'] = '/?page=adminvps&action=info&run=restart&veid=101&t=csrf';
        $_SERVER['HTTP_REFERER'] = 'https://admin.example/?page=adminvps&action=info&veid=101';
        self::assertSame('/?page=adminvps&action=info&veid=101', vps_run_redirect_path(101));

        $_GET = [];
        $_SERVER['REQUEST_URI'] = '/?page=adminvps&run=stop&veid=101&t=csrf';
        $_SERVER['HTTP_REFERER'] = 'https://admin.example/?page=adminvps&action=list&from_id=100&limit=1';
        self::assertSame(
            '/?page=adminvps&action=list&from_id=100&limit=1',
            vps_run_redirect_path(101)
        );

        $_GET = ['action' => 'info'];
        $_SERVER['REQUEST_URI'] = '/?page=adminvps&action=info&run=restart&veid=101&t=csrf';
        $_SERVER['HTTP_REFERER'] = 'https://admin.example/?page=adminvps&action=info&run=restart&veid=101&t=csrf';
        self::assertSame('?page=adminvps&action=info&veid=101', vps_run_redirect_path(101));

        $_SERVER['HTTP_REFERER'] = 'https://attacker.example/?page=adminvps&action=info&veid=101';
        self::assertSame('?page=adminvps&action=info&veid=101', vps_run_redirect_path(101));
    }
}
