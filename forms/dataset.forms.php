<?php

$DATASET_PROPERTIES = array('compression', 'recordsize', 'atime', 'relatime', 'sync');
$DATASET_UNITS_TR = array("m" => 0, "g" => 9, "t" => 19);

function is_mount_dst_valid($dst) {
	$dst = trim($dst);
	
	if(!preg_match("/^[a-zA-Z0-9\_\-\/\.]+$/", $dst) || preg_match("/\.\./", $dst))
		return false;
	
	if (strpos($dst, "/") !== 0)
		$dst = "/" . $dst;
	
	return $dst;
}

function is_ds_valid($p) {
	$p = trim($p);
	
	if(preg_match("/^\//", $p))
		return false;
	
	if(!preg_match("/^[a-zA-Z0-9\/\-\:\.\_]+$/", $p))
		return false;
	
	if(preg_match("/\/\//", $p))
		return false;
	
	return $p;
}

function dataset_list($role, $parent = null, $user = null, $dataset = null, $limit = null, $offset = null) {
	global $xtpl, $api;
	
	$params = $api->dataset->list->getParameters('output');
	$ignore = array('id', 'name', 'parent', 'user');
	$include = array('used', 'referenced', 'avail');

	if ($role == 'primary')
		$include[] = 'quota';
	else
		$include[] = 'refquota';

	$colspan = 5 + count($include);
	
	$xtpl->table_title(_('Datasets'));
	
	if (isset($_SESSION['is_admin']))
		$xtpl->table_add_category('#');
	
	$xtpl->table_add_category(_('Dataset'));
	
	foreach ($params as $name => $desc) {
		if (!in_array($name, $include))
			continue;
		
		$xtpl->table_add_category($desc->label);
	}
	
	$xtpl->table_add_category(_('Mount'));
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	
	$listParams = array(
		'role' => $role,
		'dataset' => $parent
	);
	
	if ($user)
		$listParams['user'] = $user;
	
	if ($dataset)
		$listParams['dataset'] = $dataset;
	
	if ($limit)
		$listParams['limit'] = $limit;
	
	if ($offset)
		$listParams['offset'] = $offset;
	
	$datasets = $api->dataset->list($listParams);
	$return = urlencode($_SERVER['REQUEST_URI']);
	
	foreach ($datasets as $ds) {
		if (isset($_SESSION['is_admin']))
			$xtpl->table_td(
				'<a href="?page=nas&action=list&dataset='.$ds->id.'">'.$ds->id.'</a>'
			);
		
		$xtpl->table_td($ds->name);
		
		foreach ($params as $name => $desc) {
			if (!in_array($name, $include))
				continue;
			
			$xtpl->table_td(
				$desc->type == 'Integer' ? data_size_to_humanreadable($ds->{$name}) : $ds->{$name}
			);
		}
		
		$xtpl->table_td('<a href="?page=dataset&action=mount&dataset='.$ds->id.'&vps='.$_GET['veid'].'&return='.$return.'">'._('Mount').'</a>');
		$xtpl->table_td('<a href="?page=dataset&action=new&role='.$role.'&parent='.$ds->id.'&return='.$return.'"><img src="template/icons/vps_add.png" title="'._("Create a subdataset").'"></a>');
		$xtpl->table_td('<a href="?page=dataset&action=edit&role='.$role.'&id='.$ds->id.'&return='.$return.'"><img src="template/icons/edit.png" title="'._("Edit").'"></a>');
		$xtpl->table_td('<a href="?page=dataset&action=destroy&id='.$ds->id.'&return='.$return.'"><img src="template/icons/delete.png" title="'._("Delete").'"></a>');
		
		$xtpl->table_tr();
	}
	
	$xtpl->table_td(
		'<a href="?page=dataset&action=new&role='.$role.'&parent='.$parent.'&return='.$return.'">'._('Create a new dataset').'</a>',
		false,
		true, // right
		$colspan // colspan
	);
	$xtpl->table_tr();
	
	$xtpl->table_out();
	
	$xtpl->sbar_add(_('Create dataset'), '?page=dataset&action=new&role='.$role.'&parent='.$parent.'&return='.urlencode($_SERVER['REQUEST_URI']));
}

function dataset_create_form() {
	global $xtpl, $api, $DATASET_PROPERTIES;
	
	$params = $api->dataset->create->getParameters('input');
	$quota_name = $_GET['role'] == 'hypervisor' ? 'refquota' : 'quota';
	
	if ($_GET['parent']) {
		$ds = $api->dataset->find($_GET['parent']);
		$xtpl->table_title(_('Create a new subdataset in').' '.$ds->name);
		
	} else
		$xtpl->table_title(_('Create a new dataset'));
	
	$xtpl->form_create('?page=dataset&action=new&role='.$_GET['role'].'&parent='.$_GET['parent'], 'post');
	
	if ($_GET['parent']) {
		$ds = $api->dataset->find($_GET['parent']);
		
		$xtpl->table_td($params->dataset->label);
		$xtpl->table_td($ds->name);
		$xtpl->table_tr();
		
	} else {
		$xtpl->form_add_select(
			$params->dataset->label,
			'dataset',
			resource_list_to_options($api->dataset->list(array('role' => $_GET['role'])), 'id', 'name'),
			$_POST['dataset'],
			$params->dataset->description
		);
	}
	
	$xtpl->form_add_input(_('Name'), 'text', '30', 'name', $_POST['name'],
		_('Do not prefix with VPS ID. Allowed characters: a-z A-Z 0-9 _ : .<br>'
		.'Use / as a separator to create subdatasets. Max length 254 chars.'));
	$xtpl->form_add_checkbox(_("Auto mount"), 'automount', '1', true, $params->automount->description);
	
	
	// Quota
	$quota = $params->{$quota_name};
	
	if (!$_POST[$quota_name])
		$v = data_size_unitize($_POST[$quota_name] ? $_POST[$quota_name] : $quota->default);
	
	$xtpl->table_td(
		$quota->label . ' ' .
		'<input type="hidden" name="return" value="'.($_GET['return'] ? $_GET['return'] : $_POST['return']).'">'
	);
	$xtpl->form_add_input_pure('text', '30', $quota_name, $_POST[$quota_name] ? $_POST[$quota_name] : $v[0], $quota->description);
	$xtpl->form_add_select_pure('quota_unit', array("m" => "MiB", "g" => "GiB", "t" => "TiB"), $_POST[$quota_name] ? $_POST['quota_unit'] : $v[1]);
	$xtpl->table_tr();
	
	// Remaining dataset properties
	foreach ($DATASET_PROPERTIES as $name) {
		if ($name != 'quota' && $name != 'refquota')
			$inherit = $params->{$name}->label . '<br>'
			.'<input type="checkbox" name="inherit_'.$name.'" value="1" checked> '
			._('Inherit');
		else
			$inherit = $params->{$name}->label;
		
		$xtpl->table_td($inherit);
		api_param_to_form_pure($name, $params->{$name});
		$xtpl->table_td($params->{$name}->description);
		
		$xtpl->table_tr();
	}
	
	$xtpl->form_out(_('Save'));
	
	$xtpl->sbar_add(_("Back"), $_GET['return'] ? $_GET['return'] : $_POST['return']);
	$xtpl->sbar_out(_('Dataset'));
}

function dataset_edit_form() {
	global $xtpl, $api, $DATASET_PROPERTIES;
	
	$ds = $api->dataset->find($_GET['id']);
	
	$params = $api->dataset->update->getParameters('input');
	$quota_name = $_GET['role'] == 'hypervisor' ? 'refquota' : 'quota';
	
	$xtpl->table_title(_('Edit dataset').' '.$ds->name);
	$xtpl->form_create('?page=dataset&action=edit&role='.$_GET['role'].'&id='.$ds->id, 'post');
	
	// Quota
	$quota = $params->{$quota_name};
	
	if (!$_POST[$quota_name])
		$v = data_size_unitize($ds->{$quota_name});
	
	$xtpl->table_td(
		$quota->label . ' ' .
		'<input type="hidden" name="return" value="'.($_GET['return'] ? $_GET['return'] : $_POST['return']).'">'
	);
	$xtpl->form_add_input_pure('text', '30', $quota_name, $_POST[$quota_name] ? $_POST[$quota_name] : $v[0], $quota->description);
	$xtpl->form_add_select_pure('quota_unit', array("m" => "MiB", "g" => "GiB", "t" => "TiB"), $_POST[$quota_name] ? $_POST['quota_unit'] : $v[1]);
	$xtpl->table_tr();
	
	if ($_SESSION['is_admin']) {
		api_param_to_form('admin_override', $params->admin_override);
		api_param_to_form('admin_lock_type', $params->admin_lock_type);
	}
	
	// Remaining dataset properties
	foreach ($DATASET_PROPERTIES as $name) {
		if ($name != 'quota' && $name != 'refquota')
			$inherit = $params->{$name}->label . '<br>'
			.'<input type="checkbox" name="inherit_'.$name.'" value="1" '.($ds->{$name} == $params->{$name}->default ? 'checked' : 'disabled').'> '
			._('Inherit');
		else
			$inherit = $params->{$name}->label;
		
		$xtpl->table_td($inherit);
		api_param_to_form_pure($name, $params->{$name}, $ds->{$name});
		$xtpl->table_td($params->{$name}->description);
		
		$xtpl->table_tr();
	}
	
	$xtpl->form_out(_('Save'));
	
	$xtpl->table_title(_('Backup plans'));
	
	$plans = $ds->plan->list();
	
	$xtpl->form_create('?page=dataset&action=plan_add&role='.$_GET['role'].'&id='.$ds->id, 'post');
	$xtpl->table_add_category(_('Label'));
	$xtpl->table_add_category(_('Description'));
	$xtpl->table_add_category('');
	
	foreach ($plans as $plan) {
		$xtpl->table_td($plan->environment_dataset_plan->label);
		$xtpl->table_td($plan->environment_dataset_plan->dataset_plan->description);
		$xtpl->table_td('<a href="?page=dataset&action=plan_delete&id='.$ds->id.'&plan='.$plan->id.'&return='.urlencode($_GET['return'] ? $_GET['return'] : $_POST['return']).'&t='.csrf_token().'"><img src="template/icons/delete.png" title="'._("Delete").'"></a>');
		$xtpl->table_tr();
	}
	
	$xtpl->table_td(
		_('Add backup plan').':'. ' ' .
		'<input type="hidden" name="return" value="'.($_GET['return'] ? $_GET['return'] : $_POST['return']).'">'
	);
	$xtpl->form_add_select_pure('environment_dataset_plan', resource_list_to_options($ds->environment->dataset_plan->list()));
	$xtpl->table_td('');
	$xtpl->table_tr();
	
	$xtpl->form_out(_('Add'));
	
	$xtpl->sbar_add(_("Back"), $_GET['return'] ? $_GET['return'] : $_POST['return']);
	$xtpl->sbar_out(_('Dataset'));
}

function dataset_snapshot_list($datasets, $vps = null) {
	global $xtpl, $api;
	
	$return_url = urlencode($_SERVER['REQUEST_URI']);
	
	foreach ($datasets as $ds) {
		$snapshots = $ds->snapshot->list(array('meta' => array('includes' => 'mount')));
		
		if (!$snapshots->count() && $_GET['noempty'])
			continue;
		
		$xtpl->table_title(
			$vps && $ds->id == $vps->dataset_id ? _('VPS').' #'.$vps->id : $ds->name
		);
		
		$xtpl->table_add_category(_('Date and time'));
		$xtpl->table_add_category(_('Restore'));
		$xtpl->table_add_category(_('Download'));
		$xtpl->table_add_category(_('Mount'));
		
		$xtpl->form_create('?page=backup&action=restore&dataset='.$ds->id.'&vps_id='.($vps ? $vps->id : '').'&return='.$return_url, 'post');
		
		foreach ($snapshots as $snap) {
			$xtpl->table_td(strftime("%Y-%m-%d %H:%M", strtotime($snap->created_at)));
			$xtpl->form_add_radio_pure("restore_snapshot", $snap->id);
			$xtpl->table_td('[<a href="?page=backup&action=download&dataset='.$ds->id.'&snapshot='.$snap->id.'&return='.$return_url.'">'._("Download").'</a>]');
			
			if ($snap->mount_id)
				$xtpl->table_td(_('mounted to').' <a href="?page=adminvps&action=info&veid='.$snap->mount->vps_id.'">#'.$snap->mount->vps_id.'</a>');
			else
				$xtpl->table_td('[<a href="?page=backup&action=mount&vps_id='.$vps->id.'&dataset='.$ds->id.'&snapshot='.$snap->id.'&return='.$return_url.'">'._("Mount").'</a>]');
			
			$xtpl->table_tr();
		}
		
		$xtpl->table_td('<a href="?page=backup&action=snapshot&dataset='.$ds->id.'&return='.$return_url.'&t='.csrf_token().'">'._('Make a snapshot NOW').'</a>', false, false, '2');
		$xtpl->table_td($xtpl->html_submit(_("Restore"), "restore"));
		$xtpl->table_tr();
		
		$xtpl->form_out_raw();
	}
}

function mount_list($vps_id) {
	global $xtpl, $api;
	
	$xtpl->table_title(_('Mounts'));
	
	$xtpl->table_add_category(_('Dataset'));
	$xtpl->table_add_category(_('Snapshot'));
	$xtpl->table_add_category(_('Mountpoint'));
	$xtpl->table_add_category(_('On mount fail'));
	$xtpl->table_add_category(_('State'));
	$xtpl->table_add_category(_('Expiration'));
	$xtpl->table_add_category(_('Action'));
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	
	$mounts = $api->vps($vps_id)->mount->list();
	$return = urlencode($_SERVER['REQUEST_URI']);
	
	foreach ($mounts as $m) {
		$xtpl->table_td($m->dataset->name);
		$xtpl->table_td($m->snapshot_id ? tolocaltz($m->snapshot->created_at, 'Y-m-d H:i'): '---');
		$xtpl->table_td($m->mountpoint);

		$xtpl->table_td(translate_mount_on_start_fail($m->on_start_fail));

		$state = '';

		switch ($m->current_state) {
			case 'created':
				$state = _('About to be mounted');
				break;

			case 'mounted':
				$state = _('Mounted');
				break;

			case 'unmounted':
				$state = _('Unmounted');
				break;

			case 'skipped':
				$state = _('Skipped');
				break;

			case 'delayed':
				$state = _('Trying to mount');
				break;

			case 'waiting':
				$state = _('Waiting for mount');
				break;

			default:
				$state = $m->current_state;
		}

		$xtpl->table_td($state);

		$xtpl->table_td($m->expiration_date ? tolocaltz($m->expiration_date, 'Y-m-d H:i') : '---');
		if ($m->master_enabled) {
			$xtpl->table_td(
				'<a href="?page=dataset&action=mount_toggle&vps='.$vps_id.'&id='.$m->id.'&do='.($m->enabled ? 0 : 1).'&return='.$return.'&t='.csrf_token().'">'.
				($m->enabled ? _('Disable') : _('Enable')).
				'</a>'
			);

		} else {
			$xtpl->table_td(_('Disabled by admin'));
		}

		$xtpl->table_td('<a href="?page=dataset&action=mount_edit&vps='.$vps_id.'&id='.$m->id.'&return='.$return.'"><img src="template/icons/edit.png" title="'._("Edit").'"></a>');
		$xtpl->table_td('<a href="?page=dataset&action=mount_destroy&vps='.$vps_id.'&id='.$m->id.'&return='.$return.'"><img src="template/icons/delete.png" title="'._("Delete").'"></a>');

		$color = false;

		if (!$m->enabled || !$m->master_enabled)
			$color = '#A6A6A6';

		elseif ($m->current_state != 'created' && $m->current_state != 'mounted')
			$color = '#FFCCCC';

		$xtpl->table_tr($color);
	}
	
	$xtpl->table_td(
		'<a href="?page=dataset&action=mount&vps='.$vps_id.'&return='.$return.'">'._('Create a new mount').'</a>',
		false,
		true, // right
		9 // colspan
	);
	$xtpl->table_tr();
	
	$xtpl->table_out();
	
	$xtpl->sbar_add(_('Create mount'), '?page=dataset&action=mount&vps='.$vps_id.'&return='.$return);
}

function mount_create_form() {
	global $xtpl, $api;
	
	$xtpl->table_title(_('Mount dataset'));
	$xtpl->form_create('?page=dataset&action=mount&vps='.$_GET['vps'].'&dataset='.$_GET['dataset'], 'post');
	
	$params = $api->vps->mount->create->getParameters('input');
	
	if (!$_GET['vps']) {
		$xtpl->form_add_select(_('Mount to VPS'), 'vps', resource_list_to_options(
			$api->vps->list(),
			'id',
			'hostname', true,
			function($vps) { return '#'.$vps->id.' '.$vps->hostname; }
		), $_POST['vps']);
		
	} else {
		$vps = $api->vps->find($_GET['vps']);
		
		$xtpl->table_td(_('Mount to VPS'));
		$xtpl->table_td($vps->id . ' <input type="hidden" name="vps" value="'.$vps->id.'">');
		$xtpl->table_tr();
	}
	
	if (!$_GET['dataset']) {
		$xtpl->form_add_select(_('Mount dataset'), 'dataset', resource_list_to_options($api->dataset->list(), 'id', 'name'), $_POST['dataset']);
		
	} else {
		$ds = $api->dataset->find($_GET['dataset']);
		
		$xtpl->table_td(_('Mount dataset'));
		$xtpl->table_td($ds->name . ' <input type="hidden" name="dataset" value="'.$ds->id.'">');
		$xtpl->table_tr();
	}
	
	$xtpl->table_td($params->mountpoint->label . ' <input type="hidden" name="return" value="'.($_GET['return'] ? $_GET['return'] : $_POST['return']).'">');
	api_param_to_form_pure('mountpoint', $params->mountpoint, '');
	$xtpl->table_tr();
	
	$xtpl->table_td($params->mode->label);
	api_param_to_form_pure('mode', $params->mode);
	$xtpl->table_tr();
	
	$xtpl->table_td($params->on_start_fail->label);
	api_param_to_form_pure(
		'on_start_fail',
		$params->on_start_fail,
		post_val('on_start_fail', 'mount_later'),
		translate_mount_on_start_fail
	);
	$xtpl->table_td($params->on_start_fail->description);
	$xtpl->table_tr();
	
	$xtpl->form_out(_('Save'));
	
	$xtpl->sbar_add(_("Back"), $_GET['return'] ? $_GET['return'] : $_POST['return']);
	$xtpl->sbar_out(_('Mount'));
}

function mount_edit_form($vps_id, $mnt_id) {
	global $xtpl, $api;

	$vps = $api->vps->find($vps_id);
	$m = $vps->mount->find($mnt_id);
	$params = $api->vps->mount->create->getParameters('input');
	
	$xtpl->table_title(_('Edit mount of VPS').' '.vps_link($vps).' at '.$m->mountpoint);
	
	$xtpl->form_create('?page=dataset&action=mount_edit&vps='.$vps_id.'&id='.$mnt_id, 'post');

	$xtpl->table_td($params->on_start_fail->label . ' <input type="hidden" name="return" value="'.($_GET['return'] ? $_GET['return'] : $_POST['return']).'">');
	
	api_param_to_form_pure(
		'on_start_fail',
		$params->on_start_fail,
		post_val('on_start_fail', $m->on_start_fail),
		translate_mount_on_start_fail
	);
	$xtpl->table_td($params->on_start_fail->description);
	$xtpl->table_tr();
	
	$xtpl->form_out(_('Save'));
	
	$xtpl->sbar_add(_("Back"), $_GET['return'] ? $_GET['return'] : $_POST['return']);
	$xtpl->sbar_out(_('Mount'));
}

function mount_snapshot_form() {
	global $xtpl, $api;
	
	$ds = $api->dataset->find($_GET['dataset']);
	$snap = $ds->snapshot->find($_GET['snapshot']);
	
	$xtpl->table_title(_('Mount snapshot'));
	$xtpl->form_create('?page=backup&action=mount&vps_id='.$_GET['vps'].'&dataset='.$_GET['dataset'].'&snapshot='.$_GET['snapshot'], 'post');
	
	$params = $api->vps->mount->create->getParameters('input');
	
	$xtpl->form_add_select(
		_('Mount to VPS'),
		'vps',
		resource_list_to_options($api->vps->list(), 'id', 'hostname', true, vps_label),
		$_POST['vps'] ? $_POST['vps'] : $_GET['vps_id']
	);
	
	$xtpl->table_td(_('Mount snapshot'));
	$xtpl->table_td($ds->name.' @ '.$snap->created_at);
	$xtpl->table_tr();
	
	$xtpl->table_td($params->mountpoint->label . ' <input type="hidden" name="return" value="'.($_GET['return'] ? $_GET['return'] : $_POST['return']).'">');
	api_param_to_form_pure('mountpoint', $params->mountpoint, '');
	$xtpl->table_tr();
	
	$xtpl->form_out(_('Save'));
	
	$xtpl->sbar_add(_("Back"), $_GET['return'] ? $_GET['return'] : $_POST['return']);
	$xtpl->sbar_out(_('Mount'));
}

function translate_mount_on_start_fail($v) {
	$start_fail_choices = array(
		'skip' => _('Skip'),
		'mount_later' => _('Mount later'),
		'fail_start' => _('Fail VPS start'),
		'wait_for_mount' => _('Wait until mounted')
	);

	return $start_fail_choices[$v];
}
