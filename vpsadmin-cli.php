#!/usr/bin/php
<?php
/*
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

$argc = $_SERVER['argc'];
$argv = $_SERVER['argv'];

if ($argc < 2) {
	print ("Command missing.\n");
	include WWW_ROOT.'cli/man.cli.php';
	exit (-1);
}

switch ($argv[1]) {
	case 'vps':
		include WWW_ROOT.'cli/vps.cli.php';
		break;
	default:
		print ("Illegal command.\n");
		include WWW_ROOT.'cli/man.cli.php';
		exit (-1);
}
