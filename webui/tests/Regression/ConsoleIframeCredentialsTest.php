<?php

use PHPUnit\Framework\TestCase;

class CapturingConsoleTemplate
{
    public array $vars = ['AJAX_SCRIPT' => ''];
    public string $lastTitle = '';
    public string $lastBody = '';
    public array $sidebar = [];

    public function perex($title, $body)
    {
        $this->lastTitle = $title;
        $this->lastBody = $body;
    }

    public function perex_format_errors($title, $response)
    {
        throw new RuntimeException("unexpected error: $title");
    }

    public function assign($key, $value)
    {
        $this->vars[$key] = $value;
    }

    public function sbar_add($label, $url = null)
    {
        $this->sidebar[] = [$label, $url];
    }

    public function sbar_add_trusted($label, $url = null)
    {
        $this->sidebar[] = [$label, $url];
    }

    public function sbar_add_fragment($html)
    {
        $this->sidebar[] = [$html, null];
    }

    public function sbar_out($title)
    {
        $this->sidebar[] = [$title, null];
    }

    public function form_select_html($name, $options, $selected = null)
    {
        return '<select name="' . htmlspecialchars($name, ENT_QUOTES) . '"></select>';
    }
}

class FakeConsoleTokenResource
{
    public const TOKEN = 'console session token & extra=1';

    public function create()
    {
        return (object) ['token' => self::TOKEN];
    }
}

class FakeConsoleVpsResource
{
    public function find($id, $opts)
    {
        return (object) [
            'id' => (int) $id,
            'console_token' => new FakeConsoleTokenResource(),
            'node' => (object) [
                'location' => (object) [
                    'remote_console_server' => 'https://console.example.test',
                ],
            ],
            'os_template_id' => 1,
        ];
    }
}

final class ConsoleIframeCredentialsTest extends TestCase
{
    public function testConsoleIframeUsesOnlyConsoleSessionToken(): void
    {
        if (!function_exists('_')) {
            function _($s)
            {
                return $s;
            }
        }

        function getAuthenticationToken()
        {
            global $authenticationTokenCalls;

            $authenticationTokenCalls++;

            return 'SECRET-API-TOKEN-FOR-GPTPRO-41';
        }

        function isLoggedIn()
        {
            return true;
        }

        function csrf_check()
        {
            return true;
        }

        function list_templates($vps)
        {
            return [1 => 'rescue-template'];
        }

        global $authenticationTokenCalls, $xtpl, $api;

        $authenticationTokenCalls = 0;
        $xtpl = new CapturingConsoleTemplate();
        $api = (object) ['vps' => new FakeConsoleVpsResource()];
        $_GET['veid'] = '4242';
        $_SESSION = ['auth_type' => 'token'];

        require dirname(__DIR__, 2) . '/pages/page_console.php';

        $body = $xtpl->lastBody;

        self::assertSame(0, $authenticationTokenCalls);
        self::assertStringNotContainsString('SECRET-API-TOKEN-FOR-GPTPRO-41', $body);
        self::assertStringNotContainsString('auth_token=', $body);
        self::assertStringNotContainsString('auth_type=', $body);

        self::assertMatchesRegularExpression('/<iframe src="([^"]+)"/', $body);
        preg_match('/<iframe src="([^"]+)"/', $body, $match);

        $url = html_entity_decode($match[1], ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        $parts = parse_url($url);
        $params = [];
        parse_str($parts['query'] ?? '', $params);

        self::assertSame('https', $parts['scheme'] ?? null);
        self::assertSame('console.example.test', $parts['host'] ?? null);
        self::assertSame('/console/4242', $parts['path'] ?? null);
        self::assertSame(['session'], array_keys($params));
        self::assertSame(FakeConsoleTokenResource::TOKEN, $params['session']);
    }
}
