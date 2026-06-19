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
