<?php

use PHPUnit\Framework\TestCase;
use PHPUnit\Framework\Attributes\DataProvider;

final class SystemConfigSelectedSettingTest extends TestCase
{
    public function testOnlySelectedStringIsSentDespiteUnrelatedFields(): void
    {
        $result = $this->submit('string', ['ordinary:string' => 'edited',
            'ordinary:boolean_true' => null, 'ordinary:integer_zero' => '12',
            'sysconfig_choices' => ['ordinary:choice' => '"second"']]);
        self::assertCount(1, $result['updates']);
        self::assertSame(['system_config' => ['value' => 'edited']], $result['updates'][0]['body']);
        self::assertSame('https://api.example.test/v7.0/system_configs/ordinary/string', $result['updates'][0]['uri']);
        self::assertSame('cs', $result['updates'][0]['headers']['Accept-Language']);
        self::assertSame('synthetic-token', $result['updates'][0]['headers']['X-Test-Token']);
        self::assertSame(1, $result['csrf_remaining']);
        $expected = $result['before'];
        $expected['string']['value'] = 'edited';
        self::assertSame($expected, $result['after']);
    }

    public static function ordinaryEdits(): array
    {
        return [
            ['boolean_true', null, '0'], ['boolean_false', '1', '1'],
            ['integer_zero', '-7', '-7'], ['float', '2.5', '2.5'],
            ['text', " edited\ntext ", " edited\ntext "], ['custom', '{"items":[false,0,null]}', '{"items":[false,0,null]}'],
            ['array', "---\r\n- false\r\n- 0\r\n- ''\r\n-\r\n", "---\r\n- false\r\n- 0\r\n- ''\r\n-\r\n"],
            ['hash', "---\r\nzero: 0\r\nempty: ''\r\nnested:\r\n- false\r\n-\r\n", "---\r\nzero: 0\r\nempty: ''\r\nnested:\r\n- false\r\n-\r\n"],
        ];
    }

    #[DataProvider('ordinaryEdits')]
    public function testOrdinarySelectedValueKeepsExistingTransport(string $name, $posted, $sent): void
    {
        $result = $this->submit($name, ['ordinary:' . $name => $posted]);
        self::assertCount(1, $result['updates']);
        self::assertSame($sent, $result['updates'][0]['body']['system_config']['value']);
        $expected = $result['before'];
        $expected[$name]['value'] = $sent;
        self::assertSame($expected, $result['after']);
    }

    public static function unchangedSettings(): array
    {
        return array_map(fn($name) => [$name], ['string', 'empty', 'spaces', 'unset', 'integer_zero',
            'float_zero', 'boolean_false', 'boolean_true', 'boolean_null', 'array', 'hash', 'unsupported_choice']);
    }

    #[DataProvider('unchangedSettings')]
    public function testUnchangedSelectedSettingDoesNotWrite(string $name): void
    {
        $result = $this->submit($name);
        self::assertSame([], $result['updates']);
        self::assertSame($result['before'], $result['after']);
    }

    public static function choiceEdits(): array
    {
        return [['choice', '""', ''], ['choice', '"  "', '  '], ['choice', 'null', null],
            ['choice', '"null"', 'null'], ['integer_choice', '0', 0]];
    }

    #[DataProvider('choiceEdits')]
    public function testSelectedChoicesKeepExactWireScalars(string $name, string $token, $value): void
    {
        $result = $this->submit($name, ['sysconfig_choices' => ['ordinary:' . $name => $token]]);
        self::assertCount(1, $result['updates']);
        self::assertSame($value, $result['updates'][0]['body']['system_config']['value']);
    }

    public static function invalidTargets(): array
    {
        return [[[]], [['category' => 'ordinary']], [['category' => ['ordinary'], 'name' => 'string']],
            [['category' => 'ordinary', 'name' => ['string']]], [['category' => 'ordinary', 'name' => '../string']],
            [['category' => 'ordinary', 'name' => '']], [['category' => str_repeat('x', 76), 'name' => 'string']]];
    }

    #[DataProvider('invalidTargets')]
    public function testStaleBulkOrMalformedTargetNeverWrites(array $target): void
    {
        $result = $this->submit('string', ['ordinary:string' => 'edited'], ['target' => $target]);
        self::assertSame([], $result['updates']);
        self::assertSame($result['before'], $result['after']);
        self::assertSame('Choose a setting to edit.', $result['notification']['title']);
    }

    public function testGetSaveMisuseAndInvalidCsrfNeverWrite(): void
    {
        $get = $this->submit('string', ['ordinary:string' => 'edited'], ['method' => 'GET']);
        self::assertSame([], $get['updates']);
        $csrf = $this->submit('string', ['csrf_token' => 'invalid', 'ordinary:string' => 'edited']);
        self::assertSame([], $csrf['updates']);
        self::assertTrue($csrf['csrf_invalid']);
        $guest = $this->submit('string', ['ordinary:string' => 'edited'], ['admin' => false]);
        self::assertSame([], $guest['updates']);
    }

    public function testHiddenAndMissingSelectedRowsNeverUpdate(): void
    {
        foreach (['hidden', 'missing'] as $name) {
            $result = $this->submit($name, ['ordinary:' . $name => 'changed']);
            self::assertSame([], $result['updates']);
            self::assertSame($result['before'], $result['after']);
        }
    }

    public function testNamespacesRejectBothCrossVersionDirectionsBeforeAnyWrite(): void
    {
        $legacy = $this->submit('string', ['ordinary:string' => 'edited'], ['legacy_common_check' => true]);
        self::assertTrue($legacy['csrf_invalid']);
        self::assertSame([], $legacy['updates']);
        self::assertSame($legacy['before'], $legacy['after']);
        $common = $this->submit('string', ['ordinary:string' => 'edited'], ['common_token' => true]);
        self::assertTrue($common['csrf_invalid']);
        self::assertSame([], $common['updates']);
        self::assertSame($common['before'], $common['after']);
    }

    public function testListAndEditAreReadOnlyAndCancelIsAGetLink(): void
    {
        $list = $this->submit('string', [], ['action' => 'sysconfig', 'method' => 'GET']);
        self::assertSame([], $list['updates']);
        self::assertStringNotContainsString('form_add_input', json_encode($list['rendered']));
        self::assertStringContainsString('sysconfig_edit', json_encode($list['rendered']));
        $edit = $this->submit('string', [], ['action' => 'sysconfig_edit', 'method' => 'GET']);
        self::assertSame([], $edit['updates']);
        self::assertContains(['form_csrf', ['system_config']], $edit['rendered']);
        self::assertContains(['sbar_add', ['Cancel', '?page=cluster&action=sysconfig']], $edit['rendered']);
        $hidden = $this->submit('hidden', [], ['action' => 'sysconfig_edit', 'method' => 'GET']);
        self::assertSame([], $hidden['updates']);
        self::assertStringNotContainsString('form_create', json_encode($hidden['rendered']));
    }

    public function testApiFailureRetainsSelectedDraftWithoutEchoingErrorPayload(): void
    {
        $result = $this->submit('string', ['ordinary:string' => 'retained draft'], ['fail_update' => true]);
        self::assertCount(1, $result['updates']);
        self::assertSame($result['before'], $result['after']);
        self::assertContains(['form_add_input_pure', ['text', '70', 'ordinary:string', 'retained draft']], $result['rendered']);
        self::assertStringNotContainsString('Do not echo submitted secrets', json_encode($result['rendered']));
        $checkbox = $this->submit('boolean_true', ['ordinary:boolean_true' => null], ['fail_update' => true]);
        self::assertContains(['form_add_checkbox_pure', ['ordinary:boolean_true', '1', false]], $checkbox['rendered']);
        $choice = $this->submit('choice', ['sysconfig_choices' => ['ordinary:choice' => '"second"']], ['fail_update' => true]);
        $selects = array_filter($choice['rendered'], fn($call) => $call[0] === 'table_td' && str_contains($call[1][0], '<select'));
        self::assertStringContainsString('value="&quot;second&quot;" selected', array_values($selects)[0][1][0]);
    }

    private function submit(string $name, array $overrides = [], array $options = []): array
    {
        // Run the real controller, CSRF check and client. Its normal redirect
        // exits the child; the shutdown receipt observes the network boundary.
        $script = <<<'PHP'
            $root = $argv[1];
            require $root . '/vendor/autoload.php';
            require $root . '/lib/functions.lib.php';
            require $root . '/lib/security.lib.php';
            require $root . '/lib/cluster.lib.php';
            $values = [
                'string' => ['String', 'original'],
                'empty' => ['String', ''],
                'spaces' => ['String', " \t "],
                'unset' => ['String', null],
                'text' => ['Text', "line one\nline two"],
                'custom' => ['Custom', 'raw text'],
                'integer_zero' => ['Integer', 0],
                'integer_negative' => ['Integer', -4],
                'float' => ['Float', 1.25],
                'float_zero' => ['Float', 0.0],
                'boolean_false' => ['Boolean', false],
                'boolean_true' => ['Boolean', true],
                'boolean_null' => ['Boolean', null],
                'array' => ['Array', "---\n- false\n- 0\n- ''\n-\n"],
                'hash' => ['Hash', "---\nzero: 0\nempty: ''\nnested:\n- false\n-\n"],
                'choice' => ['String', 'first'],
                'integer_choice' => ['Integer', 2],
                'hidden' => ['String', 'hidden fixture'],
                'unsupported_choice' => ['String', 'retained unsupported value'],
            ];
            $rows = [];
            foreach ($values as $name => [$type, $value]) {
                $rows[$name] = ['category' => 'ordinary', 'name' => $name, 'type' => $type,
                    'value' => $value, 'choices' => null, 'value_nullable' => null];
            }
            foreach (['choice', 'unsupported_choice', 'integer_choice'] as $name) {
                $rows[$name]['choices'] = [['value' => 'first', 'label' => 'First']];
                $rows[$name]['value_nullable'] = false;
            }
            $rows['choice']['choices'] = array_map(fn($v) => ['value' => $v, 'label' => $v === '' ? 'Empty' : 'Choice'], ['first', 'second', '', '  ', 'null']);
            $rows['choice']['value_nullable'] = true;
            $rows['integer_choice']['choices'] = [['value' => 0, 'label' => 'Zero'], ['value' => 2, 'label' => 'Two']];
            foreach ($rows as $name => &$row) {
                $row['label'] = 'Friendly ' . $name;
                $row['description'] = null;
            }
            unset($row);
            $options = json_decode(file_get_contents('php://stdin'), true, 512, JSON_THROW_ON_ERROR);
            $api = new class ('https://api.example.test') extends \HaveAPI\Client {
                public array $rows = [];
                public array $updates = [];
                public bool $failUpdate = false;

                protected function sendRequest($request, $action = null, $params = [])
                {
                    if ($request->method === 'PUT') {
                        $body = json_decode($request->payload, true, 512, JSON_THROW_ON_ERROR);
                        $this->updates[] = ['uri' => $request->uri, 'body' => $body, 'headers' => $request->headers];
                        if ($this->failUpdate) {
                            return (object) ['code' => 422, 'body' => (object) ['status' => false, 'message' => 'Do not echo submitted secrets', 'response' => (object) []]];
                        }
                        $name = basename($request->uri);
                        $this->rows[$name]['value'] = $body['system_config']['value'];
                        $response = ['system_config' => (object) $this->rows[$name]];
                    } elseif (str_ends_with($request->uri, '/system_configs')) {
                        $visible = array_filter($this->rows, fn($row) => $row['name'] !== 'hidden');
                        $response = ['system_configs' => array_map(fn($row) => (object) $row, array_values($visible))];
                    } else {
                        $name = basename($request->uri);
                        if (!isset($this->rows[$name]) || $name === 'hidden') {
                            return (object) ['code' => 404, 'body' => (object) ['status' => false, 'message' => 'Not found', 'response' => (object) []]];
                        }
                        $response = ['system_config' => (object) $this->rows[$name]];
                    }
                    $response['_meta'] = (object) [];
                    return (object) ['code' => 200, 'body' => (object) ['status' => true, 'response' => (object) $response]];
                }
            };
            $api->rows = $rows;
            $api->failUpdate = $options['fail_update'] ?? false;
            $output = (object) ['category' => (object) ['type' => 'String'],
                'name' => (object) ['type' => 'String'], 'type' => (object) ['type' => 'String'],
                'label' => (object) ['type' => 'String'], 'description' => (object) ['type' => 'String'],
                'choices' => (object) ['type' => 'Custom'], 'value_nullable' => (object) ['type' => 'Boolean'], 'value' => (object) ['type' => 'Custom']];
            $api->setDescription((object) [
                'authentication' => (object) ['token' => (object) ['http_header' => 'X-Test-Token',
                    'resources' => (object) ['token' => (object) []]]],
                'meta' => (object) ['namespace' => '_meta'],
                'resources' => (object) ['system_config' => (object) ['resources' => (object) [],
                    'actions' => (object) [
                        'index' => (object) ['aliases' => [], 'method' => 'GET', 'path' => '/v7.0/system_configs',
                            'input' => (object) ['layout' => 'object', 'namespace' => 'system_config', 'parameters' => (object) []],
                            'output' => (object) ['layout' => 'object_list', 'namespace' => 'system_configs', 'parameters' => $output],
                            'meta' => (object) []],
                        'show' => (object) ['aliases' => [], 'method' => 'GET', 'path' => '/v7.0/system_configs/{category}/{name}',
                            'input' => (object) ['layout' => 'object', 'namespace' => 'system_config', 'parameters' => (object) []],
                            'output' => (object) ['layout' => 'object', 'namespace' => 'system_config', 'parameters' => $output],
                            'meta' => (object) []],
                        'update' => (object) ['aliases' => [], 'method' => 'PUT', 'path' => '/v7.0/system_configs/{category}/{name}',
                            'input' => (object) ['layout' => 'object', 'namespace' => 'system_config',
                                'parameters' => (object) ['value' => (object) ['type' => 'Custom', 'nullable' => true, 'required' => false]]],
                            'output' => (object) ['layout' => 'object', 'namespace' => 'system_config', 'parameters' => $output],
                            'meta' => (object) []],
                    ]]],
            ]);
            $api->authenticate('token', ['token' => 'synthetic-token'], false);
            $api->setLanguage('cs');
            $_SESSION = ['is_admin' => $options['admin'] ?? true, 'csrf_base' => 'synthetic'];
            $commonToken = csrf_token('common', 2);
            $selectedToken = csrf_token('system_config', 2);
            $_GET = array_replace(['action' => $options['action'] ?? 'sysconfig_save'], $options['target']);
            $_SERVER['REQUEST_METHOD'] = $options['method'] ?? 'POST';
            $_POST = [
                'ordinary:string' => 'original', 'ordinary:empty' => '', 'ordinary:spaces' => " \t ",
                'ordinary:unset' => '', 'ordinary:text' => "line one\nline two", 'ordinary:custom' => 'raw text',
                'ordinary:integer_zero' => '0', 'ordinary:integer_negative' => '-4',
                'ordinary:float' => '1.25', 'ordinary:float_zero' => '0', 'ordinary:boolean_true' => '1',
                'ordinary:array' => $rows['array']['value'], 'ordinary:hash' => $rows['hash']['value'],
                'sysconfig_choices' => ['ordinary:choice' => '"first"'],
                'csrf_token' => ($options['common_token'] ?? false) ? $commonToken : $selectedToken,
            ];
            foreach ($options['post'] as $key => $value) {
                if ($value === null) {
                    unset($_POST[$key]);
                } else {
                    $_POST[$key] = $value;
                }
            }
            $xtpl = new class {
                public array $calls = [];
                public function __call($name, $args) { $this->calls[] = [$name, $args]; }
            };
            $config = new SystemConfig($api, true);
            register_shutdown_function(function () use ($api, $rows, $xtpl) {
                echo json_encode(['before' => $rows, 'after' => $api->rows, 'updates' => $api->updates,
                    'csrf_remaining' => $_SESSION['csrf_tokens']['system_config']['count'],
                    'notification' => $_SESSION['notification'] ?? null, 'rendered' => $xtpl->calls,
                    'csrf_invalid' => $GLOBALS['csrf_invalid'] ?? false], JSON_PRESERVE_ZERO_FRACTION | JSON_THROW_ON_ERROR);
            });
            require $root . '/forms/cluster.forms.php';
            try {
                if ($options['legacy_common_check'] ?? false) {
                    csrf_check();
                }
                require $root . '/pages/page_cluster.php';
            } catch (CsrfTokenInvalid $e) {
                $GLOBALS['csrf_invalid'] = true;
            }
            PHP;
        $process = proc_open(
            [PHP_BINARY, '-d', 'display_errors=stderr', '-r', $script, dirname(__DIR__, 2)],
            [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['redirect', 1]],
            $pipes
        );
        self::assertIsResource($process);
        fwrite($pipes[0], json_encode(array_replace(['target' => ['category' => 'ordinary', 'name' => $name], 'post' => $overrides], $options), JSON_THROW_ON_ERROR));
        fclose($pipes[0]);
        $stdout = stream_get_contents($pipes[1]);
        fclose($pipes[1]);
        self::assertSame(0, proc_close($process), $stdout);
        self::assertJson($stdout);

        return json_decode($stdout, true, 512, JSON_THROW_ON_ERROR);
    }
}
