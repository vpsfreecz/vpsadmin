<?php

use PHPUnit\Framework\TestCase;

final class ConfigJsLocalizationTest extends TestCase
{
    private string $webuiRoot;

    protected function setUp(): void
    {
        $this->webuiRoot = dirname(__DIR__, 2) . '/';
    }

    public function testConfigActivatesLocaleBeforeEmittingSessionCountdownLabels(): void
    {
        $config = file_get_contents($this->webuiRoot . 'public/config.js.php');

        $activatePos = strpos($config, 'Lang::activate($webuiLocale);');
        $labelsPos = strpos($config, 'webui_session_countdown_labels()');

        self::assertIsInt($activatePos);
        self::assertIsInt($labelsPos);
        self::assertLessThan($labelsPos, $activatePos);
        self::assertStringContainsString(
            'sessionCountdown: <?php echo webui_json(webui_session_countdown_labels()) ?>',
            $config
        );
    }

    public function testCzechCatalogContainsSessionCountdownTooltip(): void
    {
        $catalog = file_get_contents(
            $this->webuiRoot . 'lang/locale/cs_CZ.utf8/LC_MESSAGES/vpsAdmin.po'
        );

        self::assertStringContainsString(
            'msgid "Left-click - extend timeout; Long left-click - disable timeout"',
            $catalog
        );
        self::assertStringContainsString(
            '"Kliknutí levým tlačítkem - prodloužit timeout; dlouhé kliknutí levým "',
            $catalog
        );
        self::assertStringContainsString(
            '"tlačítkem - vypnout timeout"',
            $catalog
        );
    }
}
