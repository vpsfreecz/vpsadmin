<?php

use PHPUnit\Framework\TestCase;

final class NotificationDeliveryHtmlDetailsTest extends TestCase
{
    public function testHtmlPreviewUsesSandboxedIframe(): void
    {
        $this->loadNotificationsForms();

        $preview = notifications_html_preview('<html><body><p>Hello</p></body></html>');

        self::assertStringContainsString('class="notification-delivery-html-preview"', $preview);
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
        self::assertStringContainsString('width: 790px;', $css);
        self::assertStringContainsString('min-height: 650px;', $css);
        self::assertStringContainsString('height: 70vh;', $css);
        self::assertStringContainsString('max-height: 900px;', $css);
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
