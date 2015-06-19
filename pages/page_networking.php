<?php
/*
    ./pages/page_networking.php

    vpsAdmin
    Web-admin interface for OpenVZ (see http://openvz.org)
    Copyright (C) 2008-2011 Pavel Snajdr, snajpa@snajpa.net
*/

function year_list() {
	$now = date("Y");
	$ret = array();
	
	for ($i = $now - 5; $i <= $now; $i++)
		$ret[$i] = $i;
	
	return $ret;
}

function month_list() {
	$ret = array();
	
	for ($i = 1; $i <= 12; $i++) {
		$ret[$i] = $i;
	}
	
	return $ret;
}

if ($_SESSION["logged_in"]) {

$xtpl->sbar_add(_("List monthly traffic"), '?page=networking&action=list');
$xtpl->sbar_add(_("Live monitor"), '?page=networking&action=live');
$xtpl->sbar_out(_('Networking'));

switch($_GET['action']) {
	case 'list':
		$show_list = true;
		break;
	
	case 'live':
		$show_live = true;
		break;
	
	default:
		$show_list = true;
		break;
}

if ($show_list) {
	$xtpl->title(_("Networking"));
	
	$xtpl->table_title(_('Filters'));
	$xtpl->form_create('', 'get', 'networking-filter', false);
	
	$xtpl->table_td(_("Limit").':'.
		'<input type="hidden" name="page" value="networking">'.
		'<input type="hidden" name="action" value="list">'
	);
	$xtpl->form_add_input_pure('text', '40', 'limit', get_val('limit', '25'), '');
	$xtpl->table_tr();
	
	$xtpl->form_add_select(_("Year").':', 'year', year_list(), date("Y"));
		$xtpl->form_add_select(_("Month").':', 'month', month_list(), date("n"));
	
	if ($_SESSION['is_admin']) {
		$xtpl->form_add_select(_("User").':', 'user',
			resource_list_to_options($api->user->list(), 'id', 'login', true, user_label), get_val('user'));
		$xtpl->form_add_select(_("VPS").':', 'vps',
			resource_list_to_options($api->vps->list(), 'id', 'hostname', true, vps_label), get_val('vps'));
		$xtpl->form_add_select(_("Node").':', 'node', 
			resource_list_to_options($api->node->list(), 'id', 'name'), get_val('node'));
		$xtpl->form_add_select(_("Location").':', 'location',
			resource_list_to_options($api->location->list()), get_val('location'));
		$xtpl->form_add_select(_("Environment").':', 'environment',
			resource_list_to_options($api->environment->list()), get_val('environment'));
	}
	
	$xtpl->form_out(_('Show'));
	
	if ($_SESSION['is_admin'] && $_GET['action'] != 'list')
		return;
	
	$xtpl->table_title(_("Statistics"));
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	
	$traffic_per_vps = array();
	$traffic_total_ordered = array();
	
	$sql = 'SELECT v.vps_id, vps_hostname, m_nick, ip_addr
	        FROM vps v
	        INNER JOIN vps_ip ip ON v.vps_id = ip.vps_id
	        INNER JOIN members m ON v.m_id = m.m_id
	        ';
	
	if ($_SESSION['is_admin']) {
		$conds = array();
		
		if ($_GET['user'])
			$conds['v.m_id'] =  $_GET['user'];
		
		if ($_GET['vps'])
			$conds['v.vps_id'] = $_GET['vps'];
		
		if ($_GET['node'])
			$conds['vps_server'] = $_GET['node'];
		
		if ($_GET['location'])
			$conds['server_location'] = $_GET['location'];
		
		if ($_GET['environment'])
			$conds['s.environment_id'] = $_GET['environment'];
		
		if ($_GET['location'] || $_GET['environment'])
			$sql .= "INNER JOIN servers s ON v.vps_server = s.server_id\n";
		
		if (count($conds)) {
			$sql .= "WHERE\n";
			$tmp = array();
			
			foreach ($conds as $c => $v) {
				$tmp[] = "($c = ".((int)$db->check($v)).")";
			}
			
			$sql .= implode(' AND ', $tmp);
		}
		
	} else {
		$sql .= "WHERE v.m_id = ".((int) $db->check($_SESSION['member']['m_id']));
	}
	
	$rs = $db->query($sql);
	
	while ($row = $db->fetch_array($rs)) {
		if (!array_key_exists($row['vps_id'], $traffic_per_vps)) {
			$traffic_per_vps[ $row['vps_id'] ] = array(
				'hostname' => $row['vps_hostname'],
				'user_id' => $row['m_id'],
				'login' => $row['m_nick']
			);
		}
		
		if ($_GET['month'] || $_GET['year']) {
			// hour, minute, second, month, day, year
			$this_month = mktime (0, 0, 0, get_val('month', date('n')), 1, get_val('year', date('Y')));
			
			$traffic = $accounting->get_traffic_by_ip_this_month($row['ip_addr'], $this_month);
			
		} else {
			$traffic = $accounting->get_traffic_by_ip_this_month($row['ip_addr']);
		}
		
		$traffic_per_vps[ $row['vps_id'] ]['ips'][$row["ip_addr"]] = $traffic;
		
		$traffic_total_ordered[ $row['vps_id'] ] += $traffic['in'] + $traffic['out'];
	}
	
	arsort($traffic_total_ordered);
	
	$i = 0;
	$limit = get_val('limit', 25);
	
	foreach ($traffic_total_ordered as $vps_id => $total) {
		$user_id = $traffic_per_vps[$vps_id]['user_id'];
		$login = $traffic_per_vps[$vps_id]['login'];
		$hostname = $traffic_per_vps[$vps_id]['hostname'];
		
		$xtpl->table_td('<b><a href="?page=adminvps&action=info&veid='.$vps_id. '">'
						.$vps_id.'</a> '
						.'<a href="?page=adminm&section=members&action=edit&id='.$user_id. '">'
						.$login.'</a> ['.$hostname.'] </b>', false, false, 1, (count($traffic_per_vps[$vps_id]['ips'])+1));
		$xtpl->table_td(_("IP Address"), '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("IN [GB]"), '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("OUT [GB]"), '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("TOTAL [GB]"), '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_tr();
		
		foreach ($traffic_per_vps[$vps_id]['ips'] as $ip => $traffic) {
			$xtpl->table_td($ip);
			
			$in = round(($traffic['in'])/1024/1024/1024, 2);
			$out = round(($traffic['out'])/1024/1024/1024, 2);
			$total = round(($traffic['in'] + $traffic['out'])/1024/1024/1024, 2);
			
			$xtpl->table_td($in, false, true);
			$xtpl->table_td($out, false, true);
			$xtpl->table_td($total, false, true);
			$xtpl->table_tr();
		}
		
		if (++$i == $limit)
			break;
	}
	$xtpl->table_out();
}


if ($show_live) {
	$xtpl->title(_('Live monitor'));
	
	if($_SESSION["is_admin"]) {
		$xtpl->form_create('?page=adminm&section=members&action=approval_requests', 'get');
		
		$xtpl->table_td(_("Limit").':'.
			'<input type="hidden" name="page" value="networking">'.
			'<input type="hidden" name="action" value="live">'
		);
		$xtpl->form_add_input_pure('text', '30', 'limit', $_GET["limit"] ? $_GET["limit"] : 50);
		$xtpl->table_tr();
		
		$xtpl->form_add_input(_("IP address").':', 'text', '30', 'ip', $_GET["ip"]);
		$xtpl->form_add_input(_("VPS ID").':', 'text', '30', 'vps', $_GET["vps"]);
		$xtpl->form_add_input(_("Member ID").':', 'text', '30', 'member', $_GET["member"]);
		
		$xtpl->form_out(_("Show"));
	}
	
	
	$xtpl->table_add_category(_('VPS'));
	$xtpl->table_add_category(_('IP'));
	$xtpl->table_add_category(_('TCP<br>IN'));
	$xtpl->table_add_category(_('TCP<br>OUT'));
	$xtpl->table_add_category(_('UDP<br>IN'));
	$xtpl->table_add_category(_('UDP<br>OUT'));
	$xtpl->table_add_category(_('OTHERS<br>IN'));
	$xtpl->table_add_category(_('OTHERS<br>OUT'));
	$xtpl->table_add_category(_('TOTAL'));
	
	$traffic = null;
	
	if($_SESSION["is_admin"]) {
		$traffic = $accounting->get_live_traffic_by_ip(
			$_GET["limit"] ? (int)$_GET["limit"] : 50,
			$_GET["ip"],
			(int)$_GET["vps"],
			(int)$_GET["member"]
		);
	} else {
		$traffic = $accounting->get_live_traffic_by_ip(
			50,
			false,
			false,
			$_SESSION["member"]["m_id"]
		);
	}
	
	$cols = array('tcp', 'udp', 'others');
	
	foreach($traffic as $data) {
		$xtpl->table_td('<a href="?page=adminvps&action=info&veid='.$data['vps_id'].'">'.$data['vps_id'].'</a>');
		$xtpl->table_td($data['ip_addr']);
		
		foreach($cols as $col) {
			$xtpl->table_td(
				format_data_rate($data['protocols'][$col]['bps']['in'] * 8, 'bps')."<br>".
				format_data_rate($data['protocols'][$col]['pps']['in'] * 8, 'pps'),
				false, true
			);
			
			$xtpl->table_td(
				format_data_rate($data['protocols'][$col]['bps']['out'] * 8, 'bps')."<br>".
				format_data_rate($data['protocols'][$col]['pps']['out'] * 8, 'pps'),
				false, true
			);
		}
		
		$xtpl->table_td(
			format_data_rate(($data['protocols']['all']['bps']['in'] + $data['protocols']['all']['bps']['out']) * 8, 'bps')."<br>".
			format_data_rate(($data['protocols']['all']['pps']['in'] + $data['protocols']['all']['pps']['out']) * 8, 'pps'),
			false, true
		);
		
		$xtpl->table_tr();
	}
	
	$xtpl->table_out('live_monitor');
}

} else $xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
