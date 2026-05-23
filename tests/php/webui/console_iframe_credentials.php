<?php

// Regression test for webui/pages/page_console.php::setup_console().
// The iframe URL must use only the dedicated console session token.

if (!function_exists('_')) {
    function _($s)
    {
        return $s;
    }
}

$authenticationTokenCalls = 0;

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

class CapturingTemplate
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

class FakeVpsResource
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

$xtpl = new CapturingTemplate();
$api = (object) ['vps' => new FakeVpsResource()];
$_GET['veid'] = '4242';
$_SESSION = ['auth_type' => 'token'];

require __DIR__ . '/../../../webui/pages/page_console.php';

$body = $xtpl->lastBody;

if ($authenticationTokenCalls !== 0) {
    fwrite(STDERR, "setup_console() requested the API authentication token.\n");
    exit(1);
}

if (str_contains($body, 'SECRET-API-TOKEN-FOR-GPTPRO-41')) {
    fwrite(STDERR, "Rendered console iframe contains the API authentication token.\n");
    exit(1);
}

if (str_contains($body, 'auth_token=') || str_contains($body, 'auth_type=')) {
    fwrite(STDERR, "Rendered console iframe contains API credential query params.\n");
    exit(1);
}

if (!preg_match('/<iframe src="([^"]+)"/', $body, $match)) {
    fwrite(STDERR, "Unable to find the console iframe src.\n");
    exit(1);
}

$url = html_entity_decode($match[1], ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
$parts = parse_url($url);
$params = [];
parse_str($parts['query'] ?? '', $params);

if (($parts['scheme'] ?? null) !== 'https' || ($parts['host'] ?? null) !== 'console.example.test') {
    fwrite(STDERR, "Console iframe src points to the wrong server: $url\n");
    exit(1);
}

if (($parts['path'] ?? null) !== '/console/4242') {
    fwrite(STDERR, "Console iframe src points to the wrong path: $url\n");
    exit(1);
}

if (array_keys($params) !== ['session']) {
    fwrite(STDERR, "Console iframe src has unexpected query params: $url\n");
    exit(1);
}

if ($params['session'] !== FakeConsoleTokenResource::TOKEN) {
    fwrite(STDERR, "Console iframe src does not preserve the console session token: $url\n");
    exit(1);
}

echo "Console iframe omits API credentials and preserves the console session token.\n";
