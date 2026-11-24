<?php

use PHPUnit\Framework\Attributes\PreserveGlobalState;
use PHPUnit\Framework\TestCase;

#[PreserveGlobalState(false)]
final class AdminIncidentOverviewTest extends TestCase
{
    protected function setUp(): void
    {
        $root = dirname(__DIR__, 2);
        require_once $root . '/vendor/autoload.php';
        require_once $root . '/lib/functions.lib.php';
        require_once $root . '/lib/security.lib.php';
        require_once $root . '/lib/xtemplate.lib.php';
        require_once $root . '/forms/incident_policy.forms.php';
        require_once $root . '/forms/incidents.forms.php';
        require_once $root . '/forms/admin_incidents.forms.php';
        global $api, $xtpl;
        $xtpl = new XTemplate($root . '/template/template.html');
        $_SESSION = ['is_admin' => true, 'logged_in' => true];
        $_GET = ['page' => 'incidents'];
        $_POST = [];
        $_SERVER['REQUEST_METHOD'] = 'GET';
        date_default_timezone_set('UTC');
        $api = $this->client();
    }

    public function testDefaultAndTabsAreAdminOnlyAndReportsKeepsItsRoute(): void
    {
        global $api, $xtpl;
        self::assertSame('overview', admin_incidents_action());
        admin_incidents_tabs(admin_incidents_action());
        $xpath = $this->xpath($xtpl->text('main.table'));
        self::assertSame('Overview', $xpath->evaluate('string(//a[@aria-current="page"])'));
        self::assertSame('?page=incidents&action=list&list=1', $xpath->evaluate('string(//a[@data-vpsadmin-doc-id="admin.incidents.list"]/@href)'));
        foreach (['list', 'show', 'new'] as $action) {
            $_GET['action'] = $action;
            self::assertSame($action, admin_incidents_action());
        }
        $_SESSION['is_admin'] = false;
        unset($_GET['action']);
        self::assertNull(admin_incidents_action());
        $xtpl = $this->template();
        admin_incidents_menu();
        admin_incidents_tabs('overview');
        admin_incidents_page();
        self::assertSame('', $xtpl->text('main.table'));
        self::assertStringContainsString('Access forbidden', $xtpl->text('main.perex'));
        self::assertSame([], $api->requests);
    }

    public function testActualDefaultRouteUsesProjectionButMemberDefaultDoesNot(): void
    {
        global $api, $xtpl;
        require dirname(__DIR__, 2) . '/pages/page_incidents.php';
        self::assertSame('/incident_policy_exposures', $api->requests[0]['path']);
        self::assertStringContainsString('admin.incidents.overview', $xtpl->text('main.table'));
        $_SESSION['is_admin'] = false;
        $api = $this->client();
        $xtpl = $this->template();
        require dirname(__DIR__, 2) . '/pages/page_incidents.php';
        self::assertSame([], $api->requests);
        self::assertStringNotContainsString('admin.incidents.', $xtpl->text('main.table'));
    }

    public function testMissingActionsFieldsInputsAndMetadataFailClosedWithoutFallback(): void
    {
        global $api, $xtpl;
        foreach (['resource', 'action', 'output', 'input', 'sort', 'meta', 'reference'] as $missing) {
            $api = $this->client();
            $desc = $api->getDescription();
            $resource = $desc->resources->incident_policy_exposure;
            $index = $resource->actions->index;
            if ($missing === 'resource') {
                unset($desc->resources->incident_policy_exposure);
            } elseif ($missing === 'action') {
                unset($resource->actions->index);
            } elseif ($missing === 'output') {
                unset($index->output->parameters->warning_remaining);
            } elseif ($missing === 'input') {
                unset($index->input->parameters->node);
            } elseif ($missing === 'sort') {
                unset($index->input->parameters->sort);
            } elseif ($missing === 'meta') {
                unset($index->meta->global->output->parameters->next_offset);
            } else {
                $index->output->parameters->user->type = 'Integer';
            }
            $api->setDescription($desc);
            $xtpl = $this->template();
            admin_incidents_tabs('overview');
            admin_incidents_page();
            self::assertSame([], $api->requests, $missing);
            self::assertStringContainsString('Incident overview and history are unavailable on this API.', $xtpl->text('main.perex'), $missing);
            self::assertStringContainsString('action=list', $xtpl->text('main.table'));
        }
    }

    public function testPartialReferencesAreEscapedWithoutShowRequestsAndCountsStayServerFacts(): void
    {
        global $api, $xtpl;
        $row = $this->exposure();
        $row->count_7d = 2;
        $row->warning_limit = 20;
        $row->warning_remaining = 3;
        $row->stop_remaining = 0;
        $row->stop_enforced = false;
        $api->rows = [$row, clone $row, clone $row];
        admin_incidents_page();
        $html = $xtpl->text('main.table');
        self::assertStringContainsString('vps&lt;&amp;&quot;', $html);
        self::assertStringContainsString('login&lt;&amp;&quot;', $html);
        self::assertStringContainsString('Node&lt;&amp;&quot;', $html);
        self::assertStringContainsString('Policy &lt;unsafe&gt;', $html);
        self::assertStringNotContainsString('<unsafe>', $html);
        $xpath = $this->xpath($html);
        self::assertSame(['Warning: Last 7 days', '2', '20', '3'], $this->countRow($xpath, 1));
        self::assertSame(['VPS stop: Last 30 days', '9', '10', 'Threshold reached'], $this->countRow($xpath, 2));
        self::assertStringContainsString('<strong>Automatic shutdown:</strong> No<br>', $html);
        self::assertSame(['/incident_policy_exposures', '/incident_policies'], array_column($api->requests, 'path'));
        self::assertStringContainsString('action=incidents&amp;veid=17#incident-policy-alpha', $html);
        self::assertStringContainsString('action=history&amp;vps_id=17&amp;policy_key=alpha', $html);
        self::assertStringContainsString('page=node&amp;id=4', $html);
        self::assertSame('', $xpath->evaluate('string(//select[@name="stop_enforced"]/option[@selected]/@value)'));
    }

    public function testNullLimitsDatesAndUnknownOutcomesNeverBecomeZeroOrSuccess(): void
    {
        global $api, $xtpl;
        $row = $this->exposure();
        $row->configuration_valid = false;
        $row->warning_limit = null;
        $row->stop_limit = null;
        $row->warning_remaining = null;
        $row->stop_remaining = null;
        $row->latest_action_id = 81;
        $row->latest_action_kind = 'stop';
        $row->latest_action_state = 'future<state>';
        $row->latest_mail_state = 'uncertain';
        $api->rows = [$row];
        admin_incidents_page();
        $html = $xtpl->text('main.table');
        self::assertSame(['Warning: Last 7 days', '4', 'Unknown', 'Unknown'], $this->countRow($this->xpath($html), 1));
        self::assertStringContainsString('Invalid configuration', $html);
        self::assertStringContainsString('<strong>Action state:</strong> Unknown<br>', $html);
        self::assertStringContainsString('Mail outcome uncertain', $html);
        self::assertStringNotContainsString('future<state>', $html);
        self::assertStringNotContainsString('<strong>Confirmed shutdown:</strong>', $html);
    }

    public function testResourceFiltersFalsePaginationCutoffAndRefreshUseNormalClient(): void
    {
        global $api, $xtpl;
        $_GET += ['vps' => '17', 'user' => '23', 'node' => '4', 'stop_enforced' => '0', 'offset' => '25', 'limit' => '25', 'sort' => 'warning_remaining', 'direction' => 'asc', 'as_of' => '2026-11-24T12:00:00Z'];
        $api->meta['offset'] = 25;
        $api->meta['next_offset'] = 50;
        $api->meta['total_count'] = 60;
        admin_incidents_page();
        self::assertSame(['incident_policy_exposure' => ['offset' => '25', 'limit' => '25', 'as_of' => '2026-11-24T12:00:00Z', 'sort' => 'warning_remaining', 'direction' => 'asc', 'vps' => '17', 'user' => '23', 'node' => '4', 'stop_enforced' => 'false']], $api->requests[0]['params']);
        $xpath = $this->xpath($xtpl->text('main.table'));
        self::assertSame('warning_remaining', $xpath->evaluate('string(//select[@name="sort"]/option[@selected]/@value)'));
        self::assertSame(0, $xpath->query('//form//input[@name="offset"]')->length);
        self::assertSame('2026-11-24T12:00:00Z', $xpath->evaluate('string(//form//input[@name="as_of"]/@value)'));
        foreach (['Next' => '50', 'Previous' => '0', 'Refresh' => null] as $label => $offset) {
            $href = $xpath->evaluate('string(//a[normalize-space(.)="' . $label . '"]/@href)');
            parse_str(ltrim($href, '?'), $query);
            self::assertSame('0', $query['stop_enforced']);
            self::assertSame('17', $query['vps']);
            self::assertSame('warning_remaining', $query['sort']);
            if ($offset === null) {
                self::assertArrayNotHasKey('as_of', $query);
                self::assertArrayNotHasKey('offset', $query);
            } else {
                self::assertSame($offset, $query['offset']);
                self::assertSame($api->meta['as_of'], $query['as_of']);
            }
        }
    }

    public function testHistoryKeepsOriginalDeletedIdsSavedValuesAndDistinctMailStopFacts(): void
    {
        global $api, $xtpl;
        $_GET += ['vps_id' => '999', 'user_id' => '888', 'policy_key' => 'Retired_9'];
        $api->rows = [$this->history()];
        admin_incidents_page(true);
        self::assertSame(999, $api->requests[0]['params']['incident_policy_evaluation']['vps_id']);
        self::assertSame(888, $api->requests[0]['params']['incident_policy_evaluation']['user_id']);
        $html = $xtpl->text('main.table');
        self::assertStringContainsString('Retired_9', $html);
        self::assertStringNotContainsString('veid=999', $html);
        self::assertStringNotContainsString('adminm&amp;action=edit&amp;id=888', $html);
        self::assertSame(['Warning: 7 days', '7', '5'], $this->countRow($this->xpath($html), 1));
        self::assertSame(['VPS stop: 30 days', '11', '10'], $this->countRow($this->xpath($html), 2));
        self::assertStringContainsString('<strong>Action state:</strong> Completed<br>', $html);
        self::assertStringContainsString('<strong>Mail state:</strong> Mail failed<br>', $html);
        self::assertStringContainsString('<strong>Shared shutdown action:</strong> #61<br>', $html);
        self::assertStringContainsString('2026-11-24 12:30:00', $html);
        self::assertStringContainsString('chain=77', $html);
        self::assertStringContainsString('action=show&amp;id=41', $html);
    }

    public function testHistoryUsesExportedDirectionOnlyContractWithoutSort(): void
    {
        global $api, $xtpl;
        $resource = $api->incident_policy_evaluation;
        self::assertObjectNotHasProperty('sort', $resource->index->getParameters('input'));
        self::assertNotNull(admin_incidents_resource(true));
        $_GET += ['action' => 'history', 'sort' => 'evaluated_at', 'direction' => 'asc', 'vps_id' => '999',
            'policy_key' => 'Retired_9', 'limit' => '25', 'as_of' => '2026-11-24T12:00:00Z'];
        $api->rows = [$this->history()];
        $api->meta['next_offset'] = 25;
        $api->meta['total_count'] = 30;
        admin_incidents_page(true);
        self::assertSame(['/incident_policy_evaluations', '/incident_policies'], array_column($api->requests, 'path'));
        $params = $api->requests[0]['params']['incident_policy_evaluation'];
        self::assertSame(['limit' => 25, 'as_of' => '2026-11-24T12:00:00Z', 'policy_key' => 'Retired_9', 'direction' => 'asc', 'vps_id' => 999], $params);
        self::assertSame([], array_diff(array_keys($params), array_keys((array) $resource->index->getParameters('input'))));
        $html = $xtpl->text('main.table');
        $xpath = $this->xpath($html);
        self::assertSame(0, $xpath->query('//*[@name="sort"]')->length);
        self::assertSame('asc', $xpath->evaluate('string(//select[@name="direction"]/option[@selected]/@value)'));
        self::assertStringContainsString('Retired_9', $html);
        foreach (['Next', 'Refresh'] as $label) {
            parse_str(ltrim($xpath->evaluate('string(//a[normalize-space(.)="' . $label . '"]/@href)'), '?'), $query);
            self::assertArrayNotHasKey('sort', $query);
            self::assertSame('asc', $query['direction']);
        }
        $_GET['sort'] = ['unsupported'];
        self::assertArrayNotHasKey('sort', admin_incidents_params(true));
    }

    public function testOutstandingIgnoresPeriodEvenWithoutJavascriptAndDisablesLocalControls(): void
    {
        global $api, $xtpl;
        $_GET += ['scope' => 'outstanding', 'from' => '2000-01-01', 'to' => '2000-01-02'];
        $api->rows = [$this->history()];
        $api->meta['from'] = null;
        $api->meta['to'] = null;
        admin_incidents_page(true);
        self::assertArrayNotHasKey('from', $api->requests[0]['params']['incident_policy_evaluation']);
        self::assertArrayNotHasKey('to', $api->requests[0]['params']['incident_policy_evaluation']);
        $xpath = $this->xpath($xtpl->text('main.table'));
        self::assertSame(2, $xpath->query('//form//input[(@name="from" or @name="to") and @disabled]')->length);
        $xtpl->parse('main');
        $page = $xtpl->text('main');
        self::assertStringContainsString('form[name="admin-incident-filter"] select[name="scope"]', $page);
        self::assertStringNotContainsString('src="js/vps.js"', $page);
    }

    public function testInvalidScalarAndNumericFiltersStopBeforeAnyRequest(): void
    {
        global $api, $xtpl;
        foreach ([['limit' => '101'], ['offset' => '-1'], ['vps' => '1.2'], ['user' => []], ['stop_enforced' => 'false']] as $bad) {
            $_GET = ['page' => 'incidents'] + $bad;
            $api = $this->client();
            $xtpl = $this->template();
            admin_incidents_page();
            self::assertSame([], $api->requests);
            self::assertStringContainsString('Invalid filter value.', $xtpl->text('main.perex'));
        }
    }

    public function testSuccessfulEmptyAndProjectionFailureRemainDifferent(): void
    {
        global $api, $xtpl;
        $api->rows = [];
        admin_incidents_page();
        self::assertStringContainsString('No current matches for these filters.', $xtpl->text('main.table'));
        $api = $this->client();
        $api->reject = true;
        $xtpl = $this->template();
        admin_incidents_tabs('overview');
        admin_incidents_page();
        self::assertStringNotContainsString('No current matches', $xtpl->text('main.table'));
        self::assertStringContainsString('action=list', $xtpl->text('main.table'));
        self::assertStringNotContainsString('PRIVATE API failure', $xtpl->text('main.perex'));
        self::assertStringContainsString('Unable to load incident overview or history.', $xtpl->text('main.perex'));
    }

    public function testHistoryRequiresItsOwnCapabilityAndRuntimeMetadata(): void
    {
        global $api, $xtpl;
        $description = $api->getDescription();
        unset($description->resources->incident_policy_evaluation->actions->index->meta->global->output->parameters->from);
        $api->setDescription($description);
        admin_incidents_page(true);
        self::assertSame([], $api->requests);
        self::assertStringContainsString('unavailable on this API', $xtpl->text('main.perex'));
        $api = $this->client();
        unset($api->meta['next_offset']);
        $xtpl = $this->template();
        admin_incidents_tabs('history');
        admin_incidents_page(true);
        self::assertSame(['/incident_policy_evaluations'], array_column($api->requests, 'path'));
        self::assertStringContainsString('Unable to load incident overview or history.', $xtpl->text('main.perex'));
        self::assertStringContainsString('action=list', $xtpl->text('main.table'));
        self::assertStringNotContainsString('No recorded evaluations', $xtpl->text('main.table'));
    }

    private function template(): XTemplate
    {
        return new XTemplate(dirname(__DIR__, 2) . '/template/template.html');
    }

    private function xpath(string $html): DOMXPath
    {
        $dom = new DOMDocument();
        $old = libxml_use_internal_errors(true);
        $dom->loadHTML('<html><body>' . $html . '</body></html>');
        libxml_clear_errors();
        libxml_use_internal_errors($old);
        return new DOMXPath($dom);
    }

    private function countRow(DOMXPath $xpath, int $number): array
    {
        return array_map(static fn($cell) => trim($cell->textContent), iterator_to_array($xpath->query('(//table[thead/tr/th])[1]/tbody/tr[' . $number . ']/td')));
    }

    private function exposure(): object
    {
        return (object) (['id' => '17:alpha', 'vps' => (object) ['id' => 17, 'hostname' => 'vps<&"', '_meta' => (object) ['resolved' => false, 'path_params' => [17]]],
            'user' => (object) ['id' => 23, 'login' => 'login<&"', '_meta' => (object) ['resolved' => false, 'path_params' => [23]]],
            'node' => (object) ['id' => 4, 'domain_name' => 'Node<&"', '_meta' => (object) ['resolved' => false, 'path_params' => [4]]],
            'policy_key' => 'alpha', 'label' => 'Policy <unsafe>', 'owner_active' => true, 'transfer_pending' => false,
            'count_7d' => 4, 'count_30d' => 9, 'warning_period_days' => 7, 'stop_period_days' => 30, 'warning_limit' => 5, 'stop_limit' => 10,
            'warning_remaining' => 1, 'stop_remaining' => 1, 'configuration_valid' => true, 'status' => 'near_limit', 'global_mode' => 'enforce',
            'effective_mode' => 'enforce', 'warning_permitted' => true, 'stop_enforced' => true, 'outstanding_stop_state' => 'none']
            + array_fill_keys(explode(' ', 'last_incident_at last_warning_at next_warning_allowed_at last_stop_at next_stop_allowed_at accounting_since outstanding_stop_action_id outstanding_stop_chain_id latest_action_id latest_action_chain_id latest_notice_report_id latest_action_kind latest_action_state latest_mail_state latest_stop_completed_at'), null));
    }

    private function history(): object
    {
        return (object) ['id' => 51, 'incident_report_id' => 41, 'vps_id' => 999, 'user_id' => 888, 'hostname' => null, 'user_login' => null,
            'policy_key' => 'Retired_9', 'label' => 'Retired policy', 'evaluated_at' => '2026-11-20T00:00:00Z', 'detected_at' => null,
            'matched' => true, 'state' => 'recorded', 'warning_period_days' => 7, 'stop_period_days' => 30, 'count_7d' => 7, 'count_30d' => 11,
            'warning_limit' => 5, 'stop_limit' => 10, 'effective_mode' => 'enforce', 'stop_enforced' => true, 'threshold_status' => 'stop_threshold',
            'decision' => 'stop', 'action_id' => 62, 'action_kind' => 'stop', 'action_state' => 'completed', 'action_created_at' => '2026-11-20T00:00:00Z',
            'action_updated_at' => '2026-11-24T12:30:00Z', 'transaction_chain_id' => 77, 'physical_stop_action_id' => 61,
            'stop_completed_at' => '2026-11-24T12:30:00Z', 'notice_report_id' => 63, 'mail_state' => 'failed', 'mail_queued_at' => null, 'mail_finished_at' => null];
    }

    private function client(): \HaveAPI\Client
    {
        $client = new class ('https://api.example') extends \HaveAPI\Client {
            public array $requests = [];
            public array $rows = [];
            public array $meta = ['total_count' => 1, 'offset' => 0, 'limit' => 25, 'next_offset' => null, 'as_of' => '2026-11-24T12:00:00Z', 'read_at' => '2026-11-24T12:01:00Z', 'from' => '2026-10-25T12:00:00Z', 'to' => '2026-11-24T12:00:00Z'];
            public bool $reject = false;

            protected function sendRequest($request, $action = null, $params = [])
            {
                $path = $action->path();
                $this->requests[] = ['path' => $path, 'params' => $params];
                $registry = $path === '/incident_policies';
                return (object) ['code' => 200, 'body' => (object) ['status' => !$this->reject, 'message' => 'PRIVATE API failure', 'errors' => (object) [],
                    'response' => (object) [$action->getNamespace('output') => $registry ? [(object) ['key' => 'alpha', 'label' => 'Active policy']] : $this->rows, '_meta' => (object) $this->meta]]];
            }
        };
        $parameters = static fn($names) => (object) array_fill_keys($names, (object) ['type' => 'String', 'nullable' => true]);
        $resources = [];
        foreach ([false, true] as $history) {
            $name = $history ? 'incident_policy_evaluation' : 'incident_policy_exposure';
            $output = $parameters(admin_incidents_fields($history));
            if (!$history) {
                foreach (['vps' => 'hostname', 'user' => 'login', 'node' => 'domain_name'] as $reference => $label) {
                    $output->{$reference} = (object) ['type' => 'Resource', 'resource' => [$reference], 'value_id' => 'id', 'value_label' => $label];
                }
            }
            // History input names/types from the immutable 74c0af3a schema export.
            // Its server ordering is evaluated_at + ID, with direction only.
            $historyInput = (object) array_map(static fn($type) => (object) ['type' => $type, 'nullable' => false], [
                'action_kind' => 'String', 'action_state' => 'String', 'as_of' => 'Datetime', 'decision' => 'String',
                'direction' => 'String', 'from' => 'Datetime', 'limit' => 'Integer', 'mail_state' => 'String',
                'offset' => 'Integer', 'policy_key' => 'String', 'scope' => 'String', 'to' => 'Datetime',
                'user_id' => 'Integer', 'vps_id' => 'Integer',
            ]);
            $resources[$name] = (object) ['resources' => (object) [], 'actions' => (object) ['index' => (object) ['aliases' => [], 'blocking' => false, 'method' => 'GET', 'path' => '/' . $name . 's',
                'input' => (object) ['layout' => 'object', 'namespace' => $name, 'parameters' => $history ? $historyInput : $parameters(['offset', 'limit', 'as_of', 'policy_key', 'sort', 'direction', 'vps', 'user', 'node', 'status', 'effective_mode', 'stop_enforced'])],
                'output' => (object) ['layout' => 'object_list', 'namespace' => $name, 'parameters' => $output],
                'meta' => (object) ['global' => (object) ['output' => (object) ['parameters' => $parameters(array_merge(['total_count', 'offset', 'limit', 'next_offset', 'as_of', 'read_at'], $history ? ['from', 'to'] : []))]]]]]];
        }
        $resources['incident_policy'] = (object) ['resources' => (object) [], 'actions' => (object) ['index' => (object) ['aliases' => [], 'blocking' => false, 'method' => 'GET', 'path' => '/incident_policies',
            'input' => (object) ['layout' => 'object', 'namespace' => 'incident_policy', 'parameters' => (object) []],
            'output' => (object) ['layout' => 'object_list', 'namespace' => 'incident_policy', 'parameters' => $parameters(['key', 'label'])], 'meta' => (object) []]]];
        $client->setDescription((object) ['authentication' => (object) [], 'meta' => (object) ['namespace' => '_meta'], 'resources' => (object) $resources]);
        $client->rows = [$this->exposure()];
        return $client;
    }
}
