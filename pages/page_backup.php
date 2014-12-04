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

function getval($name, $default = '') {
	if (isset($_GET[$name]))
		return $_GET[$name];
	return $default;
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
				
				$msg = '';
				
				if (isset($_GET['dataset'])) {
					$ds = $api->vps($_GET['vps_id'])->dataset->find($_GET['dataset']);
					$msg = _("Are you sure you want to restore dataset").' '.$ds->name.' '._('from VPS').' #'.$_GET["vps_id"].' from '.strftime("%Y-%m-%d %H:%M", strtotime($snap->created_at)).'?';
					
				} else {
					$msg = _("Are you sure you want to restore VPS").' #'.$_GET["vps_id"].' root dataset from '.strftime("%Y-%m-%d %H:%M", strtotime($snap->created_at)).'?';
				}
				
				$xtpl->perex(
					$msg,
					'<a href="?page=backup">'.strtoupper(_("No")).'</a> | <a href="?page=backup&action=restore2&vps_id='.$_GET["vps_id"].'&restore_snapshot='.$snap->id.'&dataset='.$_GET['dataset'].'">'.strtoupper(_("Yes")).'</a>'
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
					_('Restoration scheduled.'),
					_("Restoration")." from ".strftime("%Y-%m-%d %H:%M", strtotime($snap->created_at))." ".strtolower(_("planned"))
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
		if ($_SESSION['is_admin']) {
			$xtpl->table_title(_('Filters'));
			$xtpl->form_create('', 'get');
			
			$xtpl->table_td(_("Limit").':'.
				'<input type="hidden" name="page" value="backup">'.
				'<input type="hidden" name="type" value="vps">'.
				'<input type="hidden" name="list" value="1">'
			);
			$xtpl->form_add_input_pure('text', '40', 'limit', getval('limit', '25'), '');
			$xtpl->table_tr();
			
			$xtpl->form_add_input(_("Offset").':', 'text', '40', 'offset', getval('offset', '0'), '');
			$xtpl->form_add_input(_("Member ID").':', 'text', '40', 'user', getval('user'), '');
			$xtpl->form_add_input(_("VPS ID").':', 'text', '40', 'vps', getval('vps'), '');
	// 		$xtpl->form_add_input(_("Node ID").':', 'text', '40', 'node', getval('node'), '');
			$xtpl->form_add_checkbox(_("Include subdatasets").':', 'subdatasets', '1', getval('subdatasets', '0'));
			
			$xtpl->form_out(_('Show'));
			
			$vpses = array();
			$params = array(
				'limit' => getval('limit', 25),
				'offset' => getval('offset', 0)
			);
			
			if (isset($_GET['user']) && $_GET['user'] !== '') {
				$params['user'] = $_GET['user'];
				
				$vpses = $api->vps->list($params);
				
			} elseif (isset($_GET['vps']) && $_GET['vps'] !== '') {
				$vpses[] = $api->vps->find($_GET['vps']);
				
			} elseif (isset($_GET['list']) && $_GET['list']) {
				$vpses = $api->vps->list($params);
			}
			
		} else {
			$vpses = $api->vps->list();
		}
		
		foreach ($vpses as $vps) {
			
			$xtpl->table_title(_('VPS ').'#'.$vps->id.' '._('root dataset'));
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
			
			if (isset($_GET['subdatasets']) || !$_SESSION['is_admin']) {
				$datasets = $vps->dataset->list();
				
				foreach ($datasets as $ds) {
					if (!$ds->mountpoint)
						continue;
					
					$xtpl->table_title(_('VPS ').'#'.$vps->id.': '.$ds->name);
					$xtpl->table_add_category(_('Dataset'));
					$xtpl->table_add_category(_('Approximate size'));
					$xtpl->table_add_category(_('Restore'));
					$xtpl->table_add_category(_('Download'));
					$xtpl->table_add_category(_('Mount'));
					
					$xtpl->form_create('?page=backup&action=restore&vps_id='.$vps->id.'&dataset='.$ds->id, 'post');
					
					$ds_snapshots = $vps->snapshot->list(array('dataset' => $ds->id));
					
					foreach ($ds_snapshots as $snap) {
						$xtpl->table_td(strftime("%Y-%m-%d %H:%M", strtotime($snap->created_at)));
						$xtpl->table_td('0');
						$xtpl->form_add_radio_pure("restore_snapshot", $snap->id);
						$xtpl->table_td('[<a href="?page=backup&action=download&vps_id='.$vps->id.'&snapshot='.$snap->id.'">'._("Download").'</a>]');
						$xtpl->table_td('[<a href="?page=backup&action=mount&vps_id='.$vps->id.'&snapshot='.$snap->id.'">'._("Mount").'</a>]');
						
						$xtpl->table_tr();
					}
					
					$xtpl->table_td('<a href="?page=backup&action=snapshot&vps_id='.$vps->id.'&dataset='.$ds->id.'">'._('Make a snapshot NOW').'</a>');
					$xtpl->table_td($xtpl->html_submit(_("Restore"), "restore"));
					$xtpl->table_tr();
					
					$xtpl->form_out_raw();
				}
			}
			
		}
	}

} else $xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
