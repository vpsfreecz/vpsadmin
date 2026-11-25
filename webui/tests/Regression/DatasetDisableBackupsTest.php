<?php

use PHPUnit\Framework\Attributes\PreserveGlobalState;
use PHPUnit\Framework\TestCase;

#[PreserveGlobalState(false)]
final class DatasetDisableBackupsTest extends TestCase
{
    protected function setUp(): void
    {
        $root = dirname(__DIR__, 2);
        require_once $root . '/vendor/autoload.php';
        require_once $root . '/lib/functions.lib.php';
        require_once $root . '/lib/security.lib.php';
        require_once $root . '/lib/xtemplate.lib.php';
        require_once $root . '/forms/dataset.forms.php';
        $_SESSION = ['logged_in' => true, 'is_admin' => true, 'csrf_base' => 'disable-backups-test'];
        $_GET = ['action' => 'disable_backups', 'id' => '7', 'recursive' => '0', 'role' => 'hypervisor', 'return' => '?page=backup'];
        $_POST = [];
        $_SERVER['REQUEST_METHOD'] = 'GET';
        $GLOBALS['xtpl'] = new XTemplate($root . '/template/template.html');
        $GLOBALS['api'] = self::client();
    }

    public function testCapabilityAndAdministratorGates(): void
    {
        global $api;
        self::assertTrue(dataset_disable_backups_available());
        $_SESSION['is_admin'] = false;
        self::assertFalse(dataset_disable_backups_available());
        $_SERVER['REQUEST_METHOD'] = 'POST';
        $this->page();
        self::assertSame([], $api->requests);
        $_SESSION['is_admin'] = true;
        unset($api->getDescription()->resources->dataset->actions->disable_backups->input->parameters->backup_first);
        self::assertFalse(dataset_disable_backups_available());
    }

    public function testPlanlessFormsContainExplanationThenAdminCleanupWithOldBackendSupport(): void
    {
        global $api, $xtpl;
        $plans = new class {
            public function list()
            {
                return [];
            }
        };
        $dataset = (object) ['id' => 7, 'plan' => $plans, 'environment' => (object) ['dataset_plan' => $plans]];
        dataset_backup_plans_form($dataset);
        $html = $xtpl->text('main.table');
        preg_match_all('/<form\b.*?<\/form>/s', $html, $forms);
        self::assertCount(2, $forms[0]);
        self::assertStringContainsString('action=plan_add', $forms[0][0]);
        self::assertStringContainsString('Removing this plan stops the snapshots and transfers scheduled by it. Existing snapshots remain on primary and backup pools.', $forms[0][0]);
        self::assertStringContainsString('action=disable_backups', $forms[0][1]);
        self::assertMatchesRegularExpression('/name="recursive"[^>]*\/>/', $forms[0][1]);
        self::assertDoesNotMatchRegularExpression('/name="recursive"[^>]*checked/', $forms[0][1]);
        self::assertMatchesRegularExpression('/name="backup_first"[^>]*checked/', $forms[0][1]);
        self::assertStringNotContainsString('action=disable_backups', $xtpl->text('main.perex'));
        self::assertStringNotContainsString('Existing snapshots remain', $xtpl->text('main.perex'));
        unset($api->getDescription()->resources->dataset->actions->disable_backups);
        $xtpl = new XTemplate(dirname(__DIR__, 2) . '/template/template.html');
        dataset_backup_plans_form($dataset);
        self::assertStringNotContainsString('action=disable_backups', $xtpl->text('main.table'));
        self::assertStringContainsString('Existing snapshots remain on primary and backup pools.', $xtpl->text('main.table'));
    }

    public function testConfirmationUsesConciseCopyCompleteRowsAndScopedPost(): void
    {
        global $api, $xtpl;
        $_GET['recursive'] = '1';
        $this->page();
        $html = $xtpl->text('main.table');
        self::assertStringContainsString('method="post"', $html);
        self::assertStringContainsString('name="backup_first" value="0"', $html);
        self::assertMatchesRegularExpression('/name="backup_first"[^>]*checked/', $html);
        self::assertDoesNotMatchRegularExpression('/name="recursive"[^>]*checked/', $html);
        self::assertMatchesRegularExpression('/name="confirm"[^>]*required/', $html);
        self::assertDoesNotMatchRegularExpression('/name="confirm"[^>]*checked/', $html);
        self::assertStringContainsString('>Confirm</label>', $html);
        self::assertStringContainsString('name="csrf_token"', $html);
        $document = new DOMDocument();
        $old = libxml_use_internal_errors(true);
        $document->loadHTML($html);
        libxml_clear_errors();
        libxml_use_internal_errors($old);
        $xpath = new DOMXPath($document);
        self::assertSame(1, $xpath->query('//form//p')->length);
        self::assertSame('This removes the selected datasets from all backup plans and deletes their local snapshots. Backups are preserved. Re-enabling backups will require a full transfer.', $xpath->evaluate('string(//form//p)'));
        self::assertSame('2', $xpath->evaluate('string(//form//p/parent::td/@colspan)'));
        foreach ($xpath->query('//form//tr[td]') as $row) {
            $width = 0;
            foreach ($xpath->query('./td', $row) as $cell) {
                $width += (int) $cell->getAttribute('colspan');
            }
            self::assertSame(2, $width, 'Every form row spans both columns');
        }
        foreach (['This action applies', 'all primary snapshots', 'If selected', 'If you turn this option off', 'does not create a new snapshot', 'If a snapshot cannot be preserved'] as $removed) {
            self::assertStringNotContainsString($removed, $html);
        }
        self::assertSame(['dataset.show'], array_column($api->requests, 'action'));
        self::assertSame(1, $_SESSION['csrf_tokens']['dataset_disable_backups:7']['count']);
    }

    public function testMissingAndCrossDatasetCsrfRejectBeforeMutation(): void
    {
        global $api;
        $_SERVER['REQUEST_METHOD'] = 'POST';
        $_GET['recursive'] = '1';
        $token = csrf_token('dataset_disable_backups:8', 1);
        foreach ([[], ['csrf_token' => $token]] as $post) {
            $_POST = $post + ['confirm' => '1'];
            try {
                $this->page();
                self::fail('Invalid CSRF accepted');
            } catch (CsrfTokenInvalid $e) {
                self::assertSame([], $api->requests);
            }
        }
    }

    public function testGetAndUnconfirmedPostDoNotSubmit(): void
    {
        global $api;
        $_GET['confirm'] = '1';
        $this->page();
        $_SERVER['REQUEST_METHOD'] = 'POST';
        $_POST = ['recursive' => '1', 'backup_first' => '0'];
        $this->page();
        self::assertSame(['dataset.show', 'dataset.show'], array_column($api->requests, 'action'));
    }

    public function testFreshGetHintsNeverOptIntoRecursion(): void
    {
        global $api, $xtpl;
        foreach ([null, '0', '1'] as $hint) {
            $api = self::client();
            $xtpl = new XTemplate(dirname(__DIR__, 2) . '/template/template.html');
            if ($hint === null) {
                unset($_GET['recursive']);
            } else {
                $_GET['recursive'] = $hint;
            }
            $this->page();
            $html = $xtpl->text('main.table');
            self::assertDoesNotMatchRegularExpression('/name="recursive"[^>]*checked/', $html);
            self::assertMatchesRegularExpression('/name="backup_first"[^>]*checked/', $html);
            self::assertDoesNotMatchRegularExpression('/name="confirm"[^>]*checked/', $html);
        }
    }

    public function testActualObjectLayoutReturnsResourceInstance(): void
    {
        $api = self::client([['chain' => 42]]);
        $result = $api->dataset(7)->disable_backups(['recursive' => false, 'backup_first' => true]);
        self::assertInstanceOf(\HaveAPI\Client\ResourceInstance::class, $result);
        self::assertSame(42, $result->getApiResponse()->getMeta()->action_state_id);
        self::assertSame([], $result->attributes());
    }

    public function testAcceptedPostUsesOneOrdinaryCallNotificationAndRedirect(): void
    {
        foreach ([[[], false, true], [['recursive' => '1'], true, true],
            [['backup_first' => '0'], false, false], [['recursive' => '1', 'backup_first' => '0'], true, false]] as [$options, $recursive, $backupFirst]) {
            $result = $this->post('accepted', $options);
            self::assertSame('?page=backup', $result['redirect']);
            self::assertSame(['title' => 'Backups are being disabled and local snapshots are being removed.', 'msg' => ''], $result['notification']);
            self::assertSame([['action' => 'dataset.disable_backups', 'params' => ['recursive' => $recursive, 'backup_first' => $backupFirst], 'path' => '/v7.0/datasets/7/disable_backups', 'method' => 'POST', 'input_namespace' => 'dataset']], $result['requests']);
            self::assertSame([], $result['exceptions']);
            self::assertSame([], $result['errors']);
            $_SESSION['notification'] = $result['notification'];
            show_notification();
            self::assertStringContainsString($result['notification']['title'], $GLOBALS['xtpl']->text('main.perex'));
            self::assertArrayNotHasKey('notification', $_SESSION);
        }
    }

    public function testRejectedPostUsesOrdinaryErrorsAndRegularEditor(): void
    {
        $result = $this->post('rejected');
        self::assertSame([['Cannot disable backups', 'Uncovered snapshot']], $result['errors']);
        self::assertSame('dataset editor', $result['content']);
        self::assertNull($result['notification']);
        self::assertNull($result['redirect']);
        self::assertCount(1, $result['requests']);
    }

    public function testTransportAndResponseExceptionsNeverNotifyRedirectOrReplay(): void
    {
        foreach (['transport', 'response'] as $case) {
            $result = $this->post($case);
            self::assertNull($result['notification']);
            self::assertNull($result['redirect']);
            self::assertCount(1, $result['exceptions']);
            self::assertCount(1, $result['requests']);
            self::assertSame([], $result['errors']);
        }
    }

    public function testDuplicatePostIsRejectedAndFreshConfirmationCanSubmitAfterRejection(): void
    {
        $duplicate = $this->post('duplicate');
        self::assertSame(['CsrfTokenInvalid'], $duplicate['exceptions']);
        self::assertCount(1, $duplicate['requests']);
        $reconfirmed = $this->post('reconfirm');
        self::assertCount(2, $reconfirmed['requests']);
        self::assertSame('?page=backup', $reconfirmed['redirect']);
        self::assertSame([], $reconfirmed['exceptions']);
    }

    public function testInvalidSubmittedBooleansRejectBeforeMutation(): void
    {
        foreach ([['recursive' => 'false'], ['backup_first' => 'false']] as $options) {
            $result = $this->post('accepted', $options);
            self::assertSame(['InvalidArgumentException'], $result['exceptions']);
            self::assertSame([], $result['requests']);
            self::assertNull($result['notification']);
            self::assertNull($result['redirect']);
        }
    }

    private function page(): void
    {
        global $api, $xtpl;
        require dirname(__DIR__, 2) . '/pages/page_dataset.php';
    }

    private function post(string $case, array $options = []): array
    {
        $script = tempnam(sys_get_temp_dir(), 'dataset-disable-post-');
        // Stub only dispatch/UI boundaries; the SDK, wire envelope and CSRF are real.
        $code = <<<'PHP'
            <?php
            $root = $argv[1];
            require $root . '/vendor/autoload.php';
            require $root . '/tests/Regression/DatasetDisableBackupsTest.php';
            require $root . '/lib/security.lib.php';
            $case = $argv[2];
            $options = json_decode($argv[3], true, flags: JSON_THROW_ON_ERROR);
            $entry = match ($case) {
                'rejected', 'reconfirm' => ['status' => false, 'message' => 'Uncovered snapshot'],
                'transport' => new RuntimeException('transport failure'),
                'response' => new TypeError('response failure'),
                default => ['chain' => 42],
            };
            $api = DatasetDisableBackupsTest::client([$entry, ['chain' => 43]]);
            $_SESSION = ['is_admin' => true, 'logged_in' => true, 'csrf_base' => 'route-test'];
            $_GET = ['action' => 'disable_backups', 'id' => '7', 'role' => 'hypervisor', 'recursive' => ($options['recursive'] ?? '0') === '1' ? '0' : '1', 'return' => '?page=backup'];
            $_SERVER['REQUEST_METHOD'] = 'POST';
            $_POST = $options + ['confirm' => '1', 'csrf_token' => csrf_token('dataset_disable_backups:7', 1)];
            $result = ['redirect' => null, 'notification' => null, 'content' => null, 'errors' => [], 'exceptions' => []];
            $xtpl = new class {
                public function perex_format_errors($title, $response) {
                    $GLOBALS['result']['errors'][] = [$title, $response->getMessage()];
                }
            };
            class Redirected extends Exception {}
            function redirect($target) { $GLOBALS['result']['redirect'] = $target; throw new Redirected(); }
            function notify_user($title, $msg = '') { $GLOBALS['result']['notification'] = compact('title', 'msg'); }
            function isLoggedIn() { return true; }
            function isAdmin() { return true; }
            function dataset_disable_backups_available() { return true; }
            function local_redirect_target($target, $fallback = '?page=') { return $target ?: $fallback; }
            function dataset_edit_form() { $GLOBALS['result']['content'] = 'dataset editor'; }
            if (!function_exists('_')) { function _($s) { return $s; } }
            for ($attempt = 0; $attempt < (in_array($case, ['duplicate', 'reconfirm'], true) ? 2 : 1); $attempt++) {
                if ($attempt === 1 && $case === 'reconfirm') {
                    $_POST['csrf_token'] = csrf_token('dataset_disable_backups:7', 1);
                }
                try { require $root . '/pages/page_dataset.php'; }
                catch (Redirected $e) {}
                catch (Throwable $e) { $result['exceptions'][] = get_class($e); }
            }
            $result['requests'] = $api->requests;
            echo json_encode($result, JSON_THROW_ON_ERROR);
            PHP;
        file_put_contents($script, $code);
        try {
            $process = proc_open([PHP_BINARY, $script, dirname(__DIR__, 2), $case, json_encode($options)], [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes);
            self::assertIsResource($process);
            fclose($pipes[0]);
            $stdout = stream_get_contents($pipes[1]);
            $stderr = stream_get_contents($pipes[2]);
            fclose($pipes[1]);
            fclose($pipes[2]);
            self::assertSame(0, proc_close($process), $stderr);
            self::assertSame('', $stderr);
            return json_decode($stdout, true, flags: JSON_THROW_ON_ERROR);
        } finally {
            unlink($script);
        }
    }

    public static function client(array $mutations = []): \HaveAPI\Client
    {
        $client = new class ('https://api.example') extends \HaveAPI\Client {
            public array $requests = [];
            public array $responses = [];
            public array $envelopes = [];
            public function directCall(\HaveAPI\Client\Action $action, $params = [], &$time = null)
            {
                $key = $action->getResource()->getName() . '.' . $action->name();
                $this->requests[] = ['action' => $key, 'params' => $params, 'path' => $action->path(), 'method' => $action->httpMethod(), 'input_namespace' => $action->getNamespace('input')];
                $entry = array_shift($this->responses[$key]);
                if ($entry instanceof Throwable) {
                    throw $entry;
                }
                if ($entry === null) {
                    throw new RuntimeException('Unexpected call ' . $key);
                }
                $time = 0.0;
                $body = (object) [
                    'status' => $entry['status'] ?? true, 'message' => $entry['message'] ?? '', 'errors' => (object) [],
                    'response' => (object) [$action->getNamespace('output') => $entry['data'] ?? (object) [],
                        '_meta' => (object) ['action_state_id' => $entry['chain'] ?? null, 'path_params' => $action->getLastArgs()]],
                ];
                $this->envelopes[] = $body;
                return (object) ['code' => 200, 'body' => $body];
            }
        };
        $action = static fn($namespace, $method, $path, $layout, $input, $output) => (object) [
            'aliases' => $method === 'GET' && $layout === 'object' ? ['find'] : [], 'method' => $method, 'path' => $path, 'blocking' => $method === 'POST', 'meta' => (object) [],
            'input' => (object) ['layout' => 'hash', 'namespace' => $namespace, 'parameters' => (object) $input],
            'output' => (object) ['layout' => $layout, 'namespace' => $namespace, 'parameters' => (object) $output],
        ];
        $client->setDescription((object) ['authentication' => (object) [], 'meta' => (object) ['namespace' => '_meta'], 'resources' => (object) [
            'dataset' => (object) ['resources' => (object) [
                'plan' => (object) ['resources' => (object) [], 'actions' => (object) [
                    'list' => $action('plan', 'GET', '/v7.0/datasets/{dataset_id}/plans', 'object_list', [], []),
                ]],
            ], 'actions' => (object) [
                'disable_backups' => $action(
                    'dataset',
                    'POST',
                    '/v7.0/datasets/{dataset_id}/disable_backups',
                    'object',
                    ['recursive' => (object) ['type' => 'Boolean'], 'backup_first' => (object) ['type' => 'Boolean']],
                    []
                ),
                'show' => $action('dataset', 'GET', '/v7.0/datasets/{dataset_id}', 'object', [], ['id' => (object) ['type' => 'Integer'], 'name' => (object) ['type' => 'String']]),
            ]],
        ]]);
        $dataset = (object) ['id' => 7, 'name' => 'root', '_meta' => (object) ['resolved' => true, 'path_params' => [7]]];
        $client->responses = ['dataset.disable_backups' => $mutations,
            'dataset.show' => array_fill(0, 3, ['data' => $dataset]), 'plan.list' => [['data' => []]]];
        return $client;
    }
}
