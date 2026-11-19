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
        require_once $root . '/forms/incidents.forms.php';
        global $xtpl;
        $xtpl = new XTemplate($root . '/template/template.html');
        $_SESSION = ['is_admin' => false, 'csrf_base' => 'incident-policy-test'];
        $_GET = [];
        $_POST = [];
        $_SERVER['REQUEST_METHOD'] = 'POST';
    }

    public function testDiscoveredPoliciesRenderZeroCountsAndDifferentLimitsWithoutSourceBranches(): void
    {
        global $api, $xtpl;
        $api = $this->client();
        vps_incident_page($api->vps->show(17));
        $html = $xtpl->text('main.table');
        self::assertStringNotContainsString('Each policy counts reports', $html);
        self::assertStringContainsString('First &lt;policy&gt;', $html);
        self::assertStringNotContainsString('First <policy>', $html);
        self::assertStringContainsString('Second policy', $html);
        self::assertSame([
            [['Period', 'Incidents', 'Limit', 'Action'], ['Last 7 days', '0', '5', 'Warning'], ['Last 30 days', '0', '10', 'VPS stop']],
            [['Period', 'Incidents', 'Limit', 'Action'], ['Last 7 days', '7', '9', 'Warning'], ['Last 30 days', '7', '12', 'VPS stop']],
        ], $this->periodTables($html));
        self::assertStringContainsString('policy_key=Another_2', $html);
        self::assertStringNotContainsString('<details>', $html);
        self::assertStringNotContainsString('<summary>', $html);
        self::assertStringNotContainsString('<form', $html);
        self::assertStringNotContainsString('settings_category', $html);
        self::assertSame(['/vpses/17', '/vpses/17/incident_policies'], array_column($api->requests, 'path'));
    }

    public function testReportsNavigationRetainsItsReturnAndPoliciesHaveASeparateDestination(): void
    {
        global $api, $xtpl;
        foreach ([true, false] as $supported) {
            $api = $this->client($supported);
            $xtpl = new XTemplate(dirname(__DIR__, 2) . '/template/template.html');
            $return = urlencode('/?page=adminvps&action=info&veid=17');
            vps_incident_sidebar((object) ['id' => 17], $return);
            $xtpl->sbar_out('VPS');
            $html = $xtpl->text('main.sidebar');
            $dom = $this->document($html);
            $xpath = new DOMXPath($dom);
            $reports = $xpath->query('//*[@data-vpsadmin-doc-id="vps.incident-reports.menu"]')->item(0);
            self::assertSame('Incident reports', trim($reports->textContent));
            self::assertSame('?page=incidents&action=list&list=1&vps=17&return=' . $return, $reports->getAttribute('href'));
            $policies = $xpath->query('//*[@data-vpsadmin-doc-id="vps.incidents.menu"]');
            self::assertSame($supported ? 1 : 0, $policies->length);
            if ($supported) {
                self::assertSame('Incident policies', trim($policies->item(0)->textContent));
                self::assertSame('?page=adminvps&action=incidents&veid=17', $policies->item(0)->getAttribute('href'));
            }
            self::assertSame([], $api->requests);
        }
    }

    public function testAbsentNestedCapabilityHidesFeatureWithoutFallbackRequests(): void
    {
        global $api;
        $api = $this->client(false);
        self::assertNull(vps_incident_resource());
        self::assertFalse(vps_incident_available((object) ['incident_count_7d' => 2, 'incident_policy' => 'legacy']));
        self::assertSame('', vps_incident_indicator((object) ['id' => 17]));
        self::assertSame([], $api->requests);
    }

    public function testOnlyReachedThresholdsProduceOverviewWarningAndUseStopPrecedence(): void
    {
        $vps = (object) ['id' => 17, 'incident_warning_count' => 0, 'incident_stop_threshold_count' => 0];
        self::assertSame('', vps_incident_indicator($vps));
        $vps->incident_warning_count = 2;
        self::assertStringContainsString(_('Too many incident reports: warning limit reached'), vps_incident_indicator($vps));
        $vps->incident_stop_threshold_count = 1;
        $html = vps_incident_indicator($vps);
        self::assertStringContainsString(_('Too many incident reports: VPS shutdown limit reached'), $html);
        self::assertStringContainsString('warning.png', $html);
        self::assertStringContainsString('action=incidents', $html);
        self::assertStringNotContainsString(_('Too many incident reports: warning limit reached'), $html);
    }

    public function testAdminOverrideFormsAreScopedAndPermissionIsSeparate(): void
    {
        global $api, $xtpl;
        $_SESSION['is_admin'] = true;
        $api = $this->client();
        vps_incident_page($api->vps->show(17));
        $html = $xtpl->text('main.table');
        self::assertSame(3, substr_count($html, 'name="csrf_token"'));
        self::assertSame(2, substr_count($html, 'name="policy_key"'));
        self::assertSame(1, substr_count($html, 'name="incident_enforcement_enabled"'));
        self::assertStringNotContainsString('data-incident-inherit', $html);
        self::assertStringNotContainsString('_limit_intent', $html);
        self::assertStringNotContainsString('data-incident-pending', $html);
        $xpath = new DOMXPath($this->document($html));
        self::assertSame(4, $xpath->query('//form[starts-with(@name,"incident-policy-")]//input[@type="number"]')->length);
        self::assertSame(0, $xpath->query('//form[starts-with(@name,"incident-policy-")]//select | //button')->length);
        self::assertSame(3, $xpath->query('//input[@type="submit"]')->length);
        self::assertStringContainsString('name="incident-policy-Another_2"', $html);
        self::assertStringContainsString('name="incident-permission"', $html);
        self::assertStringNotContainsString('incident_policy_Another_2', $html);
        self::assertStringNotContainsString('?page=cluster&amp;action=sysconfig', $html);
        self::assertStringNotContainsString('reset_limits', $html);
    }

    public function testNullInheritanceTargetsExactPolicyAndNeverWritesSharedPermission(): void
    {
        global $api;
        $_SESSION['is_admin'] = true;
        $_POST = ['policy_key' => 'Another_2', 'warning_limit_override' => '  ', 'stop_limit_override' => ' 19 ', 'csrf_token' => csrf_token()];
        $api = $this->client();
        self::assertTrue(vps_incident_save(17));
        $writes = array_values(array_filter($api->requests, static fn($r) => $r['method'] === 'PUT'));
        self::assertCount(1, $writes);
        self::assertSame('/vpses/17/incident_policies/Another_2', $writes[0]['path']);
        self::assertSame(['warning_limit_override' => null, 'stop_limit_override' => 19], $writes[0]['json']['incident_policy']);
        self::assertSame('/vpses/17/incident_policies/Another_2', end($api->requests)['path']);
    }

    public function testSharedFalsePermissionHasNoPolicyOrOverrideFields(): void
    {
        global $api;
        $_SESSION['is_admin'] = true;
        $_POST = ['incident_enforcement_enabled' => '0', 'csrf_token' => csrf_token()];
        $api = $this->client();
        self::assertTrue(vps_incident_save(17, true));
        $writes = array_values(array_filter($api->requests, static fn($r) => $r['method'] === 'PUT'));
        self::assertSame('/vpses/17', $writes[0]['path']);
        self::assertSame(['incident_enforcement_enabled' => false], $writes[0]['json']['vps']);
        self::assertSame('/vpses/17', end($api->requests)['path']);
    }

    public function testInvalidLimitsOrKeyAndApiRejectionNeverReportSuccess(): void
    {
        global $api, $xtpl;
        $_SESSION['is_admin'] = true;
        foreach (['-1', '1.2', '0', [], 1.5, 5, '1e2', '999999999999999999999999'] as $bad) {
            $api = $this->client();
            $_POST = ['policy_key' => 'Another_2', 'warning_limit_override' => $bad, 'stop_limit_override' => '10', 'csrf_token' => csrf_token()];
            self::assertFalse(vps_incident_save(17));
            self::assertNotContains('PUT', array_column($api->requests, 'method'));
        }
        self::assertTrue((bool) vps_incident_key(str_repeat('A', 59)));
        self::assertFalse((bool) vps_incident_key(str_repeat('A', 60)));
        self::assertFalse((bool) vps_incident_key('../foreign'));
        self::assertFalse((bool) vps_incident_key(['invalid']));
        $api = $this->client();
        $api->rejectUpdate = true;
        $_POST = ['policy_key' => 'Another_2', 'warning_limit_override' => '9', 'stop_limit_override' => '8', 'csrf_token' => csrf_token()];
        self::assertFalse(vps_incident_save(17));
        self::assertStringContainsString(_('Unable to save changes'), $xtpl->text('main.perex'));
    }

    public function testMemberGetAndInvalidCsrfNeverReachWriteOrDisclosure(): void
    {
        global $api;
        $api = $this->client();
        self::assertFalse(vps_incident_save(17));
        $_SESSION['is_admin'] = true;
        $_SERVER['REQUEST_METHOD'] = 'GET';
        self::assertFalse(vps_incident_save(17));
        self::assertSame([], $api->requests);
        $_SERVER['REQUEST_METHOD'] = 'POST';
        $this->expectException(CsrfTokenInvalid::class);
        try {
            vps_incident_save(17);
        } finally {
            self::assertSame([], $api->requests);
        }
    }

    public function testFiltersRequireExplicitPolicyAndHistoryKeepsExactRetiredKey(): void
    {
        $input = (object) ['incident_policy' => new stdClass(), 'incident_status' => new stdClass(), 'incident_enforcement_enabled' => new stdClass()];
        $_GET = ['incident_status' => 'warning', 'incident_enforcement_enabled' => '0'];
        self::assertSame([], vps_incident_list_filters($input));
        $_GET['incident_policy'] = 'Another_2';
        self::assertSame(['incident_policy' => 'Another_2', 'incident_status' => 'warning'], vps_incident_list_filters($input));
        self::assertSame([], vps_incident_list_filters(new stdClass()));
        self::assertStringContainsString('policy_key=Retired_9', vps_incident_history_url((object) ['id' => 17], 'Retired_9'));
        self::assertStringNotContainsString('codename=', vps_incident_history_url((object) ['id' => 17], 'Retired_9'));
    }

    public function testConfigurationFailureDoesNotInventCurrentLimits(): void
    {
        global $api, $xtpl;
        $api = $this->client();
        $api->policies[0]->configuration_valid = false;
        $api->policies[0]->warning_limit = null;
        $api->policies[0]->stop_limit = null;
        vps_incident_page($api->vps->show(17));
        $html = $xtpl->text('main.table');
        self::assertStringContainsString(_('Incident limits are misconfigured.'), $html);
        self::assertSame(['Last 7 days', '0', 'Unknown', 'Warning'], $this->periodTables($html)[0][1]);
        self::assertSame(['Last 30 days', '0', 'Unknown', 'VPS stop'], $this->periodTables($html)[0][2]);
    }

    public function testMatchedDetailsAreSortedAndRetiredKeysKeepOnlyAuthorizedHistory(): void
    {
        global $api, $xtpl;
        $api = $this->client();
        $api->evaluations = [
            $this->evaluation('alpha', 'First <policy>'),
            $this->evaluation('Retired_9', 'Retired policy'),
            $this->evaluation('Another_2', 'Second policy', ['state' => 'audit_only']),
            $this->evaluation('not_matched', 'Nonmatching private label', ['matched' => false]),
            $this->evaluation('failed', 'Failed private label', ['matched' => null, 'state' => 'error', 'error_class' => 'PrivateError']),
            $this->evaluation('configuration_error', 'Config private label', ['matched' => true, 'state' => 'error']),
            $this->evaluation('skipped', 'Skipped private label', ['matched' => true, 'state' => 'skipped']),
        ];
        incident_policy_evaluations($this->report());
        $html = $xtpl->text('main.table');
        self::assertSame(3, count($this->periodTables($html)));
        self::assertSame('7 days', $this->periodTables($html)[0][1][0]);
        self::assertSame('30 days', $this->periodTables($html)[0][2][0]);
        self::assertStringContainsString('These counts and limits were saved when this report was evaluated.', $html);
        self::assertLessThan(strpos($html, 'Retired policy'), strpos($html, 'Second policy'));
        self::assertLessThan(strpos($html, 'First &lt;policy&gt;'), strpos($html, 'Retired policy'));
        self::assertStringNotContainsString('First <policy>', $html);
        self::assertStringContainsString('veid=17#incident-policy-alpha', $html);
        self::assertStringContainsString('veid=17#incident-policy-Another_2', $html);
        self::assertStringNotContainsString('#incident-policy-Retired_9', $html);
        self::assertStringContainsString('vps=17&amp;policy_key=Retired_9', $html);
        foreach (['Nonmatching private label', 'Failed private label', 'Config private label', 'Skipped private label', 'PrivateError'] as $hidden) {
            self::assertStringNotContainsString($hidden, $html);
        }
        self::assertSame(['/incident_reports/41/policy_evaluations', '/vpses/17/incident_policies'], array_column($api->requests, 'path'));
    }

    public function testAdminDiagnosticsKeepMatchedTruthAndSafeErrorsSeparate(): void
    {
        global $api, $xtpl;
        $_SESSION['is_admin'] = true;
        $api = $this->client();
        $api->evaluations = [
            $this->evaluation('alpha', 'Visible policy'),
            $this->evaluation('configuration_error', 'Configuration failure', ['matched' => true, 'state' => 'error',
                'warning_limit' => null, 'stop_limit' => null, 'error_stage' => '<configuration>', 'error_class' => '<SafeError>', 'error_message' => 'DO NOT DISPLAY']),
            $this->evaluation('false', 'Nonmatching policy', ['matched' => false]),
            $this->evaluation('null', 'Selector failure', ['matched' => null, 'state' => 'error']),
        ];
        incident_policy_evaluations($this->report());
        $html = $xtpl->text('main.table');
        self::assertSame(1, count($this->periodTables($html)));
        self::assertStringContainsString('Other policy evaluations', $html);
        self::assertStringContainsString('Configuration failure', $html);
        self::assertStringContainsString('&lt;configuration&gt;', $html);
        self::assertStringContainsString('&lt;SafeError&gt;', $html);
        self::assertStringNotContainsString('DO NOT DISPLAY', $html);
        $xpath = new DOMXPath($this->document($html));
        self::assertSame(1, $xpath->query('//tr[td[1][normalize-space()="Matched:"] and td[2][normalize-space()="Yes"]]')->length);
        self::assertSame(1, $xpath->query('//tr[td[1][normalize-space()="Matched:"] and td[2][normalize-space()="No"]]')->length);
        self::assertSame(1, $xpath->query('//tr[td[1][normalize-space()="Matched:"] and td[2][normalize-space()="Unknown"]]')->length);
    }

    public function testUnavailableAssociationsAndCapabilitiesNeverInventLiveOrUnfilteredLinks(): void
    {
        global $api, $xtpl;
        $api = $this->client();
        $api->evaluations = [$this->evaluation('alpha', 'Saved policy')];
        $report = $this->report();
        $report->vps = null;
        $report->vps_id = 999;
        incident_policy_evaluations($report);
        $html = $xtpl->text('main.table');
        self::assertStringNotContainsString('action=incidents', $html);
        self::assertStringNotContainsString('policy_key=', $html);
        self::assertSame(['/incident_reports/41/policy_evaluations'], array_column($api->requests, 'path'));

        $api = $this->client();
        $api->evaluations = [$this->evaluation('alpha', 'Saved policy')];
        unset($api->getDescription()->resources->incident_report->actions->index->input->parameters->policy_key);
        $xtpl = new XTemplate(dirname(__DIR__, 2) . '/template/template.html');
        incident_policy_evaluations($this->report());
        $html = $xtpl->text('main.table');
        self::assertStringContainsString('#incident-policy-alpha', $html);
        self::assertStringNotContainsString('policy_key=', $html);

        $api = $this->client();
        unset($api->getDescription()->resources->incident_report->resources->policy_evaluation->actions->index->output->parameters->matched);
        incident_policy_evaluations($this->report());
        self::assertSame([], $api->requests);
    }

    public function testOptionalLiveLookupFailureKeepsSavedFactsWithoutErrorDisclosure(): void
    {
        global $api, $xtpl;
        $api = $this->client();
        $api->rejectPolicyIndex = true;
        $api->evaluations = [$this->evaluation('alpha', 'Saved policy')];
        incident_policy_evaluations($this->report());
        $html = $xtpl->text('main.table');
        self::assertStringContainsString('Saved policy', $html);
        self::assertStringContainsString('policy_key=alpha', $html);
        self::assertStringNotContainsString('#incident-policy-alpha', $html);
        self::assertStringNotContainsString('PRIVATE API failure', $html);
        self::assertSame(['/incident_reports/41/policy_evaluations', '/vpses/17/incident_policies'], array_column($api->requests, 'path'));
    }

    public function testNoVisibleMatchDoesNotAssertNoPolicyMatchedOrFetchNavigation(): void
    {
        global $api, $xtpl;
        $api = $this->client();
        $api->evaluations = [$this->evaluation('alpha', 'Hidden error policy', ['matched' => true, 'state' => 'error'])];
        incident_policy_evaluations($this->report());
        self::assertStringContainsString('Policy information is unavailable for this report.', $xtpl->text('main.table'));
        self::assertStringNotContainsString('No matching policies', $xtpl->text('main.table'));
        self::assertSame(['/incident_reports/41/policy_evaluations'], array_column($api->requests, 'path'));
    }

    public function testNoticeOriginDoesNotUseTriggerLookupOrPerListRowRequests(): void
    {
        global $api;
        $api = $this->client();
        $notice = $this->report();
        $notice->notice_kind = 'warning';
        $notice->notice_mail_state = 'queued';
        $notice->notice_policy_key = 'alpha';
        $notice->notice_policy_label = 'Origin <policy>';
        $notice->trigger_incident_report_id = 999;
        $list = incident_notice_html($notice);
        self::assertStringContainsString('Origin &lt;policy&gt;', $list);
        self::assertStringContainsString('Mail queued', $list);
        self::assertSame([], $api->requests);
        $detail = incident_notice_html($notice, true);
        self::assertStringContainsString('#incident-policy-alpha', $detail);
        self::assertSame(['/vpses/17/incident_policies'], array_column($api->requests, 'path'));
        incident_policy_evaluations($notice);
        self::assertSame(['/vpses/17/incident_policies'], array_column($api->requests, 'path'));
        self::assertSame('', incident_notice_html((object) ['codename' => 'oomd', 'notice_kind' => null]));
    }

    public function testRawOverridesAndBlankSiblingPreserveIndependentNullIntentWithoutJavascript(): void
    {
        global $api, $xtpl;
        $_SESSION['is_admin'] = true;
        $api = $this->client();
        $api->policies[0]->warning_limit = 3;
        vps_incident_page($api->vps->show(17));
        $xpath = new DOMXPath($this->document($xtpl->text('main.table')));
        self::assertSame('', $xpath->evaluate('string(//form[@name="incident-policy-alpha"]//input[@name="warning_limit_override"]/@value)'));
        self::assertSame('3', $xpath->evaluate('string(//form[@name="incident-policy-alpha"]//input[@name="warning_limit_override"]/@placeholder)'));
        self::assertSame('', $xpath->evaluate('string(//form[@name="incident-policy-alpha"]//input[@name="stop_limit_override"]/@value)'));
        self::assertSame('10', $xpath->evaluate('string(//form[@name="incident-policy-alpha"]//input[@name="stop_limit_override"]/@placeholder)'));
        foreach ([['', ' ', null, null], ['3', '', 3, null], ['', '10', null, 10], [' 3 ', ' 10 ', 3, 10]] as [$warning, $stop, $expectedWarning, $expectedStop]) {
            $_POST = ['policy_key' => 'alpha', 'warning_limit_override' => $warning,
                'stop_limit_override' => $stop, 'csrf_token' => csrf_token()];
            self::assertTrue(vps_incident_save(17));
            self::assertSame($expectedWarning, $api->policies[0]->warning_limit_override);
            self::assertSame($expectedStop, $api->policies[0]->stop_limit_override);
            self::assertSame('/vpses/17/incident_policies/alpha', end($api->requests)['path']);
        }
        $_POST = [];
        $xtpl = new XTemplate(dirname(__DIR__, 2) . '/template/template.html');
        vps_incident_page($api->vps->show(17));
        $xpath = new DOMXPath($this->document($xtpl->text('main.table')));
        self::assertSame('10', $xpath->evaluate('string(//form[@name="incident-policy-alpha"]//input[@name="stop_limit_override"]/@value)'));
        self::assertSame(0, $xpath->query('//form[@name="incident-policy-alpha"]//input[@placeholder]')->length);
    }

    public function testFailedDraftAndClearedOverrideDoNotInventInheritedTarget(): void
    {
        global $api, $xtpl;
        $_SESSION['is_admin'] = true;
        $api = $this->client();
        $api->policies[0]->warning_limit_override = $api->policies[0]->warning_limit = 8;
        $api->rejectUpdate = true;
        $_POST = ['policy_key' => 'alpha', 'warning_limit_override' => '', 'stop_limit_override' => '0', 'csrf_token' => csrf_token()];
        self::assertFalse(vps_incident_save(17));
        vps_incident_page($api->vps->show(17));
        $xpath = new DOMXPath($this->document($xtpl->text('main.table')));
        self::assertSame('', $xpath->evaluate('string(//form[@name="incident-policy-alpha"]//input[@name="warning_limit_override"]/@value)'));
        self::assertSame(0, $xpath->query('//form[@name="incident-policy-alpha"]//input[@name="warning_limit_override"]/@placeholder')->length);
        self::assertSame('0', $xpath->evaluate('string(//form[@name="incident-policy-alpha"]//input[@name="stop_limit_override"]/@value)'));
        self::assertSame('', $xpath->evaluate('string(//form[@name="incident-policy-Another_2"]//input[@name="warning_limit_override"]/@value)'));
        self::assertStringContainsString('Leave a limit empty to use the default.', $xtpl->text('main.table'));
        self::assertStringContainsString('Enter a positive whole number, or leave the limit empty.', $xtpl->text('main.perex'));
        $_POST['stop_limit_override'] = '11';
        self::assertFalse(vps_incident_save(17));
        $xtpl = new XTemplate(dirname(__DIR__, 2) . '/template/template.html');
        vps_incident_page($api->vps->show(17));
        self::assertStringContainsString('value="11"', $xtpl->text('main.table'));
        $api->rejectUpdate = false;
        self::assertTrue(vps_incident_save(17));
        self::assertNull($api->policies[0]->warning_limit_override);
        self::assertSame(5, $api->policies[0]->warning_limit);
        self::assertSame(11, $api->policies[0]->stop_limit_override);
        self::assertSame('/vpses/17/incident_policies/alpha', end($api->requests)['path']);
        $_POST = [];
        $xtpl = new XTemplate(dirname(__DIR__, 2) . '/template/template.html');
        vps_incident_page($api->vps->show(17));
        $xpath = new DOMXPath($this->document($xtpl->text('main.table')));
        self::assertSame('5', $xpath->evaluate('string(//form[@name="incident-policy-alpha"]//input[@name="warning_limit_override"]/@placeholder)'));
        $api->policies[0]->configuration_valid = false;
        $api->policies[0]->warning_limit = null;
        $xtpl = new XTemplate(dirname(__DIR__, 2) . '/template/template.html');
        vps_incident_page($api->vps->show(17));
        self::assertSame(0, (new DOMXPath($this->document($xtpl->text('main.table'))))->query('//form[@name="incident-policy-alpha"]//input[@name="warning_limit_override"]/@placeholder')->length);
    }

    public function testPageLandmarkContainsOnlyThisPageAndNoRedundantIntroduction(): void
    {
        global $api, $xtpl;
        $_SESSION['is_admin'] = true;
        $api = $this->client();
        $xtpl->table_title('Existing unrelated table');
        $xtpl->table_td('Keep prefix');
        $xtpl->table_tr();
        $xtpl->table_out();
        vps_incident_page($api->vps->show(17));
        $xpath = new DOMXPath($this->document($xtpl->text('main.table')));
        $page = '//*[@data-vpsadmin-doc-id="vps.incidents.page"]';
        self::assertSame(1, $xpath->query($page)->length);
        self::assertSame('div', $xpath->query($page)->item(0)->nodeName);
        foreach (['policy' => 2, 'settings' => 2, 'permission' => 1] as $id => $count) {
            self::assertSame($count, $xpath->query($page . '//*[@data-vpsadmin-doc-id="vps.incidents.' . $id . '"]')->length);
        }
        self::assertSame(0, $xpath->query($page . '//h2[normalize-space()="Incident policies"] | ' . $page . '//tr[td[normalize-space()="Incident reports:"]]')->length);
        self::assertStringNotContainsString('Keep prefix', $xpath->query($page)->item(0)->textContent);
        self::assertStringContainsString('Keep prefix', $xtpl->text('main.table'));
        $api->policies = [];
        $xtpl = new XTemplate(dirname(__DIR__, 2) . '/template/template.html');
        vps_incident_page($api->vps->show(17));
        $xpath = new DOMXPath($this->document($xtpl->text('main.table')));
        self::assertSame(1, $xpath->query($page . '//*[@data-vpsadmin-doc-id="vps.incidents.permission"]')->length);
    }

    public function testVpsFilterRemovesShutdownControlButKeepsPolicyAndStatus(): void
    {
        global $api, $xtpl;
        $api = $this->client();
        $xtpl->form_create('', 'get', 'vps-filter', false);
        $input = (object) ['incident_policy' => new stdClass(), 'incident_status' => new stdClass(), 'incident_enforcement_enabled' => new stdClass()];
        $_GET = ['incident_policy' => 'alpha', 'incident_status' => 'warning', 'incident_enforcement_enabled' => '0'];
        vps_incident_filter_form($input);
        $xtpl->form_out('Show');
        $xpath = new DOMXPath($this->document($xtpl->text('main.table')));
        self::assertSame(0, $xpath->query('//*[@name="incident_enforcement_enabled"]')->length);
        self::assertSame(1, $xpath->query('//select[@name="incident_policy"]')->length);
        self::assertSame(1, $xpath->query('//select[@name="incident_status"]')->length);
        self::assertSame(['incident_policy' => 'alpha', 'incident_status' => 'warning'], vps_incident_list_filters($input));
    }

    public function testReportFilterUsesAuthorizedChoicesAndPreservesEscapedRetiredKey(): void
    {
        global $api, $xtpl;
        $api = $this->client();
        $_GET = ['policy_key' => 'retired"<key>'];
        $xtpl->assign('AJAX_SCRIPT', '<script>window.existingRouteScript = true;</script>');
        $xtpl->form_create('', 'get', 'incident-list', false);
        $xtpl->form_set_hidden_fields(['page' => 'incidents', 'action' => 'list', 'list' => '1',
            'vps' => '17', 'user' => '23', 'codename' => 'fixture_abuse', 'limit' => '25']);
        $xtpl->form_add_input('From ID:', 'text', '40', 'from_id', '999999');
        incident_policy_filter_form();
        $xtpl->form_out('Show');
        $xpath = new DOMXPath($this->document($xtpl->text('main.table')));
        self::assertSame(0, $xpath->query('//input[@name="policy_key"]')->length);
        self::assertSame(['All policies', 'First <policy>', 'Second policy', 'retired"<key>'], array_map(static fn($n) => $n->textContent, iterator_to_array($xpath->query('//select[@name="policy_key"]/option'))));
        self::assertSame('retired"<key>', $xpath->evaluate('string(//select[@name="policy_key"]/option[@selected]/@value)'));
        self::assertSame(['/incident_policies'], array_column($api->requests, 'path'));
        self::assertSame('incidents', $xpath->evaluate('string(//form[@name="incident-list"]//input[@name="page"]/@value)'));
        self::assertSame('17', $xpath->evaluate('string(//form[@name="incident-list"]//input[@name="vps"]/@value)'));
        self::assertSame('fixture_abuse', $xpath->evaluate('string(//form[@name="incident-list"]//input[@name="codename"]/@value)'));
        $xtpl->parse('main');
        $page = $xtpl->text('main');
        self::assertStringContainsString('window.existingRouteScript = true', $page);
        self::assertStringNotContainsString('src="js/vps.js"', $page);
        $xtpl = new XTemplate(dirname(__DIR__, 2) . '/template/template.html');
        $xtpl->form_create('', 'get', 'incident-list', false);
        $xtpl->form_set_hidden_fields(['page' => 'incidents', 'action' => 'list', 'list' => '1']);
        $api->rejectRegistry = true;
        incident_policy_filter_form();
        $xtpl->form_out('Show');
        $html = $xtpl->text('main.table');
        self::assertStringContainsString('Incident settings unavailable', $html);
        self::assertStringNotContainsString('PRIVATE API failure', $html);
        self::assertStringNotContainsString('<select', $html);
        self::assertStringContainsString('name="policy_key"', $html);
        self::assertStringContainsString('name="page" value="incidents"', $html);
        $api->rejectRegistry = false;
        $api->policies = [];
        $_GET = [];
        $xtpl = new XTemplate(dirname(__DIR__, 2) . '/template/template.html');
        incident_policy_filter_form();
        $xtpl->form_out('Show');
        $html = $xtpl->text('main.table');
        self::assertStringContainsString('All policies', $html);
        self::assertStringNotContainsString('Incident settings unavailable', $html);
    }

    public function testKnownEmptyIsOnlyUsedForExhaustiveAdminSavedEvidence(): void
    {
        global $api, $xtpl;
        foreach ([false, true] as $admin) {
            foreach (['empty', 'false', 'error', 'unavailable'] as $case) {
                $_SESSION['is_admin'] = $admin;
                $xtpl = new XTemplate(dirname(__DIR__, 2) . '/template/template.html');
                $api = $this->client();
                $api->evaluations = $case === 'empty' ? [] : [$this->evaluation('alpha', 'Private evaluation', ['matched' => $case === 'false' ? false : true, 'state' => 'error'])];
                $api->rejectEvaluations = $case === 'unavailable';
                incident_policy_evaluations($this->report());
                $html = $xtpl->text('main.table');
                $known = $admin && in_array($case, ['empty', 'false'], true);
                self::assertStringContainsString($known ? 'No matching policies' : 'Policy information is unavailable for this report.', $html);
                if (!$known) {
                    self::assertStringNotContainsString('No matching policies', $html);
                }
                if (!$admin) {
                    self::assertStringNotContainsString('Private evaluation', $html);
                }
                self::assertStringNotContainsString('PRIVATE API failure', $html);
            }
        }
    }

    public function testThresholdPhrasesPreserveCountAndDifferentPeriodsAndPolicyName(): void
    {
        global $api, $xtpl;
        $_SESSION['is_admin'] = true;
        $api = $this->client();
        $api->policies[0]->warning_limit = 1;
        $api->policies[0]->warning_period_days = 1;
        $api->policies[0]->stop_limit = 3;
        $api->policies[0]->stop_period_days = 14;
        $api->policies[0]->status = 'warning';
        vps_incident_page($api->vps->show(17));
        $html = $xtpl->text('main.table');
        $xpath = new DOMXPath($this->document($html));
        self::assertSame('', $xpath->evaluate('string(//form[@name="incident-policy-alpha"]//input[@name="warning_limit_override"]/@value)'));
        self::assertSame('1', $xpath->evaluate('string(//form[@name="incident-policy-alpha"]//input[@name="warning_limit_override"]/@placeholder)'));
        self::assertSame('reports in 1 day', $xpath->evaluate('string(//form[@name="incident-policy-alpha"]//*[@data-incident-unit][1])'));
        self::assertStringContainsString('reports in 14 days', $html);
        self::assertSame(2, $xpath->query('//form[@name="incident-policy-alpha"]//tr[td/input[@type="number"]]')->length);
        self::assertStringContainsString('First &lt;policy&gt;: Too many incident reports: warning limit reached', $html);
        $notice = $this->report();
        $notice->notice_kind = 'warning';
        $notice->notice_mail_state = 'sent';
        self::assertStringContainsString('Sent', incident_notice_html($notice));
        self::assertStringNotContainsString('SMTP', incident_notice_html($notice));
    }

    private function report(): object
    {
        return (object) ['id' => 41, 'vps' => (object) ['id' => 17, '_meta' => (object) ['resolved' => true]]];
    }

    private function evaluation(string $key, string $label, array $values = []): object
    {
        return (object) ($values + ['policy_key' => $key, 'label' => $label, 'matched' => true, 'state' => 'recorded',
            'evaluated_at' => '2026-11-18T12:00:00Z', 'warning_period_days' => 7, 'stop_period_days' => 30,
            'count_7d' => 2, 'count_30d' => 4, 'warning_limit' => 5, 'stop_limit' => 10, 'decision' => 'none']);
    }

    private function document(string $html): DOMDocument
    {
        $document = new DOMDocument();
        $previous = libxml_use_internal_errors(true);
        $document->loadHTML('<html><body>' . $html . '</body></html>');
        libxml_clear_errors();
        libxml_use_internal_errors($previous);
        return $document;
    }

    private function periodTables(string $html): array
    {
        $xpath = new DOMXPath($this->document($html));
        $tables = [];
        foreach ($xpath->query('//table[thead/tr/th]') as $table) {
            $rows = [];
            foreach ($xpath->query('./thead/tr | ./tbody/tr', $table) as $row) {
                $cells = [];
                foreach ($xpath->query('./th | ./td', $row) as $cell) {
                    $cells[] = trim($cell->textContent);
                }
                $rows[] = $cells;
            }
            $tables[] = $rows;
        }
        return $tables;
    }

    private function client(bool $supported = true): \HaveAPI\Client
    {
        $client = new class ('https://api.example') extends \HaveAPI\Client {
            public array $requests = [];
            public array $policies = [];
            public array $evaluations = [];
            public bool $rejectUpdate = false;
            public bool $rejectPolicyIndex = false;
            public bool $rejectEvaluations = false;
            public bool $rejectRegistry = false;

            protected function sendRequest($request, $action = null, $params = [])
            {
                $json = json_decode($request->payload ?? '', true);
                $path = $action->path();
                $this->requests[] = ['path' => $path, 'method' => $action->httpMethod(), 'json' => $json, 'params' => $params];
                $policy = str_contains($path, '/incident_policies');
                if ($path === '/incident_policies') {
                    $data = $this->policies;
                } elseif (str_ends_with($path, '/policy_evaluations')) {
                    $data = $this->evaluations;
                } elseif ($policy && str_ends_with($path, '/incident_policies')) {
                    $data = $this->policies;
                } elseif ($policy) {
                    $key = rawurldecode(basename($path));
                    $data = current(array_filter($this->policies, static fn($p) => $p->key === $key));
                    if ($action->httpMethod() === 'PUT' && !$this->rejectUpdate) {
                        foreach ($json['incident_policy'] as $field => $value) {
                            $data->{$field} = $value;
                            $effective = str_replace('_override', '', $field);
                            $data->{$effective} = $value ?? ($key === 'alpha' ? ($effective === 'warning_limit' ? 5 : 10) : ($effective === 'warning_limit' ? 9 : 12));
                        }
                    }
                } else {
                    $data = (object) ['id' => 17, 'incident_enforcement_enabled' => true, 'incident_warning_count' => 0,
                        'incident_stop_threshold_count' => 0, 'incident_last_stop_at' => null, 'incident_action_state' => 'none',
                        'incident_action_chain_id' => null, 'incident_next_stop_allowed_at' => null];
                }
                return (object) ['code' => 200, 'body' => (object) ['status' => !(($this->rejectUpdate && $action->httpMethod() === 'PUT') || ($this->rejectPolicyIndex && $policy) || ($this->rejectRegistry && $path === '/incident_policies') || ($this->rejectEvaluations && str_ends_with($path, '/policy_evaluations'))),
                    'message' => 'PRIVATE API failure', 'errors' => (object) [], 'response' => (object) [
                        $action->getNamespace('output') => $data, '_meta' => (object) ['path_params' => [17]],
                    ],
                ]];
            }
        };
        $vpsFields = ['id' => 'Integer', 'incident_warning_count' => 'Integer', 'incident_stop_threshold_count' => 'Integer',
            'incident_enforcement_enabled' => 'Boolean', 'incident_last_stop_at' => 'Datetime', 'incident_action_state' => 'String',
            'incident_action_chain_id' => 'Integer', 'incident_next_stop_allowed_at' => 'Datetime'];
        $policyFields = ['key' => 'String', 'label' => 'String', 'description' => 'Text', 'settings_category' => 'String',
            'count_7d' => 'Integer', 'count_30d' => 'Integer', 'warning_limit' => 'Integer', 'stop_limit' => 'Integer',
            'warning_limit_override' => 'Integer', 'stop_limit_override' => 'Integer', 'configuration_valid' => 'Boolean',
            'status' => 'String', 'warning_period_days' => 'Integer', 'stop_period_days' => 'Integer',
            'last_incident_at' => 'Datetime', 'last_warning_at' => 'Datetime', 'evaluation_report_id' => 'Integer', 'evaluated_at' => 'Datetime', 'effective_mode' => 'String'];
        $evaluationFields = ['policy_key' => 'String', 'label' => 'String', 'matched' => 'Boolean', 'state' => 'String',
            'evaluated_at' => 'Datetime', 'warning_period_days' => 'Integer', 'stop_period_days' => 'Integer',
            'count_7d' => 'Integer', 'count_30d' => 'Integer', 'warning_limit' => 'Integer', 'stop_limit' => 'Integer',
            'decision' => 'String', 'error_stage' => 'String', 'error_class' => 'String', 'error_message' => 'String'];
        $parameters = static fn($fields) => (object) array_map(static fn($type) => (object) ['type' => $type, 'nullable' => true], $fields);
        $action = static fn($method, $path, $namespace, $out, $input = [], $list = false) => (object) [
            'aliases' => [], 'blocking' => false, 'method' => $method, 'path' => $path,
            'input' => (object) ['layout' => 'object', 'namespace' => $namespace, 'parameters' => $parameters($input)],
            'output' => (object) ['layout' => $list ? 'object_list' : 'object', 'namespace' => $namespace, 'parameters' => $parameters($out)], 'meta' => (object) [],
        ];
        $policyResource = (object) ['resources' => (object) [], 'actions' => (object) [
            'index' => $action('GET', '/vpses/{vps_id}/incident_policies', 'incident_policy', $policyFields, [], true),
            'show' => $action('GET', '/vpses/{vps_id}/incident_policies/{key}', 'incident_policy', $policyFields),
            'update' => $action(
                'PUT',
                '/vpses/{vps_id}/incident_policies/{key}',
                'incident_policy',
                $policyFields,
                ['warning_limit_override' => 'Integer', 'stop_limit_override' => 'Integer']
            ),
        ]];
        $client->setDescription((object) ['authentication' => (object) [], 'meta' => (object) ['namespace' => '_meta'], 'resources' => (object) [
            'incident_policy' => (object) ['resources' => (object) [], 'actions' => (object) [
                'index' => $action('GET', '/incident_policies', 'incident_policy', $policyFields, [], true),
            ]],
            'vps' => (object) ['resources' => $supported ? (object) ['incident_policy' => $policyResource] : (object) [], 'actions' => (object) [
                'show' => $action('GET', '/vpses/{vps_id}', 'vps', $vpsFields),
                'update' => $action('PUT', '/vpses/{vps_id}', 'vps', $vpsFields, ['incident_enforcement_enabled' => 'Boolean']),
            ]],
            'incident_report' => (object) ['resources' => (object) [
                'policy_evaluation' => (object) ['resources' => (object) [], 'actions' => (object) [
                    'index' => $action('GET', '/incident_reports/{incident_report_id}/policy_evaluations', 'policy_evaluation', $evaluationFields, [], true),
                ]],
            ], 'actions' => (object) [
                'index' => $action('GET', '/incident_reports', 'incident_report', ['id' => 'Integer'], ['policy_key' => 'String'], true),
                'show' => $action('GET', '/incident_reports/{incident_report_id}', 'incident_report', ['id' => 'Integer']),
            ]],
        ]]);
        foreach ([['alpha', 'First <policy>', 0, 5, 10], ['Another_2', 'Second policy', 7, 9, 12]] as [$key, $label, $count, $warning, $stop]) {
            $client->policies[] = (object) ['key' => $key, 'label' => $label, 'description' => '<short & description>',
                'settings_category' => 'incident_policy_' . $key, 'count_7d' => $count, 'count_30d' => $count,
                'warning_limit' => $warning, 'stop_limit' => $stop, 'warning_limit_override' => null, 'stop_limit_override' => null,
                'configuration_valid' => true, 'status' => $count ? 'near_limit' : 'clear',
                'warning_period_days' => 7, 'stop_period_days' => 30, 'last_incident_at' => null, 'last_warning_at' => null,
                'evaluation_report_id' => null, 'evaluated_at' => null];
        }
        return $client;
    }
}
