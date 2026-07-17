<?php

use PHPUnit\Framework\TestCase;

final class KernelHistoryVisibilityTest extends TestCase
{
    public function testKernelHistoryLinkIsBuiltOnlyForLoggedInUsers(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/lib/functions.lib.php');
        $helper = 'function node_kernel_history_link($node)';
        $escapedKernel = '$kernel = h(kernel_version($node->kernel));';
        $loginGuard = 'if (!isLoggedIn()) {';
        $historyLink = 'data-vpsadmin-doc-id="node.kernel-history"';

        $helperOffset = strpos($source, $helper);
        $kernelOffset = strpos($source, $escapedKernel, $helperOffset);
        $guardOffset = strpos($source, $loginGuard, $kernelOffset);
        $plainReturnOffset = strpos($source, 'return $kernel;', $guardOffset);
        $linkOffset = strpos($source, $historyLink, $plainReturnOffset);

        self::assertIsInt($helperOffset);
        self::assertIsInt($kernelOffset);
        self::assertIsInt($guardOffset);
        self::assertIsInt($plainReturnOffset);
        self::assertIsInt($linkOffset);
        self::assertLessThan($kernelOffset, $helperOffset);
        self::assertLessThan($guardOffset, $kernelOffset);
        self::assertLessThan($plainReturnOffset, $guardOffset);
        self::assertLessThan($linkOffset, $plainReturnOffset);
    }
}
