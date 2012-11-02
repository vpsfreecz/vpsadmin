<?php
/*
	./pages/page_transactions.php

	vpsAdmin
	Web-admin interface for OpenVZ (see http://openvz.org)
	Copyright (C) 2008-2011 Pavel Snajdr, snajpa@snajpa.net
*/
if ($_SESSION["logged_in"]) {

$xtpl->title(_("Transaction log"));

if ($_SESSION["is_admin"]) {

	$xtpl->sbar_add(_("<b>DANGEROUS:</b> delete all unfinished"), '?page=transactions&action=delete_unfinished');

	if (isset($_GET["action"])) {
		switch ($_GET["action"]) {
			case "delete_unfinished":
				del_transactions_unfinished();
				$xtpl->perex(_("Unfinished transactions deleted"), '');
				break;
			case "delete":
				if ($s = $db->findByColumnOnce("transactions", "t_id", $_GET["did"])) {
					del_transaction($_GET["did"]);
					$xtpl->perex(_("Transaction deleted"), '');
				}
				break;
		}
	}
}

$whereCond = array();
$whereCond[] = 1;

if ($_REQUEST["from"] != "") {
	$whereCond[] = "t_id < {$_REQUEST["from"]}";
} elseif ($_REQUEST["id"] != "") {
	$whereCond[] = "t_id = {$_REQUEST["id"]}";
}
if ($_REQUEST["vps"] != "") {
	$whereCond[] = "t_vps = {$_REQUEST["vps"]}";
}
if ($_REQUEST["member"] != "") {
	$whereCond[] = "t_m_id = {$_REQUEST["member"]}";
}
if ($_REQUEST["server"] != "") {
	$whereCond[] = "t_server = {$_REQUEST["server"]}";
}
if ($_REQUEST["type"] != "") {
	$whereCond[] = "t_type = {$_REQUEST["type"]}";
}
if ($_REQUEST["limit"] != "") {
	$limit = $_REQUEST["limit"];
} else {
	$limit = 50;
}
if (!$_SESSION["is_admin"]) {
	$whereCond[] = "t_m_id = {$_SESSION["member"]["m_id"]}";
	$_REQUEST["details"] = 0;
}

$xtpl->form_create('?page=transactions&filter=yes', 'post');
$xtpl->form_add_input(_("Limit").':', 'text', '40', 'limit', $limit, '');
$xtpl->form_add_input(_("Start from ID").':', 'text', '40', 'from', $_REQUEST["from"], '');
$xtpl->form_add_input(_("Exact ID").':', 'text', '40', 'id', $_REQUEST["id"], '');
$xtpl->form_add_input(_("Member ID").':', 'text', '40', 'member', $_REQUEST["member"], '');
$xtpl->form_add_input(_("VPS ID").':', 'text', '40', 'vps', $_REQUEST["vps"], '');
$xtpl->form_add_input(_("Server ID").':', 'text', '40', 'server', $_REQUEST["server"], '');
$xtpl->form_add_input(_("Transaction type").':', 'text', '40', 'type', $_REQUEST["type"], '');
$xtpl->form_add_checkbox(_("Detailed mode").':', 'details', '1', $_REQUEST["details"], $hint = '');
$xtpl->form_out(_("Show"));


$xtpl->table_add_category("ID");
$xtpl->table_add_category("TIME");
$xtpl->table_add_category("MEMBER");
$xtpl->table_add_category("SERVER");
$xtpl->table_add_category("VPS");
$xtpl->table_add_category("TYPE");
$xtpl->table_add_category("DONE?");
$xtpl->table_add_category("OK?");

while ($t = $db->find("transactions", $whereCond, "t_id DESC", $limit)) {
	$m = $db->findByColumnOnce("members", "m_id", $t["t_m_id"]);
	$s = $db->findByColumnOnce("servers", "server_id", $t["t_server"]);
	$xtpl->table_td($t["t_id"]);
	$xtpl->table_td(strftime("%Y-%m-%d %H:%M", $t["t_time"]));
	$xtpl->table_td("{$m["m_id"]} {$m["m_nick"]}");
	$xtpl->table_td(($s) ? "{$s["server_id"]} {$s["server_name"]}" : '---');
	$xtpl->table_td(($t["t_vps"] == 0) ? _("--Every--") : "<a href='?page=adminvps&action=info&veid={$t["t_vps"]}'>{$t["t_vps"]}</a>");
	$xtpl->table_td("{$t["t_type"]}".' '.transaction_label($t["t_type"]));
	$xtpl->table_td($t["t_done"]);
	$xtpl->table_td($t["t_success"]);
	if ($t["t_done"]==1 && $t["t_success"]==1)
		$xtpl->table_tr(false, 'ok');
	else if ($t["t_done"]==1 && $t["t_success"]==0)
		$xtpl->table_tr(false, 'error');
	else if ($t["t_done"]==1 && $t["t_success"]==2)
		$xtpl->table_tr(false, 'warning');
	elseif ($t["t_done"]==0 && $t["t_success"]==0) {
		if ($_SESSION["is_admin"]) {
			$xtpl->table_td('<a href="?page=transactions&action=delete&did='.$t["t_id"].'"><img src="template/icons/vps_delete.png"  title="'._("Delete transaction").'"/></a>');
		}
		$xtpl->table_tr(false, 'pending');
	} else
		$xtpl->table_tr();
	if ($_REQUEST["details"]) {
		$xtpl->table_td(nl2br(
			"<strong>"._("Input").":</strong>\n".
			print_r(json_decode(stripslashes($t["t_param"]), true), true).
			"\n<strong>"._("Output").":</strong>\n".
			print_r(json_decode(stripslashes($t["t_output"]), true), true)
		), false, false, 8);
		$xtpl->table_tr();
	}
}

$xtpl->table_out();

if ($_SESSION["is_admin"]) {
	$xtpl->sbar_out(_("Manage transactions"));
}

} else $xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
