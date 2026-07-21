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
            'cs_note' => 'Ošetřeno live patchem',
        ];

        self::assertSame(
            'Ošetřeno live patchem',
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
        $row = security_advisory_node_row_html(
            (object) [
                'id' => 42,
                'domain_name' => 'node.example.test',
                'type' => 'node',
            ],
            null,
            $langs
        );

        self::assertStringContainsString('English Note', $header);
        self::assertStringContainsString('Česky Note', $header);
        self::assertStringContainsString('data-field="en_note"', $bulk);
        self::assertStringContainsString('data-field="cs_note"', $bulk);
        self::assertStringContainsString('Mitigated by live patch', $bulk);
        self::assertStringContainsString('Ošetřeno live patchem', $bulk);
        self::assertSame(4, substr_count($bulk, 'size="14"'));
        self::assertSame(4, substr_count($row, 'size="14"'));
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

    public function testPublishRevisionIsStoredOutsideVisibleTableCells(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/forms/security_advisory.forms.php');
        $detailsStart = strpos($source, 'function security_advisory_details');
        $detailsEnd = strpos($source, 'function security_advisory_node_status_table');
        $detailsSource = substr($source, $detailsStart, $detailsEnd - $detailsStart);

        self::assertStringContainsString(
            '$xtpl->form_set_hidden_fields([',
            $detailsSource
        );
        self::assertStringNotContainsString(
            '$xtpl->form_add_input_pure(',
            $detailsSource
        );
    }
}
