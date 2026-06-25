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

        self::assertStringNotContainsString('$xtpl->table_add_category(_(\'Target\'))', $functionSource);
        self::assertStringNotContainsString('$xtpl->table_add_category(_(\'Result\'))', $functionSource);
        self::assertStringContainsString('false, false, 12', $functionSource);
    }

    public function testTelegramPairingDetailShowsGuidedPairingAndRepairFlow(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/forms/notifications.forms.php');
        $start = strpos($source, 'function notifications_receiver_action_form_fields(');
        $end = strpos($source, 'function notifications_receiver_action_new(', $start);

        self::assertNotFalse($start);
        self::assertNotFalse($end);

        $functionSource = substr($source, $start, $end - $start);

        self::assertStringContainsString('Open Telegram bot', $source);
        self::assertStringContainsString('Automatic pairing', $functionSource);
        self::assertStringContainsString('Manual pairing', $functionSource);
        self::assertStringContainsString('notifications_telegram_automatic_pairing_html($action)', $functionSource);
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
        ];

        $automatic = notifications_telegram_automatic_pairing_html($action);
        $manual = notifications_telegram_pairing_instructions_html($action);

        self::assertStringContainsString('href="https://t.me/vpsadmin_bot?start=pair-token"', $automatic);
        self::assertStringContainsString('The link includes the pairing command', $automatic);
        self::assertStringContainsString('/start pair-token', $manual);
        self::assertStringNotContainsString('href="https://t.me/vpsadmin_bot?start=pair-token"', $manual);
    }

    public function testReceiversTableDoesNotHaveUnusedActionColumn(): void
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

    public function testTelegramActionCreateRedirectsToActionDetail(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/pages/page_notifications.php');
        $start = strpos($source, "case 'receiver_action_new':");
        $end = strpos($source, "case 'receiver_action_edit':", $start);

        self::assertNotFalse($start);
        self::assertNotFalse($end);

        $caseSource = substr($source, $start, $end - $start);

        self::assertStringContainsString('$receiver_action = $receiver->action->create', $caseSource);
        self::assertStringContainsString("\$action_type === 'telegram'", $caseSource);
        self::assertStringContainsString("\$action_type === 'sms'", $caseSource);
        self::assertStringContainsString('receiver_action_edit&receiver=', $caseSource);
        self::assertStringContainsString("\$receiver_action->id", $caseSource);
    }

    public function testSmsVerificationFlowIsVisibleInReceiverActionDetail(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/forms/notifications.forms.php');
        $start = strpos($source, 'function notifications_receiver_action_form_fields(');
        $end = strpos($source, 'function notifications_receiver_action_new(', $start);

        self::assertNotFalse($start);
        self::assertNotFalse($end);

        $functionSource = substr($source, $start, $end - $start);

        self::assertStringContainsString('Phone number', $functionSource);
        self::assertStringContainsString('SMS verification', $source);
        self::assertStringContainsString('Send verification SMS', $source);
        self::assertStringContainsString('confirm_sms_verification_code', file_get_contents(dirname(__DIR__, 2) . '/pages/page_notifications.php'));
        self::assertStringContainsString('send_sms_verification_code', file_get_contents(dirname(__DIR__, 2) . '/pages/page_notifications.php'));
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

    public function testReceiverActionDeleteRequiresConfirmation(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/forms/notifications.forms.php');
        $start = strpos($source, 'function notifications_receiver_edit(');
        $end = strpos($source, 'function notifications_time_or_dash(', $start);

        self::assertNotFalse($start);
        self::assertNotFalse($end);

        $functionSource = substr($source, $start, $end - $start);

        self::assertStringContainsString('receiver_action_delete', $functionSource);
        self::assertStringContainsString('notifications_confirm_onclick', $functionSource);
        self::assertStringContainsString(
            'Do you really wish to delete this notification receiver action?',
            $functionSource
        );
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
