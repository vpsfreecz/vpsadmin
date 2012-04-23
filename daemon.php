#!/usr/bin/php
<?php
require_once "/etc/vpsadmin/config.php";

session_start();

define ('CRON_MODE', true);
define ('DEMO_MODE', false);

error_reporting(0);
// Include libraries
include WWW_ROOT.'lib/cli.lib.php';
include WWW_ROOT.'lib/db.lib.php';
include WWW_ROOT.'lib/functions.lib.php';
include WWW_ROOT.'lib/transact.lib.php';
include WWW_ROOT.'lib/vps.lib.php';
include WWW_ROOT.'lib/members.lib.php';
include WWW_ROOT.'lib/vps_status.lib.php';
include WWW_ROOT.'lib/networking.lib.php';
include WWW_ROOT.'lib/version.lib.php';
include WWW_ROOT.'lib/cluster.lib.php';
include WWW_ROOT.'lib/cluster_status.lib.php';
include WWW_ROOT.'lib/daemon.lib.php';

// init global DB
$db = new sql_db (DB_HOST, DB_USER, DB_PASS, DB_NAME);

$this_server = $db->findByColumnOnce("servers", "server_id", SERVER_ID);
$this_location = $db->findByColumnOnce("locations", "location_id", $this_server["server_location"]);

if (!$this_location["location_has_ospf"]) {
        $all_ips = get_all_ip_list(6);
        foreach ($all_ips as $id=>$ip) {
                exec ('ip -6 neigh add proxy '.$ip.' dev '.NETDEV);
        }
}

// start daemon
new vpsAdmin($db);
?>
