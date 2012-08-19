<?php
/*
    ./pages/page_networking.php

    vpsAdmin
    Web-admin interface for OpenVZ (see http://openvz.org)
    Copyright (C) 2008-2011 Pavel Snajdr, snajpa@snajpa.net
*/
if ($_SESSION["logged_in"]) {

$xtpl->title(_("Manage Networking"));

$show_list = true;

if ($show_list) {
	$this_month = date("n");
	$xtpl->table_title(_("Month:"));
	for ($i=1;$i<=12;$i++) {
		if (
				(isset($_GET["month"]) && ($_GET["month"] == $i)) ||
				($i == $this_month && (!isset($_GET["month"])))
		) {
			$xtpl->table_td("$i");
		} else {
			$xtpl->table_td("<a href=\"?page=networking&month={$i}\">$i</a>");
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

} else $xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
