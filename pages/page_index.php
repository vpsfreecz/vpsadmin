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

$xtpl->title(_("Overview"));

if ($_SESSION["is_admin"]) {
  $xtpl->table_add_category(_("Event Log <a href=\"?page=cluster&action=noticeboard\">[edit]</a>"));
} else {
  $xtpl->table_add_category(_("Event Log"));
}
$xtpl->table_add_category('');

$noticeboard = $cluster_cfg->get("noticeboard");

if ($noticeboard) {
	$xtpl->table_td(nl2br($noticeboard), false, false, 2);
	$xtpl->table_tr();
}
while($log = $db->find("log", NULL, "timestamp DESC", "5")) {
	$xtpl->table_td('['.strftime("%Y-%m-%d %H:%M", $log["timestamp"]).']');
	$xtpl->table_td($log["msg"]);
	$xtpl->table_tr();
}
$xtpl->table_td('<a href="?page=log">'._("View all").'</a>', false, false, '2');
$xtpl->table_tr();
$xtpl->table_out("notice_board");

$xtpl->table_title(_("Cluster statistics"));

$xtpl->table_add_category('Members total');

$xtpl->table_add_category('VPS total');

$xtpl->table_add_category('IPv4 left');

$members = 0;
	$sql = "SELECT COUNT(m_id) as count FROM members WHERE m_state = 'active'";
	$result = $db->query($sql);
  if ($res = $db->fetch_array($result))
    $members = $res['count'];

$xtpl->table_td($members, false, true);


	$servers = 0;
	$sql = 'SELECT COUNT(*) AS count FROM vps v INNER JOIN vps_status s ON v.vps_id = s.vps_id WHERE vps_up = 1';
	$result = $db->query($sql);
  if ($res = $db->fetch_array($result))
    $servers = $res['count'];

$xtpl->table_td($servers, false, true);

	$ip4 = count((array)get_free_ip_list(4));
$xtpl->table_td($ip4, false, true);
$xtpl->table_tr();


$xtpl->table_out();

		$xtpl->table_td('', '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("Node"), '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("VPS"), '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("Free"), '#5EAFFF; color:#FFF; font-weight:bold;');

		$xtpl->table_td('', '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("Node"), '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("VPS"), '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("Free"), '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_tr();

$sql = 'SELECT * FROM servers ORDER BY server_location,server_id';
$rslt = $db->query($sql);

$position = 1;
$last_location = 0;

while ($srv = $db->fetch_array($rslt)) {
	$node = new cluster_node($srv["server_id"]);
	
	if (
			($last_location != 0) &&
			($last_location != $srv["server_location"])
		 ) {

		 if ($position == 2) {
			$xtpl->table_td('', false, false, 5);
		}

		$xtpl->table_tr(true);
		$xtpl->table_td('', '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("Node"), '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("VPS"), '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("Free"), '#5EAFFF; color:#FFF; font-weight:bold;');

		$xtpl->table_td('', '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("Node"), '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("VPS"), '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("Free"), '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_tr(true);


		$position = 1;
	}

	$last_location = $srv["server_location"];
	
	$sql = 'SELECT * FROM servers_status WHERE server_id ="'.$srv["server_id"].'"';

	if ($result = $db->query($sql))
	    $status = $db->fetch_array($result);
	
	$icons = "";

	$last_update = date('Y-m-d H:i:s', $status["timestamp"]).' ('.date('i:s', (time()-$status["timestamp"])).')';
	
	if($node->is_under_maintenance()) {
		$icons .= '<img title="'._("The server is currently under maintenance.").'" src="template/icons/maintenance_mode.png">';
		
	} elseif ((time()-$status["timestamp"]) > 150) {

		$icons .= '<img title="'._("The server is not responding")
					 . ', last update: ' . $last_update
					 . '" src="template/icons/error.png"/>';

	} elseif ($status['daemon'] > 0) {

		$icons .= '<img title="'._("vpsAdmin on this server is not responding")
					 . ', last update: ' . $last_update
					 . '" src="template/icons/server_daemon_offline.png" alt="'
					 . _("vpsAdmin is down").'" />';

	} else {

		$icons .= '<img title="'._("The server is online")
					 . ', last update: ' . $last_update
					 . '" src="template/icons/server_online.png"/>';

	}

		$xtpl->table_td($icons);
	
	$xtpl->table_td($srv["server_name"]);

	$vps_on = $db->fetch_array($db->query("SELECT COUNT(*) AS cnt FROM vps v INNER JOIN vps_status s ON v.vps_id = s.vps_id WHERE vps_up = 1 AND vps_server = ".$db->check($node->s["server_id"])));
	$vpses = $node->s["server_type"] == "node" ? $vps_on["cnt"] : "-";
	
	$xtpl->table_td($vpses, false, true);
	$xtpl->table_td($node->s["server_type"] == "node" ? ($node->role["max_vps"] - $vpses) : "-", false, true);

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

$xtpl->table_add_category($cluster_cfg->get('page_index_info_box_title'));
$xtpl->table_td($cluster_cfg->get('page_index_info_box_content'));
$xtpl->table_tr();
$xtpl->table_out();

