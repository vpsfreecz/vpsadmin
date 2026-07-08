<?php

use PHPUnit\Framework\TestCase;

final class DataSizeFormattingTest extends TestCase
{
    public static function setUpBeforeClass(): void
    {
        require_once dirname(__DIR__, 2) . '/lib/functions.lib.php';

        $GLOBALS['DATA_SIZE_UNITS'] = [
            "b" => "B",
            "k" => "KiB",
            "m" => "MiB",
            "g" => "GiB",
            "t" => "TiB",
        ];
    }

    public function testZeroSizeUsesUnits(): void
    {
        self::assertSame('0 B', data_size_to_humanreadable_b(0));
        self::assertSame('0 KB', data_size_to_humanreadable_kb(0));
        self::assertSame('0 MB', data_size_to_humanreadable_mb(0));
    }

    public function testDataSizesAreFormatted(): void
    {
        self::assertSame('1 KiB', data_size_to_humanreadable_b(1024));
        self::assertSame('1.5 KiB', data_size_to_humanreadable_b(1536));
        self::assertSame('1.15 GiB', data_size_to_humanreadable_b(1234567890));
    }

    public function testDataRatesAreFormatted(): void
    {
        self::assertSame('1.5kbps', format_data_rate(1536, 'bps'));
        self::assertSame('1.21k', format_data_rate(1234.567, ''));
    }

    public function testCompactNumbersAreFormatted(): void
    {
        self::assertSame('1.23k', format_number_with_unit(1234));
        self::assertSame('1.23M', format_number_with_unit(1234567));
    }

    public function testLoadAveragesKeepTwoDecimals(): void
    {
        self::assertSame('0.13', format_load_average(0.125));
        self::assertSame('1.00', format_load_average(1));
        self::assertSame('1 234.50', format_load_average(1234.5));
    }

    public function testMissingLoadAveragesRemainUnknown(): void
    {
        self::assertSame('-', format_load_average(null));
        self::assertSame('-', format_load_average(''));
    }
}
