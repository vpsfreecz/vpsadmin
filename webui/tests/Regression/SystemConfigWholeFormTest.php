<?php

use PHPUnit\Framework\TestCase;

final class SystemConfigWholeFormTest extends TestCase
{
    public function testIdenticalWholeFormDoesNotWriteOrNormalizeAnySetting(): void
    {
        $result = $this->submit();

        self::assertSame([], $result['updates']);
        self::assertSame($result['before'], $result['after']);
        self::assertSame(1, $result['csrf_remaining']);
        self::assertSame('Changes saved', $result['notification']['title']);
    }

    public function testUnrelatedEditLeavesNullZeroFalseYamlAndUnsupportedChoicesUntouched(): void
    {
        $result = $this->submit(['ordinary:string' => 'edited']);

        self::assertCount(1, $result['updates']);
        self::assertSame(['system_config' => ['value' => 'edited']], $result['updates'][0]['body']);
        self::assertSame('https://api.example.test/v7.0/system_configs/ordinary/string', $result['updates'][0]['uri']);
        self::assertSame('cs', $result['updates'][0]['headers']['Accept-Language']);
        self::assertSame('synthetic-token', $result['updates'][0]['headers']['X-Test-Token']);
        $expected = $result['before'];
        $expected['string']['value'] = 'edited';
        self::assertSame($expected, $result['after']);
    }

    public function testOrdinaryEditsRetainExistingCheckboxNumberAndTextareaTransport(): void
    {
        $result = $this->submit([
            'ordinary:boolean_true' => null,
            'ordinary:integer_zero' => '-7',
            'ordinary:float' => '2.5',
            'ordinary:text' => " edited\ntext ",
            'ordinary:custom' => '{"items":[false,0,null]}',
        ]);
        $sent = [];

        foreach ($result['updates'] as $request) {
            $sent[basename($request['uri'])] = $request['body']['system_config']['value'];
        }

        self::assertSame([
            'text' => " edited\ntext ",
            'custom' => '{"items":[false,0,null]}',
            'integer_zero' => '-7',
            'float' => '2.5',
            'boolean_true' => '0',
        ], $sent);
        foreach ($result['before'] as $name => $row) {
            if (!array_key_exists($name, $sent)) {
                self::assertSame($row, $result['after'][$name]);
            }
        }
    }

    public function testBrowserTextareaLineEndingsResendOnlyTheYamlFields(): void
    {
        $array = "---\r\n- false\r\n- 0\r\n- ''\r\n-\r\n";
        $hash = "---\r\nzero: 0\r\nempty: ''\r\nnested:\r\n- false\r\n-\r\n";
        $result = $this->submit(['ordinary:array' => $array, 'ordinary:hash' => $hash]);

        self::assertSame([$array, $hash], array_map(fn($request) => $request['body']['system_config']['value'], $result['updates']));
        foreach ($result['before'] as $name => $row) {
            if (!in_array($name, ['array', 'hash'], true)) {
                self::assertSame($row, $result['after'][$name]);
            }
        }
    }

    private function submit(array $overrides = []): array
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
                'unsupported_choice' => ['String', 'retained unsupported value'],
            ];
            $rows = [];
            foreach ($values as $name => [$type, $value]) {
                $rows[$name] = ['category' => 'ordinary', 'name' => $name, 'type' => $type,
                    'value' => $value, 'choices' => null, 'value_nullable' => null];
            }
            foreach (['choice', 'unsupported_choice'] as $name) {
                $rows[$name]['choices'] = [['value' => 'first', 'label' => 'First']];
                $rows[$name]['value_nullable'] = false;
            }
            $api = new class ('https://api.example.test') extends \HaveAPI\Client {
                public array $rows = [];
                public array $updates = [];

                protected function sendRequest($request, $action = null, $params = [])
                {
                    if ($request->method === 'PUT') {
                        $body = json_decode($request->payload, true, 512, JSON_THROW_ON_ERROR);
                        $this->updates[] = ['uri' => $request->uri, 'body' => $body, 'headers' => $request->headers];
                        $name = basename($request->uri);
                        $this->rows[$name]['value'] = $body['system_config']['value'];
                        $response = ['system_config' => (object) $this->rows[$name]];
                    } else {
                        $response = ['system_configs' => array_map(fn($row) => (object) $row, array_values($this->rows))];
                    }
                    $response['_meta'] = (object) [];
                    return (object) ['code' => 200, 'body' => (object) ['status' => true, 'response' => (object) $response]];
                }
            };
            $api->rows = $rows;
            $output = (object) ['category' => (object) ['type' => 'String'],
                'name' => (object) ['type' => 'String'], 'value' => (object) ['type' => 'Custom']];
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
                        'update' => (object) ['aliases' => [], 'method' => 'PUT', 'path' => '/v7.0/system_configs/{category}/{name}',
                            'input' => (object) ['layout' => 'object', 'namespace' => 'system_config',
                                'parameters' => (object) ['value' => (object) ['type' => 'Custom', 'nullable' => true, 'required' => false]]],
                            'output' => (object) ['layout' => 'object', 'namespace' => 'system_config', 'parameters' => $output],
                            'meta' => (object) []],
                    ]]],
            ]);
            $api->authenticate('token', ['token' => 'synthetic-token'], false);
            $api->setLanguage('cs');
            $_SESSION = ['is_admin' => true, 'csrf_base' => 'synthetic'];
            $_GET = ['action' => 'sysconfig_save'];
            $_POST = [
                'ordinary:string' => 'original', 'ordinary:empty' => '', 'ordinary:spaces' => " \t ",
                'ordinary:unset' => '', 'ordinary:text' => "line one\nline two", 'ordinary:custom' => 'raw text',
                'ordinary:integer_zero' => '0', 'ordinary:integer_negative' => '-4',
                'ordinary:float' => '1.25', 'ordinary:float_zero' => '0', 'ordinary:boolean_true' => '1',
                'ordinary:array' => $rows['array']['value'], 'ordinary:hash' => $rows['hash']['value'],
                'sysconfig_choices' => ['ordinary:choice' => '"first"'], 'csrf_token' => csrf_token('common', 2),
            ];
            foreach (json_decode(file_get_contents('php://stdin'), true, 512, JSON_THROW_ON_ERROR) as $key => $value) {
                if ($value === null) {
                    unset($_POST[$key]);
                } else {
                    $_POST[$key] = $value;
                }
            }
            $xtpl = new class {
                public function __call($name, $args) {}
            };
            $config = new SystemConfig($api, true);
            register_shutdown_function(function () use ($api, $rows) {
                echo json_encode(['before' => $rows, 'after' => $api->rows, 'updates' => $api->updates,
                    'csrf_remaining' => $_SESSION['csrf_tokens']['common']['count'],
                    'notification' => $_SESSION['notification'] ?? null], JSON_PRESERVE_ZERO_FRACTION | JSON_THROW_ON_ERROR);
            });
            require $root . '/pages/page_cluster.php';
            PHP;
        $process = proc_open(
            [PHP_BINARY, '-d', 'display_errors=stderr', '-r', $script, dirname(__DIR__, 2)],
            [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['redirect', 1]],
            $pipes
        );
        self::assertIsResource($process);
        fwrite($pipes[0], json_encode($overrides, JSON_THROW_ON_ERROR));
        fclose($pipes[0]);
        $stdout = stream_get_contents($pipes[1]);
        fclose($pipes[1]);
        self::assertSame(0, proc_close($process), $stdout);
        self::assertJson($stdout);

        return json_decode($stdout, true, 512, JSON_THROW_ON_ERROR);
    }
}
