<?php

use PHPUnit\Framework\Attributes\PreserveGlobalState;
use PHPUnit\Framework\TestCase;

#[PreserveGlobalState(false)]
final class IncidentPolicyTest extends TestCase
{
    protected function setUp(): void
    {
        $root = dirname(__DIR__, 2);
        require_once $root . '/vendor/autoload.php';
        require_once $root . '/lib/functions.lib.php';
        require_once $root . '/lib/security.lib.php';
        require_once $root . '/lib/xtemplate.lib.php';
        require_once $root . '/forms/incident_policy.forms.php';
        global $xtpl;
        $xtpl = new XTemplate($root . '/template/template.html');
        $_SESSION = ['is_admin' => false, 'csrf_base' => 'incident-policy-test'];
        $_GET = [];
        $_POST = [];
        $_SERVER['REQUEST_METHOD'] = 'POST';
    }

    public function testRealClientSummaryRetainsZeroAndOldApiRendersNothing(): void
    {
        global $api, $xtpl;
        foreach ([true, false] as $supported) {
            $api = $this->client($supported);
            $vps = $api->vps->show(17);
            self::assertSame($supported, vps_incident_available($vps));
            self::assertSame($supported, str_contains(vps_incident_indicator($vps), '0/5'));
            vps_incident_details($vps);
            $html = $xtpl->text('main.table');
            self::assertSame($supported, str_contains($html, 'incident-policy'));
            self::assertStringNotContainsString('<form', $html);
            self::assertSame(['show'], array_column($api->requests, 'action'));
            $xtpl = new XTemplate(dirname(__DIR__, 2) . '/template/template.html');
        }
    }

    public function testServerCountsAndLimitsRemainSeparateFromModeAndExemption(): void
    {
        global $api, $xtpl;
        $api = $this->client(true, [
            'incident_count_7d' => 7, 'incident_count_30d' => 11,
            'incident_warning_limit' => 7, 'incident_stop_limit' => 11,
            'incident_status' => 'stop_threshold', 'incident_mode' => 'notify',
            'incident_enforcement_enabled' => false, 'incident_stop_enforced' => false,
        ]);
        $vps = $api->vps->show(17);
        self::assertStringContainsString('7/7', vps_incident_indicator($vps));
        self::assertStringContainsString('11/11', vps_incident_indicator($vps));
        self::assertStringContainsString(_('Automatic shutdown exempt'), vps_incident_indicator($vps));
        vps_incident_details($vps);
        $html = $xtpl->text('main.table');
        self::assertStringContainsString(_('Automatic shutdown limit reached'), $html);
        self::assertStringContainsString(_('Warnings only'), $html);
        self::assertStringContainsString('codename=oomd', $html);
        self::assertStringContainsString(_('No outstanding shutdown'), $html);
        self::assertSame(['show'], array_column($api->requests, 'action'));
    }

    public function testOutstandingStatesDoNotClaimConfirmedShutdownAndCooldownIsNotScheduled(): void
    {
        global $api, $xtpl;
        foreach (['pending' => _('Automatic shutdown pending'), 'failed' => _('Automatic shutdown failed'), 'uncertain' => _('Automatic shutdown outcome uncertain')] as $state => $label) {
            $api = $this->client(true, [
                'incident_action_state' => $state, 'incident_action_chain_id' => 34,
                'incident_last_stop_at' => '2026-10-29T12:00:00Z',
                'incident_next_stop_allowed_at' => '2026-10-30T12:00:00Z',
            ]);
            vps_incident_details($api->vps->show(17));
            $html = $xtpl->text('main.table');
            self::assertStringContainsString($label, $html);
            self::assertStringContainsString('?page=transactions&chain=34', $html);
            self::assertStringContainsString(_('Last confirmed automatic shutdown'), $html);
            self::assertStringContainsString('no shutdown is scheduled', $html);
            self::assertStringContainsString('at or after the cooldown ends', $html);
            self::assertStringNotContainsString('<form', $html);
            $xtpl = new XTemplate(dirname(__DIR__, 2) . '/template/template.html');
        }
    }

    public function testAdminFormDisplaysRawOverridesAndIncludesCsrfReset(): void
    {
        global $api, $xtpl;
        $_SESSION['is_admin'] = true;
        $api = $this->client(true, ['incident_warning_limit_override' => null, 'incident_stop_limit_override' => 12, 'incident_stop_limit' => 12]);
        vps_incident_details($api->vps->show(17));
        $html = $xtpl->text('main.table');
        self::assertStringContainsString('name="incident_warning_limit_override" value=""', $html);
        self::assertStringContainsString('name="incident_stop_limit_override" value="12"', $html);
        self::assertSame(2, substr_count($html, 'name="csrf_token"'));
        self::assertStringContainsString('name="reset_limits" value="1"', $html);
        self::assertStringContainsString('method="post"', $html);
        self::assertSame(2, substr_count($html, 'name="incident_policy" value="oomd"'));
    }

    public function testExplicitNullResetAndFalseReachRealHaveApiClient(): void
    {
        global $api;
        $_SESSION['is_admin'] = true;
        $_POST = ['incident_warning_limit_override' => '', 'incident_stop_limit_override' => '12', 'incident_enforcement_enabled' => '0', 'incident_policy' => 'oomd', 'csrf_token' => csrf_token()];
        $api = $this->client();
        self::assertTrue(vps_incident_save(17));
        self::assertSame(['incident_policy' => 'oomd', 'incident_warning_limit_override' => null, 'incident_stop_limit_override' => 12, 'incident_enforcement_enabled' => false], $api->requests[1]['params']);
        self::assertSame($api->requests[1]['params'], $api->requests[1]['json']['vps']);
        self::assertSame('PUT', $api->requests[1]['method']);
        self::assertSame('/vpses/17', $api->requests[1]['path']);
        self::assertSame('show', $api->requests[2]['action']);
        self::assertSame(['incident_policy' => 'oomd'], $api->requests[2]['params']);

        $_POST = ['reset_limits' => '1', 'incident_policy' => 'oomd', 'csrf_token' => csrf_token()];
        self::assertTrue(vps_incident_save(17));
        self::assertSame(['incident_policy' => 'oomd', 'incident_warning_limit_override' => null, 'incident_stop_limit_override' => null], $api->requests[4]['params']);
        self::assertSame($api->requests[4]['params'], $api->requests[4]['json']['vps']);
    }

    public function testReadOnlyAndNonPostRequestsNeverWrite(): void
    {
        global $api;
        $api = $this->client();
        self::assertFalse(vps_incident_save(17));
        $_SESSION['is_admin'] = true;
        $_SERVER['REQUEST_METHOD'] = 'GET';
        self::assertFalse(vps_incident_save(17));
        self::assertSame([], $api->requests);
    }

    public function testInvalidCsrfNeverCallsApi(): void
    {
        global $api;
        $api = $this->client();
        $_SESSION['is_admin'] = true;
        $this->expectException(CsrfTokenInvalid::class);
        try {
            vps_incident_save(17);
        } finally {
            self::assertSame([], $api->requests);
        }
    }

    public function testInvalidLimitsAndApiErrorsKeepSettingsEditableWithoutUpdateSuccess(): void
    {
        global $api, $xtpl;
        $_SESSION['is_admin'] = true;
        $api = $this->client();
        foreach (['0', '-1', '2.5', '999999999999999999999', ['bad']] as $value) {
            $_POST = ['incident_warning_limit_override' => $value, 'incident_stop_limit_override' => '', 'incident_enforcement_enabled' => '1', 'incident_policy' => 'oomd', 'csrf_token' => csrf_token()];
            self::assertFalse(vps_incident_save(17));
        }
        self::assertNotContains('update', array_column($api->requests, 'action'));
        $_POST = ['incident_warning_limit_override' => '6', 'incident_stop_limit_override' => '5', 'incident_enforcement_enabled' => '1', 'incident_policy' => 'oomd', 'csrf_token' => csrf_token()];
        $api->rejectUpdate = true;
        self::assertFalse(vps_incident_save(17));
        self::assertStringContainsString(_('Unable to save incident settings'), $xtpl->text('main.perex'));
    }

    public function testListFiltersPreserveFalseValidateStatusAndIgnoreOldApi(): void
    {
        $_GET = ['incident_status' => 'near_limit', 'incident_enforcement_enabled' => '0'];
        self::assertSame(['incident_status' => 'near_limit', 'incident_enforcement_enabled' => false], vps_incident_list_filters((object) ['incident_status' => new stdClass(), 'incident_enforcement_enabled' => new stdClass()]));
        self::assertSame([], vps_incident_list_filters(new stdClass()));
        $_GET = ['incident_status' => ['bad'], 'incident_enforcement_enabled' => 'false'];
        self::assertSame([], vps_incident_list_filters((object) ['incident_status' => new stdClass(), 'incident_enforcement_enabled' => new stdClass()]));
    }

    public function testCapabilityRequiresSelectedTypeAndNumericCount(): void
    {
        self::assertFalse(vps_incident_available((object) ['incident_count_7d' => 0]));
        self::assertFalse(vps_incident_available((object) ['incident_policy' => 'oomd', 'incident_count_7d' => 'unavailable']));
        self::assertFalse(vps_incident_available((object) ['oom_incidents_7d' => 0]));
        self::assertTrue(vps_incident_available((object) ['incident_policy' => 'oomd', 'incident_count_7d' => 0]));
    }

    public function testSelectedTypeAndSharedStopStateAreRenderedWithoutMemoryClaimsForOtherTypes(): void
    {
        global $api, $xtpl;
        $api = $this->client(true, [
            'incident_count_7d' => 4, 'incident_count_30d' => 8,
            'incident_warning_limit' => 5, 'incident_stop_limit' => 10,
        ]);
        $api->typeData['synthetic'] = (object) (['incident_policy' => 'synthetic',
            'incident_policy_label' => 'Other <test> incidents',
            'incident_count_7d' => 1, 'incident_count_30d' => 2,
            'incident_warning_limit' => 3, 'incident_stop_limit' => 6,
            'incident_action_state' => 'pending', 'incident_action_chain_id' => 45,
            'incident_last_stop_at' => '2026-10-30T12:00:00Z',
        ] + (array) $api->vpsData);
        $memory = $api->vps->show(17);
        $other = $api->vps->show(17, ['incident_policy' => 'synthetic']);
        self::assertStringContainsString('4/5', vps_incident_indicator($memory));
        self::assertStringContainsString('1/3', vps_incident_indicator($other));
        self::assertStringContainsString('2/6', vps_incident_indicator($other));
        self::assertStringContainsString('incident_policy=synthetic', vps_incident_indicator($other));
        self::assertStringContainsString('codename=synthetic', vps_incident_history_url($other));
        vps_incident_details($other);
        $html = $xtpl->text('main.table');
        self::assertStringContainsString('Other &lt;test&gt; incidents', $html);
        self::assertStringContainsString('shared across incident types', $html);
        self::assertStringContainsString(_('Automatic shutdown pending'), $html);
        self::assertStringNotContainsString("The node's memory protection", $html);
        self::assertSame(['show', 'show'], array_column($api->requests, 'action'));
    }

    public function testSettingsRequireExplicitTypeAndKeepReadbackOnThatType(): void
    {
        global $api;
        $_SESSION['is_admin'] = true;
        $api = $this->client();
        $_POST = ['reset_limits' => '1', 'csrf_token' => csrf_token()];
        self::assertFalse(vps_incident_save(17));
        self::assertSame([], $api->requests);
        $api->typeData['synthetic'] = (object) (['incident_policy' => 'synthetic', 'incident_policy_label' => 'Synthetic incidents'] + (array) $api->vpsData);
        $_POST['incident_policy'] = 'synthetic';
        self::assertTrue(vps_incident_save(17));
        self::assertSame(['incident_policy' => 'synthetic'], $api->requests[0]['params']);
        self::assertSame(['incident_policy' => 'synthetic', 'incident_warning_limit_override' => null, 'incident_stop_limit_override' => null], $api->requests[1]['json']['vps']);
        self::assertSame(['incident_policy' => 'synthetic'], $api->requests[2]['params']);
    }

    public function testReadSelectorsAreOmittedOnOldApiAndPreservedOnSupportedApi(): void
    {
        $old = $this->client(false);
        $new = $this->client();
        self::assertSame([], vps_incident_read_params($new->vps->show));
        $_GET['incident_policy'] = 'synthetic';
        self::assertSame([], vps_incident_read_params($old->vps->show));
        self::assertSame(['incident_policy' => 'synthetic'], vps_incident_read_params($new->vps->show));
        $_GET['incident_policy'] = '';
        self::assertSame(['incident_policy' => ''], vps_incident_read_params($new->vps->show));
    }

    private function client(bool $supported = true, array $attrs = []): \HaveAPI\Client
    {
        $client = new class ('https://api.example') extends \HaveAPI\Client {
            public array $requests = [];
            public object $vpsData;
            public array $typeData = [];
            public bool $rejectUpdate = false;

            protected function sendRequest($request, $action = null, $params = [])
            {
                $this->requests[] = ['action' => $action->name(), 'params' => $params['vps'], 'method' => $action->httpMethod(), 'path' => $action->path(), 'json' => json_decode($request->payload ?? '', true)];
                return (object) ['code' => 200, 'body' => (object) [
                    'status' => !($this->rejectUpdate && $action->name() === 'update'), 'message' => '',
                    'errors' => (object) [], 'response' => (object) ['vps' => $this->typeData[$params['vps']['incident_policy'] ?? 'oomd'] ?? $this->vpsData, '_meta' => (object) ['path_params' => [17]]],
                ]];
            }
        };
        $fields = ['id' => 'Integer'];
        if ($supported) {
            $fields += array_fill_keys(['incident_count_7d', 'incident_count_30d', 'incident_warning_limit', 'incident_stop_limit', 'incident_warning_limit_override', 'incident_stop_limit_override', 'incident_action_chain_id'], 'Integer');
            $fields += array_fill_keys(['incident_enforcement_enabled', 'incident_stop_enforced'], 'Boolean');
            $fields += array_fill_keys(['incident_mode', 'incident_status', 'incident_action_state', 'incident_policy', 'incident_policy_label'], 'String');
            $fields += array_fill_keys(['incident_last_incident_at', 'incident_last_warning_at', 'incident_last_stop_at', 'incident_next_stop_allowed_at', 'incident_accounting_since'], 'Datetime');
        }
        $output = array_map(static fn($type) => (object) ['type' => $type], $fields);
        foreach (['incident_warning_limit_override', 'incident_stop_limit_override'] as $field) {
            if (isset($output[$field])) {
                $output[$field]->nullable = true;
            }
        }
        $action = static fn($method, $path, $input) => (object) [
            'aliases' => [], 'blocking' => false, 'method' => $method, 'path' => $path,
            'input' => (object) ['layout' => 'object', 'namespace' => 'vps', 'parameters' => (object) $input],
            'output' => (object) ['layout' => 'object', 'namespace' => 'vps', 'parameters' => (object) $output], 'meta' => (object) [],
        ];
        $client->setDescription((object) ['authentication' => (object) [], 'meta' => (object) ['namespace' => '_meta'], 'resources' => (object) [
            'vps' => (object) ['resources' => (object) [], 'actions' => (object) [
                'show' => $action('GET', '/vpses/{vps_id}', $supported ? ['incident_policy' => (object) ['type' => 'String']] : []),
                'update' => $action('PUT', '/vpses/{vps_id}', $supported ? array_intersect_key($output, array_flip(['incident_policy', 'incident_warning_limit_override', 'incident_stop_limit_override', 'incident_enforcement_enabled'])) : []),
            ]],
        ]]);
        $client->vpsData = (object) (['id' => 17] + ($supported ? $attrs + [
            'incident_policy' => 'oomd', 'incident_policy_label' => 'VPS memory-pressure incidents',
            'incident_count_7d' => 0, 'incident_count_30d' => 0, 'incident_warning_limit' => 5, 'incident_stop_limit' => 10,
            'incident_warning_limit_override' => null, 'incident_stop_limit_override' => null, 'incident_enforcement_enabled' => true,
            'incident_mode' => 'observe', 'incident_stop_enforced' => false, 'incident_status' => 'clear',
            'incident_last_incident_at' => null, 'incident_last_warning_at' => null, 'incident_last_stop_at' => null,
            'incident_next_stop_allowed_at' => null, 'incident_action_state' => 'none', 'incident_action_chain_id' => null,
            'incident_accounting_since' => null,
        ] : []));
        return $client;
    }
}
