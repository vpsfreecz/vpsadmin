<?php

use PHPUnit\Framework\TestCase;

final class TableStateStyleTest extends TestCase
{
    public function testErrorAndFailedRowsUseReadableLinksGlobally(): void
    {
        $css = file_get_contents(
            dirname(__DIR__, 2) . '/public/template/css/scheme.css'
        );

        self::assertStringContainsString(
            'tr.failed a, tr.failed a:visited {color:#001F3F; text-decoration:underline;}',
            $css
        );
        self::assertStringContainsString(
            'tr.failed a:hover, tr.failed a:focus {color:#000;}',
            $css
        );
    }
}
