<?php

function ip_adress_list($title) {
	global $xtpl, $api;
	
	$xtpl->title(_('IP Addresses'));
	$xtpl->table_title(_('Filters'));
	$xtpl->form_create('', 'get', 'ip-filter', false);
		
	$xtpl->table_td(_("Limit").':'.
		'<input type="hidden" name="page" value="cluster">'.
		'<input type="hidden" name="action" value="ip_addresses">'.
		'<input type="hidden" name="list" value="1">'
	);
	$xtpl->form_add_input_pure('text', '40', 'limit', get_val('limit', '25'), '');
	$xtpl->table_tr();
	
	$versions = array(
		0 => 'all',
		4 => '4',
		6 => '6'
	);
	
	$xtpl->form_add_input(_("Offset").':', 'text', '40', 'offset', get_val('offset', '0'), '');
	$xtpl->form_add_select(_("Version").':', 'v', $versions, get_val('v', 0));
	$xtpl->form_add_input(_("User ID").':', 'text', '40', 'user', get_val('user'), _("'unassigned' to list free addresses"));
	$xtpl->form_add_input(_("VPS").':', 'text', '40', 'vps', get_val('vps'), _("'unassigned' to list free addresses"));
	$xtpl->form_add_select(_("Location").':', 'location',
		resource_list_to_options($api->location->list()), get_val('location'));
	
	$xtpl->form_out(_('Show'));
	
	if (!$_GET['list'])
		return;
	
	$params = array(
		'limit' => get_val('limit', 25),
		'offset' => get_val('offset', 0),
		'meta' => array('includes' => 'user,vps,location')
	);
	
	if ($_GET['user'] === 'unassigned')
		$params['user'] = null;
	elseif ($_GET['user'])
		$params['user'] = $_GET['user'];
	
	if ($_GET['vps'] === 'unassigned')
		$params['vps'] = null;
	elseif ($_GET['vps'])
		$params['vps'] = $_GET['vps'];
	
	if ($_GET['location'])
		$params['location'] = $_GET['location'];
	
	if ($_GET['v'])
		$params['version'] = $_GET['v'];
	
	$ips = $api->ip_address->list($params);
	
	$xtpl->table_add_category(_("IP address"));
	$xtpl->table_add_category(_("Location"));
	$xtpl->table_add_category(_('User'));
	$xtpl->table_add_category('VPS');
// 	$xtpl->table_add_category("&nbsp;");
	
	foreach ($ips as $ip) {
		$xtpl->table_td($ip->addr);
		$xtpl->table_td($ip->location->label);
		
		if ($ip->user_id)
			$xtpl->table_td('<a href="?page=adminm&action=edit&id='.$ip->user_id.'">'.$ip->user->login.'</a>');
		else
			$xtpl->table_td('---');
		
		if ($ip->vps_id)
			$xtpl->table_td('<a href="?page=adminvps&action=info&veid='.$ip->vps_id.'">'.$ip->vps_id.' ('.$ip->vps->hostname.')</a>');
		else
			$xtpl->table_td('---');
		
// 		$xtpl->table_td('<a href="?page=cluster&action=ipaddr_delete&ip_id='.$ip->id.'"><img src="template/icons/m_delete.png"  title="'. _("Delete from cluster") .'" /></a>');
		
		$xtpl->table_tr();
	}
	
	$xtpl->table_out();
}

function ip_add_form($ip_addresses = '') {
	global $xtpl, $api;
	
	if (!$ip_addresses && $_POST['ip_addresses'])
		$ip_addresses = $_POST['ip_addresses'];
	
	$xtpl->table_title(_("Add IP addresses"));
	$xtpl->sbar_add(_("Back"), '?page=cluster&action=ip_addresses');
	
	$xtpl->form_create('?page=cluster&action=ipaddr_add2', 'post');
	$xtpl->form_add_textarea(_("IP addresses").':', 40, 10, 'ip_addresses', $ip_addresses);
	$xtpl->form_add_select(_("Location").':', 'location',
		resource_list_to_options($api->location->list()), $_POST['location']);
	$xtpl->form_add_select(_("User").':', 'user',
		resource_list_to_options($api->user->list(), 'id', 'login'), $_POST['user']);
	
	$xtpl->form_out(_("Add"));
}

function dns_delete_form() {
	global $xtpl, $api;
	
	$ns = $api->dns_resolver->find($_GET['id']);
	
	$xtpl->table_title(_("Delete DNS resolver").' '.$ns->label.' ('.$ns->ip_addr.')');
	$xtpl->form_create('?page=cluster&action=dns_delete&id='.$_GET['id'], 'post');
	
	api_params_to_form($api->dns_resolver->delete, 'input');
	
	$xtpl->form_out(_("Delete"));
}

function os_template_edit_form() {
	global $xtpl, $api;
	
	$t = $api->os_template->find($_GET['id']);
	
	$xtpl->title2(_("Edit template").' '.$t->label);
	
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	
	$xtpl->form_create('?page=cluster&action=templates_edit&id='.$t->id, 'post');
	api_update_form($t);
	$xtpl->form_out(_("Save changes"));
	
	$xtpl->sbar_add(_("Back"), '?page=cluster&action=templates');
}

function os_template_add_form() {
	global $xtpl, $api;
	
	$xtpl->title2(_("Register new template"));
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	
	$xtpl->form_create('?page=cluster&action=template_register', 'post');
	api_create_form($api->os_template);
	$xtpl->form_out(_("Register"));
	
	$xtpl->sbar_add(_("Back"), '?page=cluster&action=templates');
}

function integrity_check_list() {
	global $xtpl, $api;

	$xtpl->sbar_add(_("Back"), '?page=cluster');
	$xtpl->sbar_add(_("Checks"), '?page=cluster&action=integrity_check');
	$xtpl->sbar_add(_("Objects"), '?page=cluster&action=integrity_objects');
	$xtpl->sbar_add(_("Facts"), '?page=cluster&action=integrity_facts');

	$xtpl->title2(_('Integrity checks'));

	$xtpl->table_title(_('Filters'));
	$xtpl->form_create('', 'get', 'check-filter', false);
		
	$xtpl->table_td(_("Limit").':'.
		'<input type="hidden" name="page" value="cluster">'.
		'<input type="hidden" name="action" value="integrity_check">'.
		'<input type="hidden" name="list" value="1">'
	);
	$xtpl->form_add_input_pure('text', '40', 'limit', get_val('limit', '25'), '');
	$xtpl->table_tr();
	
	$xtpl->form_add_input(_("Offset").':', 'text', '40', 'offset', get_val('offset', '0'), '');


	$statuses = $api->integrity_check->list->getParameters('input')
		->status
		->validators
		->include
		->values;
	$empty = array('' => _('---'));
		
	$xtpl->form_add_select(
	 	_('Status').':',
		'status',
		$empty + $statuses,
		$_GET['status']
	);
		
	$xtpl->form_out(_('Show'));

	if (!$_GET['list'])
		return;

	$xtpl->table_add_category(_('Date'));
	$xtpl->table_add_category(_('Status'));
	$xtpl->table_add_category(_('Objects'));
	$xtpl->table_add_category(_('Integral objects'));
	$xtpl->table_add_category(_('Broken objects'));
	$xtpl->table_add_category(_('Facts'));
	$xtpl->table_add_category(_('True facts'));
	$xtpl->table_add_category(_('False facts'));

	$params = array(
		'limit' => get_val('limit', 25),
		'offset' => get_val('offset', 0)
	);

	if (isset($_GET['status']) && $_GET['status'] !== '')
		$params['status'] = $statuses[ $_GET['status'] ];

	if ($_GET['id'])
		$checks = array(
			$api->integrity_check->find($_GET['id'])
		);
	else
		$checks = $api->integrity_check->list($params);

	foreach ($checks as $c) {
		$xtpl->table_td(tolocaltz($c->created_at));
		$xtpl->table_td($c->status);
		$xtpl->table_td(
			'<a href="?page=cluster&action=integrity_objects&list=1&integrity_check='.$c->id.'">'.$c->checked_objects.'</a>',
			false, true
		);
		$xtpl->table_td(
			'<a href="?page=cluster&action=integrity_objects&list=1&integrity_check='.$c->id.'&status=1">'.$c->integral_objects.'</a>',
			false, true
		);
		$xtpl->table_td(
			'<a href="?page=cluster&action=integrity_objects&list=1&integrity_check='.$c->id.'&status=2">'.$c->broken_objects.'</a>',
			false, true
		);
		$xtpl->table_td(
			'<a href="?page=cluster&action=integrity_facts&list=1&integrity_check='.$c->id.'">'.$c->checked_facts.'</a>',
			false, true
		);
		$xtpl->table_td(
			'<a href="?page=cluster&action=integrity_facts&list=1&integrity_check='.$c->id.'&status=1">'.$c->true_facts.'</a>',
			false, true
		);
		$xtpl->table_td(
			'<a href="?page=cluster&action=integrity_facts&list=1&integrity_check='.$c->id.'&status=0">'.$c->false_facts.'</a>',
			false, true
		);

		$xtpl->table_tr();
	}

	$xtpl->table_out();
}

function integrity_object_list() {
	global $xtpl, $api;

	$xtpl->sbar_add(_("Back"), $_SERVER['HTTP_REFERER']);
	$xtpl->sbar_add(_("Checks"), '?page=cluster&action=integrity_check');
	$xtpl->sbar_add(_("Objects"), '?page=cluster&action=integrity_objects');
	$xtpl->sbar_add(_("Facts"), '?page=cluster&action=integrity_facts');

	$xtpl->title2(_('Integrity objects'));

	$xtpl->table_title(_('Filters'));
	$xtpl->form_create('', 'get', 'check-filter', false);
		
	$xtpl->table_td(_("Limit").':'.
		'<input type="hidden" name="page" value="cluster">'.
		'<input type="hidden" name="action" value="integrity_objects">'.
		'<input type="hidden" name="list" value="1">'
	);
	$xtpl->form_add_input_pure('text', '40', 'limit', get_val('limit', '25'), '');
	$xtpl->table_tr();
	
	$xtpl->form_add_input(_("Offset").':', 'text', '40', 'offset', get_val('offset', '0'), '');

	$check_param = $api->integrity_object->list->getParameters('input')->integrity_check;
	api_param_to_form(
		'integrity_check',
		$check_param,
		$_GET['integrity_check']
	);

	$xtpl->form_add_select(
		_('Node').':',
		'node',
		resource_list_to_options($api->node->list(), 'id', 'name', true),
		$_GET['node']
	);

	$xtpl->form_add_input(_("Class name").':', 'text', '30', 'class_name', get_val('class_name', ''), '');
	$xtpl->form_add_input(_("Row ID").':', 'text', '30', 'row_id', get_val('row_id', ''), '');

	$statuses = $api->integrity_object->list->getParameters('input')
		->status
		->validators
		->include
		->values;
	$empty = array('' => _('---'));
		
	$xtpl->form_add_select(
	 	_('Status').':',
		'status',
		$empty + $statuses,
		$_GET['status']
	);
		
	$xtpl->form_out(_('Show'));

	if (!$_GET['list'])
		return;

	$xtpl->table_add_category(_('Check'));
	$xtpl->table_add_category(_('Node'));
	$xtpl->table_add_category(_('Class name'));
	$xtpl->table_add_category(_('ID'));
	$xtpl->table_add_category(_('Status'));
	$xtpl->table_add_category(_('Facts'));
	$xtpl->table_add_category(_('True facts'));
	$xtpl->table_add_category(_('False facts'));

	$params = array(
		'limit' => get_val('limit', 25),
		'offset' => get_val('offset', 0),
		'meta' => array('includes' => 'node')
	);

	if ($_GET['integrity_check'])
		$params['integrity_check'] = $_GET['integrity_check'];
	
	if ($_GET['node'])
		$params['node'] = $_GET['node'];
	
	if ($_GET['class_name'])
		$params['class_name'] = $_GET['class_name'];

	if ($_GET['row_id'])
		$params['row_id'] = $_GET['row_id'];
	
	if (isset($_GET['status']) && $_GET['status'] !== '')
		$params['status'] = $statuses[ $_GET['status'] ];

	$objects = $api->integrity_object->list($params);

	foreach ($objects as $o) {
		$xtpl->table_td(
			'<a href="?page=cluster&action=integrity_check&list=1&id='.$o->integrity_check_id.'">'.tolocaltz($o->integrity_check->created_at).'</a>'
		);
		$xtpl->table_td(
			'<a href="?page=cluster&action=integrity_objects&node='.$o->node_id.'">'.$o->node->name.'</a>'
		);
		$xtpl->table_td($o->class_name);
		$xtpl->table_td($o->id);
		$xtpl->table_td(boolean_icon($o->status === 'integral'));
		$xtpl->table_td(
			'<a href="?page=cluster&action=integrity_facts&list=1&integrity_object='.$o->id.'">'.$o->checked_facts.'</a>',
			false, true
		);
		$xtpl->table_td(
			'<a href="?page=cluster&action=integrity_facts&list=1&integrity_object='.$o->id.'&status=1">'.$o->true_facts.'</a>',
			false, true
		);
		$xtpl->table_td(
			'<a href="?page=cluster&action=integrity_facts&list=1&integrity_object='.$o->id.'&status=0">'.$o->false_facts.'</a>',
			false, true
		);

		$xtpl->table_tr();
	}

	$xtpl->table_out();
}

function integrity_fact_list() {
	global $xtpl, $api;

	$xtpl->sbar_add(_("Back"), $_SERVER['HTTP_REFERER']);
	$xtpl->sbar_add(_("Checks"), '?page=cluster&action=integrity_check');
	$xtpl->sbar_add(_("Objects"), '?page=cluster&action=integrity_objects');
	$xtpl->sbar_add(_("Facts"), '?page=cluster&action=integrity_facts');

	$xtpl->title2(_('Integrity facts'));

	$xtpl->table_title(_('Filters'));
	$xtpl->form_create('', 'get', 'check-filter', false);
		
	$xtpl->table_td(_("Limit").':'.
		'<input type="hidden" name="page" value="cluster">'.
		'<input type="hidden" name="action" value="integrity_facts">'.
		'<input type="hidden" name="list" value="1">'
	);
	$xtpl->form_add_input_pure('text', '40', 'limit', get_val('limit', '25'), '');
	$xtpl->table_tr();
	
	$xtpl->form_add_input(_("Offset").':', 'text', '40', 'offset', get_val('offset', '0'), '');

	$input = $api->integrity_fact->list->getParameters('input');
	api_param_to_form(
		'integrity_check',
		$input->integrity_check,
		$_GET['integrity_check']
	);
	
	$xtpl->form_add_select(
		_('Node').':',
		'node',
		resource_list_to_options($api->node->list(), 'id', 'name', true),
		$_GET['node']
	);

	$xtpl->form_add_input(_("Class name").':', 'text', '30', 'class_name', get_val('class_name', ''), '');
	$xtpl->form_add_input(_('Object ID').':', 'text', '30', 'integrity_object', $_GET['integrity_object']);

	$statuses = $input->status->validators->include->values;
	$empty = array('' => _('---'));
		
	$xtpl->form_add_select(
	 	_('Status').':',
		'status',
		$empty + $statuses,
		$_GET['status']
	);

	$severities = $input->severity->validators->include->values;
	$xtpl->form_add_select(
	 	_('Severity').':',
		'severity',
		$empty + $severities,
		$_GET['severity']
	);
		
	$xtpl->form_out(_('Show'));

	if (!$_GET['list'])
		return;

	$xtpl->table_add_category(_('Node'));
	$xtpl->table_add_category(_('Object'));
	$xtpl->table_add_category(_('Name'));
	$xtpl->table_add_category(_('Status'));
	$xtpl->table_add_category(_('Severity'));

	$params = array(
		'limit' => get_val('limit', 25),
		'offset' => get_val('offset', 0),
		'meta' => array('includes' => 'integrity_object__node')
	);

	if ($_GET['integrity_check'])
		$params['integrity_check'] = $_GET['integrity_check'];
	
	if ($_GET['node'])
		$params['node'] = $_GET['node'];
	
	if ($_GET['class_name'])
		$params['class_name'] = $_GET['class_name'];

	if ($_GET['integrity_object'])
		$params['integrity_object'] = $_GET['integrity_object'];

	if (isset($_GET['status']) && $_GET['status'] !== '')
		$params['status'] = $statuses[ $_GET['status'] ];
	
	if (isset($_GET['severity']) && $_GET['severity'] !== '')
		$params['severity'] = $severities[ $_GET['severity'] ];

	$facts = $api->integrity_fact->list($params);

	foreach ($facts as $f) {
		$xtpl->table_td(
			'<a href="?page=cluster&action=integrity_facts&node='.$f->integrity_object->node_id.'">'.$f->integrity_object->node->name.'</a>'
		);
		$xtpl->table_td(
			'<a href="?page=cluster&action=integrity_objects&list=1&integrity_check='.$f->integrity_object->integrity_check_id.'&class_name='.$f->integrity_object->class_name.'&row_id='.$f->integrity_object->row_id.'">'.($f->integrity_object->class_name.' #'.$f->integrity_object->row_id).'</a>'
		);
		$xtpl->table_td($f->name);
		$xtpl->table_td(boolean_icon($f->status === 'true'));
		$xtpl->table_td($f->severity);

		$xtpl->table_tr();

		$xtpl->table_td(
			'<strong>'._('Expected value').":</strong>\n<br>".
			'<pre>'.htmlspecialchars($f->expected_value)."</pre>\n".
			'<strong>'._('Actual value').":</strong>\n<br>".
			'<pre>'.htmlspecialchars($f->actual_value)."</pre>\n".
			'<strong>'._('Message').":</strong>\n<br>".
			'<pre>'.$f->message."</pre>\n",
			false, false, '4'
		);
		$xtpl->table_tr();
	}

	$xtpl->table_out();
}
