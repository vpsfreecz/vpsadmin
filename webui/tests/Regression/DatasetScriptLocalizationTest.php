<?php

use PHPUnit\Framework\TestCase;

final class DatasetScriptLocalizationTest extends TestCase
{
    public function testDatasetScriptInjectsLocalizedLabelsBeforeScript(): void
    {
        require_once dirname(__DIR__, 2) . '/lib/functions.lib.php';
        require_once dirname(__DIR__, 2) . '/forms/dataset.forms.php';

        $GLOBALS['xtpl'] = new class {
            public array $vars = [
                'AJAX_SCRIPT' => '',
            ];

            public function assign(string $key, string $value): void
            {
                $this->vars[$key] = $value;
            }
        };

        include_dataset_scripts();

        $script = $GLOBALS['xtpl']->vars['AJAX_SCRIPT'];

        self::assertStringContainsString(
            'window.vpsAdminDatasetLabels = ',
            $script
        );
        self::assertStringContainsString(
            '"showMoreProperties":"Show more properties"',
            $script
        );
        self::assertStringContainsString(
            '"hideProperties":"Hide properties"',
            $script
        );
        self::assertLessThan(
            strpos($script, 'src="js/dataset.js"'),
            strpos($script, 'window.vpsAdminDatasetLabels')
        );
    }

    public function testMountStartFailureLabelsCanComeFromApiMetadata(): void
    {
        require_once dirname(__DIR__, 2) . '/forms/dataset.forms.php';

        self::assertSame('Custom API label', translate_mount_on_start_fail('Custom API label'));
    }
}
