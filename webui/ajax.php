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
include WWW_ROOT.'vendor/autoload.php';
include WWW_ROOT.'lib/version.lib.php';
include WWW_ROOT.'lib/xtemplate.lib.php';
include WWW_ROOT.'lib/functions.lib.php';
include WWW_ROOT.'lib/transact.lib.php';
include WWW_ROOT.'lib/vps.lib.php';
include WWW_ROOT.'lib/members.lib.php';
include WWW_ROOT.'lib/cluster.lib.php';

include WWW_ROOT.'lib/gettext_stream.lib.php';
include WWW_ROOT.'lib/gettext_inc.lib.php';
include WWW_ROOT.'lib/gettext_lang.lib.php';

$api = new \HaveAPI\Client(INT_API_URL, API_VERSION, client_identity());
$api->registerDescriptionChangeFunc('api_description_changed');

if($_SESSION["api_description"]) {
	$api->setDescription($_SESSION["api_description"]);
}

// Create a template class

include WWW_ROOT.'config_cfg.php';

if ($_SESSION["logged_in"]) {
	try {
		$api->authenticate('token', array('token' => $_SESSION['session_token']), false);

		if ($_SESSION["transactbox_expiration"] < time()) {
			unset($_SESSION);
			session_destroy();
			$_GET["page"] = "";
		}

		switch ($_GET["page"]) {
			case 'vps':
				include WWW_ROOT.'pages/ajax_vps.php';
				break;
			default:
				header("HTTP/1.0 404 Not Found");
		}

	} catch (\HaveAPI\Client\Exception\Base $e) {
		echo "Connection to the API lost.";

	} catch (\Httpful\Exception\ConnectionErrorException $e) {
		echo "The API is not responding.";
	}
} else {
	header("HTTP/1.0 404 Not Found");
}
?>

