<?php

use PHPUnit\Framework\TestCase;

final class DataSizeFormattingTest extends TestCase
{
    public function testZeroSizeUsesUnits(): void
    {
        require_once dirname(__DIR__, 2) . '/lib/functions.lib.php';

        self::assertSame('0 B', data_size_to_humanreadable_b(0));
        self::assertSame('0 KB', data_size_to_humanreadable_kb(0));
        self::assertSame('0 MB', data_size_to_humanreadable_mb(0));
    }
}
