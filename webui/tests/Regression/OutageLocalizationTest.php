<?php

use PHPUnit\Framework\TestCase;

require_once dirname(__DIR__, 2) . '/lib/gettext_lang.lib.php';
require_once dirname(__DIR__, 2) . '/forms/outage.forms.php';

final class OutageLocalizationTest extends TestCase
{
    private array $oldSession;

    protected function setUp(): void
    {
        global $langs;

        $this->oldSession = $_SESSION ?? [];
        $_SESSION = ['user' => ['language' => 'cs']];
        $langs = [
            'en_US.utf8' => [
                'api_code' => 'en',
            ],
            'cs_CZ.utf8' => [
                'api_code' => 'cs',
            ],
        ];
    }

    protected function tearDown(): void
    {
        $_SESSION = $this->oldSession;
    }

    public function testUsesSummaryForCurrentLanguage(): void
    {
        $outage = (object) [
            'cs_summary' => 'České shrnutí',
            'en_summary' => 'English summary',
        ];

        self::assertSame(
            'České shrnutí',
            outage_localized_text($outage, 'summary')
        );
    }

    public function testFallsBackToEnglishSummary(): void
    {
        $outage = (object) [
            'cs_summary' => '',
            'en_summary' => 'English summary',
        ];

        self::assertSame(
            'English summary',
            outage_localized_text($outage, 'summary')
        );
    }

    public function testReturnsEmptyStringWhenTranslationsAreEmpty(): void
    {
        $outage = (object) [
            'cs_summary' => null,
            'en_summary' => '',
        ];

        self::assertSame('', outage_localized_text($outage, 'summary'));
    }
}
