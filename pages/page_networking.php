<?php
/*
    ./pages/page_networking.php

    vpsAdmin
    Web-admin interface for OpenVZ (see http://openvz.org)
    Copyright (C) 2008-2011 Pavel Snajdr, snajpa@snajpa.net
*/
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
		if(!$_SESSION["is_admin"])
			$show_list = true;
		else
			$show_index = true;
		break;
}

if ($show_index) {
	$xtpl->perex('',
		'<h3><a href="?page=networking&action=list">List monthly traffic</a></h3>'.
		'<h3><a href="?page=networking&action=live">Live monitor</a></h3>'
	);
}

if ($show_list) {
	$xtpl->title(_("Networking"));
	
	$this_month = date("n");
	$xtpl->table_title(_("Month:"));
	for ($i=1;$i<=12;$i++) {
		if (
				(isset($_GET["month"]) && ($_GET["month"] == $i)) ||
				($i == $this_month && (!isset($_GET["month"])))
		) {
			$xtpl->table_td("$i");
		} else {
			$xtpl->table_td("<a href=\"?page=networking".($_SESSION["is_admin"] ? "&action=list" : "")."&month={$i}\">$i</a>");
		}
	}
	$xtpl->table_tr();
	$xtpl->table_out();
    $xtpl->table_title(_("Statistics:"));
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');

  $all_vpses = get_vps_array();
  $traffic_per_vps = array();
  $traffic_total_ordered = array();

  if ($all_vpses) foreach ($all_vpses as $vps) {
		if ($vps_ips = $vps->iplist()) {
      $traffic_per_vps[$vps->veid]["vps"] = $vps;
      $traffic_per_vps[$vps->veid]["member"] = member_load($vps->ve["m_id"]);

      foreach ($vps_ips as $ip) {
        if (isset($_GET["month"])) {
          $generated = time();
          $year = date('Y', $generated);
          // hour, minute, second, month, day, year
          $this_month = mktime (1, 0, 0, $_GET["month"], 1, $year);
          $traffic = $accounting->get_traffic_by_ip_this_month($ip["ip_addr"], $this_month);
        } else {
          $traffic = $accounting->get_traffic_by_ip_this_month($ip["ip_addr"]);
        }
        $traffic_per_vps[$vps->veid]["ips"][$ip["ip_addr"]] = $traffic;

        $traffic_total_ordered[$vps->veid] += $traffic['in'] + $traffic['out'];
      }
    }
  }

  arsort($traffic_total_ordered);

  foreach ($traffic_total_ordered as $vps_id => $total) {
    $m = $traffic_per_vps[$vps_id]["member"];
    $vps = $traffic_per_vps[$vps_id]["vps"];

    $xtpl->table_td('<b><a href="?page=adminvps&action=info&veid='.$vps->ve["vps_id"]. '">'
                    .$vps->ve["vps_id"].'</a> '
                    .'<a href="?page=adminm&section=members&action=edit&id='.$m->m["m_id"]. '">'
                    .$m->m["m_nick"].'</a> ['.$vps->ve["vps_hostname"].'] </b>', false, false, 1, (count($traffic_per_vps[$vps_id]["ips"])+1));
    $xtpl->table_td(_("IP Address"), '#5EAFFF; color:#FFF; font-weight:bold;');
    $xtpl->table_td(_("IN [GB]"), '#5EAFFF; color:#FFF; font-weight:bold;');
    $xtpl->table_td(_("OUT [GB]"), '#5EAFFF; color:#FFF; font-weight:bold;');
    $xtpl->table_td(_("TOTAL [GB]"), '#5EAFFF; color:#FFF; font-weight:bold;');
    $xtpl->table_tr();

    foreach ($traffic_per_vps[$vps_id]["ips"] as $ip => $traffic) {
		$xtpl->table_td($ip);
		$in = round(($traffic['in'])/1024/1024/1024, 2);
		$out = round(($traffic['out'])/1024/1024/1024, 2);
		$total = round(($traffic['in']+$traffic['out'])/1024/1024/1024, 2);
		$xtpl->table_td($in, false, true);
		$xtpl->table_td($out, false, true);
		$xtpl->table_td($total, false, true);
		$xtpl->table_tr();
	}
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
