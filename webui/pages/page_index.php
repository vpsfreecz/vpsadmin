<?php
/*
    ./pages/page_index.php

    vpsAdmin
    Web-admin interface for OpenVZ (see http://openvz.org)
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

$xtpl->sbar_add(_('Outages'), '?page=outage&action=list');

if (isLoggedIn() && $api->monitored_event)
	$xtpl->sbar_add(_("Monitoring"), '?page=monitoring&action=list');

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
	foreach ($api->news_log->list(array('limit' => 5)) as $news) {
		$xtpl->table_td('['.tolocaltz($news->published_at, "Y-m-d H:i").']');
		$xtpl->table_td($news->message);
		$xtpl->table_tr();
	}

	$xtpl->table_td('<a href="?page=log">'._("View all").'</a>', false, false, '2');
	$xtpl->table_tr();
}

$xtpl->table_out("notice_board");

if ($api->outage) {
	$outages = $api->outage->list(array(
		'state' => 'announced',
		'limit' => 5,
		'order' => 'oldest',
	));

	if ($outages->count()) {
		$xtpl->table_title(_('Current/planned outages'));

		$xtpl->table_add_category(_('Date'));
		$xtpl->table_add_category(_('Duration'));
		$xtpl->table_add_category(_('Planned'));
		$xtpl->table_add_category(_('Systems'));
		$xtpl->table_add_category(_('Type'));
		$xtpl->table_add_category(_('Reason'));

		if (isAdmin()) {
			$xtpl->table_add_category(_('Users'));
			$xtpl->table_add_category(_('VPS'));

		} elseif (isLoggedIn()) {
			$xtpl->table_add_category(_('Affects me?'));
		}

		$xtpl->table_add_category('');

		foreach ($outages as $outage) {
			$xtpl->table_td(tolocaltz($outage->begins_at, 'Y-m-d H:i'));
			$xtpl->table_td($outage->duration.' min', false, true);
			$xtpl->table_td(boolean_icon($outage->planned));
			$xtpl->table_td(implode(', ', array_map(
				function ($v) { return h($v->label); },
				$outage->entity->list()->asArray()
			)));
			$xtpl->table_td($outage->type);
			$xtpl->table_td(h($outage->en_summary));

			if (isAdmin()) {
				$xtpl->table_td(
					'<a href="?page=outage&action=users&id='.$outage->id.'">'.
					$outage->affected_user_count.
					'</a>',
					false, true
				);
				$xtpl->table_td(
					'<a href="?page=outage&action=vps&id='.$outage->id.'">'.
					$outage->affected_direct_vps_count.
					'</a>',
					false, true
				);

			} elseif (isLoggedIn())
				$xtpl->table_td(boolean_icon($outage->affected));

			$xtpl->table_td('<a href="?page=outage&action=show&id='.$outage->id.'"><img src="template/icons/m_edit.png"  title="'. _("Details") .'" /></a>');

			$xtpl->table_tr();
		}

		$xtpl->table_out();
	}
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

$xtpl->table_td('', '#5EAFFF; color:#FFF; font-weight:bold;');
$xtpl->table_td(_("Node"), '#5EAFFF; color:#FFF; font-weight:bold;');
$xtpl->table_td(_("VPS"), '#5EAFFF; color:#FFF; font-weight:bold;');
$xtpl->table_td(_("CPU"), '#5EAFFF; color:#FFF; font-weight:bold;');
$xtpl->table_td(_("Kernel"), '#5EAFFF; color:#FFF; font-weight:bold;');

$xtpl->table_td('', '#5EAFFF; color:#FFF; font-weight:bold;');
$xtpl->table_td(_("Node"), '#5EAFFF; color:#FFF; font-weight:bold;');
$xtpl->table_td(_("VPS"), '#5EAFFF; color:#FFF; font-weight:bold;');
$xtpl->table_td(_("CPU"), '#5EAFFF; color:#FFF; font-weight:bold;');
$xtpl->table_td(_("Kernel"), '#5EAFFF; color:#FFF; font-weight:bold;');
$xtpl->table_tr();

$position = 1;
$last_location = 0;

$nodes = $api->node->public_status();

foreach ($nodes as $node) {
	if (
			($last_location != 0) &&
			($last_location != $node->location_id)
		) {

		 if ($position == 2) {
			$xtpl->table_td('', false, false, 5);
		}

		$xtpl->table_tr(true);
		$xtpl->table_td('', '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("Node"), '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("VPS"), '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("CPU"), '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("Kernel"), '#5EAFFF; color:#FFF; font-weight:bold;');

		$xtpl->table_td('', '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("Node"), '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("VPS"), '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("CPU"), '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("Kernel"), '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_tr(true);


		$position = 1;
	}

	$last_location = $node->location_id;

	$icons = "";

	$last_report = strtotime($node->last_report);
	$last_update = date('Y-m-d H:i:s', $last_report).' ('.date('i:s', (time() - $last_report)).' ago)';

	if($node->maintenance_lock != 'no') {
		$icons .= '<img title="'._("The server is currently under maintenance").': '.htmlspecialchars($node->maintenance_lock_reason).'" src="template/icons/maintenance_mode.png">';

	} elseif ((time() - $last_report) > 150) {

		$icons .= '<img title="'._("The server is not responding")
					 . ', last update: ' . $last_update
					 . '" src="template/icons/error.png"/>';

	} else {

		$icons .= '<img title="'._("The server is online")
					 . ', last update: ' . $last_update
					 . '" src="template/icons/server_online.png"/>';

	}

	$xtpl->table_td($icons);

	$xtpl->table_td($node->name);
	$xtpl->table_td($node->vps_count, false, true);

	if ($node->cpu_idle === null)
		$xtpl->table_td('---', false, true);
	else
		$xtpl->table_td(sprintf('%.2f %%', 100.0 - $node->cpu_idle), false, true);

	$xtpl->table_td(kernel_version($node->kernel), false, true);

	$position++;
	if ($position == 3) {
		$position = 1;
		$xtpl->table_tr(true);
	}

}

if($position == 2) { // last row has only one node
	$xtpl->table_td('', false, false, 5);
	$xtpl->table_tr(true);
}

$xtpl->table_out();

$xtpl->table_add_category($config->get('webui', 'index_info_box_title'));
$xtpl->table_td($config->get('webui', 'index_info_box_content'));
$xtpl->table_tr();
$xtpl->table_out();

