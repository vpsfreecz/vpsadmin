<?php
/*
    ./pages/page_backup.php

    vpsAdmin
    Web-admin interface for OpenVZ (see http://openvz.org)
    Copyright (C) 2008-2011 Pavel Snajdr, snajpa@snajpa.net
*/

if (isLoggedIn()) {
	$vps_backups = false;
	$nas_backups = false;

	backup_submenu();

	switch ($_GET["action"] ?? null) {
		case 'vps':
			$xtpl->title(_("VPS Backups"));
			backup_vps_form();
			break;

		case 'nas':
			$xtpl->title(_("NAS Backups"));
			backup_nas_form();
			break;

		case 'downloads':
			$xtpl->title(_('Downloads'));
			backup_download_list_form();
			break;

		case 'download_link':
			$xtpl->title(_('Download backup'));
			backup_download_show_form($_GET['id']);
			break;

		case 'snapshot':
			$xtpl->sbar_add(_("Back"), $_GET['return'] ?? '?page=backup');

			try {
				$ds = $api->dataset->find($_GET['dataset']);
				$return = urlencode($_GET['return']);

				$xtpl->table_title(_('Create a new snapshot of dataset').' '.$ds->name);
				$xtpl->form_create(
					'?page=backup&action=snapshot_create&dataset='.$ds->id.'&return='.$return,
					'post'
				);

				$xtpl->table_td(_('Dataset').':');
				$xtpl->table_td($ds->name);
				$xtpl->table_tr();

				$xtpl->form_add_input(
					_('Label').':', 'text', '30', 'label', post_val('label'),
					_('Optional user-defined snapshot identificator')
				);

				$xtpl->form_out(_('Go >>'));

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Dataset not found'), $e->getResponse());
			}
			break;

		case 'snapshot_create':
			csrf_check();

			try {
				$api->dataset($_GET['dataset'])->snapshot->create(array(
					'label' => post_val('label', null),
				));

				notify_user(_('Snapshot creation scheduled.'), _('Snapshot will be taken momentarily.'));
				redirect($_GET['return'] ?? '?page=');

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
					redirect($_POST['return'] ?? '?page=backup');

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
						'<input type="hidden" name="return" value="'.($_GET['return'] ?? $_POST['return']).'">'
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

		case 'snapshot_destroy':
			if (isset($_POST['confirm']) && $_POST['confirm']) {
				csrf_check();

				try {
					$api->dataset($_GET['dataset'])->snapshot($_GET['snapshot'])->delete();

					notify_user(
						_('Snapshot deleted'),
						_('The snapshot has been successfully deleted.')
					);
					redirect($_POST['return'] ?? '?page=backup');

				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('Snapshot deletion failed'), $e->getResponse());
				}

			} else {
				try {
					$ds = $api->dataset->find($_GET['dataset']);
					$snap = $ds->snapshot->find($_GET['snapshot']);
					$date = tolocaltz($snap->created_at, 'Y-m-d H:i');

					$xtpl->table_title(_('Confirm snapshot deletion'));
					$xtpl->form_create('?page=backup&action=snapshot_destroy&dataset='.$ds->id.'&snapshot='.$snap->id, 'post');

					$xtpl->table_td(
						'<strong>'._('This action is irreversible.').'</strong>',
						false, false, '2'
					);
					$xtpl->table_tr();

					$xtpl->table_td(_('Dataset').':');
					$xtpl->table_td($ds->name);
					$xtpl->table_tr();

					$xtpl->table_td(_('Snapshot').':');
					$xtpl->table_td($date);
					$xtpl->table_tr();

					$xtpl->table_td(_("Confirm") . ' ' .
						'<input type="hidden" name="return" value="'.($_GET['return'] ?? $_POST['return']).'">'
					);
					$xtpl->form_add_checkbox_pure('confirm', '1', false);
					$xtpl->table_tr();

					$xtpl->form_out(_('Delete'));

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
					redirect($_POST['return'] ?? '?page=backup');

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
						'<input type="hidden" name="return" value="'.($_GET['return'] ?? $_POST['return']).'">'
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
					redirect($_POST['return'] ?? '?page=backup');

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

					$xtpl->table_title(_('Confirm the destroyal of snapshot download').' '.$dl->snapshot->created_at);
					$xtpl->form_create('?page=backup&action=download_destroy&id='.$dl->id, 'post');

					$xtpl->form_add_checkbox(_("Confirm"), 'confirm', '1', false);

					$xtpl->form_out(_('Destroy download link'));

				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('Download link cannot be found'), $e->getResponse());
				}
			}
			break;

		default:
			backup_crossroad_form();
	}

	$xtpl->sbar_out(_('Backups'));

} else $xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
