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
        self::assertStringContainsString("'payload_json' => api_post('payload_json')", $testCase);
        self::assertStringNotContainsString('parameters' . '_json', $testCase);
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
        self::assertStringContainsString("_('Relation')", $matches);
        self::assertStringNotContainsString("_('Source')", $matches);
        self::assertStringNotContainsString("_('Order')", $matches);
        self::assertStringNotContainsString('match_order', $matches);
        self::assertStringContainsString('notifications_event_route_matches($event)', $show);
        self::assertStringNotContainsString('matched_event_route_id', $show);
    }

    public function testRouteLifecycleAndHitLabelsAreShownForAllRoutes(): void
    {
        $source = $this->notificationsFormsSource();
        $routeEdit = $this->sourceBetween(
            $source,
            'function notifications_route_edit(',
            'function notifications_matcher_new('
        );
        $routesList = $this->sourceBetween(
            $source,
            'function notifications_routes_list(',
            'function notifications_route_new('
        );

        self::assertStringContainsString("_('Route lifecycle')", $routeEdit);
        self::assertStringContainsString("_('Single-use route')", $routeEdit);
        self::assertStringContainsString("_('Hits')", $routeEdit);
        self::assertStringNotContainsString("_('Default route lifecycle')", $routeEdit);
        self::assertStringContainsString("_('Hits')", $routesList);
        self::assertStringNotContainsString('Hit count', $routesList);
    }

    public function testMatcherFormSupportsAnyEventTypeAndBooleanValues(): void
    {
        $source = $this->notificationsFormsSource();
        $matcherNew = $this->sourceBetween(
            $source,
            'function notifications_matcher_new(',
            'function notifications_receiver_targets_summary_html('
        );

        self::assertStringContainsString('notifications_event_type_labels(true, true)', $matcherNew);
        self::assertStringContainsString('Any event type', $source);
        self::assertStringContainsString(
            'notifications_matcher_value_toggle_script($field_types, $field_operators, $operator_labels)',
            $matcherNew
        );
        self::assertStringContainsString('notifications_matcher_field_select_options', $source);
        self::assertStringContainsString("\$name . ' - ' . \$description", $source);
        self::assertStringContainsString('notification-matcher-value', $matcherNew);
        self::assertStringContainsString('fieldTypes[field.val()]==="boolean"', $source);
        self::assertStringContainsString('else if(allowed.length){operator.val(allowed[0]);}', $source);
        self::assertStringContainsString("notifications_matcher_operator_reference_html(), false, false", $matcherNew);
        self::assertStringNotContainsString("notifications_matcher_operator_reference_html(), false, true", $matcherNew);
        self::assertStringContainsString("notifications_matcher_value_html('value', post_val('value'), \$field, \$field_types)", $matcherNew);
    }

    public function testEventTypeFieldMetadataHandlesCustomPayloadShapes(): void
    {
        require_once dirname(__DIR__, 2) . '/forms/notifications.forms.php';

        $magicType = new class {
            private array $attrs;

            public function __construct()
            {
                $this->attrs = [
                    'fields' => [
                        (object) [
                            'name' => 'stage',
                            'description' => 'Processing stage',
                            'type' => 'string',
                            'operators' => ['==', '!='],
                        ],
                    ],
                    'default_routed' => false,
                ];
            }

            public function attributes(): array
            {
                return $this->attrs;
            }

            public function __get(string $name): mixed
            {
                return $this->attrs[$name] ?? null;
            }
        };
        $objectType = (object) [
            'fields' => [
                (object) [
                    'name' => 'codename',
                    'description' => 'Incident codename',
                    'type' => 'string',
                    'operators' => (object) ['==' => '==', '=~' => '=~'],
                ],
            ],
        ];
        $jsonType = (object) [
            'fields' => json_encode([
                [
                    'name' => 'cgroups',
                    'description' => 'OOM cgroups',
                    'type' => 'string_list',
                    'operators' => ['contains', 'not_contains'],
                ],
            ]),
        ];

        self::assertFalse(isset($magicType->fields));
        $magicFields = notifications_event_type_field_metadata_from_type($magicType);
        $objectFields = notifications_event_type_field_metadata_from_type($objectType);
        $jsonFields = notifications_event_type_field_metadata_from_type($jsonType);

        self::assertSame('Processing stage', $magicFields['stage']['description']);
        self::assertFalse(notifications_prop($magicType, 'default_routed', true));
        self::assertSame('Incident codename', $objectFields['codename']['description']);
        self::assertSame(['==', '=~'], $objectFields['codename']['operators']);
        self::assertSame('string_list', $jsonFields['cgroups']['type']);
        self::assertSame(['contains', 'not_contains'], $jsonFields['cgroups']['operators']);
    }

    public function testEventTypesPageUsesSectionLayout(): void
    {
        $source = $this->notificationsFormsSource();
        $eventTypes = $this->sourceBetween(
            $source,
            'function notifications_event_types(',
            'function notifications_test_event('
        );

        self::assertStringContainsString('notification-event-types', $eventTypes);
        self::assertStringContainsString('notification-event-type-category', $eventTypes);
        self::assertStringContainsString('notification-event-type-fields', $eventTypes);
        self::assertStringContainsString('<section id="', $eventTypes);
        self::assertStringContainsString('<h3><code>', $eventTypes);
        self::assertStringContainsString('notification-event-type-label', $eventTypes);
        self::assertStringContainsString('notification-event-type-category-title', $eventTypes);
        self::assertStringContainsString('notification-event-type-category-count', $eventTypes);
        self::assertStringContainsString("sprintf(_('%d events'), count(\$types))", $eventTypes);
        self::assertStringNotContainsString('class="notification-event-type-category" open', $eventTypes);
        self::assertStringContainsString('notifications_event_types_hash_script();', $eventTypes);
        self::assertStringContainsString(
            'target.closest("details.notification-event-type-category").prop("open",true);',
            $eventTypes
        );
        self::assertStringContainsString('target[0].scrollIntoView', $eventTypes);
        self::assertStringContainsString('$xtpl->content_add_fragment($html);', $eventTypes);
        self::assertStringNotContainsString('$xtpl->table_td($html);', $eventTypes);
        self::assertStringNotContainsString("\$xtpl->table_tr('#fff', false, 'nohover');", $eventTypes);
        self::assertStringNotContainsString('No event-specific matchable fields', $eventTypes);
        self::assertStringContainsString('No matchable fields were reported by the API', $eventTypes);
        self::assertStringContainsString("_('Default routed')", $eventTypes);
        self::assertStringContainsString("_('Default routed') . ':</strong>", $eventTypes);
        self::assertStringNotContainsString("<th>' . _('Operators')", $eventTypes);
        self::assertStringNotContainsString("notifications_operator_list_html(\$field['operators']", $eventTypes);
        self::assertStringContainsString("'<tr><td colspan=\"4\">'", $eventTypes);
        self::assertStringContainsString('if (isAdmin() && $template)', $eventTypes);
    }

    public function testEventTypesSidebarIsGroupedSeparately(): void
    {
        $source = $this->notificationsFormsSource();
        $eventTypesSidebar = $this->sourceBetween(
            $source,
            'function notifications_event_types_sidebar(',
            'function notifications_test_event('
        );

        self::assertStringContainsString('notification-event-type-sidebar', $eventTypesSidebar);
        self::assertStringContainsString("<h3>' . _('Event types') . '</h3>", $eventTypesSidebar);
        self::assertStringContainsString("'<h4>' . h(\$category) . '</h4><ul>'", $eventTypesSidebar);
        self::assertStringContainsString('$xtpl->sbar_add_fragment($html);', $eventTypesSidebar);
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
