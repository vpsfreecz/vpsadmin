<?php
/*
    ./ajax.php

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
define ('CRON_MODE', false);

header("Cache-Control: no-cache, must-revalidate"); // HTTP/1.1
header("Expires: Sat, 11 Jan 1991 06:30:00 GMT"); // Date in the past

// Include libraries
include WWW_ROOT.'lib/version.lib.php';
include WWW_ROOT.'lib/xtemplate.lib.php';
include WWW_ROOT.'lib/db.lib.php';
include WWW_ROOT.'lib/functions.lib.php';
include WWW_ROOT.'lib/transact.lib.php';
include WWW_ROOT.'lib/vps.lib.php';
include WWW_ROOT.'lib/members.lib.php';
include WWW_ROOT.'lib/networking.lib.php';
include WWW_ROOT.'lib/cluster.lib.php';

include WWW_ROOT.'lib/gettext_stream.lib.php';
include WWW_ROOT.'lib/gettext_inc.lib.php';
include WWW_ROOT.'lib/gettext_lang.lib.php';

$db = new sql_db (DB_HOST, DB_USER, DB_PASS, DB_NAME, DB_SOCK, true);



// Create a template class

include WWW_ROOT.'config_cfg.php';

if ($_SESSION["logged_in"]) {
	$_member = member_load($_SESSION["member"]["m_id"]);
	if ($_SESSION["transactbox_expiration"] < time()) {
		unset($_SESSION);
		session_destroy();
		$_GET["page"] = "";
	}

	switch ($_GET["page"]) {
		case 'transactbox':
			$xtpl = new XTemplate(WWW_ROOT.'template/ajax_get_transactbox.html');
			include WWW_ROOT.'pages/ajax_get_transactbox.php';
			$xtpl->parse('main');
			$xtpl->out('main');
			break;
		case 'vps':
			include WWW_ROOT.'pages/ajax_vps.php';
			break;
		default:
			header("HTTP/1.0 404 Not Found");
	}
} else {
	header("HTTP/1.0 404 Not Found");
}
?>

