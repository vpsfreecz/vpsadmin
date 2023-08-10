<?php

function incident_list() {
	global $xtpl, $api;

	$xtpl->title(_('Incident reports'));
	$xtpl->table_title(_('Filters'));
	$xtpl->form_create('', 'get', 'incident-list', false);

	$xtpl->form_set_hidden_fields([
		'page' => 'incidents',
		'action' => 'list',
		'list' => '1',
	]);

	$xtpl->form_add_input(_('Limit').':', 'text', '40', 'limit', get_val('limit', '25'), '');
	$xtpl->table_tr();

	$input = $api->incident_report->list->getParameters('input');

	if (isAdmin())
		$xtpl->form_add_input(_('User ID').':', 'text', '30', 'user', get_val('user'), '');

	if (isAdmin())
		$xtpl->form_add_input(_('VPS ID').':', 'text', '30', 'vps', get_val('vps'), '');
	else
		api_param_to_form('vps', $input->vps, $_GET['vps']);

	if (isAdmin()) {
		$xtpl->form_add_input(_('Assignment ID').':', 'text', '30', 'ip_address_assignment', get_val('ip_address_assignment'), '');
	} else {
		api_param_to_form(
			'ip_address_assignment',
			$input->ip_address_assignment,
			$_GET['ip_address_assignment'],
			'ip_address_assignment_label'
		);
	}

	api_param_to_form('ip_addr', $input->ip_addr, $_GET['ip_addr']);

	if (isAdmin())
		api_param_to_form('mailbox', $input->mailbox, $_GET['mailbox']);

	api_param_to_form('codename', $input->codename, $_GET['codename']);

	$xtpl->form_out(_('Show'));

	if (!$_GET['list'])
		return;

	$params = [
		'limit' => get_val('limit', 25),
		'meta' => ['includes' => 'user,vps,ip_address_assignment'],
	];

	$filters = [
		'user', 'vps', 'ip_address_assignment', 'ip_addr', 'mailbox', 'codename'
	];

	foreach ($filters as $v) {
		if ($_GET[$v])
			$params[$v] = $_GET[$v];
	}

	$incidents = $api->incident_report->list($params);

	$xtpl->table_add_category(_('ID'));
	$xtpl->table_add_category(_('Detected at'));

	if (isAdmin())
		$xtpl->table_add_category(_('User'));

	$xtpl->table_add_category(_('VPS'));
	$xtpl->table_add_category(_('IP address'));
	$xtpl->table_add_category(_('Subject'));
	$xtpl->table_add_category(_('Codename'));

	if (isAdmin())
		$xtpl->table_add_category(_('Admin'));

	$xtpl->table_add_category('');

	foreach ($incidents as $inc) {
		$xtpl->table_td('<a href="?page=incidents&action=show&id='.$inc->id.'">'.$inc->id.'</a>');
		$xtpl->table_td(tolocaltz($inc->detected_at));

		if (isAdmin())
			$xtpl->table_td($inc->user_id ? user_link($inc->user) : $inc->raw_user_id);

		$xtpl->table_td($inc->vps_id ? vps_link($inc->vps) : $inc->raw_vps_id);
		$xtpl->table_td($inc->ip_address_assignment_id ? ($inc->ip_address_assignment->ip_addr.'/'.$inc->ip_address_assignment->ip_prefix) : '-');
		$xtpl->table_td(h($inc->subject));
		$xtpl->table_td(h($inc->codename));

		if (isAdmin())
			$xtpl->table_td($inc->filed_by_id ? user_link($inc->filed_by) : '-');

		$xtpl->table_td(
			'<a href="?page=incidents&action=show&id='.$inc->id.'"><img src="template/icons/vps_edit.png" alt="'._('Details').'" title="'._('Details').'"></a>'
		);
		$xtpl->table_tr();
	}

	$xtpl->table_out();
}

function incident_show($id) {
	global $xtpl, $api;

	$inc = $api->incident_report->show($id, [
		'meta' => ['includes' => 'user,vps,ip_address_assignment'],
	]);

	$xtpl->title(_('Incident report').' #'.$inc->id.': '.h($inc->subject));

	if (isAdmin()) {
		$xtpl->table_td(_('User').':');
		$xtpl->table_td($inc->user_id ? user_link($inc->user) : $inc->raw_user_id);
		$xtpl->table_tr();
	}

	$xtpl->table_td(_('VPS').':');
	$xtpl->table_td($inc->vps_id ? vps_link($inc->vps) : $inc->raw_vps_id);
	$xtpl->table_tr();

	$xtpl->table_td(_('IP address').':');
	$xtpl->table_td($inc->ip_address_assignment_id ? ($inc->ip_address_assignment->ip_addr.'/'.$inc->ip_address_assignment->ip_prefix) : '-');
	$xtpl->table_tr();

	$xtpl->table_td(_('Assignment').':');

	if ($inc->ip_address_assignment_id)
		$xtpl->table_td(ip_address_assignment_label($inc->ip_address_assignment));
	else {
		$xtpl->table_td('-');
	}

	$xtpl->table_tr();

	if (isAdmin()) {
		$xtpl->table_td(_('Filed by').':');
		$xtpl->table_td($inc->filed_by_id ? user_link($inc->filed_by) : '-');
		$xtpl->table_tr();

		$xtpl->table_td(_('Mailbox').':');
		$xtpl->table_td($inc->mailbox_id ? $inc->mailbox->label : '-');
		$xtpl->table_tr();
	}

	$xtpl->table_td(_('Detected at').':');
	$xtpl->table_td(tolocaltz($inc->detected_at));
	$xtpl->table_tr();

	$xtpl->table_td(_('Added at').':');
	$xtpl->table_td(tolocaltz($inc->created_at));
	$xtpl->table_tr();

	$xtpl->table_td(_('Subject').':');
	$xtpl->table_td(h($inc->subject));
	$xtpl->table_tr();

	$xtpl->table_td(_('Codename').':');
	$xtpl->table_td(h($inc->codename));
	$xtpl->table_tr();

	$xtpl->table_td(_('Text').':');
	$xtpl->table_td('<pre><code>'.h($inc->text).'</code></pre>');
	$xtpl->table_tr();

	$xtpl->table_out();
}

function incident_new($vps_id) {
	global $xtpl, $api;

	$vps = $api->vps->show($vps_id);

	$xtpl->title(_('New incident report'));

	$xtpl->form_create('?page=incidents&action=new&vps='.$vps->id, 'post');

	$xtpl->table_td(_('User').':');
	$xtpl->table_td(user_link($vps->user));
	$xtpl->table_tr();

	$xtpl->table_td(_('VPS').':');
	$xtpl->table_td(vps_link($vps));
	$xtpl->table_tr();

	$xtpl->form_add_select(
		_('IP address').':',
		'ip_address_assignment',
		resource_list_to_options(
			$api->ip_address_assignment->list([
				'vps' => $vps->id,
				'active' => true,
			]),
			'id',
			'ip_addr',
			true,
			function ($as) {
				return $as->ip_addr.'/'.$as->ip_prefix;
			}
		),
		post_val('ip_address_assignment')
	);

	$input = $api->incident_report->create->getParameters('input');

	api_param_to_form('subject', $input->subject);
	api_param_to_form('text', $input->text);
	api_param_to_form('codename', $input->codename);
	api_param_to_form('detected_at', $input->detected_at, post_val('detected_at', tolocaltz(date('c'))));

	$xtpl->form_add_number(
		_('CPU limit').':',
		'cpu_limit',
		post_val('cpu_limit'),
		0,
		10000,
		25,
		'%'
	);

	$xtpl->form_out(_('Report'));
}
