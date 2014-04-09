<?php
/*
    ./cron_nonpayers.php

    vpsAdmin
    Web-admin interface for OpenVZ (see http://openvz.org)
    Copyright (C) 2008-2014 Pavel Snajdr
    Copyright (C) 2012-2014 Jakub Skokan

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
include WWW_ROOT.'lib/version.lib.php';
include WWW_ROOT.'lib/cluster.lib.php';

$db = new sql_db (DB_HOST, DB_USER, DB_PASS, DB_NAME);

if($cluster_cfg->get("maintenance_mode")) {
	echo "MAINTENANCE";
	exit;
}

$rs = $db->query("SELECT server_id, server_name
                  FROM locations l
                  INNER JOIN servers s ON l.location_id = s.server_location
                  WHERE server_maintenance = 0
                  ORDER BY l.location_id, s.server_id");
$bad = false;

while($row = $db->fetch_array($rs)) {
	$sql = 'SELECT * FROM servers_status WHERE server_id ="'.$row["server_id"].'"';
		
	if ($result = $db->query($sql))
		$status = $db->fetch_array($result);
	
	if ((time()-$status["timestamp"]) > 150) {
		if(!$bad) {
			$bad = true;
			header('HTTP/1.1 503 Service Unavailable');
		}
	
		echo $row["server_name"]."\n";
	}
}

if(!$bad)
	echo "OK";
