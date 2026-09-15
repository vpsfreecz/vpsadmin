<?php

use PHPUnit\Framework\TestCase;

require_once dirname(__DIR__, 2) . '/lib/ip_release_selection.lib.php';

final class IpReleaseSelectionTest extends TestCase
{
    public function testSelectionSpansLargePagesAndPreservesExclusions(): void
    {
        $rows = array_map(fn($id) => ['id' => $id], range(1, 1101));
        $state = IpReleaseSelection::create($rows, ['versions' => [4, 6]], 123);
        self::assertCount(500, IpReleaseSelection::page($state, 0));
        self::assertCount(101, IpReleaseSelection::page($state, 2));
        IpReleaseSelection::update($state, 123, 0, array_map('strval', range(2, 500)));
        IpReleaseSelection::update($state, 123, 2, ['1101']);
        self::assertCount(1000, $state['selected']);
        self::assertArrayNotHasKey(1, $state['selected']);
        self::assertArrayHasKey(501, $state['selected']);
        self::assertArrayHasKey(1101, $state['selected']);
        IpReleaseSelection::update($state, 123, 2, ['1101'], 'all');
        self::assertCount(1101, $state['selected']);
        IpReleaseSelection::update($state, 123, 0, [], 'none');
        self::assertSame([], $state['selected']);
    }

    public function testAnotherAccountCannotChangeThePreview(): void
    {
        $state = IpReleaseSelection::create([['id' => 1]], [], 123);
        $this->expectException(InvalidArgumentException::class);
        IpReleaseSelection::update($state, 456, 0, []);
    }

    public function testForgedIdsCannotAddAddressesToTheSnapshot(): void
    {
        $state = IpReleaseSelection::create([['id' => 1]], [], 123);
        try {
            IpReleaseSelection::update($state, 123, 0, ['2']);
            self::fail('An address outside the displayed snapshot was accepted');
        } catch (InvalidArgumentException $e) {
            self::assertSame([1 => true], $state['selected']);
        }
    }
}
