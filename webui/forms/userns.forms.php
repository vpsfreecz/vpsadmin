<?php

function userns_or_map_list() {
	global $xtpl, $api;

	if (isAdmin())
		return userns_list();

	$ret = $api->user_namespace->list(['limit' => 0, 'meta' => ['count' => true]]);
	$cnt = $ret->getTotalCount();

	if ($cnt > 1) {
		return userns_list();

	} elseif ($cnt == 1) {
		return userns_map_list();

	} else {
		$xtpl->perex(
			_("No user namespaces found"),
			_("You do not have any user namespaces at your disposal.")
		);
	}
}

function userns_submenu () {
	global $xtpl;

	$xtpl->sbar_add(_("User namespaces"), '?page=userns&action=list');
	$xtpl->sbar_add(_("UID/GID maps"), '?page=userns&action=maps');
	$xtpl->sbar_add(_("New UID/GID map"), '?page=userns&action=map_new');
}

function userns_list() {
	global $xtpl, $api;

	$xtpl->title(_('User namespaces'));
	$xtpl->table_title(_('Filters'));
	$xtpl->form_create('', 'get', 'userns-list', false);

	$xtpl->table_td(_("Limit").':'.
		'<input type="hidden" name="page" value="userns">'.
		'<input type="hidden" name="action" value="list">'
	);
	$xtpl->form_add_input_pure('text', '40', 'limit', get_val('limit', '25'), '');
	$xtpl->table_tr();

	$input = $api->user_namespace->list->getParameters('input');

	if ($_SESSION['is_admin']) {
		$xtpl->form_add_input(_('User ID').':', 'text', '30', 'user', get_val('user'), '');
		api_param_to_form('block_count', $input->block_count, $_GET['block_count']);
	}

	api_param_to_form('size', $input->size, $_GET['size']);

	$xtpl->form_out(_('Show'));

	$params = [
		'limit' => get_val('limit', 25),
	];

	$filters = [
		'user', 'block_count', 'size'
	];

	foreach ($filters as $v) {
		if ($_GET[$v])
			$params[$v] = $_GET[$v];
	}

	$userns_list = $api->user_namespace->list($params);

	$xtpl->table_add_category(_('ID'));

	if ($_SESSION['is_admin']) {
		$xtpl->table_add_category(_('User'));
		$xtpl->table_add_category(_('Offset'));
		$xtpl->table_add_category(_('Blocks'));
	}

	$xtpl->table_add_category(_('Size'));
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');

	foreach ($userns_list as $uns) {
		$xtpl->table_td(
			'<a href="?page=userns&action=show&id='.$uns->id.'">'.$uns->id.'</a>'
		);

		if ($_SESSION['is_admin']) {
			$xtpl->table_td($uns->user_id ? user_link($uns->user) : '-');
			$xtpl->table_td($uns->offset, false, true);
			$xtpl->table_td($uns->block_count, false, true);
		}

		$xtpl->table_td($uns->size, false, true);
		$xtpl->table_td(
			'<a href="?page=userns&action=maps&user_namespace='.$uns->id.'"><img src="template/icons/vps_ip_list.png" alt="'._('List UID/GID maps').'" title="'._('List UID/GID maps').'"></a>'
		);
		$xtpl->table_td(
			'<a href="?page=userns&action=show&id='.$uns->id.'"><img src="template/icons/vps_edit.png" alt="'._('Details').'" title="'._('Details').'"></a>'
		);
		$xtpl->table_tr();
	}

	$xtpl->table_out();
}

function userns_show ($userns_id) {
	global $xtpl, $api;

	$uns = $api->user_namespace->show($userns_id);

	$xtpl->title(_('User namespace').' #'.$uns->id);

	$xtpl->table_title(_('Info'));
	$xtpl->table_td(_('ID').':');
	$xtpl->table_td($uns->id);
	$xtpl->table_tr();

	if (isAdmin()) {
		$xtpl->table_td(_('User').':');
		$xtpl->table_td($uns->user_id ? user_link($uns->user) : '-');
		$xtpl->table_tr();

		$xtpl->table_td(_('Offset').':');
		$xtpl->table_td($uns->offset);
		$xtpl->table_tr();

		$xtpl->table_td(_('Blocks').':');
		$xtpl->table_td($uns->block_count);
		$xtpl->table_tr();
	}

	$xtpl->table_td(_('Size').':');
	$xtpl->table_td($uns->size);
	$xtpl->table_tr();

	$xtpl->table_out();
}

function userns_map_list ($userns_id = null) {
	global $xtpl, $api;

	$xtpl->table_title(_('UID/GID maps'));
	$xtpl->form_create('', 'get', 'userns-map-list', false);

	$xtpl->table_td(_("Limit").':'.
		'<input type="hidden" name="page" value="userns">'.
		'<input type="hidden" name="action" value="maps">'
	);
	$xtpl->form_add_input_pure('text', '40', 'limit', get_val('limit', '25'), '');
	$xtpl->table_tr();

	$input = $api->user_namespace_map->list->getParameters('input');

	if ($_SESSION['is_admin']) {
		$xtpl->form_add_input(_('User ID').':', 'text', '30', 'user', get_val('user'), '');
		$xtpl->form_add_input(_('User namespace ID').':', 'text', '30', 'user_namespace', get_val('user_namespace'), '');
	}

	$xtpl->form_out(_('Show'));

	$params = [
		'limit' => get_val('limit', 25),
		'meta' => ['includes' => 'user_namespace']
	];

	$filters = [
		'user', 'user_namespace'
	];

	foreach ($filters as $v) {
		if ($_GET[$v])
			$params[$v] = $_GET[$v];
	}

	$maps = $api->user_namespace_map->list($params);

	$xtpl->table_add_category(_('ID'));

	if ($_SESSION['is_admin']) {
		$xtpl->table_add_category(_('User'));
	}

	$xtpl->table_add_category(_('UserNS'));
	$xtpl->table_add_category(_('Label'));
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');

	foreach ($maps as $m) {
		$xtpl->table_td(
			'<a href="?page=userns&action=map_show&id='.$m->id.'">'.$m->id.'</a>'
		);

		if ($_SESSION['is_admin']) {
			$xtpl->table_td(user_link($m->user_namespace->user));
		}

		$xtpl->table_td(
			'<a href="?page=userns&action=show&id='.$m->user_namespace->id.'">'.
			$m->user_namespace->id.
			'</a>'
		);
		$xtpl->table_td($m->label);
		$xtpl->table_td(
			'<a href="?page=userns&action=map_datasets&id='.$m->id.'"><img src="template/icons/vps_ip_list.png" alt="'._('List datasets').'" title="'._('List datasets').'"></a>'
		);
		$xtpl->table_td(
			'<a href="?page=userns&action=map_show&id='.$m->id.'"><img src="template/icons/vps_edit.png" alt="'._('Details').'" title="'._('Details').'"></a>'
		);
		$xtpl->table_td(
			'<a href="?page=userns&action=map_del&id='.$m->id.'&t='.csrf_token().'">'.
			'<img src="template/icons/m_delete.png" title="'._('Delete').'">'.
			'</a>'
		);
		$xtpl->table_tr();
	}

	$xtpl->table_out();
}

function userns_map_show ($map_id) {
	global $xtpl, $api;

	$m = $api->user_namespace_map->show($map_id);

	$xtpl->title(_('UID/GID map').' #'.$m->id.' - '.$m->label);

	$xtpl->form_create('?page=userns&action=map_edit&id='.$m->id, 'post');
	$xtpl->table_td(_('Namespace size').':');
	$xtpl->table_td($m->user_namespace->size);
	$xtpl->table_tr();

	$xtpl->form_add_input(_('Map label').':', 'text', '40', 'label', post_val('label', $m->label), '');
	$xtpl->form_out(_('Save'));

	$xtpl->table_title(_('Map entries'));

	$entries = $m->entry->list();

	$xtpl->form_create('?page=userns&action=map_entries_edit&id='.$m->id, 'post', 'userns-map-entries');
	$xtpl->table_add_category(_('Type'));
	$xtpl->table_add_category(_('ID within namespace'));
	$xtpl->table_add_category(_('ID outside namespace'));
	$xtpl->table_add_category(_('ID count'));
	$xtpl->table_add_category('');

	$i = 0;

	foreach ($entries as $e) {
		$xtpl->table_td(
			strtoupper($e->kind).
			'<input type="hidden" name="entry_id[]" value="'.$e->id.'">'
		);

		$xtpl->form_add_input_pure('text', '14', 'ns_id[]', post_val_array('ns_id', $i, $e->ns_id));
		$xtpl->form_add_input_pure('text', '14', 'host_id[]', post_val_array('host_id', $i, $e->host_id));
		$xtpl->form_add_input_pure('text', '14', 'count[]', post_val_array('count', $i, $e->count));
		$xtpl->table_td(
			'<a href="?page=userns&action=map_entry_del&map='.$m->id.'&entry='.$e->id.'&t='.csrf_token().'">'.
			'<img src="template/icons/m_delete.png" title="'._('Delete').'">'.
			'</a>'
		);
		$xtpl->table_tr();

		$i++;
	}

	$xtpl->form_add_select_pure(
		'new_kind', ['both' => 'UID&GID', 'uid' => 'UID','gid' => 'GID'],
		post_val('new_kind', 'both')
	);
	$xtpl->form_add_input_pure('text', '14', 'new_ns_id', post_val('new_ns_id', 0));
	$xtpl->form_add_input_pure('text', '14', 'new_host_id', post_val('new_host_id', 0));
	$xtpl->form_add_input_pure('text', '14', 'new_count', post_val('new_count', 0));
	$xtpl->table_td($xtpl->html_submit(_('Add'), 'add'));
	$xtpl->table_tr();

	$xtpl->table_td($xtpl->html_submit(_('Save'), 'save'), false, true, 4);
	$xtpl->table_tr();
	$xtpl->form_out_raw();
}

function userns_map_new () {
	global $xtpl, $api;

	$xtpl->table_title(_('Create a new UID/GID map'));
	$xtpl->form_create('?page=userns&action=map_new', 'post');

	$input = $api->user_namespace_map->create->getParameters('input');
	$hidden = '';

	if (isAdmin()) {
		$xtpl->form_add_input(_('User namespace ID').':', 'text', '15', 'user_namespace', post_val('user_namespace'));

	} else {
		$ret = $api->user_namespace->list(['limit' => 1, 'meta' => ['count' => true]]);
		$cnt = $ret->getTotalCount();

		if ($cnt == 1) {
			$hidden = '<input type="hidden" name="user_namespace" value="'.$ret[0]->id.'">';

		} else {
			api_param_to_form(
				'user_namespace',
				$input->user_namespace,
				post_val('user_namespace'),
				function ($userns) {
					return '#'.$userns->id.' ('.$userns->size.' IDs)';
				}
			);
		}
	}

	$xtpl->table_td(_('Label').':'.$hidden);
	$xtpl->form_add_input_pure('text', '30', 'label', post_val('label'));
	$xtpl->table_tr();

	$xtpl->form_out(_('Go >>'));
}

function userns_map_dataset_list ($map_id) {
	global $xtpl, $api;

	$map = $api->user_namespace_map->show($map_id);

	$xtpl->title(
		_('Datasets using UID/GID mapping').' '.
		'<a href="?page=userns&action=map_show&id='.$map->id.'">#'.$map->id.'</a> '.
		$map->label
	);

	dataset_list(
		'hypervisor',
		null, null, null, null, null,
		[
			'title' => _('VPS datasets'),
			'submenu' => false,
			'ugid_map' => $map->id,
		]
	);

	dataset_list(
		'primary',
		null, null, null, null, null,
		[
			'title' => _('NAS datasets'),
			'submenu' => false,
			'ugid_map' => $map->id,
		]
	);
}
