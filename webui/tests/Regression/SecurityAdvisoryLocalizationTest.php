<?php

use PHPUnit\Framework\TestCase;

final class SecurityAdvisoryLocalizationTest extends TestCase
{
    public static function setUpBeforeClass(): void
    {
        require_once dirname(__DIR__, 2) . '/lib/functions.lib.php';
        require_once dirname(__DIR__, 2) . '/forms/security_advisory.forms.php';
    }

    public function testNodeNoteUsesCurrentLanguageWithEnglishFallback(): void
    {
        global $lang;

        $lang = new class {
            public string $locale = 'cs_CZ.utf8';

            public function get_current_lang(): string
            {
                return $this->locale;
            }
        };

        $status = (object) [
            'en_note' => 'Mitigated by live patch',
            'cs_note' => 'Mitigováno live patchem',
        ];

        self::assertSame(
            'Mitigováno live patchem',
            security_advisory_localized_node_note($status)
        );

        $status->cs_note = null;
        self::assertSame(
            'Mitigated by live patch',
            security_advisory_localized_node_note($status)
        );

        $status->en_note = null;
        self::assertSame(
            '',
            security_advisory_localized_node_note($status)
        );
    }

    public function testNodeFormHasOneNoteFieldPerContentLanguage(): void
    {
        $langs = [
            (object) ['code' => 'en', 'label' => 'English'],
            (object) ['code' => 'cs', 'label' => 'Česky'],
        ];

        $header = security_advisory_node_header_html($langs);
        $bulk = security_advisory_node_bulk_row_html($langs);

        self::assertStringContainsString('English Note', $header);
        self::assertStringContainsString('Česky Note', $header);
        self::assertStringContainsString('data-field="en_note"', $bulk);
        self::assertStringContainsString('data-field="cs_note"', $bulk);
        self::assertStringContainsString('Mitigated by live patch', $bulk);
        self::assertStringContainsString('Mitigováno live patchem', $bulk);
    }

    public function testNodeSaveSendsLocalizedFieldsInsteadOfLegacyNote(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/pages/page_security_advisory.php');
        $saveStart = strpos($source, 'function security_advisory_save_nodes');
        $saveEnd = strpos($source, 'function security_advisory_datetime_param');
        $saveSource = substr($source, $saveStart, $saveEnd - $saveStart);

        self::assertStringContainsString('$name = $lang->code . \'_note\';', $saveSource);
        self::assertStringContainsString('$params[$name]', $saveSource);
        self::assertStringNotContainsString("'note' =>", $saveSource);
    }
}
