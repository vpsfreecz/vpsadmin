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
    $all_vpses = get_vps_array();
    $xtpl->table_title(_("Statistics:"));
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
    if ($all_vpses) foreach ($all_vpses as $vps) {
		$vps_ips = $vps->iplist();
		$m = member_load($vps->ve["m_id"]);
		$xtpl->table_td($vps->ve["vps_id"]. ' '.$m->m["m_nick"].' ['.$vps->ve["vps_hostname"].']', '#5EAFFF; color:#FFF; font-weight:bold;', false, 1, (count($vps_ips)+1));
		$xtpl->table_td(_("IP Address"), '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("IN [GB]"), '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("OUT [GB]"), '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_td(_("TOTAL [GB]"), '#5EAFFF; color:#FFF; font-weight:bold;');
		$xtpl->table_tr();
		if ($vps_ips)
		foreach ($vps_ips as $ip) {
			$xtpl->table_td($ip["ip_addr"]);
			if (isset($_GET["month"])) {
				$generated = time();
				$year = date('Y', $generated);
				// hour, minute, second, month, day, year
				$this_month = mktime (1, 0, 0, $_GET["month"], 1, $year);
				$traffic = $accounting->get_traffic_by_ip_this_month($ip["ip_addr"], $this_month);
			} else {
				$traffic = $accounting->get_traffic_by_ip_this_month($ip["ip_addr"]);
			}
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
?>
