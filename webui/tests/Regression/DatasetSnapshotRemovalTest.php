<?php

use PHPUnit\Framework\Attributes\PreserveGlobalState;
use PHPUnit\Framework\TestCase;

#[PreserveGlobalState(false)]
final class DatasetSnapshotRemovalTest extends TestCase
{
    protected function setUp(): void
    {
        $root = dirname(__DIR__, 2);
        require_once $root . '/vendor/autoload.php';
        require_once $root . '/lib/functions.lib.php';
        require_once $root . '/lib/security.lib.php';
        require_once $root . '/lib/xtemplate.lib.php';
        require_once $root . '/forms/dataset.forms.php';
        $_SESSION = ['logged_in' => true, 'is_admin' => true, 'csrf_base' => 'removal-test', 'user' => ['id' => 99]];
        $_GET = ['action' => 'remove_snapshots', 'id' => '7', 'return' => '?page=backup'];
        $_POST = [];
        $_SERVER['REQUEST_METHOD'] = 'GET';
        $GLOBALS['xtpl'] = new XTemplate($root . '/template/template.html');
        $GLOBALS['api'] = self::client();
    }

    public function testCapabilityRequiresAdministratorBothActionsAndCompleteInputsAndOutputs(): void
    {
        global $api;
        self::assertTrue(dataset_snapshot_removal_available());
        $_SESSION['is_admin'] = false;
        self::assertFalse(dataset_snapshot_removal_available());
        $_SESSION['is_admin'] = true;
        unset($api->getDescription()->resources->dataset->actions->preview_snapshot_removal->output->parameters->manifest);
        self::assertFalse(dataset_snapshot_removal_available());
        $api = self::client();
        unset($api->getDescription()->resources->dataset->actions->remove_snapshots->input->parameters->manifest_digest);
        self::assertFalse(dataset_snapshot_removal_available());
        $api = self::client();
        $api->getDescription()->resources->dataset->actions->remove_snapshots->method = 'GET';
        self::assertFalse(dataset_snapshot_removal_available());
    }

    public function testFreshHintsDoNotOptIntoScopeAndDisablePlansStartsChecked(): void
    {
        global $xtpl;
        $_GET += ['recursive' => '1', 'disable_plans' => '0', 'phase' => 'remove', 'confirm' => '1'];
        dataset_snapshot_removal_page();
        $html = $xtpl->text('main.table');
        self::assertDoesNotMatchRegularExpression('/name="recursive"[^>]*checked/', $html);
        self::assertMatchesRegularExpression('/name="disable_plans"[^>]*checked/', $html);
        self::assertStringNotContainsString('name="confirm"', $html);
        self::assertSame([], $GLOBALS['api']->requests);
    }

    public function testCzechCatalogRendersOptionsReviewAndFinalConfirmation(): void
    {
        // LANGUAGE selects the actual compiled catalog without requiring a Czech
        // system locale on the developer machine. Production locale selection is unchanged.
        putenv('LANGUAGE=cs_CZ.utf8');
        setlocale(LC_ALL, 'en_US.utf8');
        bindtextdomain('vpsAdmin', dirname(__DIR__, 2) . '/lang/locale');
        bind_textdomain_codeset('vpsAdmin', 'UTF-8');
        textdomain('vpsAdmin');
        dataset_snapshot_removal_options_form(7, '');
        self::assertStringContainsString('Zobrazit náhled odstranění snapshotů', $GLOBALS['xtpl']->text('main.table'));
        $this->previewPost();
        self::assertStringContainsString('Zkontroloval jsem úplný seznam', $GLOBALS['xtpl']->text('main.table'));
        self::assertStringContainsString('Změnit volby', $GLOBALS['xtpl']->text('main.table'));
        $this->stagePost('continue', ['acknowledge' => '1']);
        self::assertStringContainsString('Závěrečné potvrzení odstranění snapshotů', $GLOBALS['xtpl']->text('main.table'));
        self::assertStringContainsString('Potvrdit trvalé odstranění', $GLOBALS['xtpl']->text('main.table'));
        self::assertStringContainsString('Zpět na kontrolu', $GLOBALS['xtpl']->text('main.table'));
    }

    public function testCompleteManifestIncludesEveryLocationAndEmptyStructureAndEscapesNames(): void
    {
        global $xtpl;
        $p = self::preview();
        for ($i = 100; $i < 135; $i++) {
            $p['manifest']['snapshot_locations'][] = $p['manifest']['snapshot_locations'][0] + [];
            $last = array_key_last($p['manifest']['snapshot_locations']);
            $p['manifest']['snapshot_locations'][$last]['snapshot_id'] = $i;
            $p['manifest']['snapshot_locations'][$last]['snapshot_in_pool_id'] = $i + 100;
            $p['manifest']['snapshot_locations'][$last]['snapshot_name'] = 'source-' . $i;
        }
        $p['manifest']['counts']['snapshots'] += 35;
        $p['manifest']['counts']['snapshot_locations'] += 35;
        $p = dataset_snapshot_removal_validate($p, 7, ['recursive' => false, 'disable_plans' => true]);
        dataset_snapshot_removal_review_form(['dataset' => 7, 'preview' => $p, 'options' => $p['manifest']['options'], 'stage' => 'review', 'nonce' => 'test'], '');
        $html = $xtpl->text('main.table');
        self::assertStringContainsString('source-134', $html);
        self::assertStringContainsString('empty-tree', $html);
        self::assertStringContainsString('empty-branch', $html);
        self::assertStringContainsString('&lt;script&gt;', $html);
        self::assertStringNotContainsString('<script>', $html);
        self::assertSame(2, substr_count($html, 'same-snapshot (#11)'));
        self::assertStringContainsString('name="acknowledge"', $html);
        self::assertStringNotContainsString('name="confirm"', $html);
    }

    public function testMissingInvalidOrIncompleteRowsNeverReachReview(): void
    {
        $cases = [];
        $p = self::preview();
        unset($p['manifest']['snapshot_locations'][0]['snapshot_name']);
        $cases[] = $p;
        $p = self::preview();
        $p['manifest']['counts']['snapshot_locations']++;
        $cases[] = $p;
        $p = self::preview();
        $p['manifest_version'] = 2;
        $cases[] = $p;
        $p = self::preview();
        $p['manifest']['snapshot_locations'][1]['branch_id'] = 999;
        $cases[] = $p;
        $p = self::preview();
        $p['manifest']['snapshot_locations'][] = $p['manifest']['snapshot_locations'][0];
        $cases[] = $p;
        $p = self::preview();
        $p['manifest']['plans'][0]['action'] = 'retain';
        $cases[] = $p;
        $p = self::preview();
        $p['manifest']['trees'][0]['head'] = 'false';
        $cases[] = $p;
        foreach ($cases as $p) {
            try {
                dataset_snapshot_removal_validate($p, 7, ['recursive' => false, 'disable_plans' => true]);
                self::fail('Incomplete manifest accepted');
            } catch (UnexpectedValueException $e) {
                self::assertStringContainsString('inventory', $e->getMessage());
            }
        }
    }

    public function testPreviewAndFirstConfirmationCannotRemoveAndFinalRequiresFreshConfirmation(): void
    {
        $this->previewPost();
        self::assertSame('review', $_SESSION['dataset_snapshot_removal']['stage']);
        self::assertSame(['dataset.preview_snapshot_removal'], array_column($GLOBALS['api']->requests, 'action'));
        $this->stagePost('continue', ['acknowledge' => '1']);
        self::assertSame('final', $_SESSION['dataset_snapshot_removal']['stage']);
        self::assertCount(1, $GLOBALS['api']->requests);
        self::assertStringContainsString('name="confirm"', $GLOBALS['xtpl']->text('main.table'));
        self::assertArrayNotHasKey('confirm', $_POST);
        $this->stagePost('remove');
        self::assertArrayNotHasKey('dataset_snapshot_removal', $_SESSION);
        self::assertCount(1, $GLOBALS['api']->requests);
    }

    public function testDirectFinalAndOptionsPrincipalOrDigestDriftCannotSubmit(): void
    {
        foreach (['direct', 'options', 'principal', 'digest'] as $case) {
            $this->setUp();
            if ($case !== 'direct') {
                $this->previewPost();
                $this->stagePost('continue', ['acknowledge' => '1']);
            }
            $before = count($GLOBALS['api']->requests);
            if ($case === 'principal') {
                $_SESSION['user']['id'] = 100;
            }
            $extra = ['confirm' => '1'];
            if ($case === 'options') {
                $extra['disable_plans'] = '0';
            }
            if ($case === 'digest') {
                $extra['manifest_digest'] = 'v1:' . str_repeat('f', 64);
            }
            $this->stagePost('remove', $extra);
            self::assertCount($before, $GLOBALS['api']->requests);
            self::assertArrayNotHasKey('dataset_snapshot_removal', $_SESSION);
        }
    }

    public function testBackFromFinalReturnsToSameInventoryWithoutRemoval(): void
    {
        $this->previewPost();
        $digest = $_SESSION['dataset_snapshot_removal']['preview']['manifest_digest'];
        $this->stagePost('continue', ['acknowledge' => '1']);
        $this->stagePost('remove', ['return_review' => '1']);
        self::assertSame('review', $_SESSION['dataset_snapshot_removal']['stage']);
        self::assertSame($digest, $_SESSION['dataset_snapshot_removal']['preview']['manifest_digest']);
        self::assertCount(1, $GLOBALS['api']->requests);
    }

    public function testChangingOptionsDiscardsBothConfirmationsBeforeAnyOptionCanBeEdited(): void
    {
        $this->previewPost(['disable_plans' => '0']);
        self::assertStringNotContainsString('type="checkbox" name="disable_plans"', $GLOBALS['xtpl']->text('main.table'));
        $this->stagePost('continue', ['acknowledge' => '1']);
        $this->stagePost('remove', ['change_options' => '1']);
        self::assertArrayNotHasKey('dataset_snapshot_removal', $_SESSION);
        $html = $GLOBALS['xtpl']->text('main.table');
        self::assertStringContainsString('name="disable_plans"', $html);
        self::assertDoesNotMatchRegularExpression('/name="disable_plans"[^>]*checked/', $html);
        self::assertStringNotContainsString('name="confirm"', $html);
        self::assertCount(1, $GLOBALS['api']->requests);
    }

    public function testStaleRejectionClearsBothStagesAndRetainsOptionsWithoutRetry(): void
    {
        $this->previewPost(['disable_plans' => '0']);
        $this->stagePost('continue', ['acknowledge' => '1']);
        $GLOBALS['api']->remove = ['status' => false, 'message' => 'Localized error', 'errors' => (object) ['manifest_digest' => ['stale_preview']]];
        $this->stagePost('remove', ['confirm' => '1']);
        self::assertArrayNotHasKey('dataset_snapshot_removal', $_SESSION);
        self::assertCount(2, $GLOBALS['api']->requests);
        self::assertStringContainsString('The history has changed', $GLOBALS['xtpl']->text('main.perex'));
        self::assertStringNotContainsString('stale_preview', $GLOBALS['xtpl']->text('main.perex'));
        self::assertDoesNotMatchRegularExpression('/name="disable_plans"[^>]*checked/', $GLOBALS['xtpl']->text('main.table'));
    }

    public function testUnknownReceiptConsumesProgressionAndNeverReplays(): void
    {
        $this->previewPost();
        $this->stagePost('continue', ['acknowledge' => '1']);
        $GLOBALS['api']->remove = ['data' => (object) []];
        $this->stagePost('remove', ['confirm' => '1']);
        self::assertArrayNotHasKey('dataset_snapshot_removal', $_SESSION);
        self::assertArrayNotHasKey('notification', $_SESSION);
        self::assertStringContainsString('submission outcome is unknown', $GLOBALS['xtpl']->text('main.perex'));
        self::assertCount(2, $GLOBALS['api']->requests);
        $this->stagePost('remove', ['confirm' => '1']);
        self::assertCount(2, $GLOBALS['api']->requests);
    }

    public function testTransportFailureConsumesProgressionWithoutNotificationOrReplay(): void
    {
        $this->previewPost();
        $this->stagePost('continue', ['acknowledge' => '1']);
        $GLOBALS['api']->failure = new RuntimeException('connection lost');
        try {
            $this->stagePost('remove', ['confirm' => '1']);
            self::fail('Transport exception hidden');
        } catch (RuntimeException $e) {
            self::assertSame('connection lost', $e->getMessage());
        }
        self::assertArrayNotHasKey('dataset_snapshot_removal', $_SESSION);
        self::assertArrayNotHasKey('notification', $_SESSION);
        $this->stagePost('remove', ['confirm' => '1']);
        self::assertCount(2, $GLOBALS['api']->requests);
    }

    public function testEmptyPlanlessHistoryStillHasTwoStages(): void
    {
        $preview = self::preview();
        foreach (['snapshot_locations', 'trees', 'branches', 'plans'] as $key) {
            $preview['manifest'][$key] = [];
            $preview['manifest']['counts'][$key] = 0;
        }
        $preview['manifest']['counts']['snapshots'] = 0;
        $preview['manifest']['counts']['plans_to_disable'] = 0;
        $GLOBALS['api']->preview = $preview;
        $this->previewPost();
        self::assertSame('review', $_SESSION['dataset_snapshot_removal']['stage']);
        $this->stagePost('continue', ['acknowledge' => '1']);
        self::assertSame('final', $_SESSION['dataset_snapshot_removal']['stage']);
        self::assertCount(1, $GLOBALS['api']->requests);
    }

    public function testAcceptedRemovalUsesOneRealClientRequestAndNormalNotificationThenRedirect(): void
    {
        $script = tempnam(sys_get_temp_dir(), 'snapshot-removal-');
        file_put_contents($script, <<<'PHP'
            <?php
            $root = $argv[1];
            require $root . '/vendor/autoload.php';
            require $root . '/lib/functions.lib.php';
            require $root . '/lib/security.lib.php';
            require $root . '/lib/xtemplate.lib.php';
            require $root . '/forms/dataset.forms.php';
            require $root . '/tests/Regression/DatasetSnapshotRemovalTest.php';
            $api = DatasetSnapshotRemovalTest::client();
            $_SESSION = ['logged_in' => true, 'is_admin' => true, 'csrf_base' => 'acceptance', 'user' => ['id' => 99]];
            $_GET = ['action' => 'remove_snapshots', 'id' => '7', 'return' => '?page=backup'];
            $_SERVER['REQUEST_METHOD'] = 'POST';
            foreach (['preview', 'continue', 'remove'] as $phase) {
                $state = $_SESSION['dataset_snapshot_removal'] ?? null;
                $_POST = ['phase' => $phase, 'recursive' => '0', 'disable_plans' => '0', 'acknowledge' => '1', 'confirm' => '1',
                    'manifest_digest' => $state['preview']['manifest_digest'] ?? '',
                    'csrf_token' => csrf_token($state ? 'dataset_snapshot_removal:' . $state['nonce'] . ':' . $state['stage'] : 'dataset_snapshot_removal:preview:7', 1)];
                $api->options = ['recursive' => false, 'disable_plans' => false];
                $xtpl = new XTemplate($root . '/template/template.html');
                if ($phase === 'remove') {
                    register_shutdown_function(function () use ($api) {
                        echo json_encode(['requests' => $api->requests, 'notification' => $_SESSION['notification'] ?? null,
                            'review' => $_SESSION['dataset_snapshot_removal'] ?? null], JSON_THROW_ON_ERROR);
                    });
                }
                dataset_snapshot_removal_page();
            }
            throw new RuntimeException('Accepted removal did not redirect');
            PHP);
        try {
            $process = proc_open([PHP_BINARY, $script, dirname(__DIR__, 2)], [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes);
            self::assertIsResource($process);
            fclose($pipes[0]);
            $stdout = stream_get_contents($pipes[1]);
            $stderr = stream_get_contents($pipes[2]);
            fclose($pipes[1]);
            fclose($pipes[2]);
            self::assertSame(0, proc_close($process), $stderr);
            self::assertSame('', $stderr);
            $result = json_decode($stdout, true, flags: JSON_THROW_ON_ERROR);
            self::assertSame(['dataset.preview_snapshot_removal', 'dataset.remove_snapshots'], array_column($result['requests'], 'action'));
            self::assertSame(['recursive' => false, 'disable_plans' => false, 'manifest_digest' => self::preview()['manifest_digest']], $result['requests'][1]['params']);
            self::assertSame('/v7.0/datasets/7/remove_snapshots', $result['requests'][1]['path']);
            self::assertSame('POST', $result['requests'][1]['method']);
            self::assertSame('dataset', $result['requests'][1]['input_namespace']);
            self::assertSame('Snapshot and backup history removal has been queued.', $result['notification']['title']);
            self::assertNull($result['review']);
        } finally {
            unlink($script);
        }
    }

    public function testMissingOrCrossDatasetCsrfRejectsBeforePreview(): void
    {
        $_SERVER['REQUEST_METHOD'] = 'POST';
        $_POST = ['phase' => 'preview', 'csrf_token' => csrf_token('dataset_snapshot_removal:preview:8', 1)];
        $this->expectException(CsrfTokenInvalid::class);
        dataset_snapshot_removal_page();
    }

    private function previewPost(array $options = []): void
    {
        $_SERVER['REQUEST_METHOD'] = 'POST';
        $_POST = $options + ['phase' => 'preview', 'recursive' => '0', 'disable_plans' => '1', 'csrf_token' => csrf_token('dataset_snapshot_removal:preview:7', 1)];
        $GLOBALS['api']->options = dataset_snapshot_removal_options($_POST);
        $this->page();
    }

    private function stagePost(string $phase, array $extra = []): void
    {
        $s = $_SESSION['dataset_snapshot_removal'] ?? null;
        $_SERVER['REQUEST_METHOD'] = 'POST';
        $_POST = $extra + ['phase' => $phase, 'recursive' => ($s['options']['recursive'] ?? false) ? '1' : '0', 'disable_plans' => ($s['options']['disable_plans'] ?? true) ? '1' : '0',
            'manifest_digest' => $s['preview']['manifest_digest'] ?? self::preview()['manifest_digest'],
            'csrf_token' => $s ? csrf_token('dataset_snapshot_removal:' . $s['nonce'] . ':' . $s['stage'], 1) : 'invalid'];
        $this->page();
    }

    private function page(): void
    {
        $GLOBALS['xtpl'] = new XTemplate(dirname(__DIR__, 2) . '/template/template.html');
        global $api, $xtpl;
        require dirname(__DIR__, 2) . '/pages/page_dataset.php';
    }

    public static function preview(array $options = ['recursive' => false, 'disable_plans' => true]): array
    {
        return ['manifest_version' => 1, 'manifest_digest' => 'v1:' . str_repeat('a', 64), 'manifest' => [
            'root_dataset_id' => 7, 'options' => $options,
            'datasets' => [['id' => 7, 'parent_id' => null, 'user_id' => 9, 'name' => '<script>', 'full_name' => '<script>', 'current_history_id' => 0]],
            'copies' => array_map(static fn($role, $id) => ['id' => $id, 'dataset_id' => 7, 'pool_id' => $id, 'pool_label' => 'pool-' . $role, 'pool_role' => $role, 'pool_filesystem' => 'tank/data', 'pool_open' => true, 'node_id' => 1, 'node_name' => 'node'], ['primary', 'backup'], [1, 2]),
            'snapshot_locations' => array_map(static fn($copy) => ['snapshot_id' => 11, 'snapshot_name' => 'same-snapshot', 'snapshot_label' => null, 'created_at' => '2026-11-26T00:00:00Z', 'history_id' => 0, 'dataset_in_pool_id' => $copy, 'snapshot_in_pool_id' => $copy + 10, 'snapshot_in_pool_in_branch_id' => $copy === 2 ? 31 : null, 'branch_id' => $copy === 2 ? 21 : null, 'origin_snapshot_in_pool_in_branch_id' => null], [1, 2]),
            'trees' => [['id' => 20, 'dataset_in_pool_id' => 2, 'name' => 'tree', 'head' => true], ['id' => 22, 'dataset_in_pool_id' => 2, 'name' => 'empty-tree', 'head' => false]],
            'branches' => [['id' => 21, 'dataset_tree_id' => 20, 'name' => 'branch', 'head' => true], ['id' => 23, 'dataset_tree_id' => 22, 'name' => 'empty-branch', 'head' => false]],
            'plans' => [['id' => 30, 'dataset_in_pool_id' => 1, 'environment_dataset_plan_id' => 40, 'dataset_plan_id' => 50, 'name' => 'daily', 'action' => $options['disable_plans'] ? 'remove' : 'retain']],
            'counts' => ['datasets' => 1, 'copies' => 2, 'snapshots' => 1, 'snapshot_locations' => 2, 'trees' => 2, 'branches' => 2, 'plans' => 1, 'plans_to_disable' => $options['disable_plans'] ? 1 : 0],
        ]];
    }

    public static function client(): \HaveAPI\Client
    {
        $client = new class ('https://api.example') extends \HaveAPI\Client {
            public array $requests = [];
            public array $options = ['recursive' => false, 'disable_plans' => true];
            public array $remove = ['chain' => 42];
            public ?array $preview = null;
            public ?Throwable $failure = null;
            public function directCall(\HaveAPI\Client\Action $action, $params = [], &$time = null)
            {
                $key = 'dataset.' . $action->name();
                $this->requests[] = ['action' => $key, 'params' => $params, 'path' => $action->path(), 'method' => $action->httpMethod(), 'input_namespace' => $action->getNamespace('input')];
                if ($action->name() === 'remove_snapshots' && $this->failure) {
                    throw $this->failure;
                }
                $entry = $action->name() === 'preview_snapshot_removal' ? ['data' => $this->preview ?? DatasetSnapshotRemovalTest::preview($this->options)] : $this->remove;
                $time = 0.0;
                if (isset($entry['envelope'])) {
                    return (object) ['code' => 200, 'body' => $entry['envelope']];
                }
                return (object) ['code' => 200, 'body' => (object) ['status' => $entry['status'] ?? true, 'message' => $entry['message'] ?? '', 'errors' => $entry['errors'] ?? (object) [],
                    'response' => ($entry['status'] ?? true) ? (object) ['dataset' => $entry['data'] ?? (object) [], '_meta' => (object) ['action_state_id' => $entry['chain'] ?? null, 'path_params' => [7]]] : null]];
            }
        };
        $action = static fn($name, $input, $output, $layout = 'hash') => (object) ['aliases' => [], 'method' => 'POST', 'path' => '/v7.0/datasets/{dataset_id}/' . $name, 'blocking' => $name === 'remove_snapshots', 'meta' => (object) [],
            'input' => (object) ['layout' => 'hash', 'namespace' => 'dataset', 'parameters' => (object) $input],
            'output' => (object) ['layout' => $layout, 'namespace' => 'dataset', 'parameters' => (object) $output]];
        $booleans = ['recursive' => (object) ['type' => 'Boolean'], 'disable_plans' => (object) ['type' => 'Boolean']];
        $client->setDescription((object) ['authentication' => (object) [], 'meta' => (object) ['namespace' => '_meta'], 'resources' => (object) ['dataset' => (object) ['resources' => (object) [], 'actions' => (object) [
            'preview_snapshot_removal' => $action('preview_snapshot_removal', $booleans, ['manifest_version' => (object) ['type' => 'Integer'], 'manifest_digest' => (object) ['type' => 'String'], 'manifest' => (object) ['type' => 'Custom']]),
            'remove_snapshots' => $action('remove_snapshots', $booleans + ['manifest_digest' => (object) ['type' => 'String']], [], 'object'),
        ]]]]);
        return $client;
    }
}
