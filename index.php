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
session_start();
define ("CRON_MODE", false);
define ("DEBUG", false);

// Include libraries
include WWW_ROOT.'vendor/autoload.php';
include WWW_ROOT.'lib/version.lib.php';
include WWW_ROOT.'lib/xtemplate.lib.php';
include WWW_ROOT.'lib/db.lib.php';
include WWW_ROOT.'lib/functions.lib.php';
include WWW_ROOT.'lib/transact.lib.php';
include WWW_ROOT.'lib/vps.lib.php';
include WWW_ROOT.'lib/members.lib.php';
include WWW_ROOT.'lib/networking.lib.php';
include WWW_ROOT.'lib/cluster.lib.php';
include WWW_ROOT.'lib/cluster_ip.lib.php';
include WWW_ROOT.'lib/ajax.lib.php';
include WWW_ROOT.'lib/mail.lib.php';
include WWW_ROOT.'lib/log.lib.php';
include WWW_ROOT.'lib/helpbox.lib.php';
include WWW_ROOT.'lib/nas.lib.php';

include WWW_ROOT.'forms/nas.forms.php';

include WWW_ROOT.'lib/gettext_stream.lib.php';
include WWW_ROOT.'lib/gettext_inc.lib.php';
include WWW_ROOT.'lib/gettext_lang.lib.php';
// include configuration
include WWW_ROOT.'config_cfg.php';

// connect to database
$db = new sql_db (DB_HOST, DB_USER, DB_PASS, DB_NAME, DB_SOCK, true);

$api = new \HaveAPI\Client(API_URL, API_VERSION, "vpsadmin-www v".VERSION);
$api->registerDescriptionChangeFunc('api_description_changed');

if($_SESSION["api_description"]) {
	$api->setDescription($_SESSION["api_description"]);
}

// Create a template class
$xtpl = new XTemplate(WWW_ROOT.'template/template.html');
// Create a langauge class
$lang = new Lang($langs, $xtpl);

$xtpl->assign("L_USERNAME", _("Username"));
$xtpl->assign("L_PASSWORD", _("Password"));
$xtpl->assign("L_LOGIN", _("Login"));
$xtpl->assign("L_LOGOUT", _("Logout"));

$xtpl->assign("L_TRANSACTION_LOG", _("Transaction log"));
$xtpl->assign("L_LAST10", _("last 10"));
$xtpl->assign("L_ACTION", _("Action"));


if (isset($_SESSION["logged_in"]) && $_SESSION["logged_in"]) {
	$api->authenticate('token', array('token' => $_SESSION['auth_token']), false);
	
	$_member = member_load($_SESSION["member"]["m_id"]);
	
	try {
		$api->user->touch($_SESSION["member"]["m_id"]);
		$_SESSION["transactbox_expiration"] = time() + USER_LOGIN_INTERVAL;
		$xtpl->assign('AJAX_SCRIPT', ajax_getHTML('ajax.php?page=transactbox', 'transactions', 1000));
		
	} catch (\HaveAPI\AuthenticationFailed $e) {
		unset($_SESSION);
		session_destroy();
		$_GET["page"] = "";
	}
}

$Cluster_ipv4 = new Cluster_ipv4($xtpl, $db);
$Cluster_ipv6 = new Cluster_ipv6($xtpl, $db);

$_GET["page"] = isset($_GET["page"]) ? $_GET["page"] : false;

$db_ver = $cluster_cfg->get("db_version");
$db_check = $db_ver == DB_VERSION;
$xtpl->assign('DB_VERSION', $db_ver);

if(!$db_check)
	$cluster_cfg->set("maintenance_mode", true);

if (($_GET["page"] != "login") &&
				($_GET["page"] != "lang") &&
				($_GET["page"] != "about") &&
				(!$_SESSION["is_admin"]) &&
				$cluster_cfg->get("maintenance_mode"))
	{
		$request_page = "";
		include WWW_ROOT.'pages/page_index.php';
		$xtpl->perex(_("Maintenance mode"), _("vpsAdmin is currently in maintenance mode, any actions are disabled. <br />
										This is usually used during outage to prevent data corruption.<br />
										Please be patient."));
} else {
	show_notification();
	
	switch ($_GET["page"]) {
		case 'adminvps':
			include WWW_ROOT.'pages/page_adminvps.php';
			break;
		case 'about':
			include WWW_ROOT.'pages/page_about.php';
			break;
		case 'login':
			include WWW_ROOT.'pages/page_login.php';
			break;
		case 'adminm':
			include WWW_ROOT.'pages/page_adminm.php';
			break;
		case 'transactions':
			include WWW_ROOT.'pages/page_transactions.php';
			break;
		case 'networking':
			include WWW_ROOT.'pages/page_networking.php';
			break;
		case 'cluster':
			include WWW_ROOT.'pages/page_cluster.php';
			break;
		case 'log':
			include WWW_ROOT.'pages/page_log.php';
			break;
		case 'backup':
			include WWW_ROOT.'pages/page_backup.php';
			break;
		case 'nas':
			include WWW_ROOT.'pages/page_nas.php';
			break;
		case 'gencfg':
			include WWW_ROOT.'pages/page_gencfg.php';
			break;
		case 'lang';
			$lang->change($_GET['newlang']);
			break;
		case 'console':
			include WWW_ROOT.'pages/page_console.php';
			break;
		case 'jumpto':
			include WWW_ROOT.'pages/page_jumpto.php';
			break;
		default:
			include WWW_ROOT.'pages/page_index.php';
	}
	$request_page = $_GET["page"];
}



if (isset($_SESSION["logged_in"]) && $_SESSION["logged_in"]) {
    $xtpl->menu_add(_("Status"),'?page=', ($_GET["page"] == ''));
    $xtpl->menu_add(_("Members"),'?page=adminm', ($_GET["page"] == 'adminm'));
    $xtpl->menu_add(_("VPS"),'?page=adminvps', ($_GET["page"] == 'adminvps'));
    if ($_SESSION["is_admin"]) {
		$xtpl->menu_add(_("Backups"),'?page=backup', ($_GET["page"] == 'backup'));
		
		if(NAS_PUBLIC || $_SESSION["is_admin"])
			$xtpl->menu_add(_("NAS"),'?page=nas', ($_GET["page"] == 'nas'));
		
		$xtpl->menu_add(_("Networking"),'?page=networking', ($_GET["page"] == 'networking'));
		$xtpl->menu_add(_("Cluster"),'?page=cluster', ($_GET["page"] == 'cluster'));
		$xtpl->menu_add(_("Transaction log"),'?page=transactions', ($_GET["page"] == 'transactions'), true);
    } else {
		$xtpl->menu_add(_("Backups"),'?page=backup', ($_GET["page"] == 'backup'));
		
		if(NAS_PUBLIC || $_SESSION["is_admin"])
			$xtpl->menu_add(_("NAS"),'?page=nas', ($_GET["page"] == 'nas'));
		
		$xtpl->menu_add(_("Networking"),'?page=networking', ($_GET["page"] == 'networking'));
		$xtpl->menu_add(_("Transaction log"),'?page=transactions', ($_GET["page"] == 'transactions'), true);
    }

    list_transactions();
} else {
    $xtpl->menu_add(_("Status"),'?page=', ($_GET["page"] == ''));
    $xtpl->menu_add(_("About vpsAdmin"),'?page=about', ($_GET["page"] == 'about'), true);
}

if(!$_SESSION["logged_in"])
	$_SESSION["access_url"] = $_SERVER["REQUEST_URI"];

$xtpl->logbox(
	isset($_SESSION["logged_in"]) ? $_SESSION["logged_in"] : false,
	isset($_SESSION["member"]) ? $_SESSION["member"]["m_nick"] : false,
	isset($_SESSION["is_admin"]) ? $_SESSION["is_admin"] : false,
	$cluster_cfg->get("maintenance_mode"),
	!$db_check
);

$xtpl->adminbox($cluster_cfg->get("adminbox_content"));

$help = get_helpbox();

if ($help) {
	if ($_SESSION["is_admin"])
		$help["content"] .= '<br><br><a href="?page=cluster&action=helpboxes_edit&id='.$help["id"].'" title="'._("Edit").'"><img src="template/icons/edit.png" title="'._("Edit").'">'._("Edit help box").'</a>';
	
	$xtpl->helpbox(_("Help"), nl2br($help["content"]));
} else if ($_SESSION["is_admin"]) {
	$xtpl->helpbox(_("Help"), '<a href="?page=cluster&action=helpboxes_add&help_page='.$_GET["page"].'&help_action='.$_GET["action"].'" title="'._("Edit").'"><img src="template/icons/edit.png" title="'._("Edit").'">'._("Edit help box").'</a>');
}

$lang->lang_switcher();

$xtpl->assign('PAGE_TITLE', $cluster_cfg->get("page_title"));

if (defined('TRACKING_CODE')) {
  $xtpl->assign('TRACKING_CODE', TRACKING_CODE);
}
$xtpl->parse('main');
$xtpl->out('main');

?>
