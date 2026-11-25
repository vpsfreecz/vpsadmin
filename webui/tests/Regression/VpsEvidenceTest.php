<?php

use PHPUnit\Framework\Attributes\PreserveGlobalState;
use PHPUnit\Framework\TestCase;

#[PreserveGlobalState(false)]
final class VpsEvidenceTest extends TestCase
{
    protected function setUp(): void
    {
        $root = dirname(__DIR__, 2);
        require_once $root . '/vendor/autoload.php';
        require_once $root . '/lib/functions.lib.php';
        require_once $root . '/lib/xtemplate.lib.php';
        require_once $root . '/forms/incident_policy.forms.php';
        require_once $root . '/forms/incidents.forms.php';
        require_once $root . '/forms/vps_evidence.forms.php';
        global $xtpl;
        $xtpl = new XTemplate($root . '/template/template.html');
        $_SESSION = ['logged_in' => true, 'is_admin' => false];
        $_GET = [];
        date_default_timezone_set('Europe/Prague');
    }

    private function row(array $values = []): array
    {
        return array_replace([
            'id' => '17:example', 'vps' => ['id' => 17, 'hostname' => '<vps>'], 'hostname' => '<vps>',
            'signal' => 'example', 'label' => '<Signal>', 'representation' => 'qualified_duration',
            'configuration_valid' => true, 'credit_us' => 1,
            'window_from' => '2026-11-24T12:00:00.000001Z', 'window_to' => '2026-11-25T12:00:00.000001Z',
            'window_seconds' => 86400, 'threshold_seconds' => 300, 'repeat_seconds' => 86400,
            'reporting_enabled' => false, 'last_incident_at' => null,
            'last_observed_at' => '2026-11-25T11:58:00.000001Z', 'observation_age_seconds' => 120.0,
            'observation_state' => 'stale', 'qualification' => 'qualified',
            'report_eligible' => false, 'report_due' => false, 'window_complete' => false,
            'measurement' => 'rtnl_latency', 'peak_unit' => 'microseconds', 'peak_value' => 1000001,
            'peak_is_lower_bound' => true, 'condition_measurement' => 'rtnl_latency',
            'condition_operator' => 'gt', 'condition_value' => 1000000, 'condition_unit' => 'microseconds',
            'user' => ['id' => 4, 'login' => '<owner>'], 'node' => ['id' => 8, 'domain_name' => '<node>'],
        ], $values);
    }

    public function testStalePartialCreditAndTypedPeakKeepExactPositiveSubsecondValue(): void
    {
        $html = $this->renderRow($this->row());
        self::assertStringContainsString('0.000001 s', $html);
        self::assertStringContainsString('Stale observation', $html);
        self::assertStringContainsString('RTNL latency: ≥1.000001 s', $html);
        self::assertStringContainsString('RTNL latency is greater than 1 s', $html);
        self::assertStringContainsString('2026-11-25 13:00:00.000001 +01:00', $html);
        self::assertStringContainsString('Incomplete observations', $html);
        self::assertStringContainsString('&lt;Signal&gt;', $html);
        self::assertStringContainsString('&lt;vps&gt;', $html);
        self::assertStringNotContainsString('<owner>', $html);
        self::assertStringNotContainsString('&lt;owner&gt;', $html);
        self::assertStringNotContainsString('<node>', $html);
        self::assertStringNotContainsString('<form', $html);
        self::assertStringContainsString('vps=17', $html);
    }

    public function testFreshZeroNoDataAndUnavailableOwnershipRemainDistinct(): void
    {
        $fresh = $this->renderRow($this->row(['credit_us' => 0, 'observation_state' => 'fresh', 'qualification' => 'ineligible',
            'measurement' => null, 'peak_unit' => null, 'peak_value' => null, 'peak_is_lower_bound' => null]));
        self::assertStringContainsString('Fresh observation', $fresh);
        self::assertStringContainsString('Ineligible', $fresh);
        self::assertStringNotContainsString('≥', $fresh);
        self::assertStringNotContainsString('Zero recorded credit', $fresh);
        $empty = $this->renderRow($this->row(['credit_us' => 0, 'observation_state' => 'no_data']));
        self::assertStringContainsString('No observations', $empty);
        $unavailable = $this->renderRow($this->row(['credit_us' => null, 'observation_state' => 'no_data']));
        self::assertStringContainsString('Unavailable', $unavailable);
        self::assertStringContainsString('Unavailable', $unavailable);
        self::assertStringNotContainsString('Zero recorded credit', $unavailable);
        self::assertStringNotContainsString('credited duration is a lower bound', $unavailable);
    }

    public function testInvalidConfigurationNeverInventsCreditOrThresholdAndAdminReferencesEscape(): void
    {
        $_SESSION['is_admin'] = true;
        $html = $this->renderRow($this->row(['configuration_valid' => false, 'credit_us' => null,
            'window_from' => null, 'window_to' => null, 'window_seconds' => null, 'threshold_seconds' => null,
            'repeat_seconds' => null, 'report_due' => null]));
        self::assertStringContainsString('Invalid configuration', $html);
        self::assertStringContainsString('<dt>Reporting threshold</dt><dd>Not available</dd>', $html);
        self::assertStringContainsString('Unavailable', $html);
        self::assertStringNotContainsString('credited duration is a lower bound', $html);
        self::assertStringContainsString('?page=adminm&action=edit&id=4', $html);
        self::assertStringContainsString('?page=node&id=8', $html);
    }

    public function testRealClientUsesScopedChildAndTopLevelPaginationWithoutExtraLookups(): void
    {
        global $api, $xtpl;
        $api = $this->client();
        vps_evidence_page((object) ['id' => 17]);
        self::assertSame(['/vpses/17/evidence'], array_column($api->requests, 'path'));
        self::assertStringContainsString('vps.evidence.page', $xtpl->text('main.table'));
        $xtpl = new XTemplate(dirname(__DIR__, 2) . '/template/template.html');
        $_GET = ['offset' => '25', 'limit' => '25', 'vps' => '17', 'signal' => 'example'];
        vps_evidence_page();
        $html = $xtpl->text('main.table');
        self::assertSame(['/vpses/17/evidence', '/vps_evidence'], array_column($api->requests, 'path'));
        self::assertSame(['vps_evidence' => ['vps' => 17, 'offset' => 25, 'limit' => 25, 'signal' => 'example']], $api->requests[1]['params']);
        self::assertStringContainsString('offset=0', $html);
        self::assertStringContainsString('offset=50', $html);
        $dom = new DOMDocument();
        @$dom->loadHTML($html);
        $links = (new DOMXPath($dom))->query('//a[normalize-space()="Previous" or normalize-space()="Next"]');
        foreach ($links as $link) {
            parse_str(parse_url($link->getAttribute('href'), PHP_URL_QUERY), $query);
            self::assertSame('17', $query['vps']);
            self::assertSame('example', $query['signal']);
            self::assertSame('25', $query['limit']);
        }
        self::assertStringContainsString('Read at', $html);
        self::assertStringContainsString('13:00:00.000001 +01:00', $html);
    }

    public function testEmptyInvalidMetadataCannotPresentACompleteEmptyOverview(): void
    {
        global $api, $xtpl;
        $api = $this->client();
        $api->rows = [];
        $api->meta['configuration_valid'] = false;
        $api->meta['unavailable_signals'] = ['example'];
        vps_evidence_page();
        $html = $xtpl->text('main.table');
        self::assertStringContainsString('Invalid configuration', $html);
        self::assertStringContainsString('Invalid configuration', $html);
        self::assertStringNotContainsString('No VPS has recorded credit above zero', $html);
    }

    public function testOldApiHidesNavigationAndReadFailureDoesNotExposePrivateDetails(): void
    {
        global $api, $xtpl;
        $api = $this->client();
        vps_evidence_sidebar();
        $xtpl->sbar_out('VPS');
        self::assertStringContainsString('vps-evidence.menu', $xtpl->text('main.sidebar'));
        self::assertSame([], $api->requests);
        $api->reject = true;
        vps_evidence_page();
        self::assertStringContainsString('Unable to load memory pressure data.', $xtpl->text('main.perex'));
        self::assertStringNotContainsString('PRIVATE', $xtpl->text('main.perex'));
        unset($api->getDescription()->resources->vps_evidence);
        self::assertNull(vps_evidence_resource());
    }

    public function testInvalidFilterAndGuestPageMakeNoEvidenceRequest(): void
    {
        global $api, $xtpl;
        $api = $this->client();
        $_GET = ['offset' => ['25']];
        vps_evidence_page();
        self::assertStringContainsString('Invalid filter value.', $xtpl->text('main.perex'));
        self::assertSame([], $api->requests);
        $_SESSION['logged_in'] = false;
        include dirname(__DIR__, 2) . '/pages/page_vps_evidence.php';
        self::assertStringContainsString('Access forbidden', $xtpl->text('main.perex'));
        self::assertSame([], $api->requests);
    }

    public function testHistoryUsesTheSameVpsAndExplicitUtcNullAndPartialDayPresentation(): void
    {
        global $api, $xtpl;
        $api = $this->client(true);
        $_GET = ['pressure_days' => '30'];
        vps_evidence_page((object) ['id' => 17]);
        self::assertSame(['/vpses/17/evidence', '/vps_pressure_history'], array_column($api->requests, 'path'));
        self::assertSame(['vps_pressure_history' => ['vps' => 17, 'days' => 30]], $api->requests[1]['params']);
        $html = $xtpl->text('main.table');
        foreach (['Date (UTC)', '2026-11-27', 'No recorded data', 'Today (partial day)', '0.250001 s', 'History for the current owner'] as $text) {
            self::assertStringContainsString($text, $html);
        }
        self::assertStringNotContainsString('History since', $html);
    }

    public function testUnavailableHistoryKeepsCurrentDataAndNeverInventsAZeroDay(): void
    {
        global $api, $xtpl;
        $api = $this->client(true);
        $api->historyMeta['available'] = false;
        vps_evidence_page((object) ['id' => 17]);
        $html = $xtpl->text('main.table');
        self::assertStringContainsString('0.000001 s', $html);
        self::assertStringContainsString('History is unavailable.', $html);
        self::assertStringNotContainsString('2026-11-27', $html);
    }

    public function testIssueFilterKeepsWireValuesAndUsesVisiblePressureNameForBothChoiceFormats(): void
    {
        global $api, $xtpl;
        foreach ([['rtnl_latency'], (object) ['rtnl_latency' => 'RTNL latency']] as $choices) {
            $api = $this->client();
            $xtpl = new XTemplate(dirname(__DIR__, 2) . '/template/template.html');
            $signal = $api->getDescription()->resources->vps_evidence->actions->index->input->parameters->signal;
            $signal->label = 'Evidence signal';
            $signal->validators = (object) ['include' => (object) ['values' => $choices]];
            vps_evidence_page();
            $html = $xtpl->text('main.table');
            $dom = new DOMDocument();
            @$dom->loadHTML($html);
            $options = (new DOMXPath($dom))->query('//select[@name="signal"]/option');
            self::assertSame('', $options->item(0)->getAttribute('value'));
            self::assertSame('rtnl_latency', $options->item(1)->getAttribute('value'));
            self::assertSame('Memory pressure', $options->item(1)->textContent);
            self::assertStringNotContainsString('Evidence signal', $html);
        }
    }

    private function renderRow(array $row): string
    {
        return implode(' ', vps_evidence_cells($row));
    }

    public function testThresholdMeterCapsAtOneAndKeepsExactTextWhileNullHasNoMeter(): void
    {
        $html = $this->renderRow($this->row(['signal' => 'rtnl_latency', 'credit_us' => 600250000]));
        self::assertStringContainsString('Memory pressure', $html);
        self::assertStringContainsString('value="1"', $html);
        self::assertStringContainsString('600.25 s', $html);
        self::assertStringContainsString('aria-valuetext=', $html);
        self::assertStringNotContainsString('<meter', $this->renderRow($this->row(['threshold_seconds' => null])));
        self::assertStringNotContainsString('<meter', $this->renderRow($this->row(['credit_us' => null])));
    }

    public function testUnsupportedOrUnauthorizedFiltersAreNeverSilentlyDropped(): void
    {
        global $api, $xtpl;
        $api = $this->client();
        $_GET = ['user' => '4'];
        vps_evidence_page();
        self::assertSame([], $api->requests);
        self::assertStringContainsString('Invalid filter value.', $xtpl->text('main.perex'));
        $_GET = ['node' => '8'];
        unset($api->getDescription()->resources->vps_evidence->actions->index->input->parameters->node);
        vps_evidence_page();
        self::assertSame([], $api->requests);
    }

    private function client(bool $history = false): \HaveAPI\Client
    {
        $client = new class ('https://api.example') extends \HaveAPI\Client {
            public array $requests = [];
            public array $rows = [];
            public array $meta = ['total_count' => 51, 'offset' => 25, 'limit' => 25, 'next_offset' => 50,
                'read_at' => '2026-11-25T12:00:00.000001Z', 'configuration_valid' => true, 'unavailable_signals' => []];
            public bool $reject = false;
            public array $historyRows = [];
            public array $historyMeta = ['available' => true, 'timezone' => 'UTC', 'total_recorded_us' => 250001, 'ownership_limited' => true];

            protected function sendRequest($request, $action = null, $params = [])
            {
                $this->requests[] = ['path' => $action->path(), 'params' => $params];
                $history = $action->path() === '/vps_pressure_history';
                return (object) ['code' => 200, 'body' => (object) ['status' => !$this->reject,
                    'message' => 'PRIVATE API failure', 'errors' => (object) [], 'response' => (object) [
                        $action->getNamespace('output') => array_map(static fn($row) => (object) $row, $history ? $this->historyRows : $this->rows),
                        '_meta' => (object) ($history ? $this->historyMeta : $this->meta),
                    ],
                ]];
            }
        };
        $parameters = static fn($fields) => (object) array_map(static fn($type) => (object) ['type' => $type, 'nullable' => true, 'label' => '', 'description' => ''], $fields);
        $fields = array_fill_keys(array_keys($this->row()), 'Custom');
        $fields['credit_us'] = 'Integer';
        $action = static fn($path, $namespace) => (object) [
            'aliases' => [], 'blocking' => false, 'method' => 'GET', 'path' => $path,
            'input' => (object) ['layout' => 'object', 'namespace' => $namespace,
                'parameters' => $parameters(['vps' => 'Integer', 'offset' => 'Integer', 'limit' => 'Integer', 'signal' => 'String', 'node' => 'Integer', 'location' => 'Integer', 'environment' => 'Integer', 'user' => 'Integer'])],
            'output' => (object) ['layout' => 'object_list', 'namespace' => $namespace, 'parameters' => $parameters($fields)],
            'meta' => (object) [],
        ];
        $resource = static fn($path, $namespace) => (object) ['resources' => (object) [],
            'actions' => (object) ['index' => $action($path, $namespace)]];
        $client->setDescription((object) ['authentication' => (object) [], 'meta' => (object) ['namespace' => '_meta'],
            'resources' => (object) [
                'vps_evidence' => $resource('/vps_evidence', 'vps_evidence'),
                'vps' => (object) ['actions' => (object) [], 'resources' => (object) [
                    'evidence' => $resource('/vpses/{vps_id}/evidence', 'evidence'),
                ]],
            ],
        ]);
        if ($history) {
            $r = $resource('/vps_pressure_history', 'vps_pressure_history');
            $r->actions->index->input->parameters = $parameters(['vps' => 'Integer', 'days' => 'Integer']);
            $r->actions->index->output->parameters = $parameters(['id' => 'String', 'from_at' => 'Custom', 'to_at' => 'Custom', 'recorded_us' => 'Integer', 'partial_day' => 'Boolean']);
            $client->getDescription()->resources->vps_pressure_history = $r;
            $client->historyRows = [
                ['id' => '2026-11-27', 'from_at' => '2026-11-27T00:00:00Z', 'to_at' => '2026-11-28T00:00:00Z', 'recorded_us' => null, 'partial_day' => false],
                ['id' => '2026-11-28', 'from_at' => '2026-11-28T00:00:00Z', 'to_at' => '2026-11-29T00:00:00Z', 'recorded_us' => 250001, 'partial_day' => true],
            ];
        }
        $client->rows = [$this->row()];
        return $client;
    }
}
