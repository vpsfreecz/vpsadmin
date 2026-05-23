<?php

// Regression test for webui/forms/users.forms.php::webauthn_list().
// The access token must be submitted in the POST body, not in the form URL.

if (!function_exists('_')) {
    function _($s)
    {
        return $s;
    }
}

function h($v)
{
    if (is_null($v)) {
        return '';
    }

    return htmlspecialchars((string) $v, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function boolean_icon($v)
{
    return $v ? 'yes' : 'no';
}

function tolocaltz($value, $fmt = null)
{
    return (string) $value;
}

function csrf_token()
{
    return 'csrf-token';
}

function getWebAuthnNewRegistrationUrl()
{
    return 'https://auth.example.test/webauthn/registration/new';
}

function getSelfUri()
{
    return 'https://webui.example.test';
}

class EmptyCollection implements IteratorAggregate, Countable
{
    public function getIterator(): Traversable
    {
        return new ArrayIterator([]);
    }

    public function count(): int
    {
        return 0;
    }
}

class FakeWebauthnCredentialResource
{
    public function list()
    {
        return new EmptyCollection();
    }
}

class FakeUser
{
    public int $id = 101;
    public FakeWebauthnCredentialResource $webauthn_credential;

    public function __construct()
    {
        $this->webauthn_credential = new FakeWebauthnCredentialResource();
    }
}

class CapturingTemplate
{
    public array $forms = [];
    public array $hiddenFields = [];

    public function table_title($title) {}
    public function table_add_category($title) {}
    public function table_td($content, ...$args) {}
    public function table_tr() {}
    public function table_out() {}
    public function form_out($label) {}
    public function sbar_add($label, $url = null) {}

    public function form_create($action = '?page=', $method = 'post', $name = 'generic_form', $csrf = true)
    {
        $this->forms[] = [
            'action' => $action,
            'method' => $method,
            'name' => $name,
        ];
    }

    public function form_set_hidden_fields($keyvals)
    {
        $this->hiddenFields[] = $keyvals;
    }
}

$secretToken = 'SECRET-OAUTH2-ACCESS-TOKEN-GPTPRO-42';
$xtpl = new CapturingTemplate();
$_SESSION = [
    'user' => ['id' => 101],
    'auth_type' => 'oauth2',
    'access_token' => ['access_token' => $secretToken],
];

require __DIR__ . '/../../../webui/forms/users.forms.php';

webauthn_list(new FakeUser());

$form = null;
foreach ($xtpl->forms as $candidate) {
    if ($candidate['name'] === 'webauthn_register') {
        $form = $candidate;
        break;
    }
}

if (!$form) {
    fwrite(STDERR, "Passkey registration form was not rendered.\n");
    exit(1);
}

if ($form['method'] !== 'post') {
    fwrite(STDERR, "Passkey registration form does not use POST.\n");
    exit(1);
}

if (str_contains($form['action'], 'access_token') || str_contains($form['action'], $secretToken)) {
    fwrite(STDERR, "Passkey registration form action contains the access token.\n");
    exit(1);
}

$hidden = end($xtpl->hiddenFields);
if (($hidden['access_token'] ?? null) !== $secretToken) {
    fwrite(STDERR, "Passkey registration form does not include the access token body field.\n");
    exit(1);
}

if (($hidden['redirect_uri'] ?? null) !== 'https://webui.example.test/?page=adminm&action=webauthn_register&id=101') {
    fwrite(STDERR, "Passkey registration form has an unexpected redirect URI.\n");
    exit(1);
}

echo "Passkey registration submits API credentials by POST body only.\n";
