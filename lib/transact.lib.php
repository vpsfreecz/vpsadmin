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
define ('T_CREATE_VE', 3001);
define ('T_DESTROY_VE', 3002);
define ('T_REINSTALL_VE', 3003);
define ('T_MIGRATE_OFFLINE', 4001);
define ('T_MIGRATE_OFFLINE_PART2', 4011);
define ('T_MIGRATE_ONLINE', 4002);
define ('T_MIGRATE_ONLINE_PART2', 4012);
define ('T_BACKUP_MOUNT', 5001);
define ('T_BACKUP_UMOUNT', 5002);
define ('T_BACKUP_RESTORE', 5003);
define ('T_BACKUP_DOWNLOAD', 5004);
define ('T_FIREWALL_RELOAD', 6001);
define ('T_FIREWALL_FLUSH', 6002);
define ('T_CLUSTER_STORAGE_CFG_RELOAD', 7001);
define ('T_CLUSTER_STORAGE_STARTUP', 7002);
define ('T_CLUSTER_STORAGE_SHUTDOWN', 7003);
define ('T_CLUSTER_STORAGE_SOFTWARE_INSTALL', 7004);
define ('T_CLUSTER_TEMPLATE_COPY', 7101);
define ('T_CLUSTER_TEMPLATE_DELETE', 7102);
define ('T_CLUSTER_IP_REGISTER', 7201);
define ('T_ENABLE_FEATURES', 8001);
define ('T_ENABLE_TUNTAP', 8002); //deprecated
define ('T_ENABLE_IPTABLES', 8003); //deprecated
define ('T_ENABLE_FUSE', 8004);
define ('T_SPECIAL_ISPCP', 8101);

function add_transaction_clusterwide($m_id, $vps_id, $t_type, $t_param = 'none') {
    global $db, $cluster;
    $sql = "INSERT INTO transaction_groups
		    SET is_clusterwide=1";
    $db->query_trans($sql);
    $group_id = $db->insert_id();
    $servers = $cluster->list_servers();
    foreach ($servers as $id=>$name)
	add_transaction($m_id, $id, $vps_id, $t_type, $t_param, $group_id);
}
function add_transaction_locationwide($m_id, $vps_id, $t_type, $t_param = 'none', $location_id) {
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

function add_transaction($m_id, $server_id, $vps_id, $t_type, $t_param = 'none', $transact_group = NULL) {
    global $db;
    $sql_check = 'SELECT COUNT(*) AS count FROM transactions
		WHERE
			t_time > "'.(time() - 5).'"
		AND	t_m_id = "'.$db->check($m_id).'"
		AND	t_server = "'.$db->check($server_id).'"
		AND	t_vps = "'.$db->check($vps_id).'"
		AND	t_type = "'.$db->check($t_type).'"
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
			    t_success = 0,
			    t_done = 0,
			    t_param = "'.$db->check(serialize($t_param)).'"';
	if ($transact_group) $sql .= ', t_group="'.$transact_group.'"';
	$result = $db->query_trans($sql);
    }
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

function exec_wrapper ($command, &$output=NULL, &$retval=NULL) {
    exec($command, $output, $retval);
	//echo $command."\n";
}

function do_all_transactions_by_server($server_id, $force = false) {
    global $db;
    if ($force)
	$sql = 'SELECT * FROM transactions WHERE t_done = 1 AND t_success = 0 AND t_server = '.$db->check($server_id).' ORDER BY t_id ASC';
    else
	$sql = 'SELECT * FROM transactions WHERE t_done = 0 AND t_server = '.$db->check($server_id).' ORDER BY t_id ASC';
    if ($result = $db->query($sql))
	while ($t = $db->fetch_array($result))
	    do_transaction($t);
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
	    if (($t['t_done'] == 1) && ($t['t_success'] == 0)) $status = 'error';
	    if (($t['t_done'] == 1) && ($t['t_success'] == 1)) $status = 'ok';
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
	case T_BACKUP_UMOUNT:
	    $action_label = 'Umount backup';
		break;
	default:
	    $action_label = '['.$t_type.']';
    }
return $action_label;
}

function umount_backuper($vps_id) {
	global $db;
	$server = $db->findByColumnOnce("servers", "server_id", SERVER_ID);
	$location = $db->findByColumnOnce("locations", "location_id", $server["server_location"]);
	$vps = $db->findByColumnOnce("vps", "vps_id", $vps_id);
	if ($server && $location && $vps &&
			$location["location_has_rdiff_backup"] &&
			$vps["vps_backup_mounted"]) {
		$sshfs_path = str_replace("{vps_id}", $vps["vps_id"], $location["location_rdiff_mount_sshfs"]);
		$vps_sshfs_dir = "/var/lib/vz/private/{$vps["vps_id"]}/vpsadmin_backuper";
		$vps_sshfs_path = "/var/lib/vz/root/{$vps["vps_id"]}/vpsadmin_backuper";
		exec_wrapper ("umount {$vps_sshfs_path}");
		exec_wrapper ("umount {$sshfs_path}");
		$db->query("UPDATE vps SET vps_backup_mounted=0 WHERE vps_id = {$vps["vps_id"]}");
	}
	return true;
}
function do_transaction($t) {
    global $db, $firewall, $cluster_cfg, $cluster;
    $ret = false;
    $output[0] = 'SUCCESS';
    if ($t['t_server'] == SERVER_ID && !(DEMO_MODE))
    switch ($t['t_type']) {
	case T_START_VE:
		$params = unserialize($t['t_param']);
		if ($vps = vps_load($t['t_vps'])) {
		    exec_wrapper (BIN_VZCTL.' start '.$db->check($vps->veid), $output, $retval);
		    $ret = ($retval == 0);
		    if ($params["onboot"]) {
		        exec_wrapper (BIN_VZCTL.' set '.$db->check($t['t_vps']).' --save --onboot yes', $output, $retval);
		        $ret &= ($retval == 0);
		    }
		}
		break;
	case T_STOP_VE:
		if ($vps = vps_load($t['t_vps'])) {
			umount_backuper($t['t_vps']);
		    exec_wrapper (BIN_VZCTL.' stop '.$db->check($vps->veid), $output, $retval);
		    $ret = ($retval == 0);
		    exec_wrapper (BIN_VZCTL.' set '.$db->check($vps->veid).' --save --onboot no', $output, $retval);
		    $ret &= ($retval == 0);
		}
		break;
	case T_RESTART_VE:
		$params = unserialize($t['t_param']);
		if ($vps = vps_load($t['t_vps'])) {
			umount_backuper($t['t_vps']);
		    exec_wrapper (BIN_VZCTL.' restart '.$db->check($vps->veid), $output, $retval);
		    $ret = ($retval == 0);
		    if ($params["onboot"]) {
		        exec_wrapper (BIN_VZCTL.' set '.$db->check($t['t_vps']).' --save --onboot yes', $output, $retval);
		        $ret &= ($retval == 0);
		    }
		}
		break;
	case T_EXEC_LIMITS:
	case T_EXEC_PASSWD:
	case T_EXEC_HOSTNAME:
	case T_EXEC_DNS:
	case T_EXEC_IPADD:
	case T_EXEC_IPDEL:
		if ($vps = vps_load($t['t_vps'])) {
		    exec_wrapper (BIN_VZCTL.' set '.$db->check($vps->veid).' --save '.$db->check(unserialize($t['t_param'])), $output, $retval);
		    $ret = ($retval == 0);
		}
		break;
	case T_EXEC_OTHER:
		break;
	case T_CREATE_VE:
		$params = unserialize($t['t_param']);
		exec_wrapper(BIN_VZCTL.' create '.$db->check($t['t_vps']).' --ostemplate '.$db->check($params['template']).' --hostname '.$db->check($params['hostname']), $output, $retval);
		if ($retval != 0)
		    $ret = false;
		else {
		    $onboot = $params["onboot"] ? ' --onboot yes' : '';
		    exec_wrapper (BIN_VZCTL.' set '.$db->check($t['t_vps']).' --applyconfig basic --save --nameserver '.$db->check($params['nameserver']).$onboot, $output, $retval);
		    $ret = ($retval == 0);
		}
		break;
	case T_DESTROY_VE:
		exec_wrapper(BIN_VZCTL.' destroy '.$db->check($t['t_vps']), $output, $retval);
		$ret = ($retval == 0);
		break;
	case T_REINSTALL_VE:
		$retval = $retvala = $retvalb = $retvalc = $retvald = 1;
		$params = unserialize($t['t_param']);
		umount_backuper($t['t_vps']);
		exec_wrapper(BIN_VZCTL.' stop '.$t['t_vps'], $output, $retval);
		if ($retval == 0) exec_wrapper(BIN_VZCTL.' destroy '.$db->check($t['t_vps']), $output, $retvala);
		if ($retvala == 0) exec_wrapper(BIN_VZCTL.' create '.$db->check($t['t_vps']).' --ostemplate '.$db->check($params['template']).' --hostname '.$db->check($params['hostname']), $output, $retvalb);
		if ($retvalb == 0) exec_wrapper (BIN_VZCTL.' set '.$db->check($t['t_vps']).' --applyconfig basic --save --nameserver '.$db->check($params['nameserver']).' --onboot yes', $output, $retvalc);
		if ($retvalc == 0) exec_wrapper(BIN_VZCTL.' start '.$db->check($t['t_vps']), $output, $retvald);
		$ret = ($retvald == 0);
		break;
	case T_MIGRATE_OFFLINE:
		$params = unserialize($t['t_param']);
		umount_backuper($t['t_vps']);
		if ($params["on_shared_storage"]) {
			exec_wrapper('vzctl stop '.$db->check($t['t_vps']));
			add_transaction($_SESSION["member"]["m_id"], $db->check($params['target_id']), $db->check($t['t_vps']), T_MIGRATE_OFFLINE_PART2, array());
		} else {
			exec_wrapper('vzmigrate '.$db->check($params['target']).' '.$db->check($t['t_vps']), $output, $retval);
			if ($vps = vps_load($t['t_vps'])) {
				foreach($params["ips"] as $ip)
					$vps->ipdel($ip);
				$vps->nameserver($cluster->get_first_suitable_dns($cluster->get_location_of_server($vps->ve["vps_server")));
			}
		}
		$ret = ($retval == 0);
		break;
	case T_MIGRATE_OFFLINE_PART2:
		exec_wrapper (BIN_VZCTL.' start '.$db->check($t['t_vps']), $output, $retval);
		$ret = ($retval == 0);
		break;
	case T_MIGRATE_ONLINE:
		$params = unserialize($t['t_param']);
		if ($params["on_shared_storage"]) {
			exec_wrapper('vzctl chkpnt '.$db->check($t['t_vps']), $output, $retval);
			if (($retval != 0) && ($params)) {
			    $sql = 'UPDATE transactions SET t_type='.T_MIGRATE_OFFLINE.' WHERE t_id='.$db->check($t['t_id']);
			    $db->query_trans($sql);
			    umount_backuper($t['t_vps']);
				exec_wrapper('vzctl stop '.$db->check($t['t_vps']));
				add_transaction($_SESSION["member"]["m_id"], $db->check($params['target_id']), $db->check($t['t_vps']), T_MIGRATE_OFFLINE_PART2, array());
			} else {
				add_transaction($_SESSION["member"]["m_id"], $db->check($params['target_id']), $db->check($t['t_vps']), T_MIGRATE_ONLINE_PART2, array());
			};
		} else {
			umount_backuper($t['t_vps']);
			exec_wrapper('vzmigrate --online '.$db->check($params['target']).' '.$db->check($t['t_vps']), $output, $retval);
			// If we were not successful using online migration, fall back to offline one
			if (($retval != 0) && ($params)) {
			    $sql = 'UPDATE transactions SET t_type='.T_MIGRATE_OFFLINE.' WHERE t_id='.$db->check($t['t_id']);
			    $db->query_trans($sql);
			    exec_wrapper('vzmigrate '.$db->check($params['target']).' '.$db->check($t['t_vps']), $output, $retval);
			}
		}
		$ret = ($retval == 0);
		break;
	case T_MIGRATE_ONLINE_PART2:
		exec_wrapper (BIN_VZCTL.' restore '.$db->check($t['t_vps']), $output, $retval);
		$ret = ($retval == 0);
		break;
	case T_CLUSTER_TEMPLATE_COPY:
		$params = unserialize($t["t_param"]);
		$this_node = new cluster_node(SERVER_ID);
		$ret = $this_node->fetch_remote_template($params["templ_id"], $params["remote_server_id"]);
		break;
	case T_CLUSTER_TEMPLATE_DELETE:
		$params = unserialize($t["t_param"]);
		$this_node = new cluster_node(SERVER_ID);
		$ret = $this_node->delete_template($params["templ_id"]);
		break;
	case T_CLUSTER_IP_REGISTER:
		$params = unserialize($t["t_param"]);
		$ret = true;
		if ($params["ip_v"] == 6) {
		    $ret &= $firewall->commit_rule6("-N INPUT_".$params["ip_id"]);
		    $ret &= $firewall->commit_rule6("-N OUTPUT_".$params["ip_id"]);
		    $ret &= $firewall->commit_rule6("-A FORWARD -s {$params["ip_addr"]} -g OUTPUT_{$params["ip_id"]}");
		    $ret &= $firewall->commit_rule6("-A FORWARD -d {$params["ip_addr"]} -g INPUT_{$params["ip_id"]}");
		    $ret &= $firewall->commit_rule6("-A aztotal -s {$params["ip_addr"]}");
		    $ret &= $firewall->commit_rule6("-A aztotal -d {$params["ip_addr"]}");
		} else {
		    $ret &= $firewall->commit_rule("-N INPUT_".$params["ip_id"]);
		    $ret &= $firewall->commit_rule("-N OUTPUT_".$params["ip_id"]);
		    $ret &= $firewall->commit_rule("-A FORWARD -s {$params["ip_addr"]} -g OUTPUT_{$params["ip_id"]}");
		    $ret &= $firewall->commit_rule("-A FORWARD -d {$params["ip_addr"]} -g INPUT_{$params["ip_id"]}");
		    $ret &= $firewall->commit_rule("-A anix -s {$params["ip_addr"]}");
		    $ret &= $firewall->commit_rule("-A anix -d {$params["ip_addr"]}");
		    $ret &= $firewall->commit_rule("-A atranzit -s {$params["ip_addr"]}");
		    $ret &= $firewall->commit_rule("-A atranzit -d {$params["ip_addr"]}");
		    $ret &= $firewall->commit_rule("-A aztotal -s {$params["ip_addr"]}");
		    $ret &= $firewall->commit_rule("-A aztotal -d {$params["ip_addr"]}");
		}
		break;
	case T_ENABLE_FEATURES:
		umount_backuper($t['t_vps']);
		exec_wrapper (BIN_VZCTL. ' stop '.$db->check($t['t_vps']), $trash, $trash2);
    exec_wrapper (BIN_VZCTL.' set '.$db->check($t['t_vps']).' --feature "nfsd:on" --feature "nfs:on" --save', $output, $retval);
		exec_wrapper (BIN_VZCTL.' set '.$db->check($t['t_vps']).' --capability net_admin:on --save', $output, $retval);
		exec_wrapper (BIN_VZCTL.' exec '.$db->check($t['t_vps']).' mkdir -p /dev/net', $output, $retval);
		exec_wrapper (BIN_VZCTL.' exec '.$db->check($t['t_vps']).' mknod /dev/net/tun c 10 200', $output, $retval);
		exec_wrapper (BIN_VZCTL.' exec '.$db->check($t['t_vps']).' chmod 600 /dev/net/tun', $output, $retval);
		exec_wrapper (BIN_VZCTL.' exec '.$db->check($t['t_vps']).' mknod /dev/fuse c 10 229', $output, $retval);
    exec_wrapper (BIN_VZCTL.' set '.$db->check($t['t_vps']).'  --save', $output, $retval);
    $modules = array('ip_conntrack', 'ip_conntrack_ftp', 'ip_conntrack_irc', 'ip_nat_ftp', 'ip_nat_irc', 'ip_tables',
						 'ipt_LOG', 'ipt_REDIRECT', 'ipt_REJECT', 'ipt_TCPMSS', 'ipt_TOS', 'ipt_conntrack', 'ipt_helper',
						 'ipt_length', 'ipt_limit', 'ipt_multiport', 'ipt_state', 'ipt_tcpmss', 'ipt_tos', 'ipt_ttl',
						 'iptable_filter', 'iptable_mangle', 'iptable_nat');
		$iptables_cmd = '';
		foreach ($modules as $module) {
			$iptables_cmd .= ' --iptables '.$module;
		}
		exec_wrapper (BIN_VZCTL.' set '.$db->check($t['t_vps']).' '.$iptables_cmd.' --save', $output, $retval);
		exec_wrapper (BIN_VZCTL.' set '.$db->check($t['t_vps']).' --numiptent 1000 --save', $output, $retval);
		exec_wrapper (BIN_VZCTL.' set '.$db->check($t['t_vps']).' --devices c:10:200:rw --devices c:10:229:rw --save', $output, $retval);
		exec_wrapper (BIN_VZCTL. ' start '.$db->check($t['t_vps']), $trash, $retval);
		$ret = ($retval == 0);
		break;
	case T_ENABLE_TUNTAP:
			break;
	case T_ENABLE_FUSE:
		break;
	case T_ENABLE_IPTABLES:
		break;
	case T_RESTART_NODE:
		$sql = 'UPDATE transactions SET t_done=1,
				t_success=1,
				t_output="'.serialize($ret).'"
				WHERE t_id='.$db->check($t['t_id']);
		$db->query_trans($sql);
		exec_wrapper ('reboot', $output, $retval);
		$ret = true;
		break;
	case T_SPECIAL_ISPCP:
		sleep(30);
		$params = unserialize($t["t_param"]);
		exec_wrapper (BIN_VZCTL.' exec '.$db->check($t['t_vps']).' /root/ispcp-setup.py '.$params, $output, $retval);
		$ret = ($retval == 0);
		break;
	case T_BACKUP_MOUNT:
		$server = $db->findByColumnOnce("servers", "server_id", SERVER_ID);
		$location = $db->findByColumnOnce("locations", "location_id", $server["server_location"]);
		$vps = $db->findByColumnOnce("vps", "vps_id", $t['t_vps']);
		if ($server && $location && $vps &&
				$location["location_has_rdiff_backup"] &&
				(!$vps["vps_backup_mounted"])) {
			$sshfs_path = str_replace("{vps_id}", $vps["vps_id"], $location["location_rdiff_mount_sshfs"]);
			$sshfs_target_path = str_replace("{vps_id}", $vps["vps_id"], $location["location_rdiff_target_path"]);
			echo $sshfs_path;
			exec_wrapper ("mkdir -p $sshfs_path");
			$vps_sshfs_dir = "/var/lib/vz/private/{$vps["vps_id"]}/vpsadmin_backuper";
			$vps_sshfs_path = "/var/lib/vz/root/{$vps["vps_id"]}/vpsadmin_backuper";
			exec_wrapper ("sshfs -o ro {$location["location_rdiff_target"]}:{$sshfs_target_path}".
				' '."{$sshfs_path}", $output, $retval);
			exec_wrapper ("mkdir -p {$vps_sshfs_dir}");
			exec_wrapper ("mount --bind {$sshfs_path} {$vps_sshfs_path}");
			$db->query("UPDATE vps SET vps_backup_mounted=1 WHERE vps_id = {$vps["vps_id"]}");
			$ret = true;
		} else $ret = false;
		break;
	case T_BACKUP_UMOUNT:
		$server = $db->findByColumnOnce("servers", "server_id", SERVER_ID);
		$location = $db->findByColumnOnce("locations", "location_id", $server["server_location"]);
		$vps = $db->findByColumnOnce("vps", "vps_id", $t['t_vps']);
		if ($server && $location && $vps &&
				$location["location_has_rdiff_backup"] &&
				$vps["vps_backup_mounted"]) {
			$sshfs_path = str_replace("{vps_id}", $vps["vps_id"], $location["location_rdiff_mount_sshfs"]);
			$vps_sshfs_dir = "/var/lib/vz/private/{$vps["vps_id"]}/vpsadmin_backuper";
			$vps_sshfs_path = "/var/lib/vz/root/{$vps["vps_id"]}/vpsadmin_backuper";
			exec_wrapper ("umount {$vps_sshfs_path}");
			exec_wrapper ("umount {$sshfs_path}");
			$db->query("UPDATE vps SET vps_backup_mounted=0 WHERE vps_id = {$vps["vps_id"]}");
			$ret = true;
		} else $ret = false;
		break;
	default:
		return false;
    } else $ret = false;


    if (DEMO_MODE) $ret = true;
    if ($ret != false)
	$sql = 'UPDATE transactions SET t_done=1,
				t_success=1,
				t_output="'.serialize($ret).'"
				WHERE t_id='.$db->check($t['t_id']);
    else $sql = 'UPDATE transactions SET t_done=1, t_success=0 WHERE t_id='.$db->check($t['t_id']);
    $db->query_trans($sql);
    return $ret;
}

