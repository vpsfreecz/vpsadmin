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
include WWW_ROOT.'lib/mail.lib.php';

$db = new sql_db (DB_HOST, DB_USER, DB_PASS, DB_NAME);

$whereCond = "m_mailer_enable = 1";
while ($m = $db->find("members", $whereCond)) {
	$member = member_load($m["m_id"]);
	if (($member->m["m_paid_until"] - time()) <= 604800) {
		$subject = $cluster_cfg->get("mailer_tpl_payment_warning_subj");
		$subject = str_replace("%member%", $m["m_nick"], $subject);
		
		$content = $cluster_cfg->get("mailer_tpl_payment_warning");
		$content = str_replace("%member%", $m["m_nick"], $content);
		$content = str_replace("%memberid%", $m["m_id"], $content);
		$content = str_replace("%expiredate%", ($m["m_paid_until"]) ? strftime("%Y-%m-%d", $m["m_paid_until"]) : '---', $content);
		$content = str_replace("%monthly%", $m["m_monthly_payment"], $content);
		
		send_mail($m["m_mail"], $subject, $content, $cluster_cfg->get("mailer_admins_in_cc") ? explode(",", $cluster_cfg->get("mailer_admins_cc_mails")) : array());
    }
}
?>
