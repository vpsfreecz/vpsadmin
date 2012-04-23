<?php
/*
    ./index.php

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

define ("CRON_MODE", false);
define ("DEBUG", false);

// Include libraries
include WWW_ROOT.'lib/version.lib.php';
include WWW_ROOT.'lib/db.lib.php';
include WWW_ROOT.'lib/functions.lib.php';
include WWW_ROOT.'lib/transact.lib.php';
include WWW_ROOT.'lib/vps.lib.php';
include WWW_ROOT.'lib/members.lib.php';
include WWW_ROOT.'lib/vps_status.lib.php';
include WWW_ROOT.'lib/networking.lib.php';
include WWW_ROOT.'lib/firewall.lib.php';
include WWW_ROOT.'lib/cluster.lib.php';
include WWW_ROOT.'lib/cluster_ip.lib.php';
include WWW_ROOT.'lib/api_defines.lib.php';
include WWW_ROOT.'lib/api.lib.php';

include WWW_ROOT.'config_cfg.php';

static $SUPPORTED_CALLS = array(
										"cfg_diskspace" => array("list"),
										"cfg_dns" => array("list"),
										"cfg_privvmpages" => array("list"),
										"cfg_templates" => array("list"),
										"cluster" => array("list"),
										"locations" => array("list"),
										"servers" => array("list"),
										"vps" => array("list", "start", "stop", "restart",
																	 "create", "destroy", "allow_feature",
																	 "migrate", "migrate_online", "limits",
																	 "passwd"),
										"vps_ip" => array("list", "assign", "unassign"),
										"vps_status" => array("list"),
										"transactions" => array("list"),
									);

// connect to database
$db = new sql_db (DB_HOST, DB_USER, DB_PASS, DB_NAME);

if (!$cluster_cfg->get("api_enabled")) {
	api_reply(RET_EDISABLED);
}

// authenticate the call
if (!isset($_POST["api_key"]) || 
		!($api_key = $cluster_cfg->get("api_key")) ||
		!($_POST["api_key"] == $api_key)
		) {
	api_reply(RET_ENOAC);
}

$reqbody = null;

// try to parse request body from JSON
if (!isset($_POST["request"]) ||
		!($reqbody = json_decode($_POST["request"], true))) {
	api_reply(RET_EMALFORM);
}

// test class validity
if (!isset($reqbody["class"]) ||
		!array_key_exists($reqbody["class"], $SUPPORTED_CALLS)) {
	api_reply(RET_EINVALIDREQ);
}

// test command validity
if (!isset($reqbody["cmd"]) ||
		!in_array($reqbody["cmd"], $SUPPORTED_CALLS[$reqbody["class"]])) {
	api_reply(RET_EINVALIDREQ);
}

include WWW_ROOT . 'api/api_' . $reqbody["class"] . '.php';

// if we've gotten here, the call is unimplemented
api_reply(RET_ENI);