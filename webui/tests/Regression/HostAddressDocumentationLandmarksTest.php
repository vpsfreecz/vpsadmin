<?php

use PHPUnit\Framework\TestCase;

final class HostAddressDocumentationLandmarksTest extends TestCase
{
    public function testHostAddressActionsHaveStableDocumentationIds(): void
    {
        $vpsForms = file_get_contents(dirname(__DIR__, 2) . '/forms/vps.forms.php');
        $networkingForms = file_get_contents(dirname(__DIR__, 2) . '/forms/networking.forms.php');

        self::assertStringContainsString(
            '<a data-vpsadmin-doc-id="networking.manage-host-addresses" href="?page=networking&action=route_edit',
            $vpsForms
        );
        self::assertStringContainsString(
            '<a data-vpsadmin-doc-id="networking.add-host-addresses" href="?page=networking&action=hostaddr_new',
            $networkingForms
        );
    }
}
