<?php

use PHPUnit\Framework\TestCase;

if (!function_exists('T_ngettext')) {
    function T_ngettext($single, $plural, $number)
    {
        if (!is_int($number)) {
            throw new TypeError('plural count must be an integer');
        }

        $GLOBALS['plural_formatting_counts'][] = $number;
        return $number === 1 ? $single : $plural;
    }
}

final class PluralFormattingTest extends TestCase
{
    protected function setUp(): void
    {
        require_once dirname(__DIR__, 2) . '/lib/functions.lib.php';
        $GLOBALS['plural_formatting_counts'] = [];
    }

    public function testFractionalResourceAmountUsesIntegerPluralSelector(): void
    {
        self::assertSame('0.5 cores', format_cluster_resource_amount('cpu', 0.5, '0.5'));
        self::assertSame([2], $GLOBALS['plural_formatting_counts']);
    }

    public function testWholeFloatResourceAmountCanUseSingularForm(): void
    {
        self::assertSame('1 core', format_cluster_resource_amount('cpu', 1.0, '1'));
        self::assertSame([1], $GLOBALS['plural_formatting_counts']);
    }
}
