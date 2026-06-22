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
        self::assertStringContainsString('notifications_telegram_pairing_link_html($action)', $functionSource);
        self::assertStringContainsString('Generate new pairing command', $functionSource);
        self::assertStringContainsString('Re-pair Telegram chat', $functionSource);
        self::assertStringContainsString('pauses Telegram delivery until pairing succeeds', $functionSource);
        self::assertStringNotContainsString('create new pairing token', $functionSource);
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
        self::assertStringContainsString('receiver_action_edit&receiver=', $caseSource);
        self::assertStringContainsString("\$receiver_action->id", $caseSource);
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
}
