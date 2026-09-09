<?php

use PHPUnit\Framework\TestCase;

final class IpReleaseCapacityContractTest extends TestCase
{
    public function testEveryCampaignFitsTheMemberAddressFetch(): void
    {
        require_once dirname(__DIR__, 2) . '/forms/ip_release.forms.php';
        $model = file_get_contents(dirname(__DIR__, 3) . '/api/models/ip_release_campaign.rb');
        self::assertSame(1, preg_match('/MAX_ADDRESSES = (\d+)/', $model, $matches));
        self::assertSame((int) $matches[1], IP_RELEASE_MAX_ADDRESSES);
    }
}
