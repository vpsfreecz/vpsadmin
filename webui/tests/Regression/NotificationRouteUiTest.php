<?php

use PHPUnit\Framework\TestCase;

final class NotificationRouteUiTest extends TestCase
{
    public function testRouteFormsExposeSubjectScope(): void
    {
        $source = $this->notificationsFormsSource();
        $routeNew = $this->sourceBetween(
            $source,
            'function notifications_route_new(',
            'function notifications_route_subroutes('
        );
        $routeEdit = $this->sourceBetween(
            $source,
            'function notifications_route_edit(',
            'function notifications_matcher_new('
        );

        foreach ([$routeNew, $routeEdit] as $functionSource) {
            self::assertStringContainsString('notifications_subject_scope_options', $functionSource);
            self::assertStringContainsString("'subject_scope'", $functionSource);
            self::assertStringContainsString("_('Scope')", $functionSource);
        }

        self::assertStringContainsString("api_post('subject_scope')", $source);
        self::assertStringContainsString("\$params['subject_scope'] = \$subject_scope", $source);
    }

    public function testRouteListsShowSubjectScope(): void
    {
        $source = $this->notificationsFormsSource();
        $routesList = $this->sourceBetween(
            $source,
            'function notifications_routes_list(',
            'function notifications_route_new('
        );
        $subroutes = $this->sourceBetween(
            $source,
            'function notifications_route_subroutes(',
            'function notifications_route_edit('
        );

        foreach ([$routesList, $subroutes] as $functionSource) {
            self::assertStringContainsString("_('Scope')", $functionSource);
            self::assertStringContainsString('notifications_subject_scope_label', $functionSource);
        }
    }

    public function testEventLogFiltersAllowEmptySeverityAndRoutingState(): void
    {
        $source = $this->sourceBetween(
            $this->notificationsFormsSource(),
            'function notifications_events(',
            'function notifications_event_show('
        );

        self::assertStringContainsString("\$value !== null && \$value !== ''", $source);
        self::assertStringContainsString("\$delivery_action !== null && \$delivery_action !== ''", $source);
        self::assertStringContainsString("api_get_uint('event_route_id')", $source);
        self::assertStringContainsString("\$params['event_route_id'] = \$route_id", $source);
        self::assertStringNotContainsString('matched_event_route_id', $source);
        self::assertStringContainsString(
            "api_param_to_form('severity', \$input->severity, get_val('severity'), null, true)",
            $source
        );
        self::assertStringContainsString(
            "api_param_to_form('routing_state', \$input->routing_state, get_val('routing_state'), null, true)",
            $source
        );
    }

    public function testSubjectScopeLabelsAreStable(): void
    {
        $source = $this->sourceBetween(
            $this->notificationsFormsSource(),
            'function notifications_subject_scope_options(',
            'function notifications_short_value('
        );

        self::assertStringContainsString("'self' => _('Own events')", $source);
        self::assertStringContainsString("'visible' => _('Visible events')", $source);
    }

    public function testTestEventFormExposesAdminSubjectScope(): void
    {
        $source = $this->notificationsFormsSource();
        $testForm = $this->sourceBetween(
            $source,
            'function notifications_test_event(',
            "notifications_sidebar('test'"
        );
        $pageSource = file_get_contents(dirname(__DIR__, 2) . '/pages/page_notifications.php');
        $testCase = $this->sourceBetween($pageSource, "case 'test':", 'default:');

        self::assertStringContainsString('notifications_test_subject_scope_options', $testForm);
        self::assertStringContainsString("'subject_scope'", $testForm);
        self::assertStringContainsString("\$params['subject_scope'] = api_post('subject_scope')", $testCase);
    }

    public function testEventDetailsListMatchedRoutes(): void
    {
        $source = $this->notificationsFormsSource();
        $matches = $this->sourceBetween(
            $source,
            'function notifications_event_route_matches(',
            'function notifications_event_show('
        );
        $show = $this->sourceBetween(
            $source,
            'function notifications_event_show(',
            'function notifications_delivery_show('
        );

        self::assertStringContainsString('$event->route_match->list()', $matches);
        self::assertStringContainsString("_('Matched routes')", $matches);
        self::assertStringContainsString('notifications_event_route_matches($event)', $show);
        self::assertStringNotContainsString('matched_event_route_id', $show);
    }

    public function testReceiverTargetStatusUsesReceiverTargetEnabledField(): void
    {
        $source = $this->sourceBetween(
            $this->notificationsFormsSource(),
            'function notifications_receiver_action_secret_html(',
            'function notifications_target_status_html('
        );

        self::assertStringContainsString("notifications_prop(\$action, 'target_enabled')", $source);
        self::assertStringContainsString("notifications_prop(\$action, 'delivery_method_enabled')", $source);
        self::assertStringContainsString('notifications_target_action_status_html($action)', $source);
        self::assertStringNotContainsString('notifications_target_status_html($action)', $source);
    }

    private function notificationsFormsSource(): string
    {
        return file_get_contents(dirname(__DIR__, 2) . '/forms/notifications.forms.php');
    }

    private function sourceBetween(string $source, string $startNeedle, string $endNeedle): string
    {
        $start = strpos($source, $startNeedle);
        self::assertNotFalse($start);
        $end = strpos($source, $endNeedle, $start);
        self::assertNotFalse($end);

        return substr($source, $start, $end - $start);
    }
}
