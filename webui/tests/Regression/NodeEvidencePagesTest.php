<?php

use PHPUnit\Framework\TestCase;

final class NodeEvidencePagesTest extends TestCase
{
    public static function setUpBeforeClass(): void
    {
        require_once dirname(__DIR__, 2) . '/lib/functions.lib.php';
    }

    public function testAdminOnlyEvidencePagesAreGuarded(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/pages/page_node.php');
        $forms = file_get_contents(dirname(__DIR__, 2) . '/forms/node.forms.php');

        self::assertStringContainsString("if (isAdmin()) {", $source);
        self::assertStringContainsString("_('Kernel parameters')", $source);
        self::assertStringContainsString("_('Sysctls')", $source);
        self::assertStringContainsString("_('Software versions')", $source);
        self::assertStringContainsString("node_admin_page_forbidden();", $source);
        self::assertStringContainsString(
            "case 'vpsfree_cz_configuration':",
            $forms
        );
    }

    public function testSystemHistoryIsAvailableToEveryLoggedInUser(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/pages/page_node.php');
        $systemLink = strpos($source, "_('System history')");
        $adminGuard = strpos($source, 'if (isAdmin()) {');
        $systemAction = strpos($source, "case 'system_history':");

        self::assertIsInt($systemLink);
        self::assertIsInt($adminGuard);
        self::assertIsInt($systemAction);
        self::assertLessThan($adminGuard, $systemLink);
        self::assertStringContainsString('node_system_history_table', $source);
    }

    public function testSystemHistoryUsesCompactCgroupVersions(): void
    {
        self::assertSame('v1', node_system_cgroup_version('cgroup_v1'));
        self::assertSame('v2', node_system_cgroup_version('cgroup_v2'));
        self::assertSame('unknown', node_system_cgroup_version('cgroup_invalid'));
        self::assertSame('unknown', node_system_cgroup_version(null));
    }

    public function testNodeCreateFormHidesReportedCapacityFields(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/forms/cluster.forms.php');

        self::assertStringContainsString(
            "api_create_form(\$api->node, ['cpus', 'total_memory', 'total_swap']);",
            $source
        );
    }

    public function testKernelParameterPageUsesOnlyTheBootedSequence(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/forms/node.forms.php');

        self::assertStringContainsString("_('Booted parameters')", $source);
        self::assertStringContainsString(
            "usort(\$booted, fn(\$a, \$b) => \$a['position'] <=> \$b['position'])",
            $source
        );
        self::assertStringNotContainsString("table_add_category(_('Position'))", $source);
        self::assertStringNotContainsString('h($row[\'position\'] + 1)', $source);
        self::assertStringNotContainsString('node_kernel_parameter_diff(', $source);
    }

    public function testRawKernelCommandLineIsEscapedAndMarkedAsCode(): void
    {
        $html = node_kernel_command_line_value('quiet test=<script>');

        self::assertSame(
            '<code class="node-kernel-command-line">quiet test=&lt;script&gt;</code>',
            $html
        );
        self::assertSame('unavailable', node_kernel_command_line_value(null));
    }

    public function testRevisionLinksRequireExactCommitsAndMarkModifiedSources(): void
    {
        $revision = str_repeat('a', 40);
        $link = node_software_revision_link('nixpkgs', $revision, true);

        self::assertStringContainsString('github.com/NixOS/nixpkgs/commit/' . $revision, $link);
        self::assertStringContainsString('>aaaaaaaaaaaa</a>', $link);
        self::assertStringContainsString('(modified)', $link);
        $configurationLink = node_software_revision_link(
            'vpsfree_cz_configuration',
            $revision
        );
        self::assertStringContainsString(
            'github.com/vpsfreecz/vpsfree-cz-configuration/commit/' . $revision,
            $configurationLink
        );
        self::assertSame('unavailable', node_software_revision_link('vpsadmin', 'dev'));
        self::assertSame('unavailable', node_software_revision_link('vpsadminos', 'staging'));
    }

    public function testUnreadAvailableSysctlIsNotDescribedAsEffective(): void
    {
        [$result, $color] = node_sysctl_result(true, null, null);

        self::assertSame('effective value could not be read', $result);
        self::assertSame('#FFE27A', $color);
    }
}
