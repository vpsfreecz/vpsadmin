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
			$list_backups = true;
			break;
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
		case "restore":
			$xtpl->perex(
				_("Are you sure you want to restore VPS").' '.$_GET["vps_id"].' from '.strftime("%Y-%m-%d %H:%M", $_POST["restore_timestamp"]).'?',
				'<a href="?page=backup">'.strtoupper(_("No")).'</a> | <a href="?page=backup&action=restore2&vps_id='.$_GET["vps_id"].'&timestamp='.$_POST["restore_timestamp"].'&backup_first='.$_POST["backup_first"].'">'.strtoupper(_("Yes")).'</a>'
			);
			break;
		case 'restore2':
			$vps = vps_load($_GET["vps_id"]);
			$xtpl->perex_cmd_output(_("Restoration of VPS")." {$_GET["vps_id"]} from ".strftime("%Y-%m-%d %H:%M", $_GET["timestamp"])." ".strtolower(_("planned")));
			$vps->restore($_GET["timestamp"], $_GET["backup_first"]);
			break;
		case 'download':
			$vps = vps_load($_GET["veid"]);
			$xtpl->perex(_("Download of backup from ").strftime("%Y-%m-%d %H:%M", $_GET["timestamp"])." ".strtolower(_("planned")),
				_("Preparing the archive may take several hours. You will receive email with download link when it is done.")
			);
			$vps->download_backup($_GET["timestamp"]);
			break;
		default:
			$list_backups = true;
	}
	
	if($list_backups) {
		$loaded_vps = array();
		
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
		
		$lastId = 0;
		
		while ($backup = $db->find("vps_backups", $listCond, "vps_id, timestamp")) {
			if (isset($loaded_vps[$backup["vps_id"]]))
				$vps = $loaded_vps[$backup["vps_id"]];
			else
				$vps = $db->findByColumnOnce("vps", "vps_id", $backup["vps_id"]);
			
			if($lastId != $backup["vps_id"]) {
				if($lastId > 0) {
					$xtpl->table_td(_("Current VPS state"));
					$xtpl->table_td('-');
					$xtpl->table_td('[<a href="?page=backup&action=download&veid='.$lastId.'&timestamp=current">'._("Download").'</a>]');
					$xtpl->table_tr();
					$xtpl->form_add_checkbox(_("Make a full backup before restore?"), "backup_first", "1", false);
					$xtpl->form_out(_("Restore"));
				}
					
				if ($_SESSION["is_admin"]) {
					$m = $db->findByColumnOnce("members", "m_id", $vps["m_id"]);
					$xtpl->table_title("VPS {$backup["vps_id"]} [{$vps["vps_hostname"]}, {$m["m_id"]} {$m["m_nick"]}]");
				} else
					$xtpl->table_title("VPS {$backup["vps_id"]} [{$vps["vps_hostname"]}]");
				
				$xtpl->table_add_category(_('Date and time'));
				$xtpl->table_add_category(_('Restore'));
				$xtpl->table_add_category(_('Download'));
				
				$xtpl->form_create('?page=backup&action=restore&vps_id='.$backup["vps_id"].'', 'post');
				
				$lastId = $backup["vps_id"];
			}
			
			$xtpl->form_add_radio(
				strftime("%Y-%m-%d %H:%M", $backup["timestamp"]),
				"restore_timestamp", $backup["timestamp"]
			);
			$xtpl->table_td('[<a href="?page=backup&action=download&veid='.$backup["vps_id"].'&timestamp='.$backup["timestamp"].'">'._("Download").'</a>]');
			$xtpl->table_tr();
		}
		
		if ($lastId) {
			$xtpl->table_td(_("Current VPS state"));
			$xtpl->table_td('-');
			$xtpl->table_td('[<a href="?page=backup&action=download&veid='.$lastId.'&timestamp=current">'._("Download").'</a>]');
			$xtpl->table_tr();
			$xtpl->form_add_checkbox(_("Make a full backup before restore?"), "backup_first", "1", false);
			$xtpl->form_out(_("Restore"));
		} else
			$xtpl->title2(_("No backups found."));
		
		if ($_SESSION["is_admin"]) {
			$xtpl->sbar_out(_("Manage backups"));
		}
	}

} else $xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));

/*


*/
?>
