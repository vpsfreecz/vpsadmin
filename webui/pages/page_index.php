<?php

/*
    ./pages/page_index.php

    vpsAdmin
    Web-admin interface for vpsAdminOS (see https://vpsadminos.org)
    Copyright (C) 2008-2009 Pavel Snajdr, snajpa@snajpa.net

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

$return_url = urlencode($_SERVER['REQUEST_URI']);

$xtpl->sbar_add(_('Maintenances and Outages'), '?page=outage&action=list');

if (isLoggedIn()) {
    if ($api->monitored_event) {
        $xtpl->sbar_add(_("Monitoring"), '?page=monitoring&action=list');
    }

    $xtpl->sbar_add(_("OOM Reports"), '?page=oom_reports&action=list');
    $xtpl->sbar_add(_("Incident Reports"), '?page=incidents&action=list&return=' . $return_url);
}

$xtpl->sbar_out(_('Overview'));

$xtpl->title(_("Overview"));

if (isAdmin()) {
    $xtpl->table_add_category(_("Event Log <a href=\"?page=cluster&action=sysconfig\">[edit]</a>"));
} else {
    $xtpl->table_add_category(_("Event Log"));
}

$xtpl->table_add_category('');

$noticeboard = $config->get("webui", "noticeboard");

if ($noticeboard) {
    $xtpl->table_td(nl2br($noticeboard), false, false, 2);
    $xtpl->table_tr();
}

if ($api->news_log) {
    foreach ($api->news_log->list(['limit' => 5]) as $news) {
        $xtpl->table_td('[' . tolocaltz($news->published_at, "Y-m-d H:i") . ']');
        $xtpl->table_td($news->message);
        $xtpl->table_tr();
    }

    $xtpl->table_td('<a href="?page=log">' . _("View all") . '</a>', false, false, '2');
    $xtpl->table_tr();
}

$xtpl->table_out("notice_board");

if ($api->outage) {
    outage_list_recent();
}

$xtpl->table_title(_("Cluster statistics"));

$xtpl->table_add_category('Members total');
$xtpl->table_add_category('VPS total');
$xtpl->table_add_category('IPv4 left');

$stats = $api->cluster->public_stats();

$xtpl->table_td($stats->user_count, false, true);
$xtpl->table_td($stats->vps_count, false, true);
$xtpl->table_td($stats->ipv4_left, false, true);
$xtpl->table_tr();

$xtpl->table_out();

// Node status

$nodes = $api->node->public_status();

$goresheatUrl = $config->get('webui', 'goresheat_url');

if ($goresheatUrl) {
    $goresheatServers = [];

    foreach ($nodes as $node) {
        $goresheatServers[$node->fqdn] = [
            'rootUrl' => $goresheatUrl,
            'serverUrl' => $goresheatUrl . '/' . $node->fqdn . '/',
        ];
    }

    $xtpl->assign(
        'AJAX_SCRIPT',
        ($xtpl->vars['AJAX_SCRIPT'] ?? '') .
        '<script type="text/javascript">window.goresheatServers = ' . json_encode($goresheatServers) . ';</script>' .
        '<script type="text/javascript" src="js/goresheat.js"></script>'
    );
}

$xtpl->table_td('', '#5EAFFF; color:#FFF; font-weight:bold;');
$xtpl->table_td(_("Node"), '#5EAFFF; color:#FFF; font-weight:bold;');
$xtpl->table_td(_("Storage"), '#5EAFFF; color:#FFF; font-weight:bold;');
$xtpl->table_td(_("VPS"), '#5EAFFF; color:#FFF; font-weight:bold;');
$xtpl->table_td(_("CPU"), '#5EAFFF; color:#FFF; font-weight:bold;');
$xtpl->table_td(_("Kernel"), '#5EAFFF; color:#FFF; font-weight:bold;');
$xtpl->table_td(_("cgroups") . ' [<a style="color: #ffffff;" href="https://kb.vpsfree.org/manuals/vps/cgroups" target="_blank" title="' . _('Read more about cgroups in KB') . '">?</a>]', '#5EAFFF; color:#FFF; font-weight:bold;');

if ($goresheatUrl) {
    $xtpl->table_td('', '#5EAFFF; color:#FFF; font-weight:bold;');
}

$xtpl->table_tr();

$last_location = 0;
$munin = new Munin($config);

foreach ($nodes as $node) {
    if ($last_location != 0 && $last_location != $node->location_id) {
        $xtpl->table_tr(true);
        $xtpl->table_td('', '#5EAFFF; color:#FFF; font-weight:bold;');
        $xtpl->table_td(_("Node"), '#5EAFFF; color:#FFF; font-weight:bold;');
        $xtpl->table_td(_("Storage"), '#5EAFFF; color:#FFF; font-weight:bold;');
        $xtpl->table_td(_("VPS"), '#5EAFFF; color:#FFF; font-weight:bold;');
        $xtpl->table_td(_("CPU"), '#5EAFFF; color:#FFF; font-weight:bold;');
        $xtpl->table_td(_("Kernel"), '#5EAFFF; color:#FFF; font-weight:bold;');
        $xtpl->table_td(_("cgroups") . ' [<a style="color: #ffffff;" href="https://kb.vpsfree.org/manuals/vps/cgroups" target="_blank" title="' . _('Read more about cgroups in KB') . '">?</a>]', '#5EAFFF; color:#FFF; font-weight:bold;');

        if ($goresheatUrl) {
            $xtpl->table_td('', '#5EAFFF; color:#FFF; font-weight:bold;');
        }

        $xtpl->table_tr(true);
    }

    $last_location = $node->location_id;

    $icons = "";
    $last_report = null;
    $last_update = null;

    if (!is_null($node->last_report)) {
        $last_report = strtotime($node->last_report);
        $last_update = date('Y-m-d H:i:s', $last_report) . ' (' . date('i:s', (time() - $last_report)) . ' ago)';
    }

    if ($node->maintenance_lock != 'no') {
        $icons .= '<img title="' . _("The server is currently under maintenance") . ': ' . htmlspecialchars($node->maintenance_lock_reason) . '" src="template/icons/maintenance_mode.png">';

    } elseif (is_null($last_report) || (time() - $last_report) > 150) {

        $icons .= '<img title="' . _("The server is not responding")
                     . ', last update: ' . ($last_update ?? _('never'))
                     . '" src="template/icons/error.png"/>';
    } else {

        $icons .= '<img title="' . _("The server is online")
                     . ', last update: ' . $last_update
                     . '" src="template/icons/server_online.png"/>';

    }

    $xtpl->table_td($icons);
    $xtpl->table_td((isLoggedIn() ? node_link($node, $node->name) : $node->name));

    if ($node->pool_scan == 'scrub') {
        $xtpl->table_td(_('scrub, ') . round($node->pool_scan_percent, 1) . '&nbsp;%');
    } elseif ($node->pool_scan == 'resilver') {
        $xtpl->table_td(_('resilver, ') . round($node->pool_scan_percent, 1) . '&nbsp;%');
    } else {
        $xtpl->table_td($node->pool_state);
    }

    $xtpl->table_td($node->vps_count, false, true);

    if ($node->cpu_idle === null) {
        $xtpl->table_td('---', false, true);
    } else {
        $xtpl->table_td(
            $munin->linkHostPath(sprintf('%.2f %%', 100.0 - $node->cpu_idle), $node->fqdn, '#system'),
            false,
            true
        );
    }

    $xtpl->table_td(
        kernel_version($node->kernel),
        false,
        true
    );

    $xtpl->table_td(
        cgroup_version($node->cgroup_version),
        false,
        true
    );

    if ($goresheatUrl) {
        if ($node->type == 'node' && $node->maintenance_lock == 'no') {
            $fullGoresheatUrl = $goresheatUrl . '/' . $node->fqdn . '/';
            $xtpl->table_td('<a href="#heatmap-' . $node->fqdn . '" onclick="showGoresheatWindow(\'' . $goresheatUrl . '\', \'' . $fullGoresheatUrl . '\', \'' . $node->fqdn . '\', event)"><img src="template/icons/heatmap.png" width="16" alt="' . _('Heatmap') . '" title="' . _('Heatmap') . '"></a>');
        } else {
            $xtpl->table_td('');
        }
    }

    $xtpl->table_tr();
}

$xtpl->table_out();

$xtpl->table_add_category($config->get('webui', 'index_info_box_title'));
$xtpl->table_td($config->get('webui', 'index_info_box_content'));
$xtpl->table_tr();
$xtpl->table_out();
