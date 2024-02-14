<?php

function node_details_table($node_id) {
    global $xtpl, $api, $config;

    $node = $api->node->find(
        $node_id,
        ['meta' => ['includes' => 'location__environment']]
    );

    $xtpl->title(_('Node').' '.$node->domain_name);

    $xtpl->table_td(_('Location').':');
    $xtpl->table_td($node->location->label);
    $xtpl->table_tr();

    $xtpl->table_td(_('Environment').':');
    $xtpl->table_td($node->location->environment->label);
    $xtpl->table_tr();

    $xtpl->table_out();

    $xtpl->table_title(_('Storage pools'));
    $xtpl->table_add_category(_('Name'));
    $xtpl->table_add_category(_('State'));
    $xtpl->table_add_category(_('Scan'));
    $xtpl->table_add_category(_('Performance'));

    $pools = $api->pool->list([
        'node' => $node->id
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
            $scan = _('scrub - checking data integrity').', '.round($pool->scan_percent, 1).'&nbsp;% '._('done');
            $perf = _('decreased');
            break;
        case 'resilver':
            $scan = _('resilver - replacing disk').', '.round($pool->scan_percent, 1).'&nbsp;% '._('done');
            $perf = _('decreased');
            break;
        case 'error':
            $scan = _('error - unable to check pool status');
            $perf = _('unknown');
            break;
        default:
            $scan = $pool->scan;
            $perf = _('unknown');
            break;
        }

        $xtpl->table_td($scan);
        $xtpl->table_td($perf);

        if ($pool->state != 'online' || $pool->scan != 'none')
            $color = '#FFE27A';
        else
            $color = false;

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
