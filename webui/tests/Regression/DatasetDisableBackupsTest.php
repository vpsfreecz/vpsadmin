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
        $_GET = ['id' => '7', 'recursive' => '0', 'role' => 'hypervisor', 'return' => '?page=backup'];
        $_POST = [];
        $_SERVER['REQUEST_METHOD'] = 'GET';
        $GLOBALS['xtpl'] = new XTemplate($root . '/template/template.html');
        $GLOBALS['api'] = $this->client();
    }

    public function testSafeDefaultAndExplicitOptOut(): void
    {
        self::assertTrue(dataset_disable_backups_option([]));
        self::assertTrue(dataset_disable_backups_option(['backup_first' => '1']));
        self::assertFalse(dataset_disable_backups_option(['backup_first' => '0']));
        $this->expectException(InvalidArgumentException::class);
        dataset_disable_backups_option(['backup_first' => 'false']);
    }

    public function testCapabilityAndAdministratorGates(): void
    {
        global $api;
        self::assertTrue(dataset_disable_backups_available());
        $_SESSION['is_admin'] = false;
        self::assertFalse(dataset_disable_backups_available());
        $_SERVER['REQUEST_METHOD'] = 'POST';
        dataset_disable_backups_page();
        self::assertSame([], $api->requests);
        $_SESSION['is_admin'] = true;
        unset($api->getDescription()->resources->dataset->actions->disable_backups->input->parameters->backup_first);
        self::assertFalse(dataset_disable_backups_available());
    }

    public function testPlanlessFormKeepsExplanationAndAdminEntryWithOldBackendSupport(): void
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
        self::assertStringContainsString('action=disable_backups', $xtpl->text('main.perex'));
        self::assertStringContainsString('Existing snapshots remain on primary and backup pools.', $xtpl->text('main.perex'));
        unset($api->getDescription()->resources->dataset->actions->disable_backups);
        $xtpl = new XTemplate(dirname(__DIR__, 2) . '/template/template.html');
        dataset_backup_plans_form($dataset);
        self::assertStringNotContainsString('action=disable_backups', $xtpl->text('main.perex'));
        self::assertStringContainsString('Existing snapshots remain on primary and backup pools.', $xtpl->text('main.perex'));
    }

    public function testConfirmationShowsSafeDefaultEscapedScopeAndScopedPost(): void
    {
        global $api, $xtpl;
        $_GET['recursive'] = '1';
        dataset_disable_backups_page();
        $html = $xtpl->text('main.table');
        self::assertStringContainsString('method="post"', $html);
        self::assertStringContainsString('name="backup_first" value="0"', $html);
        self::assertMatchesRegularExpression('/name="backup_first"[^>]*checked/', $html);
        self::assertStringContainsString('name="confirm"', $html);
        self::assertStringContainsString('name="csrf_token"', $html);
        self::assertStringContainsString('child&lt;script&gt;', $html);
        self::assertStringContainsString('If you turn this option off, cleanup permanently deletes', $html);
        self::assertStringContainsString('does not create a new snapshot', $html);
        self::assertStringContainsString('If a snapshot cannot be preserved by the normal transfer, cleanup does not start.', $html);
        self::assertStringContainsString('Separately mounted datasets outside this subtree are excluded.', $xtpl->text('main.perex'));
        self::assertSame(['dataset.show', 'dataset.list'], array_column($api->requests, 'action'));
        self::assertSame(1, $_SESSION['csrf_tokens']['dataset_disable_backups:7:1']['count']);
    }

    public function testMissingAndCrossScopeCsrfRejectBeforeMutation(): void
    {
        global $api;
        $_SERVER['REQUEST_METHOD'] = 'POST';
        $_GET['recursive'] = '1';
        $token = csrf_token('dataset_disable_backups:7:0', 1);
        foreach ([[], ['csrf_token' => $token]] as $post) {
            $_POST = $post + ['confirm' => '1'];
            try {
                dataset_disable_backups_page();
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
        dataset_disable_backups_page();
        $_SERVER['REQUEST_METHOD'] = 'POST';
        dataset_disable_backups_page();
        self::assertSame(['dataset.show', 'dataset.show'], array_column($api->requests, 'action'));
    }

    public function testOneMutationUsesTwoBooleansAndOrdinaryReceipt(): void
    {
        $api = $this->client([['chain' => 42]], [$this->state(true)]);
        self::assertSame(['state' => 'complete', 'chain' => 42], dataset_disable_backups_submit($api, 7, true, true));
        self::assertSame(['dataset.disable_backups', 'action_state.poll'], array_column($api->requests, 'action'));
        self::assertSame(['recursive' => true, 'backup_first' => true], $api->requests[0]['params']);
        self::assertSame('POST', $api->requests[0]['method']);
        self::assertSame('/v7.0/datasets/7/disable_backups', $api->requests[0]['path']);
        self::assertSame('dataset', $api->requests[0]['input_namespace']);
        self::assertSame(['dataset', '_meta'], array_keys((array) $api->envelopes[0]->response));
        self::assertSame([], (array) $api->envelopes[0]->response->dataset);
        self::assertSame(42, $api->envelopes[0]->response->_meta->action_state_id);
        self::assertSame(['timeout' => 15], $api->requests[1]['params']);
    }

    public function testPendingFailedAndUnknownReceiptsNeverReportSuccessOrRetry(): void
    {
        foreach ([[$this->state(null), 'pending'], [$this->state(false), 'failed'],
            [new RuntimeException('poll lost'), 'unknown'],
            [['data' => (object) ['finished' => true, 'status' => 'true']], 'unknown']] as [$poll, $expected]) {
            $api = $this->client([['chain' => 42]], [$poll]);
            self::assertSame(['state' => $expected, 'chain' => 42], dataset_disable_backups_submit($api, 7, false, true));
            self::assertSame(['dataset.disable_backups', 'action_state.poll'], array_column($api->requests, 'action'));
        }
    }

    public function testUnknownSubmissionDoesNotPollOrReplay(): void
    {
        foreach ([new RuntimeException('connection lost'), [], ['chain' => 0]] as $response) {
            $api = $this->client([$response]);
            self::assertSame(['state' => 'unknown'], dataset_disable_backups_submit($api, 7, false, true));
            self::assertSame(['dataset.disable_backups'], array_column($api->requests, 'action'));
        }
    }

    public function testRejectedRequestDoesNotRetryOrClaimCompletion(): void
    {
        $api = $this->client([['status' => false, 'message' => 'Uncovered snapshot', 'data' => (object) []]]);
        self::assertSame(['state' => 'rejected', 'error' => 'Uncovered snapshot'], dataset_disable_backups_submit($api, 7, false, true));
        self::assertCount(1, $api->requests);
    }

    public function testDuplicatePostCannotSubmitAgainAndUsesOnlyNormalCsrfState(): void
    {
        global $api;
        $api = $this->client([['chain' => 42]], [$this->state(null)]);
        dataset_disable_backups_page();
        $_SERVER['REQUEST_METHOD'] = 'POST';
        $_POST = ['confirm' => '1', 'csrf_token' => csrf_token('dataset_disable_backups:7:0')];
        dataset_disable_backups_page();
        self::assertSame(['recursive' => false, 'backup_first' => true], $api->requests[1]['params']);
        try {
            dataset_disable_backups_page();
            self::fail('Duplicate submission accepted');
        } catch (CsrfTokenInvalid $e) {
            self::assertCount(1, array_filter($api->requests, static fn($r) => $r['action'] === 'dataset.disable_backups'));
        }
        self::assertSame(['logged_in', 'is_admin', 'csrf_base', 'csrf_tokens'], array_keys($_SESSION));
    }

    public function testOptOutStillSubmitsOnlyOneOrdinaryOperation(): void
    {
        $api = $this->client([['chain' => 42]], [$this->state(true)]);
        self::assertSame(['state' => 'complete', 'chain' => 42], dataset_disable_backups_submit($api, 7, false, false));
        self::assertSame(['recursive' => false, 'backup_first' => false], $api->requests[0]['params']);
        self::assertCount(2, $api->requests);
    }

    public function testCompleteDisplayRefreshesDatasetAndPlans(): void
    {
        global $api, $xtpl;
        dataset_disable_backups_form(7, false, '?page=backup', ['state' => 'complete', 'chain' => 42]);
        self::assertSame(['dataset.show', 'plan.list'], array_column($api->requests, 'action'));
        self::assertStringContainsString('Backups are disabled and primary snapshots have been removed.', $xtpl->text('main.perex'));
    }

    public function testPendingStatusUsesExistingReadOnlyTaskDetail(): void
    {
        global $api, $xtpl;
        dataset_disable_backups_form(7, false, '?page=backup', ['state' => 'pending', 'chain' => 42]);
        self::assertStringContainsString('?page=transactions&amp;chain=42', $xtpl->text('main.perex'));
        self::assertStringContainsString('Transaction log', $xtpl->text('main.perex'));
        self::assertStringContainsString('It will continue if you close this page.', $xtpl->text('main.perex'));
        self::assertStringNotContainsString('<form', $xtpl->text('main.table'));
        self::assertSame(['dataset.show'], array_column($api->requests, 'action'));
    }

    public function testFailedTaskShowsPartialOutcomeAndNoResubmissionForm(): void
    {
        global $api, $xtpl;
        dataset_disable_backups_form(7, false, '?page=backup', ['state' => 'failed', 'chain' => 42]);
        self::assertStringContainsString('Some changes may have completed.', $xtpl->text('main.perex'));
        self::assertStringNotContainsString('Backups are disabled and primary snapshots have been removed.', $xtpl->text('main.perex'));
        self::assertStringNotContainsString('<form', $xtpl->text('main.table'));
        self::assertSame(['dataset.show'], array_column($api->requests, 'action'));
    }

    private function state(?bool $status): array
    {
        return ['data' => (object) ['finished' => $status !== null, 'status' => $status]];
    }

    private function client(array $mutations = [], array $polls = []): \HaveAPI\Client
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
                    'hash',
                    ['recursive' => (object) ['type' => 'Boolean'], 'backup_first' => (object) ['type' => 'Boolean']],
                    []
                ),
                'show' => $action('dataset', 'GET', '/v7.0/datasets/{dataset_id}', 'object', [], ['id' => (object) ['type' => 'Integer'], 'name' => (object) ['type' => 'String']]),
                'list' => $action('dataset', 'GET', '/v7.0/datasets', 'object_list', [], ['id' => (object) ['type' => 'Integer'], 'name' => (object) ['type' => 'String']]),
            ]],
            'action_state' => (object) ['resources' => (object) [], 'actions' => (object) [
                'poll' => $action('action_state', 'GET', '/v7.0/action_states/{action_state_id}/poll', 'hash', [], []),
            ]],
        ]]);
        $dataset = (object) ['id' => 7, 'name' => 'root', '_meta' => (object) ['resolved' => true, 'path_params' => [7]]];
        $child = (object) ['id' => 8, 'name' => 'child<script>', '_meta' => (object) ['resolved' => true, 'path_params' => [8]]];
        $client->responses = ['dataset.disable_backups' => $mutations, 'action_state.poll' => $polls,
            'dataset.show' => array_fill(0, 3, ['data' => $dataset]), 'dataset.list' => [['data' => [$dataset, $child]]], 'plan.list' => [['data' => []]]];
        return $client;
    }
}
