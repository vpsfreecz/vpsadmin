#!/usr/bin/php
<?php
/*
    ./cron.php

    vpsAdmin
    Web-admin interface for OpenVZ (see http://openvz.org)
    Copyright (C) 2008-2011 Pavel Snajdr, snajpa@snajpa.net
*/

include '/etc/vpsadmin/config.php';
session_start();
define ('CRON_MODE', true);
define ('DEMO_MODE', false);

// Include libraries
include WWW_ROOT.'lib/cli.lib.php';
include WWW_ROOT.'lib/db.lib.php';
include WWW_ROOT.'lib/functions.lib.php';
include WWW_ROOT.'lib/transact.lib.php';
include WWW_ROOT.'lib/vps.lib.php';
include WWW_ROOT.'lib/members.lib.php';
include WWW_ROOT.'lib/vps_status.lib.php';
include WWW_ROOT.'lib/networking.lib.php';
include WWW_ROOT.'lib/firewall.lib.php';
include WWW_ROOT.'lib/version.lib.php';
include WWW_ROOT.'lib/cluster.lib.php';
include WWW_ROOT.'lib/cluster_status.lib.php';

$db = new sql_db (DB_HOST, DB_USER, DB_PASS, DB_NAME);

$this_server = $db->findByColumnOnce("servers", "server_id", SERVER_ID);
$this_location = $db->findByColumnOnce("locations", "location_id", $this_server["server_location"]);

do_all_transactions_by_server(SERVER_ID);
update_all_vps_status();

if (!$this_location["location_has_ospf"]) {
	$all_ips = get_all_ip_list(6);
	foreach ($all_ips as $id=>$ip) {
		exec ('ip -6 neigh add proxy '.$ip.' dev '.NETDEV);
	}
}
$accounting->load_accounting();
$accounting->all_ip4_add();
$accounting->all_ip6_add();
$accounting->update_traffic_table();
$all_vps = get_vps_array();

// cluster_status.lib.php
update_server_status();

$cluster_cfg->set("lock_cron_".SERVER_ID, false);

if ($this_location["location_has_rdiff_backup"]) {
	while ($vps = $db->findByColumn("vps", "vps_server", SERVER_ID)) {
		$sql = "UPDATE vps SET vps_backup_mounted = 0 WHERE vps_id = ".$vps["vps_id"];
		$db->query($sql);
	}
}
?>
