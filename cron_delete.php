#!/usr/bin/php
<?php
/*
    ./cron_nonpayers.php

    vpsAdmin
    Web-admin interface for OpenVZ (see http://openvz.org)
    Copyright (C) 2008-2012 Pavel Snajdr
    Copyright (C) 2012 Jakub Skokan

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
$_SESSION["is_admin"] = true;
define ('CRON_MODE', true);
define ('DEMO_MODE', false);

// Include libraries
include WWW_ROOT.'lib/db.lib.php';
include WWW_ROOT.'lib/functions.lib.php';
include WWW_ROOT.'lib/transact.lib.php';
include WWW_ROOT.'lib/vps.lib.php';
include WWW_ROOT.'lib/members.lib.php';
include WWW_ROOT.'lib/networking.lib.php';
include WWW_ROOT.'lib/version.lib.php';
include WWW_ROOT.'lib/cluster.lib.php';
include WWW_ROOT.'lib/nas.lib.php';
include WWW_ROOT.'lib/mail.lib.php';

$db = new sql_db (DB_HOST, DB_USER, DB_PASS, DB_NAME);

// First delete members
$member_timeout = $cluster_cfg->get("general_member_delete_timeout") * 24 * 60 * 60;

$rs = $db->query("SELECT m_id FROM members WHERE m_state = 'deleted' AND m_deleted < ".$db->check((time() - $member_timeout)));

while($row = $db->fetch_array($rs)) {
	$m = new member_load($row["m_id"]);
	
	$m->delete_all_vpses(false);
	$m->destroy(false);
}

// Delete expired VPSes
$vps_timeout = $cluster_cfg->get("general_vps_delete_timeout") * 24 * 60 * 60;

$rs = $db->query("SELECT vps_id FROM vps WHERE vps_deleted IS NOT NULL AND vps_deleted < ".$db->check((time() - $vps_timeout)));

while($row = $db->fetch_array($rs)) {
	$vps = new vps_load($row["vps_id"]);
	
	if($vps->ve["vps_backup_export"])
		nas_export_delete($vps->ve["vps_backup_export"]);
	
	$vps->destroy(false);
}
