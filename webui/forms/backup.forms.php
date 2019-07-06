<?php

function backup_crossroad_form() {
	global $xtpl;

	$xtpl->perex('',
		'<h3><a href="?page=backup&action=vps">VPS backups</a></h3>'.
		'<h3><a href="?page=backup&action=nas">NAS backups</a></h3>'.
		'<h3><a href="?page=backup&action=downloads">Downloads</a></h3>'
	);
}

function backup_submenu() {
	global $xtpl;

	$xtpl->sbar_add(_("VPS backups"), '?page=backup&action=vps');
	$xtpl->sbar_add(_("NAS backups"), '?page=backup&action=nas');
	$xtpl->sbar_add(_("Downloads"), '?page=backup&action=downloads');
}

function backup_vps_form() {
	global $xtpl, $api;

	if (isAdmin()) {
		$xtpl->table_title(_('Filters'));
		$xtpl->form_create('', 'get', 'backup-filter', false);

		$xtpl->table_td(_("Limit").':'.
			'<input type="hidden" name="page" value="backup">'.
			'<input type="hidden" name="action" value="vps">'.
			'<input type="hidden" name="list" value="1">'
		);
		$xtpl->form_add_input_pure('text', '40', 'limit', get_val('limit', '25'), '');
		$xtpl->table_tr();

		$xtpl->form_add_input(_("Offset").':', 'text', '40', 'offset', get_val('offset', '0'), '');
		$xtpl->form_add_input(_("Member ID").':', 'text', '40', 'user', get_val('user'), '');
		$xtpl->form_add_input(_("VPS ID").':', 'text', '40', 'vps', get_val('vps'), '');
// 		$xtpl->form_add_input(_("Node ID").':', 'text', '40', 'node', get_val('node'), '');
		$xtpl->form_add_checkbox(_("Include subdatasets").':', 'subdatasets', '1', get_val('subdatasets', '0'));
		$xtpl->form_add_checkbox(_("Ignore datasets without snapshots").':', 'noempty', '1', get_val('noempty', '0'));

		$xtpl->form_out(_('Show'));

		$vpses = array();
		$params = array(
			'limit' => get_val('limit', 25),
			'offset' => get_val('offset', 0)
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

		if (isAdmin() && !$_GET['subdatasets'])
			$params['limit'] = 1;

		$datasets = $api->dataset->list($params);

		dataset_snapshot_list($datasets, $vps);
	}
}

function backup_nas_form() {
	global $xtpl, $api;

	$datasets = array();

	if (isAdmin()) {
		$xtpl->table_title(_('Filters'));
		$xtpl->form_create('', 'get', 'backup-filter', false);

		$xtpl->table_td(_("Limit").':'.
			'<input type="hidden" name="page" value="backup">'.
			'<input type="hidden" name="action" value="nas">'.
			'<input type="hidden" name="list" value="1">'
		);
		$xtpl->form_add_input_pure('text', '40', 'limit', get_val('limit', '25'), '');
		$xtpl->table_tr();

		$xtpl->form_add_input(_("Offset").':', 'text', '40', 'offset', get_val('offset', '0'), '');
		$xtpl->form_add_input(_("Member ID").':', 'text', '40', 'user', get_val('user'), '');
// 		$xtpl->form_add_input(_("Node ID").':', 'text', '40', 'node', get_val('node'), '');
		$xtpl->form_add_checkbox(_("Include subdatasets").':', 'subdatasets', '1', get_val('subdatasets', '0'));
		$xtpl->form_add_checkbox(_("Ignore datasets without snapshots").':', 'noempty', '1', get_val('noempty', '0'));

		$xtpl->form_out(_('Show'));

		if ($_GET['list']) {
			$params = array(
				'limit' => get_val('limit', 25),
				'offset' => get_val('offset', 0),
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

function backup_download_list_form() {
	global $xtpl, $api;

	$downloads = $api->snapshot_download->list(array(
		'meta' => array('includes' => 'snapshot__dataset,user'))
	);

	if (isAdmin())
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

		if (isAdmin())
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

function backup_download_show_form($id) {
	global $xtpl, $api;

	try {
		$dl = $api->snapshot_download->show($id, [
			'meta' => ['includes' => 'snapshot__dataset,user'],
		]);
	} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
		$xtpl->perex_format_errors(_('Download not found'), $e->getResponse());
		return;
	}

	if (isAdmin()) {
		$xtpl->table_td(_('User').':');
		$xtpl->table_td(user_link($dl->user));
		$xtpl->table_tr();
	}

	if ($dl->snapshot_id) {
		$xtpl->table_td(_('Dataset').':');
		$xtpl->table_td($dl->snapshot->dataset->name);
		$xtpl->table_tr();

		$xtpl->table_td(_('Snapshot').':');
		$xtpl->table_td(tolocaltz($dl->snapshot->created_at, 'Y-m-d H:i'));
		$xtpl->table_tr();
	}

	$xtpl->table_td(_('File name').':');
	$xtpl->table_td($dl->file_name);
	$xtpl->table_tr();

	$xtpl->table_td(_('Size').':');
	$xtpl->table_td($dl->size ? (round($dl->size / 1024, 2) . "&nbsp;GiB") : '---');
	$xtpl->table_tr();

	$xtpl->table_td(_('Expiration').':');
	$xtpl->table_td(tolocaltz($dl->expiration_date, 'Y-m-d'));
	$xtpl->table_tr();

	$xtpl->table_td(_('Download link').':');
	$xtpl->table_td($dl->ready ? '<a href="'.$dl->url.'">'._('download').'</a>' : _('preparing'));
	$xtpl->table_tr();

	$xtpl->table_out();

	$xtpl->sbar_add(
		'<br>'._('Remove download'),
		'?page=backup&action=download_destroy&id='.$dl->id
	);
}
