<?php
/*
    ./lib/transact.lib.php

    vpsAdmin
    Web-admin interface for OpenVZ (see http://openvz.org)
    Copyright (C) 2008-2011 Pavel Snajdr, snajpa@snajpa.net
*/
define ('T_RESTART_NODE', 3);
define ('T_START_VE', 1001);
define ('T_STOP_VE', 1002);
define ('T_RESTART_VE', 1003);
define ('T_EXEC_OTHER', 2001);
define ('T_EXEC_PASSWD', 2002);
define ('T_EXEC_LIMITS', 2003);
define ('T_EXEC_HOSTNAME', 2004);
define ('T_EXEC_DNS', 2005);
define ('T_EXEC_IPADD', 2006);
define ('T_EXEC_IPDEL', 2007);
define ('T_EXEC_APPLYCONFIG', 2008);
define ('T_CREATE_VE', 3001);
define ('T_DESTROY_VE', 3002);
define ('T_REINSTALL_VE', 3003);
define ('T_CLONE_VE', 3004);
define ('T_MIGRATE_OFFLINE', 4001);
define ('T_MIGRATE_OFFLINE_PART2', 4011);
define ('T_MIGRATE_ONLINE', 4002);
define ('T_MIGRATE_ONLINE_PART2', 4012);
// define ('T_BACKUP_MOUNT', 5001);
// define ('T_BACKUP_UMOUNT', 5002);
define ('T_BACKUP_RESTORE_PREPARE', 5002);
define ('T_BACKUP_RESTORE_FINISH', 5003);
define ('T_BACKUP_DOWNLOAD', 5004);
define ('T_BACKUP_SCHEDULE', 5005);
define ('T_BACKUP_REGULAR', 5006);
define ('T_BACKUP_EXPORTS', 5007);
define ('T_BACKUP_VE_MOUNT', 5101);
define ('T_BACKUP_VE_UMOUNT', 5102);
define ('T_BACKUP_VE_REMOUNT', 5103);
define ('T_BACKUP_VE_GENERATE_MOUNT_SCRIPTS', 5104);
define ('T_FIREWALL_RELOAD', 6001);
define ('T_FIREWALL_FLUSH', 6002);
define ('T_CLUSTER_STORAGE_CFG_RELOAD', 7001);
define ('T_CLUSTER_STORAGE_STARTUP', 7002);
define ('T_CLUSTER_STORAGE_SHUTDOWN', 7003);
define ('T_CLUSTER_STORAGE_SOFTWARE_INSTALL', 7004);
define ('T_CLUSTER_TEMPLATE_COPY', 7101);
define ('T_CLUSTER_TEMPLATE_DELETE', 7102);
define ('T_CLUSTER_IP_REGISTER', 7201);
define ('T_CLUSTER_CONFIG_CREATE', 7301);
define ('T_CLUSTER_CONFIG_DELETE', 7302);
define ('T_ENABLE_FEATURES', 8001);
define ('T_ENABLE_TUNTAP', 8002); //deprecated
define ('T_ENABLE_IPTABLES', 8003); //deprecated
define ('T_ENABLE_FUSE', 8004);
define ('T_SPECIAL_ISPCP', 8101);
define ('T_MAIL_SEND', 9001);

function add_transaction_clusterwide($m_id, $vps_id, $t_type, $t_param = array(), $server_types = array('node', 'backuper', 'mailer', 'storage')) {
    global $db, $cluster;
    $sql = "INSERT INTO transaction_groups
		    SET is_clusterwide=1";
    $db->query_trans($sql);
    $group_id = $db->insert_id();
    $servers = list_servers(false, $server_types);
    foreach ($servers as $id=>$name)
	add_transaction($m_id, $id, $vps_id, $t_type, $t_param, $group_id);
}
function add_transaction_locationwide($m_id, $vps_id, $t_type, $t_param = '', $location_id) {
    global $db, $cluster;
    $sql = "INSERT INTO transaction_groups
		    SET is_locationwide=1,
			location_id=".$db->check($location_id);
    $db->query($sql);
    $group_id = $db->insert_id();
    $servers = $cluster->list_servers_by_location($location_id);
    foreach ($servers as $id=>$name)
	add_transaction($m_id, $id, $vps_id, $t_type, $t_param, $group_id);
}

function add_transaction($m_id, $server_id, $vps_id, $t_type, $t_param = array(), $transact_group = NULL, $dep = NULL) {
    global $db;
    $sql_check = 'SELECT COUNT(*) AS count FROM transactions
		WHERE
			t_time > "'.(time() - 5).'"
		AND	t_m_id = "'.$db->check($m_id).'"
		AND	t_server = "'.$db->check($server_id).'"
		AND	t_vps = "'.$db->check($vps_id).'"
		AND	t_type = "'.$db->check($t_type).'"
		AND t_depends_on = '. ($dep ? '"'.$db->check($dep).'"' : 'NULL') .'
		AND	t_success = 0
		AND	t_done = 0
		AND	t_param = "'.$db->check(serialize($t_param)).'"';
    $result_check = $db->query($sql_check);
    $row = $db->fetch_array($result_check);
    if ($row['count'] <= 0) {
	$sql = 'INSERT INTO transactions
			SET t_time = "'.$db->check(time()).'",
			    t_m_id = "'.$db->check($m_id).'",
			    t_server = "'.$db->check($server_id).'",
			    t_vps = "'.$db->check($vps_id).'",
			    t_type = "'.$db->check($t_type).'",
			    t_depends_on = '. ($dep ? '"'.$db->check($dep).'"' : 'NULL') .',
			    t_success = 0,
			    t_done = 0,
			    t_param = "'.$db->check(count($t_param) ? json_encode($t_param) : '{}').'"';
	if ($transact_group) $sql .= ', t_group="'.$transact_group.'"';
	$result = $db->query($sql);
    }
}

function is_transaction_in_queue($t_type, $veid) {
	global $db;
	
	$rs = $db->query("SELECT COUNT(t_id) AS cnt FROM transactions WHERE t_type = '".$db->check($t_type)."' AND t_done = 0 AND t_vps = '".$db->check($veid)."'");
	$row = $db->fetch_array($rs);
	
	return $row["cnt"] > 0;
}

function get_last_transaction($t_type, $veid) {
	global $db;
	
	$rs = $db->query("SELECT * FROM transactions WHERE t_type = '".$db->check($t_type)."' AND t_vps = '".$db->check($veid)."' ORDER BY t_id DESC LIMIT 1");
	
	return $db->fetch_array($rs);
}

function del_transaction($t_id) {
    global $db;
    $sql = 'DELETE FROM transactions WHERE t_id = '.$db->check($t_id);
    $result = $db->query($sql);
}

function del_transactions_unfinished() {
	global $db;
	$sql = 'DELETE FROM transactions WHERE t_done = 0';
	$result = $db->query($sql);
}

function do_transaction_by_id($t_id) {
    global $db;
    $sql = 'SELECT * FROM transactions WHERE t_done = 0 AND t_id = '.$db->check($t_id);
    if ($result = $db->query($sql))
	if ($t = $db->fetch_array($result))
	    return do_transaction($t);
	else return false;
    else return false;
}

function list_transactions() {
    global $xtpl;
    global $db;
    if ($_SESSION["is_admin"])
	$sql = 'SELECT * FROM transactions
		LEFT JOIN members
		ON transactions.t_m_id = members.m_id
		LEFT JOIN servers
		ON transactions.t_server = servers.server_id
		ORDER BY transactions.t_id DESC LIMIT 10';
    else
	$sql = 'SELECT * FROM transactions
		LEFT JOIN members
		ON transactions.t_m_id = members.m_id
		LEFT JOIN servers
		ON transactions.t_server = servers.server_id
		WHERE members.m_id = "'.$db->check($_SESSION["member"]["m_id"]).'"
		ORDER BY transactions.t_id DESC LIMIT 10';
    if ($result = $db->query($sql))
	while ($t = $db->fetch_array($result)) {
	    if ($t['t_done'] == 0) $status = 'pending';
	    else if (($t['t_done'] == 1) && ($t['t_success'] == 0)) $status = 'error';
	    else if (($t['t_done'] == 1) && ($t['t_success'] == 1)) $status = 'ok';
	    else if (($t['t_done'] == 1) && ($t['t_success'] == 2)) $status = 'warning';
	    
	    $xtpl->transaction($t['t_id'],($t["server_name"] == "") ? "---" : $t["server_name"],
				    ($t["t_vps"] == 0) ? "---" : $t["t_vps"], transaction_label($t['t_type']), $status);
	}
    $xtpl->transactions_out();
}

function transaction_label ($t_type) {
    switch ($t_type) {
	case T_RESTART_NODE:
	    $action_label = 'REBOOT';
	    break;
	case T_START_VE:
	    $action_label = 'Start';
	    break;
	case T_STOP_VE:
	    $action_label = 'Stop';
	    break;
	case T_RESTART_VE:
	    $action_label = 'Restart';
	    break;
	case T_EXEC_LIMITS:
	    $action_label = 'Limits';
	    break;
	case T_EXEC_PASSWD:
	    $action_label = 'Passwd';
	    break;
	case T_EXEC_HOSTNAME:
	    $action_label = 'Hostname';
	    break;
	case T_EXEC_DNS:
	    $action_label = 'DNS Server';
	    break;
	case T_EXEC_IPADD:
	    $action_label = 'IP +';
	    break;
	case T_EXEC_IPDEL:
	    $action_label = 'IP -';
	    break;
	case T_EXEC_APPLYCONFIG:
	    $action_label = 'Apply config';
	    break;
	case T_EXEC_OTHER:
	    $action_label = 'exec';
	    break;
	case T_CREATE_VE:
	    $action_label = 'New';
	    break;
	case T_DESTROY_VE:
	    $action_label = 'Delete';
	    break;
	case T_REINSTALL_VE:
	    $action_label = 'Reinstall';
	    break;
	case T_CLONE_VE:
		$action_label = 'Clone';
		break;
	case T_MIGRATE_OFFLINE:
	    $action_label = 'Migrate';
	    break;
	case T_MIGRATE_ONLINE:
	    $action_label = 'Migrate live';
	    break;
	case T_MIGRATE_OFFLINE_PART2:
	    $action_label = '*Off-Migrace';
	    break;
	case T_MIGRATE_ONLINE_PART2:
	    $action_label = '*ON-MIGRACE';
	    break;
	case T_FIREWALL_RELOAD:
	    $action_label = 'FW Reload';
	    break;
	case T_FIREWALL_FLUSH:
	    $action_label = 'FW Flush';
	    break;
	case T_CLUSTER_STORAGE_CFG_RELOAD:
	    $action_label = 'STRG rld';
	    break;
	case T_CLUSTER_STORAGE_STARTUP:
	    $action_label = 'STRG up';
	    break;
	case T_CLUSTER_STORAGE_SHUTDOWN:
	    $action_label = 'STRG down';
	    break;
	case T_CLUSTER_STORAGE_SOFTWARE_INSTALL:
	    $action_label = 'STRG install';
	    break;
	case T_CLUSTER_TEMPLATE_COPY:
	    $action_label = 'TMPL copy';
	    break;
	case T_CLUSTER_TEMPLATE_DELETE:
	    $action_label = 'TMPL del';
	    break;
	case T_CLUSTER_IP_REGISTER:
	    $action_label = 'IP reg';
	    break;
	case T_CLUSTER_CONFIG_CREATE:
		$action_label = 'Create config';
		break;
	case T_CLUSTER_CONFIG_DELETE:
		$action_label = 'Delete config';
		break;
	case T_ENABLE_FEATURES:
	    $action_label = 'Enable features';
	    break;
	// DEPRECATED:
	case T_ENABLE_TUNTAP:
	    $action_label = 'Enable tuntap';
	    break;
	// DEPRECATED:
	case T_ENABLE_IPTABLES:
	    $action_label = 'Enable iptables';
	    break;
	// DEPRECATED:
	case T_ENABLE_FUSE:
	    $action_label = 'Enable fuse';
	    break;
	case T_SPECIAL_ISPCP:
	    $action_label = 'Setup ispCP';
	    break;
	case T_BACKUP_MOUNT:
	    $action_label = 'Mount backup';
		break;
	case T_BACKUP_RESTORE_PREPARE:
		$action_label = 'Restore (1)';
		break;
	case T_BACKUP_RESTORE_FINISH:
		$action_label = 'Restore (2)';
		break;
	case T_BACKUP_DOWNLOAD:
		$action_label = 'Download backup';
		break;
	case T_BACKUP_SCHEDULE:
		$action_label = 'On-demand backup';
		break;
	case T_BACKUP_REGULAR:
		$action_label = 'Backup';
		break;
	case T_BACKUP_EXPORTS:
		$action_label = 'Exports';
		break;
	case T_BACKUP_VE_MOUNT:
		$action_label = 'Mount backup';
		break;
	case T_BACKUP_VE_UMOUNT:
		$action_label = 'Umount backup';
		break;
	case T_BACKUP_VE_REMOUNT:
		$action_label = 'Remount backup';
		break;
	case T_BACKUP_VE_GENERATE_MOUNT_SCRIPTS:
		$action_label = 'Generate mount scripts';
		break;
	case T_MAIL_SEND:
		$action_label = 'Mail';
		break;
	default:
	    $action_label = '['.$t_type.']';
    }
return $action_label;
}
