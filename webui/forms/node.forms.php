<?php

function node_details_table($node_id)
{
    global $xtpl, $api, $config;

    $node = $api->node->find(
        $node_id,
        ['meta' => ['includes' => 'location__environment']]
    );

    $xtpl->title(_('Node') . ' ' . $node->domain_name);

    $xtpl->table_td(_('Location') . ':');
    $xtpl->table_td($node->location->label);
    $xtpl->table_tr();

    $xtpl->table_td(_('Environment') . ':');
    $xtpl->table_td($node->location->environment->label);
    $xtpl->table_tr();

    $xtpl->table_out();

    $xtpl->table_title(_('Storage pools'));
    $xtpl->table_add_category(_('Name'));
    $xtpl->table_add_category(_('State'));
    $xtpl->table_add_category(_('Scan'));
    if (isAdmin()) {
        $xtpl->table_add_category(_('Space usage'));
    }
    $xtpl->table_add_category(_('Performance'));

    $pools = $api->pool->list([
        'node' => $node->id,
    ]);

    foreach ($pools as $pool) {
        $xtpl->table_td($pool->name);

        switch ($pool->state) {
            case 'online':
                $state = _('online');
                break;
            case 'degraded':
                $state = _('degraded - one or more disks have failed, the pool continues to function');
                break;
            case 'suspended':
                $state = _('suspended - the pool is not operational');
                break;
            case 'faulted':
                $state = _('faulted - the pool is not operational');
                break;
            case 'error':
                $state = _('error - unable to check pool status');
                break;
            default:
                $state = _('unknown');
                break;
        }

        $xtpl->table_td($state);

        switch ($pool->scan) {
            case 'none':
                $scan = _('none');
                $perf = _('nominal');
                break;
            case 'scrub':
                $scan = _('scrub - checking data integrity') . ', ' . format_decimal_number($pool->scan_percent, 1, false) . '&nbsp;% ' . _('done');
                $perf = _('decreased');
                break;
            case 'resilver':
                $scan = _('resilver - replacing disk') . ', ' . format_decimal_number($pool->scan_percent, 1, false) . '&nbsp;% ' . _('done');
                $perf = _('decreased');
                break;
            case 'error':
                $scan = _('error - unable to check pool status');
                $perf = _('unknown');
                break;
            case 'unknown':
                $scan = _('unknown');
                $perf = _('unknown');
                break;
            default:
                $scan = $pool->scan;
                $perf = _('unknown');
                break;
        }

        $xtpl->table_td($scan);

        if (isAdmin()) {
            $usedSpace = $pool->used_space;
            $totalSpace = $pool->total_space;
            $availableSpace = $pool->available_space;

            if ($usedSpace === null || $totalSpace === null || $availableSpace === null
                || $totalSpace <= 0) {
                $space_usage = _('unknown');
            } else {
                $used = data_size_to_humanreadable($usedSpace);
                $total = data_size_to_humanreadable($totalSpace);
                $free = data_size_to_humanreadable($availableSpace);
                $pct = format_decimal_number(($usedSpace / $totalSpace) * 100, 1, false);

                $space_usage = sprintf(_('%s used of %s (%s free, %s%%)'), $used, $total, $free, $pct);
            }

            $xtpl->table_td($space_usage);
        }
        $xtpl->table_td($perf);

        if ($pool->state != 'online' || $pool->scan != 'none') {
            $color = '#FFE27A';
        } else {
            $color = false;
        }

        $xtpl->table_tr($color);
    }

    $xtpl->table_out();

    $munin = new Munin($config);
    $munin->setGraphWidth(390);

    if ($munin->isEnabled()) {
        $xtpl->table_title(_('Graphs'));

        $xtpl->table_td($munin->linkHost(_('See all graphs in Munin'), $node->fqdn), false, false, '2');
        $xtpl->table_tr();

        $xtpl->table_td($munin->linkHostGraphPath($node->fqdn, 'cpu', 'day'));
        $xtpl->table_td($munin->linkHostGraphPath($node->fqdn, 'load', 'day'));
        $xtpl->table_tr();

        $xtpl->table_td($munin->linkHostGraphPath($node->fqdn, 'memory', 'day'));
        $xtpl->table_td($munin->linkHostGraphPath($node->fqdn, 'uptime', 'day'));
        $xtpl->table_tr();

        $xtpl->table_td($munin->linkHostGraphPath($node->fqdn, 'diskstats_utilization', 'day', true));
        $xtpl->table_td($munin->linkHostGraphPath($node->fqdn, 'diskstats_latency', 'day', true));
        $xtpl->table_tr();

        $xtpl->table_out();
    }
}

function node_kernel_history_table($node_id)
{
    global $xtpl, $api;

    $node = $api->node->find($node_id);
    $events = $api->node($node_id)->kernel_history->list([
        'limit' => 500,
    ]);

    $xtpl->title(_('Kernel history') . ': ' . $node->domain_name);

    $xtpl->table_title(_('Kernel history'), 'node.kernel-history');
    $xtpl->table_add_category(_('Event'));
    $xtpl->table_add_category(_('Effective or observed time'));
    $xtpl->table_add_category(_('Booted kernel'));
    $xtpl->table_add_category(_('Reported kernel'));
    $xtpl->table_add_category(_('Origin'));
    $xtpl->table_add_category(_('Time precision'));

    foreach ($events as $event) {
        switch ($event->event_type) {
            case 'boot':
                $eventLabel = _('System boot');
                break;
            case 'livepatch':
                $eventLabel = _('Live patch change');
                break;
            case 'reported_release_change':
                $eventLabel = _('Reported kernel change');
                break;
            default:
                $eventLabel = $event->event_type;
                break;
        }

        if ($event->effective_at) {
            $eventTime = tolocaltz($event->effective_at);
        } elseif ($event->observed_after) {
            $eventTime = sprintf(
                _('after %s, before %s'),
                tolocaltz($event->observed_after),
                tolocaltz($event->observed_before)
            );
        } else {
            $eventTime = sprintf(_('before %s'), tolocaltz($event->observed_before));
        }

        $eventCell = h($eventLabel);
        if (isAdmin() && $event->event_type === 'boot') {
            $eventCell = '<a data-vpsadmin-doc-id="node.kernel-boot-evidence"'
                . ' href="?page=node&amp;action=kernel_boot_evidence&amp;id=' . (int) $node->id
                . '&amp;event_id=' . (int) $event->id . '">' . h($eventLabel) . '</a>';
        }

        $xtpl->table_td($eventCell);
        $xtpl->table_td(h($eventTime));
        $xtpl->table_td(h(kernel_version($event->booted_release)));
        $xtpl->table_td(h(kernel_version($event->reported_release)));
        $xtpl->table_td(h(node_kernel_event_origin_label($event->source)));
        $xtpl->table_td(h(node_kernel_event_confidence_label($event->confidence)));
        $xtpl->table_tr($event->current ? '#DFF0D8' : false);
    }

    if ($events->count() == 0) {
        $xtpl->table_td(_('No kernel history is available yet.'), false, false, 6);
        $xtpl->table_tr();
    }

    $xtpl->table_out('node-kernel-history');
}

function node_kernel_boot_evidence_table($node_id, $event_id)
{
    global $xtpl, $api;

    $node = $api->node->find($node_id);
    $event = $api->node_kernel_event->find($event_id);

    if ((int) $event->node->id !== (int) $node->id || $event->event_type !== 'boot') {
        $xtpl->perex(
            _('Access forbidden'),
            _('The requested boot evidence does not belong to this Node.')
        );
        return;
    }

    $xtpl->title(_('Boot evidence') . ': ' . $node->domain_name);
    $xtpl->table_title(_('Boot evidence'), 'node.kernel-boot-evidence');
    $xtpl->table_td(_('Origin') . ':');
    $xtpl->table_td(h(node_kernel_event_origin_label($event->source)));
    $xtpl->table_tr();
    $xtpl->table_td(_('Time precision') . ':');
    $xtpl->table_td(h(node_kernel_event_confidence_label($event->confidence)));
    $xtpl->table_tr();
    $xtpl->table_td(_('Boot ID') . ':');
    $xtpl->table_td(h($event->boot_id ?? _('unavailable')));
    $xtpl->table_tr();
    $xtpl->table_td(_('Boot time') . ':');
    $xtpl->table_td($event->booted_at ? h(tolocaltz($event->booted_at)) : h(_('unavailable')));
    $xtpl->table_tr();
    $xtpl->table_td(_('Previous observation') . ':');
    $xtpl->table_td(
        $event->observed_after ? h(tolocaltz($event->observed_after)) : h(_('unavailable'))
    );
    $xtpl->table_tr();
    $xtpl->table_td(_('First observation') . ':');
    $xtpl->table_td(h(tolocaltz($event->observed_before)));
    $xtpl->table_tr();

    $evidenceId = $event->node_kernel_evidence_id ?? null;
    if ($evidenceId === null) {
        $xtpl->table_out('node-kernel-boot-evidence');
        $xtpl->perex(
            _('Detailed evidence unavailable'),
            _('This boot was reconstructed from legacy Node status samples, which did not contain kernel parameters.')
        );
        return;
    }

    $evidence = $api->node_kernel_evidence->find($evidenceId);
    $parameters = node_evidence_component_rows($api->node_kernel_parameter, [
        'node' => $node->id,
        'node_kernel_evidence' => $evidence->id,
        'source' => 'event',
    ]);
    $errors = node_evidence_component_rows($api->node_kernel_evidence_error, [
        'node' => $node->id,
        'node_kernel_evidence' => $evidence->id,
        'source' => 'event',
    ]);

    $xtpl->table_td(_('Evidence observed at') . ':');
    $xtpl->table_td(h(tolocaltz($evidence->observed_at)));
    $xtpl->table_tr();
    $xtpl->table_td(_('Evidence received at') . ':');
    $xtpl->table_td(h(tolocaltz($evidence->received_at)));
    $xtpl->table_tr();
    $xtpl->table_td(_('Report schema version') . ':');
    $xtpl->table_td(h($evidence->report_schema_version));
    $xtpl->table_tr();
    $xtpl->table_td(_('Evidence revision') . ':');
    $xtpl->table_td('<code>' . h($evidence->snapshot_revision) . '</code>');
    $xtpl->table_tr();
    $xtpl->table_td(_('Kernel source revision') . ':');
    $xtpl->table_td(h($evidence->kernel_source_revision ?? _('unavailable')));
    $xtpl->table_tr();
    $xtpl->table_out('node-kernel-boot-evidence');

    $xtpl->table_td(_('Raw boot command line') . ':');
    $xtpl->table_td(node_kernel_command_line_value($evidence->kernel_command_line));
    $xtpl->table_tr();
    $xtpl->table_out('node-kernel-boot-command-line');

    $xtpl->table_title(_('Booted parameters'));
    $xtpl->table_add_category(_('Name'));
    $xtpl->table_add_category(_('Value'));
    foreach ($parameters as $parameter) {
        $xtpl->table_td(h($parameter->name));
        $xtpl->table_td($parameter->value === null ? '-' : h($parameter->value));
        $xtpl->table_tr();
    }
    if (count($parameters) === 0) {
        $xtpl->table_td(
            _('No kernel parameter evidence is available for this boot.'),
            false,
            false,
            2
        );
        $xtpl->table_tr();
    }
    $xtpl->table_out('node-kernel-boot-parameters');

    if (count($errors) > 0) {
        $xtpl->table_title(_('Collection errors'));
        $xtpl->table_add_category(_('Component'));
        $xtpl->table_add_category(_('Reason'));
        foreach ($errors as $error) {
            $xtpl->table_td(h($error->component));
            $xtpl->table_td(h($error->reason));
            $xtpl->table_tr();
        }
        $xtpl->table_out('node-kernel-boot-errors');
    }
}

function node_system_history_table($node_id)
{
    global $xtpl, $api;

    $node = $api->node->find($node_id);
    $states = $api->node_system_state->list([
        'node' => $node->id,
        'limit' => 1000,
    ]);

    $xtpl->title(_('System history') . ': ' . $node->domain_name);

    $xtpl->table_title(_('System history'), 'node.system-history');
    $xtpl->table_add_category(_('Observation period'));
    $xtpl->table_add_category(_('CPUs'));
    $xtpl->table_add_category(_('Linux-visible memory'));
    $xtpl->table_add_category(_('Swap'));
    $xtpl->table_add_category(_('Cgroup version'));

    foreach ($states as $state) {
        $period = h(tolocaltz($state->first_observed_at))
            . '<br>&ndash;<br>'
            . h(tolocaltz($state->last_observed_at));
        if ($state->current) {
            $period .= '<br><strong>' . h(_('current')) . '</strong>';
        }

        $xtpl->table_td($period);
        $xtpl->table_td($state->cpus === null ? h(_('unknown')) : h($state->cpus));
        $xtpl->table_td(
            $state->total_memory === null
                ? h(_('unknown'))
                : h(data_size_to_humanreadable($state->total_memory))
        );
        $xtpl->table_td(
            $state->total_swap === null
                ? h(_('unknown'))
                : h(data_size_to_humanreadable($state->total_swap))
        );
        $xtpl->table_td(h(node_system_cgroup_version($state->cgroup_version)));
        $xtpl->table_tr($state->current ? '#DFF0D8' : false);
    }

    if ($states->count() === 0) {
        $xtpl->table_td(_('No system history is available yet.'), false, false, 5);
        $xtpl->table_tr();
    }

    $xtpl->table_out('node-system-history');
}

function node_admin_page_forbidden()
{
    global $xtpl;

    $xtpl->perex(_('Access forbidden'), _('This Node evidence is available only to administrators.'));
}

function node_kernel_parameters_table($node_id)
{
    global $xtpl, $api;

    $node = $api->node->find($node_id);
    $parameters = $api->node_kernel_parameter->list([
        'node' => $node->id,
        'source' => 'current',
        'limit' => 1000,
    ]);
    $evidences = $api->node_kernel_evidence->list([
        'node' => $node->id,
        'limit' => 1,
    ]);

    $booted = [];
    foreach ($parameters as $parameter) {
        $booted[] = [
            'position' => $parameter->position,
            'name' => $parameter->name,
            'value' => $parameter->value,
        ];
    }
    usort($booted, fn($a, $b) => $a['position'] <=> $b['position']);

    $commandLine = null;
    foreach ($evidences as $evidence) {
        $commandLine = $evidence->kernel_command_line;
        break;
    }

    $xtpl->title(_('Kernel parameters') . ': ' . $node->domain_name);

    $xtpl->table_td(_('Raw boot command line') . ':');
    $xtpl->table_td(node_kernel_command_line_value($commandLine));
    $xtpl->table_tr();
    $xtpl->table_out('node-kernel-command-line');

    $xtpl->table_title(_('Booted parameters'), 'node.kernel-parameters');
    $xtpl->table_add_category(_('Name'));
    $xtpl->table_add_category(_('Value'));

    foreach ($booted as $row) {
        $xtpl->table_td(h($row['name']));
        $xtpl->table_td($row['value'] === null ? '-' : h($row['value']));
        $xtpl->table_tr();
    }

    if (count($booted) === 0) {
        $xtpl->table_td(_('No kernel parameter evidence is available yet.'), false, false, 2);
        $xtpl->table_tr();
    }
    $xtpl->table_out('node-kernel-parameters');
}

function node_sysctls_table($node_id)
{
    global $xtpl, $api;

    $node = $api->node->find($node_id);
    $sysctls = iterator_to_array($api->node_sysctl->list([
        'node' => $node->id,
        'source' => 'current',
        'limit' => 1000,
    ]));
    usort($sysctls, fn($a, $b) => strcmp($a->name, $b->name));

    $xtpl->title(_('Sysctls') . ': ' . $node->domain_name);
    $xtpl->table_title(_('Current sysctls'), 'node.sysctls');
    $xtpl->table_add_category(_('Name'));
    $xtpl->table_add_category(_('Configured value'));
    $xtpl->table_add_category(_('Effective value'));
    $xtpl->table_add_category(_('Result'));

    foreach ($sysctls as $sysctl) {
        $name = '<a href="?page=node&amp;action=sysctl_history&amp;id=' . (int) $node->id
            . '&amp;name=' . rawurlencode($sysctl->name) . '">' . h($sysctl->name) . '</a>';
        [$result, $color] = node_sysctl_result(
            $sysctl->available,
            $sysctl->configured_value,
            $sysctl->effective_value
        );

        $xtpl->table_td($name);
        $xtpl->table_td(h($sysctl->configured_value ?? _('not configured')));
        $xtpl->table_td(h($sysctl->available ? ($sysctl->effective_value ?? _('unknown')) : _('unavailable')));
        $xtpl->table_td(h($result));
        $xtpl->table_tr($color);
    }

    if (count($sysctls) === 0) {
        $xtpl->table_td(_('No sysctl evidence is available yet.'), false, false, 4);
        $xtpl->table_tr();
    }
    $xtpl->table_out('node-sysctls');
}

function node_sysctl_history_table($node_id, $name)
{
    global $xtpl, $api;

    $node = $api->node->find($node_id);
    $changes = $api->node_sysctl_change->list([
        'node' => $node->id,
        'name' => $name,
        'limit' => 1000,
    ]);

    $xtpl->title(
        _('Sysctl history') . ': ' . h($name) . ' (' . h($node->domain_name) . ')'
    );
    $xtpl->table_title(_('Sysctl history'), 'node.sysctl-history');
    $xtpl->table_add_category(_('Observed'));
    $xtpl->table_add_category(_('Previous state'));
    $xtpl->table_add_category(_('New state'));

    foreach ($changes as $change) {
        $xtpl->table_td(h(node_evidence_observed_interval($change)));
        $xtpl->table_td(node_sysctl_state($change, 'before'));
        $xtpl->table_td(node_sysctl_state($change, 'after'));
        $xtpl->table_tr($change->after_available === false ? '#F2DEDE' : false);
    }

    if ($changes->count() === 0) {
        $xtpl->table_td(_('No history is available for this sysctl yet.'), false, false, 3);
        $xtpl->table_tr();
    }
    $xtpl->table_out('node-sysctl-history');
}

function node_software_versions_table($node_id)
{
    global $xtpl, $api;

    $node = $api->node->find($node_id);
    $versions = $api->node_software_version->list([
        'node' => $node->id,
        'source' => 'current',
        'limit' => 100,
    ]);
    $deployments = $api->node_software_deployment->list([
        'node' => $node->id,
        'limit' => 500,
    ]);
    $changes = $api->node_software_change->list([
        'node' => $node->id,
        'limit' => 1000,
    ]);

    $matrix = [];
    foreach ($versions as $version) {
        $matrix[$version->component][$version->generation] = $version;
    }
    $changesByEvent = [];
    foreach ($changes as $change) {
        $changesByEvent[$change->node_kernel_event->id][] = $change;
    }

    $xtpl->title(_('Software versions') . ': ' . $node->domain_name);
    $xtpl->table_title(_('Current software versions'), 'node.software-versions');
    $xtpl->table_add_category(_('Component'));
    $xtpl->table_add_category(_('Booted closure version'));
    $xtpl->table_add_category(_('Booted closure revision'));
    $xtpl->table_add_category(_('Current closure version'));
    $xtpl->table_add_category(_('Current closure revision'));

    $components = ['vpsadminos', 'vpsadmin', 'nixpkgs'];
    if (isset($matrix['vpsfree_cz_configuration'])) {
        $components[] = 'vpsfree_cz_configuration';
    }

    foreach ($components as $component) {
        $booted = $matrix[$component]['booted'] ?? null;
        $current = $matrix[$component]['current'] ?? null;
        $xtpl->table_td(h(node_software_component_label($component)));
        $xtpl->table_td(h($booted->version ?? '-'));
        $xtpl->table_td(node_software_revision_link(
            $component,
            $booted->revision ?? null,
            $booted->revision_dirty ?? false
        ));
        $xtpl->table_td(h($current->version ?? '-'));
        $xtpl->table_td(node_software_revision_link(
            $component,
            $current->revision ?? null,
            $current->revision_dirty ?? false
        ));
        $xtpl->table_tr();
    }
    $xtpl->table_out();

    $xtpl->table_title(_('Software deployment history'), 'node.software-deployments');
    $xtpl->table_add_category(_('Observed'));
    $xtpl->table_add_category(_('System'));
    $xtpl->table_add_category(_('Component'));
    $xtpl->table_add_category(_('Previous'));
    $xtpl->table_add_category(_('New'));

    $hasChanges = false;
    foreach ($deployments as $deployment) {
        $deploymentChanges = $changesByEvent[$deployment->id] ?? [];
        foreach ($deploymentChanges as $index => $change) {
            $hasChanges = true;
            $xtpl->table_td($index === 0 ? h(node_evidence_observed_interval($deployment)) : '');
            $xtpl->table_td(h($change->generation === 'booted'
                ? _('booted closure')
                : _('current closure')));
            $xtpl->table_td(h(node_software_component_label($change->component)));
            $xtpl->table_td(node_software_change_value(
                $change->component,
                $change->before_version,
                $change->before_revision,
                $change->before_revision_dirty,
                true
            ));
            $xtpl->table_td(node_software_change_value(
                $change->component,
                $change->after_version,
                $change->after_revision,
                $change->after_revision_dirty,
                false
            ));
            $xtpl->table_tr();
        }
    }

    if (!$hasChanges) {
        $xtpl->table_td(_('No software deployment history is available yet.'), false, false, 5);
        $xtpl->table_tr();
    }
    $xtpl->table_out();
}

function node_evidence_observed_interval($event)
{
    if ($event->effective_at ?? null) {
        return tolocaltz($event->effective_at);
    }
    if ($event->observed_after ?? null) {
        return sprintf(
            _('after %s, before %s'),
            tolocaltz($event->observed_after),
            tolocaltz($event->observed_before)
        );
    }

    return sprintf(_('before %s'), tolocaltz($event->observed_before));
}

function node_sysctl_availability($value)
{
    if ($value === null) {
        return _('no earlier value');
    }

    return $value ? _('available') : _('unavailable');
}

function node_sysctl_history_value($value)
{
    return $value === null ? '-' : $value;
}

function node_sysctl_state($change, $prefix)
{
    return makeDefinitionList([
        _('Available') => node_sysctl_availability($change->{$prefix . '_available'}),
        _('Configured value') => node_sysctl_history_value($change->{$prefix . '_configured_value'}),
        _('Effective value') => node_sysctl_history_value($change->{$prefix . '_effective_value'}),
    ], 'inline node-sysctl-state');
}

function node_software_component_label($component)
{
    switch ($component) {
        case 'vpsadminos':
            return 'vpsAdminOS';
        case 'vpsadmin':
            return 'vpsAdmin';
        case 'nixpkgs':
            return 'nixpkgs';
        case 'vpsfree_cz_configuration':
            return _('vpsFree.cz configuration');
        default:
            return $component;
    }
}

function node_software_change_value($component, $version, $revision, $revisionDirty, $baseline)
{
    if ($version === null && $revision === null) {
        return $baseline ? h(_('initial baseline')) : '-';
    }

    return h($version ?? '-') . ' / ' . node_software_revision_link(
        $component,
        $revision,
        $revisionDirty
    );
}
