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

function show_traffic_row ($arr) {
	global $xtpl;

	$in = round(($arr['in'])/1024/1024/1024, 2);
	$out = round(($arr['out'])/1024/1024/1024, 2);
	$total = round(($arr['in'] + $arr['out'])/1024/1024/1024, 2);
	
	$xtpl->table_td($in, false, true);
	$xtpl->table_td($out, false, true);
	$xtpl->table_td($total, false, true);
}

if ($_SESSION["logged_in"]) {

switch($_GET['action']) {
	case 'ip_addresses':
		ip_address_list('networking');
		break;
	
	case "ipaddr_assign":
		ip_assign_form($_GET['id']);
		break;
	
	case "ipaddr_assign2":
		csrf_check();

		try {
			$ip = $api->ip_address->show($_GET['id']);
			$api->vps($_POST['vps'])->ip_address->create(array('ip_address' => $ip->id));

			notify_user(_('IP assigned'), '');
			redirect($_GET['return'] ? $_GET['return'] : '?page=networking&action=ip_addresses');
		
		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			$xtpl->perex_format_errors(_('Action failed'), $e->getResponse());
			ip_assign_form($_GET['id']);
		}

		break;
	
	case "ipaddr_unassign":
		ip_unassign_form($_GET['id']);
		break;
	
	case "ipaddr_unassign2":
		csrf_check();

		if (!$_POST['confirm']) {
			ip_unassign_form($_GET['id']);
			break;
		}

		try {
			$ip = $api->ip_address->show($_GET['id']);

			if ($_SESSION['is_admin'] && $_POST['disown'])
				$ip->update(array('user' => null));

			$ip->vps->ip_address->delete($ip->id);

			notify_user(_('IP removed'), '');
			redirect($_GET['return'] ? $_GET['return'] : '?page=networking&action=ip_addresses');
		
		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			$xtpl->perex_format_errors(_('Action failed'), $e->getResponse());
			ip_unassign_form($_GET['id']);
		}

		break;
	
	case 'ip_ranges':
		$xtpl->sbar_add(_("New IP range"), '?page=networking&action=ip_range_new');
		ip_range_list();
		break;

	case 'ip_range_new':
		ip_range_new_step1();
		break;
	
	case 'ip_range_new2':
		ip_range_new_step2($_POST['location']);
		break;
	
	case 'ip_range_new3':
		csrf_check();

		try {
			$r = $api->ip_range->create(array('network' => $_POST['network']));

			notify_user(_('Range').' '.$r->address.'/'.$r->prefix.' '._('created').'.');
			redirect('?page=networking&action=ip_ranges');

		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			$xtpl->perex_format_errors(_('Action failed'), $e->getResponse());
			ip_range_new_step2($_POST['network']);
		}
		break;

	case 'traffic':
		$show_traffic = true;
		break;
	
	case 'live':
		$show_live = true;
		break;
	
	default:
		$show_traffic = true;
		break;
}

$xtpl->sbar_add(_("IP addresses"), '?page=networking&action=ip_addresses');
$xtpl->sbar_add(_("IP ranges"), '?page=networking&action=ip_ranges');
$xtpl->sbar_add(_("List monthly traffic"), '?page=networking&action=traffic');
$xtpl->sbar_add(_("Live monitor"), '?page=networking&action=live');
$xtpl->sbar_out(_('Networking'));

if ($show_traffic) {
	$xtpl->title(_("Networking"));
	
	$xtpl->table_title(_('Filters'));
	$xtpl->form_create('', 'get', 'networking-filter', false);
	
	$xtpl->table_td(_("Limit").':'.
		'<input type="hidden" name="page" value="networking">'.
		'<input type="hidden" name="action" value="list">'
	);
	$xtpl->form_add_input_pure('text', '40', 'limit', get_val('limit', '25'), '');
	$xtpl->table_tr();
	
	$xtpl->form_add_select(_("Year").':', 'year', year_list(), get_val('year', date("Y")));
	$xtpl->form_add_select(_("Month").':', 'month', month_list(), get_val('month', date("n")));
	
	if ($_SESSION['is_admin']) {
		$xtpl->form_add_input(_("IP address").':', 'text', '30', 'ip_addr', get_val('ip_addr'));
		$xtpl->form_add_input(_("User").':', 'text', '30', 'user', get_val('user'));
		$xtpl->form_add_input(_("VPS").':', 'text', '30', 'vps', get_val('vps'));
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
	
	$traffic_per_vps = array();
	$traffic_total_ordered = array();
	
	$sql = 'SELECT v.vps_id, vps_hostname, m.m_id, m_nick, ip_addr
	        FROM vps v
			INNER JOIN vps_ip ip ON v.vps_id = ip.vps_id
			INNER JOIN networks n ON n.id = ip.network_id
	        INNER JOIN members m ON v.m_id = m.m_id
	        ';
	
	if ($_SESSION['is_admin']) {
		$conds = array('n.role' => 0);

		if ($_GET['ip_addr'])
			$conds['ip.ip_addr'] = trim($_GET['ip_addr']);

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
				$tmp[] = "($c = '".($db->check($v))."')";
			}
			
			$sql .= implode(' AND ', $tmp);
		}
		
	} else {
		$sql .= "WHERE n.role = 0 AND v.m_id = ".((int) $db->check($_SESSION['member']['m_id']));
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
		
		$xtpl->table_td(
			'<strong>VPS <a href="?page=adminvps&action=info&veid='.$vps_id. '">'
			.$vps_id.'</a> '
			.'<a href="?page=adminm&section=members&action=edit&id='.$user_id. '">'
			.$login.'</a> ['.$hostname.']</strong>'
		);

		$xtpl->table_td(_("PUBLIC [GB]"), '#5EAFFF; color:#FFF; font-weight:bold; text-align: center;', false, '3');
		$xtpl->table_td(_("PRIVATE [GB]"), '#5EAFFF; color:#FFF; font-weight:bold; text-align: center;', false, '3');
		$xtpl->table_td(_("SUM [GB]"), '#5EAFFF; color:#FFF; font-weight:bold; text-align: center;', false, '3');
		$xtpl->table_tr();

		$xtpl->table_td(_("IP Address"), '#5EAFFF; color:#FFF; font-weight:bold;');
		
		$xtpl->table_td(_("IN"), '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("OUT"), '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("TOTAL"), '#5EAFFF; color:#FFF; font-weight:bold;');
		
		$xtpl->table_td(_("IN"), '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("OUT"), '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("TOTAL"), '#5EAFFF; color:#FFF; font-weight:bold;');
		
		$xtpl->table_td(_("IN"), '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("OUT"), '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("TOTAL"), '#5EAFFF; color:#FFF; font-weight:bold;');

		$xtpl->table_tr();
		
		foreach ($traffic_per_vps[$vps_id]['ips'] as $ip => $traffic) {
			$xtpl->table_td($ip);

			show_traffic_row($traffic['public']);
			show_traffic_row($traffic['private']);
			show_traffic_row($traffic);

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
