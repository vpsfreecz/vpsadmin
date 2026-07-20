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
        self::assertStringContainsString("case 'kernel_boot_evidence':", $source);
        self::assertStringContainsString("_('Sysctls')", $source);
        self::assertStringContainsString("_('Software versions')", $source);
        self::assertStringContainsString("node_admin_page_forbidden();", $source);
        self::assertStringContainsString(
            "case 'system_configuration':",
            $forms
        );
    }

    public function testKernelHistorySeparatesOriginFromTimePrecision(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/forms/node.forms.php');
        $historyStart = strpos($source, 'function node_kernel_history_table');
        $historyEnd = strpos($source, 'function node_kernel_boot_evidence_table');
        $historySource = substr($source, $historyStart, $historyEnd - $historyStart);

        self::assertStringContainsString("table_add_category(_('Origin'))", $source);
        self::assertStringContainsString("table_add_category(_('Time precision'))", $source);
        self::assertStringNotContainsString("table_add_category(_('Evidence quality'))", $source);
        self::assertStringContainsString("table_out('node-kernel-history')", $historySource);
        self::assertSame('node', node_kernel_event_origin_label('node_report'));
        self::assertSame(
            'reconstructed',
            node_kernel_event_origin_label('reconstructed_node_status')
        );
        self::assertSame('exact', node_kernel_event_confidence_label('exact'));
        self::assertSame('inferred', node_kernel_event_confidence_label('inferred'));
        self::assertSame('incomplete', node_kernel_event_confidence_label('incomplete'));
    }

    public function testBootEvidenceDrilldownIsNodeScopedAndUsesEventParameters(): void
    {
        $source = file_get_contents(dirname(__DIR__, 2) . '/forms/node.forms.php');

        self::assertStringContainsString(
            'data-vpsadmin-doc-id="node.kernel-boot-evidence"',
            $source
        );
        self::assertStringContainsString(
            '(int) $event->node->id !== (int) $node->id',
            $source
        );
        self::assertStringContainsString(
            '$event->node_kernel_evidence_id ?? null',
            $source
        );
        self::assertStringNotContainsString(
            '$event->node_kernel_evidence ?? null',
            $source
        );
        self::assertStringContainsString("'source' => 'event'", $source);
        self::assertStringContainsString("'node_kernel_evidence' => \$evidence->id", $source);
        self::assertStringContainsString("_('Detailed evidence unavailable')", $source);
    }

    public function testEvidenceComponentRowsFetchEveryPage(): void
    {
        $resource = new class {
            public array $calls = [];

            public function list(array $input): array
            {
                $this->calls[] = $input;
                $fromId = $input['from_id'] ?? 0;
                $lastId = min(1001, $fromId + $input['limit']);

                if ($fromId >= $lastId) {
                    return [];
                }

                return array_map(
                    fn($id) => (object) ['id' => $id],
                    range($fromId + 1, $lastId)
                );
            }
        };

        $rows = node_evidence_component_rows($resource, ['node' => 123]);

        self::assertCount(1001, $rows);
        self::assertSame(1, $rows[0]->id);
        self::assertSame(1001, $rows[1000]->id);
        self::assertCount(2, $resource->calls);
        self::assertArrayNotHasKey('from_id', $resource->calls[0]);
        self::assertSame(1000, $resource->calls[1]['from_id']);
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
        $functions = file_get_contents(dirname(__DIR__, 2) . '/lib/functions.lib.php');
        $revision = str_repeat('a', 40);
        $link = node_software_revision_link('nixpkgs', $revision, true);

        self::assertStringNotContainsString('vpsfree-cz-configuration', $functions);
        self::assertStringContainsString('github.com/NixOS/nixpkgs/commit/' . $revision, $link);
        self::assertStringContainsString('>aaaaaaaaaaaa</a>', $link);
        self::assertStringContainsString('(modified)', $link);
        self::assertSame(
            'system_configuration',
            node_software_component_key('vpsfree_cz_configuration')
        );
        self::assertSame(
            'unavailable',
            node_software_revision_link('system_configuration', $revision)
        );

        define('SOFTWARE_REVISION_LINKS', [
            'nixpkgs' => 'https://github.com/NixOS/nixpkgs/commit/',
            'system_configuration'
                => 'https://github.com/vpsfreecz/vpsfree-cz-configuration/commit/',
            'unsafe' => 'javascript:alert(1)',
        ]);
        $configurationLink = node_software_revision_link('system_configuration', $revision);
        self::assertStringContainsString(
            'github.com/vpsfreecz/vpsfree-cz-configuration/commit/' . $revision,
            $configurationLink
        );
        self::assertSame('unavailable', node_software_revision_link('unsafe', $revision));
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
