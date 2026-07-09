<?php

use PHPUnit\Framework\TestCase;

class EmptyWebauthnCollection implements IteratorAggregate, Countable
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
        return new EmptyWebauthnCollection();
    }
}

class FakeWebauthnUser
{
    public int $id = 101;
    public FakeWebauthnCredentialResource $webauthn_credential;

    public function __construct()
    {
        $this->webauthn_credential = new FakeWebauthnCredentialResource();
    }
}

class CapturingWebauthnTemplate
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

final class WebauthnRegistrationCredentialsTest extends TestCase
{
    public function testPasskeyRegistrationPostsAccessTokenInBodyOnly(): void
    {
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

        global $xtpl;

        $secretToken = 'SECRET-OAUTH2-ACCESS-TOKEN-GPTPRO-42';
        $xtpl = new CapturingWebauthnTemplate();
        $_SESSION = [
            'user' => ['id' => 101],
            'auth_type' => 'oauth2',
            'access_token' => ['access_token' => $secretToken],
        ];

        require dirname(__DIR__, 2) . '/forms/users.forms.php';

        webauthn_list(new FakeWebauthnUser());

        $form = null;
        foreach ($xtpl->forms as $candidate) {
            if ($candidate['name'] === 'webauthn_register') {
                $form = $candidate;
                break;
            }
        }

        self::assertNotNull($form);
        self::assertSame('post', $form['method']);
        self::assertStringNotContainsString('access_token', $form['action']);
        self::assertStringNotContainsString($secretToken, $form['action']);

        $hidden = end($xtpl->hiddenFields);
        self::assertSame($secretToken, $hidden['access_token'] ?? null);
        self::assertSame(
            'https://webui.example.test/?page=adminm&action=webauthn_register&id=101',
            $hidden['redirect_uri'] ?? null
        );
    }
}
