<?php

use PHPUnit\Framework\TestCase;

class SystemConfigChoiceOption
{
    public function __construct(private array $data) {}

    public function __get($name)
    {
        return $this->data[$name] ?? null;
    }

    public function attributes()
    {
        return $this->data;
    }
}

final class SystemConfigChoicesTest extends TestCase
{
    protected function setUp(): void
    {
        require_once dirname(__DIR__, 2) . '/lib/functions.lib.php';
        require_once dirname(__DIR__, 2) . '/lib/cluster.lib.php';
        $_SESSION = [];
    }

    private function option(array $overrides = []): array
    {
        return array_replace([
            'category' => 'synthetic',
            'name' => 'setting',
            'type' => 'String',
            'value' => 'first',
            'choices' => [
                ['value' => '', 'label' => 'Empty'],
                ['value' => 'first', 'label' => 'First'],
            ],
            'value_nullable' => true,
        ], $overrides);
    }

    private function config(array $option): SystemConfig
    {
        $api = new class ($option) {
            public $system_config;

            public function __construct(array $option)
            {
                $this->system_config = new class ($option) {
                    public function __construct(private array $option) {}

                    public function index()
                    {
                        return [new SystemConfigChoiceOption($this->option)];
                    }
                };
            }
        };

        return new SystemConfig($api, true, 'en');
    }

    public function testNullableEmptyStringAndLiteralNullRemainDistinct(): void
    {
        $option = $this->option(['choices' => [
            ['value' => '', 'label' => 'Empty'],
            ['value' => 'null', 'label' => 'Literal null'],
        ]]);
        $choices = system_config_choices($option);

        self::assertSame(['""', '"null"', 'null'], array_keys($choices));
        $config = $this->config($option);
        self::assertSame([[['synthetic', 'setting', null, true]], []], system_config_changes($config, [
            'sysconfig_choices' => ['synthetic:setting' => 'null'],
        ]));
        self::assertSame([[['synthetic', 'setting', '', true]], []], system_config_changes($config, [
            'sysconfig_choices' => ['synthetic:setting' => '""'],
        ]));
    }

    public function testSavesIntegerZeroAsAnIntegerAndRejectsStringEquivalent(): void
    {
        $config = $this->config($this->option([
            'type' => 'Integer', 'value' => 2,
            'choices' => [['value' => 0, 'label' => 'Zero'], ['value' => 2, 'label' => 'Two']],
            'value_nullable' => false,
        ]));

        self::assertSame([[['synthetic', 'setting', 0, true]], []], system_config_changes($config, [
            'sysconfig_choices' => ['synthetic:setting' => '0'],
        ]));
        self::assertSame([[], ['synthetic:setting']], system_config_changes($config, [
            'sysconfig_choices' => ['synthetic:setting' => '"0"'],
        ]));
    }

    public function testUnsupportedCurrentValuesStaySelectedAndUnchanged(): void
    {
        $option = $this->option(['value' => null, 'value_nullable' => false]);
        $html = system_config_choice_html('synthetic:setting', system_config_choices($option), null);

        self::assertStringContainsString('<option selected disabled value="null">', $html);
        self::assertSame(1, substr_count($html, 'selected'));
        self::assertSame([[], []], system_config_changes($this->config($option), []));
        self::assertSame([[], []], system_config_changes($this->config($option), [
            'sysconfig_choices' => ['synthetic:setting' => 'null'],
        ]));
    }

    public function testSelectedUnchangedValidChoiceDoesNotWrite(): void
    {
        self::assertSame([[], []], system_config_changes($this->config($this->option()), [
            'sysconfig_choices' => ['synthetic:setting' => '"first"'],
        ]));
    }

    public function testLegacyFloatIsNotSilentlySelectedAsAnIntegerChoice(): void
    {
        $option = $this->option([
            'type' => 'Integer', 'value' => 0.0,
            'choices' => [['value' => 0, 'label' => 'Zero']], 'value_nullable' => false,
        ]);
        $html = system_config_choice_html('synthetic:setting', system_config_choices($option), $option['value']);

        self::assertStringContainsString('<option selected disabled value="0.0">', $html);
        self::assertSame(1, substr_count($html, 'selected'));
        self::assertSame([[], []], system_config_changes($this->config($option), []));
    }

    public function testEscapesTokensAndApiLabels(): void
    {
        $value = '\"><script>alert(1)</script>';
        $option = $this->option(['choices' => [['value' => $value, 'label' => '<b>Localized label</b>']]]);
        $html = system_config_choice_html('synthetic:setting', system_config_choices($option), $value);

        self::assertStringNotContainsString('<script>', $html);
        self::assertStringNotContainsString('<b>', $html);
        self::assertStringContainsString('&lt;b&gt;Localized label&lt;/b&gt;', $html);
        self::assertStringContainsString(' selected', $html);
    }

    public function testMalformedPresentMetadataDoesNotBecomeAnUnrestrictedInput(): void
    {
        $option = $this->option(['choices' => [['value' => 1, 'label' => 'Wrong type']]]);

        self::assertSame([[], ['synthetic:setting']], system_config_changes($this->config($option), [
            'synthetic:setting' => 'replacement',
        ]));
    }

    public function testMissingMetadataAndStaleFormsKeepTheExistingInputPath(): void
    {
        $option = $this->option();
        unset($option['choices'], $option['value_nullable']);
        self::assertNull(system_config_choices($option));
        self::assertSame([[['synthetic', 'setting', 'replacement', false]], []], system_config_changes($this->config($option), [
            'synthetic:setting' => 'replacement',
        ]));
        self::assertSame([[['synthetic', 'setting', 'replacement', false]], []], system_config_changes($this->config($this->option()), [
            'synthetic:setting' => 'replacement',
        ]));
    }

    public function testNonchoiceCheckboxKeepsUncheckedSaveBehavior(): void
    {
        $option = $this->option(['type' => 'Boolean', 'value' => true, 'choices' => null, 'value_nullable' => null]);
        self::assertSame([[['synthetic', 'setting', '0', false]], []], system_config_changes($this->config($option), []));
    }

    public function testRejectsMalformedChoiceTokens(): void
    {
        foreach (['{invalid', '[]', 'true', '9007199254740992', null] as $token) {
            self::assertSame([[], ['synthetic:setting']], system_config_changes($this->config($this->option()), [
                'sysconfig_choices' => ['synthetic:setting' => $token],
            ]));
        }
    }

    public function testFormRendersServerLabelsAndRetainsPostedTypedDraft(): void
    {
        require_once dirname(__DIR__, 2) . '/forms/cluster.forms.php';
        global $api, $xtpl;

        $option = $this->option();
        $api = new class ($option) {
            public $system_config;

            public function __construct(array $option)
            {
                $this->system_config = new class ($option) {
                    public function __construct(private array $option) {}

                    public function index()
                    {
                        return [new SystemConfigChoiceOption($this->option)];
                    }
                };
            }
        };
        $xtpl = new class {
            public array $calls = [];

            public function __call($name, $args)
            {
                $this->calls[] = [$name, $args];
            }
        };
        $_POST = ['sysconfig_choices' => ['synthetic:setting' => '""']];
        system_config_form();
        $rendered = json_encode($xtpl->calls);

        self::assertStringContainsString('sysconfig_choices[synthetic:setting]', $rendered);
        self::assertStringContainsString('Empty', $rendered);
        self::assertStringNotContainsString('form_add_input_pure', $rendered);
        $select = array_values(array_filter($xtpl->calls, fn($call) => $call[0] === 'table_td' && str_contains($call[1][0], '<select')))[0][1][0];
        self::assertStringContainsString('value="&quot;&quot;" selected', $select);
    }

    public function testRealClientSendsExactChoiceScalarsWithoutChangingOrdinaryInput(): void
    {
        require_once dirname(__DIR__, 2) . '/vendor/autoload.php';
        $client = new class ('https://api.example.test') extends \HaveAPI\Client {
            public array $requests = [];

            protected function sendRequest($request, $action = null, $params = [])
            {
                $body = json_decode($request->payload, true, 512, JSON_THROW_ON_ERROR);
                $this->requests[] = ['uri' => $request->uri, 'method' => $request->method,
                    'headers' => $request->headers, 'body' => $body];

                return (object) ['code' => 200, 'body' => (object) ['status' => true,
                    'response' => (object) ['system_config' => (object) [
                        'category' => 'synthetic', 'name' => 'setting',
                        'value' => $body['system_config']['value'],
                    ], '_meta' => (object) []]]];
            }
        };
        $valueParameter = (object) ['type' => 'Custom', 'nullable' => true, 'required' => false];
        $action = (object) ['method' => 'PUT', 'path' => '/v7.0/system_configs/{category}/{name}',
            'input' => (object) ['layout' => 'object', 'namespace' => 'system_config',
                'parameters' => (object) ['value' => $valueParameter]],
            'output' => (object) ['layout' => 'object', 'namespace' => 'system_config',
                'parameters' => (object) ['value' => (object) ['type' => 'Custom']]],
            'meta' => (object) []];
        $resource = (object) ['actions' => (object) ['update' => $action], 'resources' => (object) []];
        $client->setDescription((object) ['authentication' => (object) ['token' => (object) [
            'http_header' => 'X-Test-Token', 'resources' => (object) ['token' => (object) []],
        ]], 'meta' => (object) ['namespace' => '_meta'],
            'resources' => (object) ['system_config' => $resource]]);
        $client->authenticate('token', ['token' => 'synthetic-token'], false);
        $client->setLanguage('cs');

        foreach (['', " \t\n ", 0, '0', null] as $value) {
            $result = system_config_update($client, 'synthetic', 'setting', $value, true);
            self::assertSame($value, $result->value);
            $request = $client->requests[array_key_last($client->requests)];
            self::assertSame(['system_config' => ['value' => $value]], $request['body']);
            self::assertSame('https://api.example.test/v7.0/system_configs/synthetic/setting', $request['uri']);
            self::assertSame('PUT', $request['method']);
            self::assertSame('cs', $request['headers']['Accept-Language']);
            self::assertSame('synthetic-token', $request['headers']['X-Test-Token']);
            self::assertSame($valueParameter, $client->system_config->update->getParameters('input')->value);
            self::assertTrue($valueParameter->nullable);
        }

        system_config_update($client, 'synthetic', 'setting', '', false);
        self::assertSame(['system_config' => ['value' => null]], $client->requests[array_key_last($client->requests)]['body']);
        self::assertTrue($valueParameter->nullable);
    }
}
