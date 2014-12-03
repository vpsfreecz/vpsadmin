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
		case 'snapshot':
			try {
				$api->vps($_GET['vps_id'])->snapshot->create();
				
				notify_user(_('Snapshot creation scheduled.'), _('Snapshot will be taken momentarily.'));
				redirect('?page=backup');
				
			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Snapshot failed'), $e->getResponse());
			}
		
		case 'restore':
			try {
				$snap = $api->vps($_GET['vps_id'])->snapshot->find($_POST['restore_snapshot']);
				
				$xtpl->perex(
					_("Are you sure you want to restore VPS").' '.$_GET["vps_id"].' from '.strftime("%Y-%m-%d %H:%M", strtotime($snap->created_at)).'?',
					'<a href="?page=backup">'.strtoupper(_("No")).'</a> | <a href="?page=backup&action=restore2&vps_id='.$_GET["vps_id"].'&restore_snapshot='.$snap->id.'">'.strtoupper(_("Yes")).'</a>'
				);
				
			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('VPS or snapshot not found'), $e->getResponse());
			}
			
			break;
		
		case 'restore2':
			try {
				$snap = $api->vps($_GET['vps_id'])->snapshot->find($_GET['restore_snapshot']);
				$snap->rollback();
				
				notify_user(
					_('VPS restoration scheduled.'),
					_("Restoration of VPS")." {$_GET["vps_id"]} from ".strftime("%Y-%m-%d %H:%M", strtotime($snap->created_at))." ".strtolower(_("planned"))
				);
				redirect('?page=backup');
				
			}  catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('VPS restoration failed'), $e->getResponse());
			}
			break;
/*
		case 'download':
			$vps = vps_load($_GET["vps_id"]);
			
			$xtpl->perex(
				($_GET["timestamp"] == "current") ?
					_("Are you sure you want to download current state of VPS?")
					: _("Are you sure you want to download VPS").' '.$_GET["vps_id"].' from '.strftime("%Y-%m-%d %H:%M", $_GET["timestamp"]).'?'
				, '<a href="?page=backup">'.strtoupper(_("No")).'</a> | <a href="?page=backup&action=download2&vps_id='.$_GET["vps_id"].'&timestamp='.$_GET["timestamp"].'">'.strtoupper(_("Yes")).'</a>'
			);
			break;
		case 'download2':
			$vps = vps_load($_GET["vps_id"]);
			
			$xtpl->perex(
				($_GET["timestamp"] == "current") ?
					_("Download current state of VPS planned")
					: _("Download of backup from ").strftime("%Y-%m-%d %H:%M", $_GET["timestamp"])." ".strtolower(_("planned"))
				, _("Preparing the archive may take several hours. You will receive email with download link when it is done.")
			);
			$vps->download_backup($_GET["timestamp"]);
			break;
*/
		default:
			$list_backups = true;
	}
	
	if($list_backups) {
		$vpses = $api->vps->list();
		
		foreach ($vpses as $vps) {
			
			$xtpl->table_title(_('VPS ').'#'.$vps->id);
			$xtpl->table_add_category(_('Date and time'));
			$xtpl->table_add_category(_('Approximate size'));
			$xtpl->table_add_category(_('Restore'));
			$xtpl->table_add_category(_('Download'));
			$xtpl->table_add_category(_('Mount'));
			
			$xtpl->form_create('?page=backup&action=restore&vps_id='.$vps->id.'', 'post');
			
			$snapshots = $vps->snapshot->list();
			
			foreach ($snapshots as $snap) {
				$xtpl->table_td(strftime("%Y-%m-%d %H:%M", strtotime($snap->created_at)));
				$xtpl->table_td('0');
				$xtpl->form_add_radio_pure("restore_snapshot", $snap->id);
				$xtpl->table_td('[<a href="?page=backup&action=download&vps_id='.$vps->id.'&snapshot='.$snap->id.'">'._("Download").'</a>]');
				$xtpl->table_td('[<a href="?page=backup&action=mount&vps_id='.$vps->id.'&snapshot='.$snap->id.'">'._("Mount").'</a>]');
				$xtpl->table_tr();
			}
			
			$xtpl->table_td('<a href="?page=backup&action=snapshot&vps_id='.$vps->id.'">'._('Make a snapshot NOW').'</a>');
			$xtpl->table_td($xtpl->html_submit(_("Restore"), "restore"));
			$xtpl->table_tr();
			
			$xtpl->form_out_raw();
			
		}
	}

} else $xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
