<?php

use PHPUnit\Framework\TestCase;

final class NotificationDeliveryHtmlDetailsTest extends TestCase
{
    public function testHtmlPreviewUsesSandboxedIframe(): void
    {
        $this->loadNotificationsForms();

        $preview = notifications_html_preview('<html><body><p>Hello</p></body></html>');

        self::assertStringContainsString('class="notification-delivery-html-preview"', $preview);
        self::assertStringContainsString('class="notification-delivery-html-frame"', $preview);
        self::assertStringContainsString('<iframe sandbox=""', $preview);
        self::assertStringContainsString('title="HTML preview"', $preview);
        self::assertStringContainsString('&lt;p&gt;Hello&lt;/p&gt;', $preview);
        self::assertStringNotContainsString('<p>Hello</p>', $preview);
    }

    public function testHtmlSourceIsCollapsedByDefault(): void
    {
        $this->loadNotificationsForms();

        $source = notifications_html_source_details('<p>Hello</p>');

        self::assertMatchesRegularExpression(
            '/<details class="notification-delivery-html-source">\s*<summary>HTML source<\/summary>/',
            $source
        );
        self::assertDoesNotMatchRegularExpression('/<details\b[^>]*\sopen(?:\s|=|>)/', $source);
        self::assertStringContainsString('&lt;p&gt;Hello&lt;/p&gt;', $source);
    }

    public function testHtmlPreviewStylesUseAvailableContentWidth(): void
    {
        $css = file_get_contents(dirname(__DIR__, 2) . '/public/template/css/main.css');

        self::assertStringContainsString('.notification-delivery-html-preview', $css);
        self::assertStringContainsString('.notification-delivery-html-frame', $css);
        self::assertStringContainsString('#notification-delivery-html', $css);
        self::assertStringContainsString('width: 100%;', $css);
        self::assertStringContainsString('max-width: none;', $css);
        self::assertStringContainsString('min-height: 650px;', $css);
        self::assertStringContainsString('height: 75vh;', $css);
        self::assertStringContainsString('height: calc(100% - 12px);', $css);
        self::assertStringContainsString('resize: vertical;', $css);
        self::assertStringContainsString('padding: 0;', $css);
        self::assertStringNotContainsString('width: 790px;', $css);
        self::assertStringNotContainsString('max-height: 900px;', $css);
    }

    public function testDeliveryQueueAndLogTableOmitsWideSummaryColumns(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/forms/notifications.forms.php');
        $start = strpos($source, 'function notifications_deliveries_admin(');
        $end = strpos($source, 'function notifications_events(', $start);

        self::assertNotFalse($start);
        self::assertNotFalse($end);

        $functionSource = substr($source, $start, $end - $start);

        self::assertStringNotContainsString('$xtpl->table_add_category(_(\'Result\'))', $functionSource);
        self::assertStringContainsString('notifications_delivery_group_html($delivery)', $functionSource);
        self::assertStringContainsString('false, false, 13', $functionSource);
    }

    public function testDeliveryLogFilterIncludesAbortedState(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/forms/notifications.forms.php');
        $functionSource = $this->sourceBetween(
            $source,
            'function notifications_delivery_state_group_states(',
            'function notifications_delivery_state_choices('
        );

        self::assertStringContainsString("return ['sent', 'failed', 'canceled', 'skipped', 'aborted'];", $functionSource);
    }

    public function testEventDetailDeliveryTableUsesVerticalResultRows(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/forms/notifications.forms.php');
        $functionSource = $this->sourceBetween(
            $source,
            'function notifications_event_show(',
            'function notifications_delivery_show('
        );

        self::assertStringContainsString('notifications_delivery_route_link($delivery, $event->user_id)', $functionSource);
        self::assertStringContainsString('notifications_delivery_transaction_chain_link($delivery)', $functionSource);
        self::assertStringContainsString("_('Result') . ':'", $functionSource);
        self::assertStringContainsString("_('Delivery attempts') . ':'", $functionSource);
        self::assertStringContainsString('false, false, 6', $functionSource);
        self::assertStringContainsString("false, false, 8", $functionSource);
        self::assertStringNotContainsString('$xtpl->table_add_category(_(\'Result\'))', $functionSource);
    }

    public function testDeliveryDetailsUseRouteAndTransactionChainLinks(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/forms/notifications.forms.php');
        $functionSource = $this->sourceBetween(
            $source,
            'function notifications_delivery_show(',
            'function notifications_delivery_email_show('
        );

        self::assertStringContainsString('notifications_delivery_route_link($delivery, $event->user_id)', $functionSource);
        self::assertStringContainsString('notifications_delivery_transaction_chain_link($delivery)', $functionSource);
        self::assertStringContainsString("_('Transaction chain') . ':'", $functionSource);
        self::assertStringContainsString("_('Notification group') . ':'", $functionSource);
        self::assertStringContainsString('notifications_delivery_group_event_ids($delivery)', $functionSource);
        self::assertStringContainsString("_('Effective delivery') . ':'", $functionSource);
    }

    public function testTargetFormShowsLinkedUserLoginForAdmins(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/forms/notifications.forms.php');
        $functionSource = $this->sourceBetween(
            $source,
            'function notifications_target_form_fields(',
            'function notifications_sms_verification_controls('
        );

        self::assertStringContainsString('$api->user->show($user_id)', $functionSource);
        self::assertStringContainsString('user_link($target_user)', $functionSource);
        self::assertStringNotContainsString("h((string) \$user_id)", $functionSource);
    }

    public function testTelegramPairingDetailShowsGuidedPairingAndRepairFlow(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/forms/notifications.forms.php');
        $start = strpos($source, 'function notifications_target_form_fields(');
        $end = strpos($source, 'function notifications_sms_verification_controls(', $start);

        self::assertNotFalse($start);
        self::assertNotFalse($end);

        $functionSource = substr($source, $start, $end - $start);

        self::assertStringContainsString('Open Telegram bot', $source);
        self::assertStringContainsString('Automatic pairing', $functionSource);
        self::assertStringContainsString('Manual pairing', $functionSource);
        self::assertStringContainsString('notifications_telegram_automatic_pairing_html($target)', $functionSource);
        self::assertStringContainsString('Generate new pairing command', $functionSource);
        self::assertStringContainsString('Re-pair Telegram chat', $functionSource);
        self::assertStringContainsString('pauses Telegram delivery until pairing succeeds', $functionSource);
        self::assertStringNotContainsString('create new pairing token', $functionSource);
    }

    public function testTelegramPairingSeparatesAutomaticLinkFromManualCommand(): void
    {
        $this->loadNotificationsForms();

        $action = (object) [
            'telegram_pairing_url' => 'https://t.me/vpsadmin_bot?start=pair-token',
            'telegram_pairing_command' => '/start pair-token',
            'telegram_bot_name' => 'vpsadmin_bot',
        ];

        $automatic = notifications_telegram_automatic_pairing_html($action);
        $manual = notifications_telegram_pairing_instructions_html($action);

        self::assertStringContainsString('href="https://t.me/vpsadmin_bot?start=pair-token"', $automatic);
        self::assertStringContainsString('The link includes the pairing command', $automatic);
        self::assertStringContainsString('@vpsadmin_bot', $manual);
        self::assertStringContainsString('/start pair-token', $manual);
        self::assertStringNotContainsString('href="https://t.me/vpsadmin_bot?start=pair-token"', $manual);
    }

    public function testReceiversTableSplitsEditAndDeleteActions(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/forms/notifications.forms.php');
        $functionSource = $this->sourceBetween(
            $source,
            'function notifications_receivers(',
            'function notifications_receiver_action_target_html('
        );

        self::assertSame(2, substr_count($functionSource, '$xtpl->table_add_category(\'\');'));
        self::assertStringContainsString('false, false, 7', $functionSource);
        self::assertStringNotContainsString('$xtpl->table_td(\'\');', $functionSource);
    }

    public function testTargetTablesSplitEditAndDeleteActions(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/forms/notifications.forms.php');
        $targetsSource = $this->sourceBetween(
            $source,
            'function notifications_targets(',
            'function notifications_receivers('
        );
        $receiverSource = $this->sourceBetween(
            $source,
            'function notifications_receiver_edit(',
            'function notifications_time_or_dash('
        );

        self::assertSame(2, substr_count($targetsSource, '$xtpl->table_add_category(\'\');'));
        self::assertStringContainsString('false, false, 8', $targetsSource);
        self::assertSame(2, substr_count($receiverSource, '$xtpl->table_add_category(\'\');'));
        self::assertStringContainsString('false, false, 8', $receiverSource);
    }

    public function testTargetListUsesTargetStatusFields(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/forms/notifications.forms.php');
        $targetsSource = $this->sourceBetween(
            $source,
            'function notifications_targets(',
            'function notifications_receivers('
        );
        $targetStatusSource = $this->sourceBetween(
            $source,
            'function notifications_target_status_html(',
            'function notifications_target_action_status_html('
        );
        $receiverStatusSource = $this->sourceBetween(
            $source,
            'function notifications_receiver_action_secret_html(',
            'function notifications_target_status_html('
        );

        self::assertStringContainsString('notifications_target_status_html($target)', $targetsSource);
        self::assertStringContainsString('enabled', $targetStatusSource);
        self::assertStringNotContainsString('target_enabled', $targetStatusSource);
        self::assertStringContainsString('target_enabled', $receiverStatusSource);
    }

    public function testNotificationFilterSelectsAreLeftAligned(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/forms/notifications.forms.php');
        $deliveryFilters = $this->sourceBetween(
            $this->sourceBetween(
                $source,
                'function notifications_deliveries_admin(',
                'function notifications_events('
            ),
            '$xtpl->table_title(_(\'Filters\'));',
            '$xtpl->form_out(_(\'Show\'));'
        );
        $eventFilters = $this->sourceBetween(
            $this->sourceBetween(
                $source,
                'function notifications_events(',
                'function notifications_event_show('
            ),
            '$xtpl->table_title(_(\'Filters\'));',
            '$xtpl->form_out(_(\'Show\'));'
        );

        foreach ([$deliveryFilters, $eventFilters] as $filterSource) {
            self::assertDoesNotMatchRegularExpression(
                '/notifications_select_html\([\s\S]*?\)\s*,\s*false\s*,\s*true/',
                $filterSource
            );
        }
    }

    public function testTelegramTargetCreateRedirectsToTargetDetail(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/pages/page_notifications.php');
        $start = strpos($source, "case 'target_new':");
        $end = strpos($source, "case 'target_edit':", $start);

        self::assertNotFalse($start);
        self::assertNotFalse($end);

        $caseSource = substr($source, $start, $end - $start);

        self::assertStringContainsString('$target = $api->notification_target->create($params)', $caseSource);
        self::assertStringContainsString('$receiver->target->create', $caseSource);
        self::assertStringContainsString("\$action_type === 'telegram'", $caseSource);
        self::assertStringContainsString("\$action_type === 'sms'", $caseSource);
        self::assertStringContainsString('notifications_target_url($target->id, $user_id, $receiver ? $receiver->id : null)', $caseSource);
    }

    public function testSmsVerificationFlowIsVisibleInReceiverActionDetail(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/forms/notifications.forms.php');
        $start = strpos($source, 'function notifications_target_form_fields(');
        $end = strpos($source, 'function notifications_sms_verification_controls(', $start);

        self::assertNotFalse($start);
        self::assertNotFalse($end);

        $functionSource = substr($source, $start, $end - $start);

        self::assertStringContainsString('Phone number', $functionSource);
        self::assertStringContainsString("'40',\n            'target_value'", $functionSource);
        self::assertStringContainsString('SMS verification', $source);
        self::assertStringContainsString('Send verification SMS', $source);
        self::assertStringContainsString('confirm_sms_verification_code', file_get_contents(dirname(__DIR__, 2) . '/pages/page_notifications.php'));
        self::assertStringContainsString('send_sms_verification_code', file_get_contents(dirname(__DIR__, 2) . '/pages/page_notifications.php'));
    }

    public function testEmailVerificationFlowIsVisibleInTargetDetail(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/forms/notifications.forms.php');
        $page = file_get_contents(dirname(__DIR__, 2) . '/pages/page_notifications.php');
        $functionSource = $this->sourceBetween(
            $source,
            'function notifications_target_form_fields(',
            'function notifications_sms_verification_controls('
        );

        self::assertStringContainsString('Custom e-mail address', $functionSource);
        self::assertStringContainsString('one custom address', $functionSource);
        self::assertStringContainsString('notifications_email_target_custom_row_class($target_kind)', $functionSource);
        self::assertStringContainsString('notification-email-custom-target', $source);
        self::assertStringContainsString('notification-email-custom-target-hidden', $source);
        self::assertStringContainsString('notificationsToggleEmailTargetValue', $source);
        self::assertStringContainsString('fadeIn(150)', $source);
        self::assertStringContainsString('fadeOut(150)', $source);
        self::assertStringContainsString('input.prop("disabled",!isCustom)', $source);
        self::assertStringContainsString('E-mail verification', $source);
        self::assertStringContainsString('Send verification e-mail', $source);
        self::assertStringContainsString('confirm_email_verification', $page);
        self::assertStringContainsString('send_email_verification', $page);
    }

    public function testTargetFormContentIsLeftAligned(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/forms/notifications.forms.php');
        $functionSource = $this->sourceBetween(
            $source,
            'function notifications_target_form_fields(',
            'function notifications_sms_verification_controls('
        );
        $smsControlsSource = $this->sourceBetween(
            $source,
            'function notifications_sms_verification_controls(',
            'function notifications_email_verification_controls('
        );
        $emailControlsSource = $this->sourceBetween(
            $source,
            'function notifications_email_verification_controls(',
            'function notifications_target_new('
        );

        foreach ([$functionSource, $smsControlsSource, $emailControlsSource] as $formSource) {
            self::assertDoesNotMatchRegularExpression('/table_td\([\s\S]*?,\s*false\s*,\s*true/', $formSource);
        }
    }

    public function testSmsDeliveryDetailsShowsMessagePayload(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/forms/notifications.forms.php');
        $start = strpos($source, 'function notifications_delivery_show(');
        $end = strpos($source, 'function notifications_delivery_email_show(', $start);

        self::assertNotFalse($start);
        self::assertNotFalse($end);

        $functionSource = substr($source, $start, $end - $start);

        self::assertStringContainsString('notifications_delivery_sms_show($delivery)', $functionSource);
        self::assertStringContainsString('function notifications_delivery_sms_show($delivery)', $source);
        self::assertStringContainsString('Gateway callback', $source);
    }

    public function testReceiverTargetUnlinkRequiresConfirmation(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/forms/notifications.forms.php');
        $start = strpos($source, 'function notifications_receiver_edit(');
        $end = strpos($source, 'function notifications_time_or_dash(', $start);

        self::assertNotFalse($start);
        self::assertNotFalse($end);

        $functionSource = substr($source, $start, $end - $start);

        self::assertStringContainsString('receiver_target_delete', $functionSource);
        self::assertStringContainsString('notifications_confirm_onclick', $functionSource);
        self::assertStringContainsString(
            "notifications_target_url(notifications_prop(\$target, 'notification_target_id'), \$receiver->user_id, \$receiver->id)",
            $functionSource
        );
        self::assertStringContainsString(
            'Do you really wish to unlink this notification target from the receiver?',
            $functionSource
        );
    }

    public function testReceiverTargetLinksDoNotHaveEnabledControls(): void
    {
        $forms = file_get_contents(dirname(__DIR__, 2) . '/forms/notifications.forms.php');
        $page = file_get_contents(dirname(__DIR__, 2) . '/pages/page_notifications.php');

        foreach ([$forms, $page] as $source) {
            self::assertStringNotContainsString('Enable receiver link', $source);
            self::assertStringNotContainsString('Link enabled', $source);
            self::assertStringNotContainsString('link_enabled', $source);
            self::assertStringNotContainsString('receiver_target_toggle', $source);
        }
    }

    public function testTargetEditCanReturnToReceiverContext(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/forms/notifications.forms.php');
        $functionSource = $this->sourceBetween(
            $source,
            'function notifications_target_edit(',
            'function notifications_receiver_edit('
        );

        self::assertStringContainsString('notifications_target_context_receiver', $functionSource);
        self::assertStringContainsString('Back to receiver', $functionSource);
        self::assertStringContainsString("notifications_sidebar('receivers'", $functionSource);
    }

    public function testRateLimitListUsesNestedUserApiHandle(): void
    {
        $this->loadNotificationsForms();

        global $api;

        $api = new class {
            public $userHandle;
            public array $requestedUsers = [];

            public function __construct()
            {
                $this->userHandle = new class {
                    public $notification_rate_limit;

                    public function __construct()
                    {
                        $this->notification_rate_limit = new class {
                            public function __call($name, $args)
                            {
                                if ($name !== 'list') {
                                    throw new BadMethodCallException($name);
                                }

                                return [
                                    (object) [
                                        'id' => 'email-minute',
                                    ],
                                ];
                            }
                        };
                    }
                };
            }

            public function user($id)
            {
                $this->requestedUsers[] = $id;

                return $this->userHandle;
            }
        };
        $user = (object) [
            'id' => 42,
            'notification_rate_limit' => false,
        ];

        $limits = notifications_rate_limits_for_user($user);

        self::assertSame([42], $api->requestedUsers);
        self::assertCount(1, $limits);
        self::assertSame('email-minute', $limits[0]->id);
    }

    public function testRateLimitUpdateUsesNestedUserApiHandle(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/pages/page_notifications.php');
        $caseSource = $this->sourceBetween($source, "case 'limits':", "case 'test':");

        self::assertStringContainsString(
            '$api->user($user_id)->notification_rate_limit($limit->id)->update',
            $caseSource
        );
        self::assertStringNotContainsString(
            '$user->notification_rate_limit($limit->id)->update',
            $caseSource
        );
    }

    public function testUserDetailDeliveryMethodFormUsesTwoColumns(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/pages/page_adminm.php');
        $functionSource = $this->sourceBetween(
            $source,
            'function adminm_print_notification_delivery_methods(',
            'function print_newm()'
        );

        self::assertSame(2, substr_count($functionSource, '$xtpl->table_add_category('));
        self::assertSame(1, substr_count($functionSource, '$xtpl->table_add_category(\'&nbsp;\');'));
        self::assertSame(2, preg_match_all("/false,\\s*false,\\s*'2'/", $functionSource));
        self::assertDoesNotMatchRegularExpression("/false,\\s*false,\\s*'3'/", $functionSource);
    }

    private function loadNotificationsForms(): void
    {
        if (!function_exists('_')) {
            function _($s)
            {
                return $s;
            }
        }

        if (!function_exists('h')) {
            function h($value)
            {
                if ($value === null) {
                    return '';
                }

                return htmlspecialchars((string) $value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
            }
        }

        require_once dirname(__DIR__, 2) . '/forms/notifications.forms.php';
    }

    private function sourceBetween(string $source, string $startNeedle, string $endNeedle): string
    {
        $start = strpos($source, $startNeedle);

        self::assertNotFalse($start);

        $end = strpos($source, $endNeedle, $start + strlen($startNeedle));

        self::assertNotFalse($end);

        return substr($source, $start, $end - $start);
    }
}
