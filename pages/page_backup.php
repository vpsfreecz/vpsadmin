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
		case "mount":
			if ($vps = $db->findByColumnOnce("vps", "vps_id", $_GET["mvps_id"])) {
				if ($_SESSION["is_admin"] || ($vps["m_id"] == $_SESSION["member"]["m_id"])) {
					add_transaction($_SESSION["member"]["m_id"], $vps["vps_server"], $vps["vps_id"], T_BACKUP_MOUNT);
				} else $list_backups = true;
			} else $list_backups = true;
			break;
		case "umount":
			if ($vps = $db->findByColumnOnce("vps", "vps_id", $_GET["uvps_id"])) {
				if ($_SESSION["is_admin"] || ($vps["m_id"] == $_SESSION["member"]["m_id"])) {
					add_transaction($_SESSION["member"]["m_id"], $vps["vps_server"], $vps["vps_id"], T_BACKUP_UMOUNT);
				} else $list_backups = true;
			} else $list_backups = true;
			break;
		case "download":
			break;
		case "restore":
			break;
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
	while ($backup = $db->find("vps_backups", $listCond, "vps_id, idB ASC")) {
		$vps_backups[$backup["vps_id"]][] = $backup;
	}
	if ($vps_backups) foreach ($vps_backups as $k=>$backups) {
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
		$xtpl->table_add_category(_("ID"));
		$xtpl->table_add_category(_("Start"));
		$xtpl->table_add_category(_("End"));
		$xtpl->table_add_category(_("Elapsed"));
		$xtpl->table_add_category(_("Diff size"));
		foreach ($backups as $backup) {
			$details = unserialize($backup["details"]);
			$xtpl->table_td($backup["idB"], false, true);
			$xtpl->table_td(date("d.m.Y H:i:s",$details["StartTime"][1]));
			$xtpl->table_td(date("d.m.Y H:i:s",$details["EndTime"][1]));
			$xtpl->table_td(sec2hms($details["ElapsedTime"][1]));
			$xtpl->table_td(sprintf("%2.2f GB", ($details["TotalDestinationSizeChange"][1]/1024/1024/1024)), false, true);
			$xtpl->table_tr();
		}
		$xtpl->table_out();
		if (!$is_deleted) {
			$xtpl->table_td(_("Mount Backup FS into /vpsadmin_backuper/:"));
			if ($vps["vps_backup_mounted"]) {
				$xtpl->table_td("<a href=\"?page=backup&action=umount&uvps_id={$vps["vps_id"]}\">[Umount Backup FS]</a>");
			} else {
				$xtpl->table_td("<a href=\"?page=backup&action=mount&mvps_id={$vps["vps_id"]}\">[Mount Backup FS]</a>");
			}
			$xtpl->table_tr();
			$xtpl->table_out();
		}
	} else {
		$xtpl->title2(_("Sorry, no backups found. Perhaps the location does not support rdiff-backup."));
	}

if ($_SESSION["is_admin"]) {
	$xtpl->sbar_out(_("Manage backups"));
}

} else $xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));

/*


*/
?>
