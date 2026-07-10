<?php

use PHPUnit\Framework\TestCase;

final class HeaderVersionLocalizationTest extends TestCase
{
    private string $webuiRoot;

    protected function setUp(): void
    {
        $this->webuiRoot = dirname(__DIR__, 2) . '/';
    }

    public function testHeaderUsesLocalizedVersionLabel(): void
    {
        $index = file_get_contents($this->webuiRoot . 'public/index.php');
        $template = file_get_contents($this->webuiRoot . 'template/template.html');

        self::assertStringContainsString(
            '$xtpl->assign("L_VERSION", _("Version"));',
            $index
        );
        self::assertStringContainsString('{L_VERSION}: {VERSION}', $template);
        self::assertStringNotContainsString('>version: {VERSION}<', $template);
    }
}
