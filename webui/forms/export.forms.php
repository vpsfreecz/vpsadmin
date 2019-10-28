<?php

function export_list() {
	global $xtpl, $api;

	$xtpl->title(_('NFS exports'));

	$xtpl->sbar_add(_("Export dataset"), '?page=export&action=export_dataset');

	$params = [
		'meta' => ['includes' => 'dataset,snapshot,host_ip_address,user'],
	];

	if (isAdmin()) {
		$xtpl->table_title(_('Filters'));
		$xtpl->form_create('', 'get', 'export-filter', false);

		$xtpl->table_td(_("Limit").':'.
			'<input type="hidden" name="page" value="export">'
		);
		$xtpl->form_add_input_pure('text', '40', 'limit', get_val('limit', '25'), '');
		$xtpl->table_tr();

		$xtpl->form_add_input(_("Offset").':', 'text', '40', 'offset', get_val('offset', '0'), '');
		$xtpl->form_add_input(_("User ID").':', 'text', '40', 'user', get_val('user'));

		$xtpl->form_out(_('Show'));

		$params['limit'] = get_val('limit', 25);
		$params['offset'] = get_val('offset', 0);

		if ($_GET['user'])
			$params['user'] = $_GET['user'];
	}

	if (isAdmin())
		$xtpl->table_add_category(_('User'));

	$xtpl->table_add_category(_('Dataset'));
	$xtpl->table_add_category(_('Snapshot'));
	$xtpl->table_add_category(_('Address'));
	$xtpl->table_add_category(_('Path'));
	$xtpl->table_add_category(_('Enabled'));
	$xtpl->table_add_category(_('Expiration'));
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');

	$exports = $api->export->list($params);

	foreach ($exports as $ex) {
		if (isAdmin())
			$xtpl->table_td(user_link($ex->user));

		$xtpl->table_td($ex->dataset->name);
		$xtpl->table_td($ex->snapshot_id ? $ex->snapshot->created_at : '-');
		$xtpl->table_td($ex->host_ip_address->addr);
		$xtpl->table_td($ex->path);
		$xtpl->table_td(boolean_icon($ex->enabled));
		$xtpl->table_td($ex->expiration_date ? tolocaltz($ex->expiration_date, 'Y-m-d H:i') : '---');
		$xtpl->table_td('<a href="?page=export&action=edit&export='.$ex->id.'"><img src="template/icons/edit.png" title="'._("Edit").'"></a>');
		$xtpl->table_td('<a href="?page=export&action=destroy&export='.$ex->id.'"><img src="template/icons/delete.png" title="'._("Delete").'"></a>');
		$xtpl->table_tr();
	}

	$xtpl->table_out();
}

function export_dataset_form() {
	global $xtpl, $api;

	$xtpl->title(_('Select dataset to export'));
	$xtpl->sbar_add(_("Back"), '?page=export');

	$xtpl->form_create('?page=export&action=export_dataset', 'post');
	$xtpl->form_add_select(
		_('Dataset').':',
		'dataset',
		resource_list_to_options($api->dataset->list([
			'role' => 'primary',
		]), 'id', 'name'),
		post_val('dataset')
	);
	$xtpl->form_out(_('Continue'));
}

function export_create_form($dataset_id, $snapshot_id) {
	global $xtpl, $api;

	$xtpl->sbar_add(_("Back"), '?page=export');

	$ds = $api->dataset->show($dataset_id);

	if ($snapshot_id)
		$snap = $ds->snapshot->show($snapshot_id);
	else
		$snap = null;

	$xtpl->title(_('Create NFS export'));
	$xtpl->form_create('?page=export&action=create&dataset='.$ds->id.'&snapshot='.$snapshot_id, 'post');

	if (isAdmin()) {
		$xtpl->table_td(_('User').':');
		$xtpl->table_td(user_link($ds->user));
		$xtpl->table_tr();
	}

	$xtpl->table_td(_('Dataset').':');
	$xtpl->table_td($ds->name);
	$xtpl->table_tr();

	if ($snap) {
		$xtpl->table_td(_('Snapshot').':');
		$xtpl->table_td(tolocaltz($snap->created_at));
		$xtpl->table_tr();
	}

	$input = $api->export->create->getParameters('input');
	$params = ['all_vps', 'rw', 'sync', 'subtree_check', 'root_squash'];

	if (isAdmin())
		$params[] = 'threads';

	foreach ($params as $p) {
		api_param_to_form($p, $input->{$p}, $ex->{$p});
	}

	$xtpl->form_add_checkbox(
		_('Start').':',
		'enabled',
		'1',
		post_val('enabled', true),
		_('Start the NFS server.')
	);

	$xtpl->form_out(_('Create'));
}

function export_edit_form($id) {
	global $xtpl, $api;

	$ex = $api->export->show($id);

	$xtpl->sbar_add(_("Back"), '?page=export');
	$xtpl->sbar_add(_("Add host"), '?page=export&action=add_host&export='.$ex->id);
	$xtpl->sbar_add(_("Destroy"), '?page=export&action=destroy&export='.$ex->id);

	$xtpl->title(_('NFS export').' #'.$ex->id);

	if (isAdmin()) {
		$xtpl->table_td(_('User').':');
		$xtpl->table_td(user_link($ex->user));
		$xtpl->table_tr();
	}

	$xtpl->table_td(_('Dataset').':');
	$xtpl->table_td($ex->dataset->name);
	$xtpl->table_tr();

	if ($ex->snapshot_id) {
		$xtpl->table_td(_('Snapshot').':');
		$xtpl->table_td(tolocaltz($ex->snapshot->created_at));
		$xtpl->table_tr();
	}

	$xtpl->table_td(_('Address').':');
	$xtpl->table_td($ex->host_ip_address->addr);
	$xtpl->table_tr();

	$xtpl->table_td(_('Path').':');
	$xtpl->table_td($ex->path);
	$xtpl->table_tr();

	$xtpl->table_td(_('Mount path').':');
	$xtpl->table_td($ex->host_ip_address->addr.':'.$ex->path);
	$xtpl->table_tr();

	if ($ex->expiration_date) {
		$xtpl->table_td(_('Expiration').':');
		$xtpl->table_td(tolocaltz($ex->expiration_date, 'Y-m-d H:i'));
		$xtpl->table_tr();
	}

	$xtpl->table_out();

	$xtpl->table_title(_('Default parameters'));
	$xtpl->form_create('?page=export&action=edit&export='.$ex->id, 'post');

	$input = $api->export->update->getParameters('input');
	$params = ['all_vps', 'rw', 'sync', 'subtree_check', 'root_squash'];

	if (isAdmin())
		$params[] = 'threads';

	foreach ($params as $p) {
		api_param_to_form($p, $input->{$p}, $ex->{$p});
	}

	$xtpl->form_out(_('Save'));

	$xtpl->table_title(_('Status'));
	$xtpl->form_create('?page=export&action='.($ex->enabled ? 'disable' : 'enable').'&export='.$ex->id, 'post');
	$xtpl->table_td(_('Status').':');

	if ($ex->enabled)
		$xtpl->table_td(_('NFS server is running, the export can be mounted.'));
	else
		$xtpl->table_td(_('NFS server is stopped, the export cannot mounted.'));
	$xtpl->table_tr();
	$xtpl->form_out($ex->enabled ? _('Stop') : _('Start'));

	$xtpl->table_title(_('Hosts'));
	$hosts = $ex->host->list();

	$xtpl->table_add_category(_('Address'));
	$xtpl->table_add_category(_('RW'));
	$xtpl->table_add_category(_('Sync'));
	$xtpl->table_add_category(_('Subtree check'));
	$xtpl->table_add_category(_('Root squash'));
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');

	foreach ($hosts as $h) {
		$xtpl->table_td($h->ip_address->addr.'/'.$h->ip_address->prefix);
		$xtpl->table_td(boolean_icon($h->rw));
		$xtpl->table_td(boolean_icon($h->sync));
		$xtpl->table_td(boolean_icon($h->subtree_check));
		$xtpl->table_td(boolean_icon($h->root_squash));
		$xtpl->table_td('<a href="?page=export&action=edit_host&export='.$ex->id.'&host='.$h->id.'"><img src="template/icons/edit.png" title="'._("Edit").'"></a>');
		$xtpl->table_td('<a href="?page=export&action=del_host&export='.$ex->id.'&host='.$h->id.'&t='.csrf_token().'"><img src="template/icons/delete.png" title="'._("Delete").'"></a>');
		$xtpl->table_tr();
	}

	$xtpl->table_td('<a href="?page=export&action=add_host&export='.$ex->id.'">'._('Add host').'</a>', false, true, '7');
	$xtpl->table_tr();

	$xtpl->table_out();

	$xtpl->table_title(_('Mount command'));
	$xtpl->table_td("
		<textarea rows=\"1\" cols=\"80\" readonly>
mount -t nfs {$ex->host_ip_address->addr}:{$ex->path} /mnt/export-{$ex->id}
		</textarea>
	");
	$xtpl->table_tr();
	$xtpl->table_out();

	$xtpl->table_title(_('fstab entry'));
	$xtpl->table_td("
		<textarea rows=\"1\" cols=\"80\" readonly>
{$ex->host_ip_address->addr}:{$ex->path} /mnt/export-{$ex->id} nfs vers=3 0 0
		</textarea>
	");
	$xtpl->table_tr();
	$xtpl->table_out();

	$xtpl->table_title(_('systemd mount unit'));
	$xtpl->table_td("
		<textarea rows=\"15\" cols=\"80\" readonly>
# /etc/systemd/system/export\\x2d{$ex->id}.mount
[Unit]
Description=Mount of export {$ex->id}
Requires=network-online.target
After=network-online.target

[Mount]
What={$ex->host_ip_address->addr}:{$ex->path}
Where=/mnt/export-{$ex->id}
Options=vers=3
Type=nfs

[Install]
WantedBy=multi-user.target
		</textarea>
	");
	$xtpl->table_tr();
	$xtpl->table_out();
}

function export_destroy_form($id) {
	global $xtpl, $api;

	$ex = $api->export->show($id);

	$xtpl->sbar_add(_("Back to list"), '?page=export');
	$xtpl->sbar_add(_("Back to details"), '?page=export&action=edit&export='.$ex->id);

	$xtpl->title(_('Confirm deletion of NFS export').' #'.$ex->id);
	$xtpl->form_create('?page=export&action=destroy&export='.$ex->id, 'post');

	if (isAdmin()) {
		$xtpl->table_td(_('User').':');
		$xtpl->table_td(user_link($ex->user));
		$xtpl->table_tr();
	}

	$xtpl->table_td(_('Dataset').':');
	$xtpl->table_td($ex->dataset->name);
	$xtpl->table_tr();

	if ($ex->snapshot_id) {
		$xtpl->table_td(_('Snapshot').':');
		$xtpl->table_td(tolocaltz($ex->snapshot->created_at));
		$xtpl->table_tr();
	}

	$xtpl->table_td(_('Address').':');
	$xtpl->table_td($ex->host_ip_address->addr);
	$xtpl->table_tr();

	$xtpl->table_td(_('Path').':');
	$xtpl->table_td($ex->path);
	$xtpl->table_tr();

	$xtpl->table_td(_('Mount path').':');
	$xtpl->table_td($ex->host_ip_address->addr.':'.$ex->path);
	$xtpl->table_tr();

	$xtpl->table_td(
		_('Stop the NFS server and remove the export. Data on the exported '.
		  'dataset are not affected by this operation.'),
		false, false, '2'
	);
	$xtpl->table_tr();

	$xtpl->form_add_checkbox(
		_('Confirm').':',
		'confirm',
		'1',
		post_val('confirm', false)
	);

	$xtpl->form_out(_('Delete export'));
}

function export_host_add_form($export_id) {
	global $xtpl, $api;

	$ex = $api->export->show($export_id);

	$xtpl->sbar_add(_("Back"), '?page=export&action=edit&export='.$ex->id);

	$xtpl->title(_('NFS export').' #'.$ex->id.': '._('add host'));

	$xtpl->form_create('?page=export&action=add_host&export='.$ex->id, 'post');

	$addr_filters = [
		'version' => 4,
		'assigned' => true,
		'limit' => 50,
		'meta' => ['includes' => 'network_interface__vps'],
	];

	if (isAdmin())
		$addr_filters['user'] = $ex->user_id;

	$xtpl->form_add_select(
		_('IPv4 address').':',
		'ip_address',
		resource_list_to_options(
			$api->ip_address->list($addr_filters),
			'id', 'addr', false,
			function($ip) {
				$s = "{$ip->addr}/{$ip->prefix}";

				if ($ip->network_interface_id && $ip->network_interface->vps_id) {
					$vps = $ip->network_interface->vps;
					$s .= " (VPS #{$vps->id} {$vps->hostname})";
				}

				return $s;
			}
		),
		post_val('ip_address')
	);

	$input = $ex->host->create->getParameters('input');
	$params = ['rw', 'sync', 'subtree_check', 'root_squash'];

	foreach ($params as $p) {
		api_param_to_form($p, $input->{$p}, $ex->{$p});
	}

	$xtpl->form_out(_('Save'));
}

function export_host_edit_form($export_id, $host_id) {
	global $xtpl, $api;

	$ex = $api->export->show($export_id);
	$host = $ex->host->show($host_id);

	$xtpl->sbar_add(_("Back"), '?page=export&action=edit&export='.$ex->id);

	$xtpl->title(_('NFS export').' #'.$ex->id.': '._('host').' '.$host->ip_address->addr.'/'.$host->ip_address->prefix);

	$xtpl->form_create('?page=export&action=edit_host&export='.$ex->id.'&host='.$host->id, 'post');

	$xtpl->table_td(_('Address').':');
	$xtpl->table_td($host->ip_address->addr.'/'.$host->ip_address->prefix);
	$xtpl->table_tr();

	$input = $host->update->getParameters('input');
	$params = ['rw', 'sync', 'subtree_check', 'root_squash'];

	foreach ($params as $p) {
		api_param_to_form($p, $input->{$p}, $host->{$p});
	}

	$xtpl->form_out(_('Save'));
}
