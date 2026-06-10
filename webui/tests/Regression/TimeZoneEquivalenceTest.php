<?php

use PHPUnit\Framework\TestCase;

final class TimeZoneEquivalenceTest extends TestCase
{
    public function testEquivalentZonesShareSampledOffsets(): void
    {
        require_once dirname(__DIR__, 2) . '/lib/functions.lib.php';

        $referenceTime = strtotime('2026-06-10 12:00:00 UTC');

        self::assertTrue(
            time_zones_have_same_offsets(
                'Europe/Prague',
                'Europe/Amsterdam',
                $referenceTime
            )
        );
        self::assertTrue(
            time_zones_have_same_offsets(
                'Europe/Prague',
                'Europe/Prague',
                $referenceTime
            )
        );
    }

    public function testDifferentZonesDoNotShareSampledOffsets(): void
    {
        require_once dirname(__DIR__, 2) . '/lib/functions.lib.php';

        $referenceTime = strtotime('2026-06-10 12:00:00 UTC');

        self::assertFalse(
            time_zones_have_same_offsets(
                'Europe/Prague',
                'UTC',
                $referenceTime
            )
        );
    }

    public function testInvalidZonesAreNotEquivalent(): void
    {
        require_once dirname(__DIR__, 2) . '/lib/functions.lib.php';

        self::assertFalse(time_zones_have_same_offsets('Invalid/Zone', 'UTC'));
        self::assertFalse(time_zones_have_same_offsets(null, 'UTC'));
        self::assertFalse(time_zones_have_same_offsets('', 'UTC'));
    }
}
