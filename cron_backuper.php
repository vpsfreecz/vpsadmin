#!/usr/bin/php
<?php
/*
	./cron.php

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
include WWW_ROOT.'lib/version.lib.php';
include WWW_ROOT.'lib/cluster.lib.php';
include WWW_ROOT.'lib/cluster_status.lib.php';


$db = new sql_db (DB_HOST, DB_USER, DB_PASS, DB_NAME);

if (!$cluster_cfg->get("lock_cron_backup_".SERVER_ID)) {
	$cluster_cfg->set("lock_cron_backup_".SERVER_ID, true);
	$whereCond = "vps_server = ".SERVER_ID;
/*
	$cluster_cfg->set("backuper_server", "172.16.100.6");
	$cluster_cfg->set("backuper_server_path_vps", "/storage/vps/{vps_id}");
	$cluster_cfg->set("backuper_local_mount_sshfs", "/backuper/sshfs/{vps_id}");
	$cluster_cfg->set("backuper_local_mount_archfs", "/backuper/archfs/{vps_id}");
	$cluster_cfg->set("backuper_keep_history", 14);
*/
	$server = $db->findByColumnOnce("servers", "server_id", SERVER_ID);
	$location = $db->findByColumnOnce("locations", "location_id", $server["server_location"]);
	if (!$location["location_has_rdiff_backup"]) {
		$cluster_cfg->set("lock_cron_backup_".SERVER_ID, false);
		die ("Fatal: Rdiff-backup is not supported in this location.");
	}
	$backuper_keep_history = $location["location_rdiff_history"];
	$backuper_server = $location["location_rdiff_target"];
	$backuper_server_path_vps = $location["location_rdiff_target_path"];
	while ($vps = $db->find("vps", $whereCond)) {
		if ($vps["vps_backup_enabled"]) {
			umount_backuper($vps["vps_id"]);
			$rdiff_cmd = "rdiff-backup /var/lib/vz/private/{$vps["vps_id"]} {$backuper_server}::{$backuper_server_path_vps}";
			$rdiff_cmd = str_replace("{vps_id}", $vps["vps_id"], $rdiff_cmd);
			$rdiff_cleanup_cmd = "rdiff-backup --remove-older-than {$backuper_keep_history}B {$backuper_server}::{$backuper_server_path_vps}";
			$rdiff_cleanup_cmd = str_replace("{vps_id}", $vps["vps_id"], $rdiff_cleanup_cmd);
			exec($rdiff_cmd);
			exec($rdiff_cleanup_cmd);
			$path = $backuper_server."::".$backuper_server_path_vps;
			$path = str_replace("{vps_id}", $vps["vps_id"], $path);
			$lspath = "{$backuper_server_path_vps}/rdiff-backup-data/session_statistics";
			$lspath = str_replace("{vps_id}", $vps["vps_id"], $lspath);
			$cmd = "ssh $backuper_server \"ls -1r $lspath* 2> /dev/null\"\n";
			$output = array();
			exec($cmd, $output);
			// Go through backups and save details to the DB
			$count = 0;
			$db->destroyByCond("vps_backups", "vps_id = {$vps["vps_id"]}");
			foreach ($output as $line) {
				$cat = array();
				exec ("ssh $backuper_server \"cat $line\"", $cat);
				$file_cat = array();
				foreach ($cat as $ln) {
					$tmp = explode(" ", $ln, 3);
					$file_cat[$tmp[0]] = $tmp;
				}
				$timestamp = str_replace($lspath.".", "", $line);
				$timestamp = str_replace(".data", "", $timestamp);
				$timestamp = (strtotime($timestamp));
				$backup["id"] = NULL;
				$backup["vps_id"] = $vps["vps_id"];
				$backup["timestamp"] = $timestamp;
				$backup["idB"] = $count;
				$backup["details"] = serialize($file_cat);
				$db->save(true, $backup, "vps_backups");
				$count++;
			}
		}
	}
	$cluster_cfg->set("lock_cron_backup_".SERVER_ID, false);
}
?>
