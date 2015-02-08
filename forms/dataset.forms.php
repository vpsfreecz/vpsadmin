<?php

$DATASET_PROPERTIES = array('compression', 'recordsize', 'atime', 'relatime', 'sync');

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

function dataset_quota_unitize($val) {
	$units = array("t" => 19, "g" => 9, "m" => 0);
	
	if (!$val)
		return array(0, "g");
	
	foreach ($units as $u => $ex) {
		if ($val >= (2 << $ex))
			return array($val / (2 << $ex), $u);
	}
	
	return array($val, "m");
}

function dataset_list($role, $parent) {
	global $xtpl, $api;
	
	$params = $api->dataset->list->getParameters('output');
	$ignore = array('id', 'name', 'parent', 'user');
	$include = array('quota', 'refquota', 'used', 'avail');
	$colspan = 4 + count($include);
	
	$xtpl->table_add_category(_('Dataset'));
	
	foreach ($params as $name => $desc) {
		if (!in_array($name, $include))
			continue;
		
		$xtpl->table_add_category($desc->label);
	}
	
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	
	$datasets = $api->dataset->list(array('dataset' => $parent));
	
	foreach ($datasets as $ds) {
		$xtpl->table_td($ds->name);
		
		foreach ($params as $name => $desc) {
			if (!in_array($name, $include))
				continue;
			
			$xtpl->table_td(
				$desc->type == 'Integer' ? nas_size_to_humanreadable($ds->{$name}) : $ds->{$name}
			);
		}
		
		$return = urlencode($_SERVER['REQUEST_URI']);
		
		$xtpl->table_td('<a href="?page=dataset&action=new&role='.$role.'&parent='.$ds->id.'&return='.$return.'"><img src="template/icons/vps_add.png" title="'._("Create a subdataset").'"></a>');
		$xtpl->table_td('<a href="?page=dataset&action=edit&role='.$role.'&id='.$ds->id.'&return='.$return.'"><img src="template/icons/edit.png" title="'._("Edit").'"></a>');
		$xtpl->table_td('<a href="?page=dataset&action=destroy&id='.$ds->id.'"><img src="template/icons/delete.png" title="'._("Delete").'"></a>');
		
		$xtpl->table_tr();
	}
	
	$xtpl->table_td(
		'<a href="?page=dataset&action=new&role='.$role.'&parent='.$parent.'&return='.urlencode($_SERVER['REQUEST_URI']).'">'._('Create a new dataset').'</a>',
		false,
		true, // right
		$colspan // colspan
	);
	$xtpl->table_tr();
	
	$xtpl->table_out();
}

function dataset_create_form() {
	global $xtpl, $api, $DATASET_PROPERTIES;
	
	$params = $api->dataset->create->getParameters('input');
	$quota_name = $_GET['role'] == 'hypervisor' ? 'refquota' : 'quota';
	
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
	$v = dataset_quota_unitize($_POST[$quota_name] ? $_POST[$quota_name] : $quota->default);
	
	$xtpl->table_td(
		$quota->label . ' ' .
		'<input type="hidden" name="return" value="'.($_GET['return'] ? $_GET['return'] : $_POST['return']).'">'
	);
	$xtpl->form_add_input_pure('text', '30', $quota_name, $v[0], $quota->description);
	$xtpl->form_add_select_pure('quota_unit', array("m" => "MiB", "g" => "GiB", "t" => "TiB"), $v[1]);
	$xtpl->table_tr();
	
	// Remaining dataset properties
	foreach ($DATASET_PROPERTIES as $name) {
		if ($name != 'quota' && $name != 'refquota')
			$override = $params->{$name}->label . '<br>'
			.'<input type="checkbox" name="override_'.$name.'" value="1"> '
			._('Override');
		else
			$override = $params->{$name}->label;
		
		$xtpl->table_td($override);
		api_param_to_form_pure($name, $params->{$name});
		$xtpl->table_td($params->{$name}->description);
		
		$xtpl->table_tr();
	}
	
	$xtpl->form_out(_('Save'));
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
		$v = dataset_quota_unitize($ds->{$quota_name});
	
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
			$override = $params->{$name}->label . '<br>'
			.'<input type="checkbox" name="override_'.$name.'" value="1" '.($ds->{$name} == $params->{$name}->default ? '' : 'checked').'> '
			._('Override');
		else
			$override = $params->{$name}->label;
		
		$xtpl->table_td($override);
		api_param_to_form_pure($name, $params->{$name}, $ds->{$name});
		$xtpl->table_td($params->{$name}->description);
		
		$xtpl->table_tr();
	}
	
	$xtpl->form_out(_('Save'));
}

