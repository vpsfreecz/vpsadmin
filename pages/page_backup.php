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
	$vps_backups = false;
	$nas_backups = false;
	
	switch ($_GET["action"]) {
		case 'vps':
			$xtpl->title(_("VPS Backups"));
			$vps_backups = true;
			break;
		
		case 'nas':
			$xtpl->title(_("NAS Backups"));
			$nas_backups = true;
			break;
		
		case 'downloads':
			$xtpl->title(_('Downloads'));
			$list_downloads = true;
			break;
		
		case 'snapshot':
			csrf_check();
			
			try {
				$api->dataset($_GET['dataset'])->snapshot->create();
				
				notify_user(_('Snapshot creation scheduled.'), _('Snapshot will be taken momentarily.'));
				redirect($_GET['return'] ? $_GET['return'] : '?page=');
				
			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Snapshot failed'), $e->getResponse());
			}
			break;
		
		case 'restore':
			if (isset($_POST['confirm']) && $_POST['confirm']) {
				csrf_check();
				
				try {
					$ds = $api->dataset->find($_GET['dataset']);
					$snap = $ds->snapshot->find($_POST['restore_snapshot']);
					$snap->rollback();
					
					notify_user(
						_('Restoration scheduled.'),
						_("Restoration of dataset").' '.$ds->name.' '._('from').' '.strftime("%Y-%m-%d %H:%M", strtotime($snap->created_at)).' '._("planned")
					);
					redirect($_POST['return'] ? $_POST['return'] : '?page=backup');
					
				}  catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('Dataset restoration failed'), $e->getResponse());
				}
				
			} else {
				try {
					$ds = $api->dataset->find($_GET['dataset']);
					$snap = $ds->snapshot->find($_POST['restore_snapshot']);
					
					$msg = '';
					
					if ($_GET['vps_id']) {
						$vps = $api->vps->find($_GET['vps_id']);
						
						if ($ds->id == $vps->dataset_id)
							$msg = _("Restore VPS").' #'.$_GET["vps_id"].' root dataset from '.strftime("%Y-%m-%d %H:%M", strtotime($snap->created_at)).'?';
						else
							$msg = _("Restore dataset").' '.$ds->name.' '._('from VPS').' #'.$vps->id.' from '.strftime("%Y-%m-%d %H:%M", strtotime($snap->created_at)).'?';
						
					} else {
						$msg = _("Restore dataset").' '.$ds->name.' '._('from').' '.strftime("%Y-%m-%d %H:%M", strtotime($snap->created_at)).'?';
					}
					
					$xtpl->table_title(_('Confirm the restoration of dataset').' '.$ds->name);
					$xtpl->form_create('?page=backup&action=restore&dataset='.$ds->id.'&vps_id='.$_GET['vps_id'], 'post');
					
					$xtpl->table_td("<strong>$msg</strong>", false, false, '3');
					$xtpl->table_tr();
					
					$xtpl->table_td(_("Confirm") . ' ' .
						'<input type="hidden" name="return" value="'.($_GET['return'] ? $_GET['return'] : $_POST['return']).'">'
						. '<input type="hidden" name="restore_snapshot" value="'.$_POST['restore_snapshot'].'">'
					);
					$xtpl->form_add_checkbox_pure('confirm', '1', false);
					$xtpl->table_td(_('The dataset will be restored and all data that has not been snapshoted will be lost.'));
					$xtpl->table_tr();
					
					$xtpl->form_out(_('Restore dataset'));
					
				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('Dataset or snapshot not found'), $e->getResponse());
				}
			}
			
			break;
		
		case 'download':
			if (isset($_POST['confirm']) && $_POST['confirm']) {
				csrf_check();
				
				try {
					$ds = $api->dataset->find($_GET['dataset']);
					$snap = $ds->snapshot->find($_GET['snapshot']);
					
					$api->snapshot_download->create(array(
						'format' => $_POST['format'],
						'snapshot' => $snap->id,
					));
					
					notify_user(
						  _("Download of snapshot of").' '.$ds->name.' '. _('from').' '.strftime("%Y-%m-%d %H:%M", strtotime($snap->created_at))." "._("planned")
						, _("Preparing the archive may take several hours. You will receive email with download link when it is done.")
					);
					redirect($_POST['return'] ? $_POST['return'] : '?page=backup');
					
				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('Download failed'), $e->getResponse());
				}
				
			} else {
				try {
					$ds = $api->dataset->find($_GET['dataset']);
					$snap = $ds->snapshot->find($_GET['snapshot']);
					
					$xtpl->table_title(_('Confirm the download of snapshot of dataset').' '.$ds->name);
					$xtpl->form_create('?page=backup&action=download&dataset='.$ds->id.'&snapshot='.$snap->id, 'post');

					$xtpl->table_td('<strong>'._('Please confirm the download of snapshot of dataset').' '.$ds->name.' '._('from').' '.strftime("%Y-%m-%d %H:%M", strtotime($snap->created_at)).'</strong>', false, false, '2');
					$xtpl->table_tr();

					$formats = array(
						'archive' => _('tar.gz archive'),
						'stream' => _('ZFS data stream'),
					);
					$xtpl->form_add_select(_('Format').':', 'format', $formats, $_POST['format']);
					
					$xtpl->table_td(_("Confirm") . ' ' .
						'<input type="hidden" name="return" value="'.($_GET['return'] ? $_GET['return'] : $_POST['return']).'">'
					);
					$xtpl->form_add_checkbox_pure('confirm', '1', false);
					$xtpl->table_tr();
					
					$xtpl->form_out(_('Download snapshot'));
					
				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('Dataset or snapshot not found'), $e->getResponse());
				}
			}
			
			break;
		
		case 'mount':
			if (isset($_POST['vps'])) {
				csrf_check();
				
				try {
					$api->vps($_POST['vps'])->mount->create(array(
						'snapshot' => $_GET['snapshot'],
						'mountpoint' => $_POST['mountpoint']
					));
					
					notify_user(_('Snapshot mount in progress'), _('The snapshot will be mounted momentarily.'));
					redirect($_POST['return'] ? $_POST['return'] : '?page=backup');
					
				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('Snapshot mount failed'), $e->getResponse());
					mount_snapshot_form();
				}
				
			} else {
				mount_snapshot_form();
			}
			
			break;
		
		case 'download_destroy':
			if (isset($_POST['confirm']) && $_POST['confirm']) {
				csrf_check();
				
				try {
					$api->snapshot_download($_GET['id'])->delete();
					
					notify_user(_('Download link destroyed'), _('Download link was successfully destroyed.'));
					redirect('?page=backup&action=downloads');
					
				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('Failed to destroy download link'), $e->getResponse());
				}
				
			} else {
				try {
					$dl = $api->snapshot_download->find($_GET['id']);
					
					$xtpl->table_title(_('Confirm the destroyal of snapshow download').' '.$dl->snapshot->created_at);
					$xtpl->form_create('?page=backup&action=download_destroy&id='.$dl->id, 'post');
					
					$xtpl->form_add_checkbox(_("Confirm"), 'confirm', '1', false);
					
					$xtpl->form_out(_('Destroy download link'));
					
				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('Download link cannot be found'), $e->getResponse());
				}
			}
			break;
		
		default:
			$xtpl->perex('',
				'<h3><a href="?page=backup&action=vps">VPS backups</a></h3>'.
				'<h3><a href="?page=backup&action=nas">NAS backups</a></h3>'.
				'<h3><a href="?page=backup&action=downloads">Downloads</a></h3>'
			);
	}
	
	$xtpl->sbar_add(_("VPS backups"), '?page=backup&action=vps');
	$xtpl->sbar_add(_("NAS backups"), '?page=backup&action=nas');
	$xtpl->sbar_add(_("Downloads"), '?page=backup&action=downloads');
	$xtpl->sbar_out(_('Backups'));
	
	if($vps_backups) {
		if ($_SESSION['is_admin']) {
			$xtpl->table_title(_('Filters'));
			$xtpl->form_create('', 'get', 'backup-filter', false);
			
			$xtpl->table_td(_("Limit").':'.
				'<input type="hidden" name="page" value="backup">'.
				'<input type="hidden" name="action" value="vps">'.
				'<input type="hidden" name="list" value="1">'
			);
			$xtpl->form_add_input_pure('text', '40', 'limit', getval('limit', '25'), '');
			$xtpl->table_tr();
			
			$xtpl->form_add_input(_("Offset").':', 'text', '40', 'offset', getval('offset', '0'), '');
			$xtpl->form_add_input(_("Member ID").':', 'text', '40', 'user', getval('user'), '');
			$xtpl->form_add_input(_("VPS ID").':', 'text', '40', 'vps', getval('vps'), '');
	// 		$xtpl->form_add_input(_("Node ID").':', 'text', '40', 'node', getval('node'), '');
			$xtpl->form_add_checkbox(_("Include subdatasets").':', 'subdatasets', '1', getval('subdatasets', '0'));
			$xtpl->form_add_checkbox(_("Ignore datasets without snapshots").':', 'noempty', '1', getval('noempty', '0'));
			
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
			$datasets = $api->dataset->list();
		}
		
		foreach ($vpses as $vps) {
			$params = array('dataset' => $vps->dataset_id);
			
			if ($_SESSION['is_admin'] && !$_GET['subdatasets'])
				$params['limit'] = 1;
			
			$datasets = $api->dataset->list($params);
			
			dataset_snapshot_list($datasets, $vps);
		}
	}
	
	if ($nas_backups) {
		$datasets = array();
		
		if ($_SESSION['is_admin']) {
			$xtpl->table_title(_('Filters'));
			$xtpl->form_create('', 'get', 'backup-filter', false);
			
			$xtpl->table_td(_("Limit").':'.
				'<input type="hidden" name="page" value="backup">'.
				'<input type="hidden" name="action" value="nas">'.
				'<input type="hidden" name="list" value="1">'
			);
			$xtpl->form_add_input_pure('text', '40', 'limit', getval('limit', '25'), '');
			$xtpl->table_tr();
			
			$xtpl->form_add_input(_("Offset").':', 'text', '40', 'offset', getval('offset', '0'), '');
			$xtpl->form_add_input(_("Member ID").':', 'text', '40', 'user', getval('user'), '');
	// 		$xtpl->form_add_input(_("Node ID").':', 'text', '40', 'node', getval('node'), '');
			$xtpl->form_add_checkbox(_("Include subdatasets").':', 'subdatasets', '1', getval('subdatasets', '0'));
			$xtpl->form_add_checkbox(_("Ignore datasets without snapshots").':', 'noempty', '1', getval('noempty', '0'));
			
			$xtpl->form_out(_('Show'));
			
			if ($_GET['list']) {
				$params = array(
					'limit' => getval('limit', 25),
					'offset' => getval('offset', 0),
					'role' => 'primary'
				);
				
				if (!$_GET['subdatasets'])
					$params['to_depth'] = 0;
				
				if (isset($_GET['user']) && $_GET['user'] !== '')
					$params['user'] = $_GET['user'];
				
				$datasets = $api->dataset->list($params);
			}
			
		} else {
			$datasets = $api->dataset->list(array('role' => 'primary'));
		}
		
		dataset_snapshot_list($datasets);
	}
	
	if ($list_downloads) {
		$downloads = $api->snapshot_download->list(array(
			'meta' => array('includes' => 'snapshot__dataset,user'))
		);

		if ($_SESSION['is_admin'])
			$xtpl->table_add_category(_('User'));

		$xtpl->table_add_category(_('Dataset'));
		$xtpl->table_add_category(_('Snapshot'));
		$xtpl->table_add_category(_('File name'));
		$xtpl->table_add_category(_('Size'));
		$xtpl->table_add_category(_('Expiration'));
		$xtpl->table_add_category(_('Download'));
		$xtpl->table_add_category('');
		
		foreach ($downloads as $dl) {
			if (strlen($dl->file_name) > 35)
				$short_name = substr($dl->file_name, 0, 35) . '...';

			else $short_name = $dl->file_name;

			if ($_SESSION['is_admin'])
				$xtpl->table_td('<a href="?page=adminm&action=edit&id='.$dl->user_id.'">'.$dl->user->login.'</a>');
				
			$xtpl->table_td($dl->snapshot_id ? $dl->snapshot->dataset->name : '---');
			$xtpl->table_td($dl->snapshot_id ? tolocaltz($dl->snapshot->created_at, 'Y-m-d H:i') : '---');
			$xtpl->table_td('<span title="'.$dl->file_name.'">'.$short_name.'</span>');
			$xtpl->table_td($dl->size ? (round($dl->size / 1024, 2) . "&nbsp;GiB") : '---');
			$xtpl->table_td(tolocaltz($dl->expiration_date, 'Y-m-d'));
			$xtpl->table_td($dl->ready ? '<a href="'.$dl->url.'">'._('Download').'</a>' : _('in progress'));
			$xtpl->table_td($dl->ready ? '<a href="?page=backup&action=download_destroy&id='.$dl->id.'"><img src="template/icons/delete.png" title="'._("Delete").'"></a>' : '');
			$xtpl->table_tr();
		}
		
		$xtpl->table_out();
	}

} else $xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
