<?php

use PHPUnit\Framework\TestCase;

final class XssReportSinksTest extends TestCase
{
    public function testTriagedWebUiXssSinksKeepExpectedEscapingPatterns(): void
    {
        $this->assertFileContains(
            'webui/pages/page_transactions.php',
            'h($chain->user_session->label)',
            'VULN-03 session labels must be escaped in transaction details.'
        );

        $this->assertFileContains(
            'webui/forms/userns.forms.php',
            'h($m->label)',
            'VULN-04 UID/GID map labels must be escaped.'
        );

        $this->assertFileContains(
            'api/lib/vpsadmin/api/authentication/webauthn_register.erb',
            'const url = new URL(<%= js_string(redirect_uri) %>);',
            'VULN-05 redirect_uri must be emitted as a script-safe JavaScript string literal.'
        );

        $this->assertFileContains(
            'api/lib/vpsadmin/api/authentication/webauthn_register.rb',
            '.gsub(\'<\', \'\\\\u003c\')',
            'VULN-05 script string encoding must neutralize closing script tags.'
        );

        $this->assertFileContains(
            'webui/lib/xtemplate.lib.php',
            '$this->sbar_add_trusted($title, local_redirect_target($link));',
            'VULN-06/VULN-44 sidebar hrefs must be validated and escaped centrally.'
        );

        $this->assertFileContains(
            'webui/lib/xtemplate.lib.php',
            '$this->assign(\'SBI_LINK\', h($link));',
            'VULN-06/VULN-44 sidebar hrefs must be HTML-escaped centrally.'
        );

        $this->assertFileContains(
            'webui/pages/page_jumpto.php',
            '$value = h($v->value);',
            'VULN-103 jump-to result values must be escaped before highlighting.'
        );

        $this->assertFileContains(
            'webui/pages/page_networking.php',
            '$href = \'?\' . http_build_query([',
            'VULN-12 networking drill-down links must be built from typed values.'
        );

        $this->assertFileContains(
            'webui/forms/vps.forms.php',
            '$value = api_get_uint($r);',
            'VULN-13 VPS resource URL parameters must be parsed as unsigned integers.'
        );

        $this->assertFileContains(
            'webui/forms/vps.forms.php',
            'vps_link($vps) . \' \' . h($vps->hostname)',
            'VULN-15 VPS hostnames must be escaped in VPS forms.'
        );

        $this->assertFileContains(
            'webui/pages/page_backup.php',
            'name="return" value="\' . h($_GET[\'return\'] ?? $_POST[\'return\'] ?? \'\') . \'"',
            'VULN-19 backup confirmation return fields must be escaped.'
        );

        $this->assertFileContains(
            'webui/pages/page_dataset.php',
            'name="return" value="\' . h($_GET[\'return\'] ?? $_POST[\'return\'] ?? \'\') . \'"',
            'VULN-21 dataset confirmation return fields must be escaped.'
        );

        $this->assertFileContains(
            'webui/pages/page_adminm.php',
            'h($u->full_name)',
            'VULN-23 delete-user full names must be escaped.'
        );

        $this->assertFileContains(
            'webui/public/config.js.php',
            'json_encode(getSelfUri(), JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT)',
            'VULN-28 host-derived config URL must be JSON encoded.'
        );

        $this->assertFileContains(
            'webui/forms/dns.forms.php',
            '<code>\' . h($r->dnskey_pubkey) . \'</code>',
            'VULN-33 DNSSEC public keys must be escaped.'
        );

        $this->assertFileContains(
            'webui/pages/page_index.php',
            'h(kernel_version($node->kernel))',
            'VULN-34 public node kernel strings must be escaped.'
        );

        $this->assertFileContains(
            'webui/forms/cluster.forms.php',
            'h($node->version)',
            'VULN-34 admin node version strings must be escaped.'
        );

        $this->assertFileContains(
            'webui/forms/oom_reports.forms.php',
            'h($usage->memtype)',
            'VULN-35 OOM usage metric names must be escaped.'
        );

        $this->assertFileContains(
            'webui/forms/oom_reports.forms.php',
            'h($stat->parameter)',
            'VULN-35 OOM stat metric names must be escaped.'
        );

        $this->assertFileContains(
            'webui/pages/page_adminm.php',
            '$registerMessage = h($_GET[\'registerMessage\'] ?? \'\');',
            'VULN-39 passkey callback messages must be escaped before notification.'
        );

        $this->assertFileContains(
            'webui/public/index.php',
            'rawurlencode($_GET["page"] ?? \'\')',
            'VULN-43 help-box page parameter must be URL encoded.'
        );

        $this->assertFileContains(
            'webui/lib/xtemplate.lib.php',
            '\'<form action="\' . h($action) . \'" method="\' . h($method) . \'" name="\' . h($name)',
            'GPTPRO-107 form action/method/name attributes must be escaped centrally.'
        );

        $this->assertFileContains(
            'webui/pages/page_lifetimes.php',
            'nl2br(h($s->reason))',
            'GPTPRO-111 lifetime change reasons must be escaped before nl2br.'
        );
    }

    private function assertFileContains(string $path, string $needle, string $message): void
    {
        $source = file_get_contents(dirname(__DIR__, 3) . '/' . $path);

        self::assertStringContainsString($needle, $source, $message);
    }
}
