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

    public function testCommitHashIsNotCachedAcrossDeployments(): void
    {
        $root = sys_get_temp_dir() . '/vpsadmin-webui-revision-' . bin2hex(random_bytes(8));
        mkdir($root);
        define('WEBUI_ROOT', $root);
        require_once $this->webuiRoot . 'lib/functions.lib.php';

        try {
            $_SESSION['commit_hash'] = str_repeat('a', 40);
            file_put_contents($root . '/.git-revision', str_repeat('b', 40) . "\n");

            self::assertSame(str_repeat('b', 40), getCommitHash());
            self::assertSame(str_repeat('a', 40), $_SESSION['commit_hash']);
        } finally {
            unlink($root . '/.git-revision');
            rmdir($root);
        }
    }
}
