<?php

use PHPUnit\Framework\TestCase;

final class XssSharedHelpersTest extends TestCase
{
    public function testSharedHelpersEscapeAttributesAndHostDerivedUrls(): void
    {
        require_once dirname(__DIR__, 2) . '/lib/functions.lib.php';
        require_once dirname(__DIR__, 2) . '/lib/xtemplate.lib.php';
        require_once dirname(__DIR__, 2) . '/lib/login.lib.php';

        $payload = '" onclick="alert(1)"><script>alert(2)</script>';

        self::assertSame(
            '&quot; onclick=&quot;alert(1)&quot;&gt;&lt;script&gt;alert(2)&lt;/script&gt;',
            h($payload)
        );

        self::assertSame('?page=', local_redirect_target($payload));
        self::assertSame('?page=cluster', local_redirect_target('?page=cluster'));

        $xtpl = new XTemplate('', '', null, 'main', false);
        $xtpl->sbar_add('Back', $payload);
        self::assertSame('?page=', $xtpl->vars['SBI_LINK']);

        $xtpl->sbar_add('Back', '?page=history&list=1');
        self::assertSame('?page=history&amp;list=1', $xtpl->vars['SBI_LINK']);

        $xtpl->sbar_add_trusted('Console action', "javascript:vps_do('start');");
        self::assertSame('javascript:vps_do(&#039;start&#039;);', $xtpl->vars['SBI_LINK']);

        $xtpl->form_create('?page=cluster&type=' . $payload, 'post" autofocus="autofocus', 'x"><script>', false);
        $form = $xtpl->vars['TABLE_FORM_BEGIN'];

        self::assertStringContainsString('&quot;', $form);
        self::assertStringNotContainsString('<script>', $form);
        self::assertStringNotContainsString('autofocus="autofocus"', $form);

        $_SERVER = [
            'HTTP_X_FORWARDED_HOST' => 'victim.example"+alert(1)+"',
            'HTTP_HOST' => 'webui.example.test',
            'SERVER_NAME' => 'fallback.example.test',
            'SERVER_PORT' => '80',
        ];
        self::assertSame('http://webui.example.test', getSelfUri());

        $_SERVER = [
            'HTTP_X_FORWARDED_HOST' => 'proxy.example.test:8443',
            'HTTP_HOST' => 'webui.example.test',
            'HTTP_X_FORWARDED_PROTO' => 'https',
            'SERVER_NAME' => 'fallback.example.test',
            'SERVER_PORT' => '80',
        ];
        self::assertSame('https://proxy.example.test:8443', getSelfUri());
    }
}
