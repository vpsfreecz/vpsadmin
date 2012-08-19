<?php
/*
    ./pages/page_backup.php

    vpsAdmin
    Web-admin interface for OpenVZ (see http://openvz.org)
    Copyright (C) 2008-2011 Pavel Snajdr, snajpa@snajpa.net
*/
function sec2hms ($sec, $padHours = false) {
	$hms = "";
	$hours = intval(intval($sec) / 3600);
	$hms .= ($padHours)
		? str_pad($hours, 2, "0", STR_PAD_LEFT). ":"
		: $hours. ":";
	$minutes = intval(($sec / 60) % 60);
	$hms .= str_pad($minutes, 2, "0", STR_PAD_LEFT). ":";
	$seconds = intval($sec % 60);
	$hms .= str_pad($seconds, 2, "0", STR_PAD_LEFT);
	return $hms;
}
if ($_SESSION["logged_in"]) {
	$xtpl->title(_("Manage Backups"));
	$list_backups = false;
	switch ($_GET["action"]) {
		case "cleanup":
			if ($_SESSION["is_admin"]) {
				if (!($vps = $db->findByColumnOnce("vps", "vps_id", $_GET["vps_id"]))) {
					$db->query("DELETE FROM vps_backups WHERE vps_id = '{$_GET["vps_id"]}'");
				}
			}
			unset ($_GET["vps_id"]);
			break;
			$list_backups = true;
		case "cleanup_all":
			if ($_SESSION["is_admin"]) {
				$deleted = array();
				while ($backup = $db->find("vps_backups")) {
					if (!($vps = $db->findByColumnOnce("vps", "vps_id", $backup["vps_id"]))) {
						$deleted[] = $backup["vps_id"];
						$db->query("DELETE FROM vps_backups WHERE vps_id = '{$backup["vps_id"]}'");
					}
				}
			}
			$perex = implode($deleted, "\n<br />");
			$xtpl->perex("Backups cleaned-up", $perex);
			break;
			$list_backups = true;
		default:
			$list_backups = true;
	}


	if ($_SESSION["is_admin"]) {

	$xtpl->sbar_add(_("<b>DANGEROUS:</b> clean-up all deleted"), '?page=backup&action=cleanup_all');

		$listCond[] = "1";
		if (isset($_GET["vps_id"])) {
			$listCond[] = "vps_id = {$db->check($_GET["vps_id"])}";
		}
		if (isset($_GET["m_id"])) {
			while ($vps = $db->findByColumn("vps", "m_id", $_GET["m_id"])) {
				$vpses[] = "(vps_id = {$vps["vps_id"]})";
				$loaded_vps[$vps["vps_id"]] = $vps;
			}
			$listCond[] = implode(" OR ", $vpses);
		}
	} else {
		$vpses = array();
		while ($vps = $db->findByColumn("vps", "m_id", $_SESSION["member"]["m_id"])) {
			$vpses[] = "(vps_id = {$vps["vps_id"]})";
			$loaded_vps[$vps["vps_id"]] = $vps;
		}
		$listCond[] = implode(" OR ", $vpses);
	}
	while ($backup = $db->find("vps_backups", $listCond, "vps_id")) {
		$vps_backups[$backup["vps_id"]] = $backup;
	}
	if ($vps_backups) foreach ($vps_backups as $k=>$backup) {
		if (isset($loaded_vps[$k])) {
			$vps = $loaded_vps[$k];
		} else {
			if (!($vps = $db->findByColumnOnce("vps", "vps_id", $k))) {
				$vps["vps_hostname"] = "DELETED";
			}
		}
		if ($_SESSION["is_admin"]) {
			if (isset($vps["m_id"])) {
				$is_deleted = false;
				$m = $db->findByColumnOnce("members", "m_id", $vps["m_id"]);
				$xtpl->table_title("VPS {$k} [{$vps["vps_hostname"]}, {$m["m_id"]} {$m["m_nick"]}]");
			} else {
				$is_deleted = true;
				$xtpl->table_title("<a href='?page=backup&action=cleanup&vps_id={$k}'>[clean-up]</a> DELETED VPS {$k}");
			}
		} else {
			$xtpl->table_title("VPS {$k} [{$vps["vps_hostname"]}]");
		}
		$xtpl->table_add_category('');
		$xtpl->table_add_category('');
		$details = nl2br(base64_decode($backup["details"]));
    $xtpl->table_td($details, false, false, 2);
    $xtpl->table_tr();
		$xtpl->table_out();
	} else {
		$xtpl->title2(_("No backups found."));
	}

if ($_SESSION["is_admin"]) {
	$xtpl->sbar_out(_("Manage backups"));
}

} else $xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));

/*


*/
?>
