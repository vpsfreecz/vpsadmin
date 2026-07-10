<?php

use PHPUnit\Framework\TestCase;

final class ExportScriptLocalizationTest extends TestCase
{
    public function testExportScriptInjectsLocalizedLabelsBeforeScript(): void
    {
        require_once dirname(__DIR__, 2) . '/lib/functions.lib.php';
        require_once dirname(__DIR__, 2) . '/forms/export.forms.php';

        $GLOBALS['xtpl'] = new class {
            public array $vars = [
                'AJAX_SCRIPT' => '',
            ];

            public function assign(string $key, string $value): void
            {
                $this->vars[$key] = $value;
            }
        };

        include_export_scripts();

        $script = $GLOBALS['xtpl']->vars['AJAX_SCRIPT'];

        self::assertStringContainsString(
            'window.vpsAdminExportLabels = ',
            $script
        );
        self::assertStringContainsString(
            '"showAdvancedOptions":"Show advanced options"',
            $script
        );
        self::assertStringContainsString(
            '"hideAdvancedOptions":"Hide advanced options"',
            $script
        );
        self::assertLessThan(
            strpos($script, 'src="js/export.js"'),
            strpos($script, 'window.vpsAdminExportLabels')
        );
    }
}
