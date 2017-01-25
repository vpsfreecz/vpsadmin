<?php

function environment_configs($user_id) {
	global $xtpl, $api;
	
	$cfgs = $api->user($user_id)->environment_config->list(array(
		'meta' => array('includes' => 'environment')
	));
	
	$xtpl->title(_('User').' <a href="?page=adminm&action=edit&id='.$user_id.'">#'.$user_id.'</a>: '._('Environment configs'));
	
	$xtpl->table_add_category(_('Environment'));
	$xtpl->table_add_category(_('Create VPS'));
	$xtpl->table_add_category(_('Destroy VPS'));
	$xtpl->table_add_category(_('VPS count'));
	$xtpl->table_add_category(_('VPS lifetime'));
	
	if ($_SESSION['is_admin']) {
		$xtpl->table_add_category(_('Default'));
		$xtpl->table_add_category('');
	}
	
	foreach ($cfgs as $c) {
		$vps_count = $api->vps->list(array(
			'limit' => 0,
			'environment' => $c->environment_id,
			'user' => $user_id,
			'meta' => array('count' => true)
		));

		$xtpl->table_td($c->environment->label);
		$xtpl->table_td(boolean_icon($c->can_create_vps));
		$xtpl->table_td(boolean_icon($c->can_destroy_vps));
		$xtpl->table_td(
			$vps_count->getTotalCount() .' / '. $c->max_vps_count,
			false,
			true
		);
		$xtpl->table_td(format_duration($c->vps_lifetime), false, true);
		
		if ($_SESSION['is_admin']) {
			$xtpl->table_td(boolean_icon($c->default));
			$xtpl->table_td('<a href="?page=adminm&section=members&action=env_cfg_edit&id='.$user_id.'&cfg='.$c->id.'"><img src="template/icons/m_edit.png"  title="'._("Edit").'"></a>');
		}
		
		$xtpl->table_tr();
	}
	
	$xtpl->table_out();
	
	$xtpl->sbar_add('<br><img src="template/icons/m_edit.png"  title="'._("Back to user details").'" />'._('Back to user details'), "?page=adminm&section=members&action=edit&id=$user_id");
}

function env_cfg_edit_form($user_id, $cfg_id) {
	global $xtpl, $api;
	
	$cfg = $api->user($user_id)->environment_config->find($cfg_id, array(
		'meta' => array('includes' => 'environment')
	));
	
	$xtpl->title(_('User').' <a href="?page=adminm&action=edit&id='.$user_id.'">#'.$user_id.'</a>: '._('Environment config for').' '.$cfg->environment->label);
	
	$xtpl->form_create("?page=adminm&action=env_cfg_edit&id=$user_id&cfg=$cfg_id");
	
	$xtpl->table_td(_('Environment'));
	$xtpl->table_td($cfg->environment->label);
	$xtpl->table_tr();
	
	api_update_form($cfg);
	
	$xtpl->form_out(_('Save'));
	
	$xtpl->sbar_add('<br><img src="template/icons/m_edit.png"  title="'._("Back to environment configs").'" />'._('Back to user details'), "?page=adminm&section=members&action=env_cfg&id=$user_id");
}

function list_user_sessions($user_id) {
	global $xtpl, $api;

	$u = $api->user->find($user_id);

	$xtpl->title(_('Session log of').' <a href="?page=adminm&action=edit&id='.$u->id.'">#'.$u->id. '</a> '.$u->login);
	$xtpl->table_title(_('Filters'));
	$xtpl->form_create('', 'get', 'user-session-filter', false);
	
	$xtpl->table_td(_("Limit").':'.
		'<input type="hidden" name="page" value="adminm">'.
		'<input type="hidden" name="action" value="user_sessions">'.
		'<input type="hidden" name="id" value="'.$user_id.'">'.
		'<input type="hidden" name="list" value="1">'
	);
	$xtpl->form_add_input_pure('text', '40', 'limit', get_val('limit', '25'), '');
	$xtpl->table_tr();
	
	$xtpl->form_add_input(_("Offset").':', 'text', '40', 'offset', get_val('offset', '0'), '');
	$xtpl->form_add_input(_("Exact ID").':', 'text', '40', 'session_id', get_val('session_id', ''), '');
	$xtpl->form_add_input(_("Authentication type").':', 'text', '40', 'auth_type', get_val('auth_type', ''), '');
	$xtpl->form_add_input(_("IP Address").':', 'text', '40', 'ip_addr', get_val('ip_addr', ''), '');
	$xtpl->form_add_input(_("User agent").':', 'text', '40', 'user_agent', get_val('user_agent', ''), '');
	$xtpl->form_add_input(_("Client version").':', 'text', '40', 'client_version', get_val('client_version', ''), '');
	$xtpl->form_add_input(_("Token").':', 'text', '40', 'auth_token_str', get_val('auth_token_str', ''), '');

	if ($_SESSION['is_admin'])
		$xtpl->form_add_input(_("Admin ID").':', 'text', '40', 'admin', get_val('admin', ''), '');

	$xtpl->form_add_checkbox(_('Detailed output').':', 'details', '1', isset($_GET['details']));

	$xtpl->form_out(_('Show'));

	if (!$_GET['list'])
		return;

	$params = array(
		'limit' => get_val('limit', 25),
		'offset' => get_val('offset', 0),
		'user' => $user_id
	);

	$conds = array('auth_type', 'ip_addr', 'user_agent', 'client_version',
			'auth_token_str', 'admin');

	foreach ($conds as $c) {
		if ($_GET[$c])
			$params[$c] = $_GET[$c];
	}

	$includes = array();

	if ($_SESSION['is_admin'])
		$params['meta'] = array('includes' => 'admin');

	if ($_GET['session_id'])
		$sessions = array( $api->user_session->show($_GET['session_id']));
	else
		$sessions = $api->user_session->list($params);

	$xtpl->table_add_category(_("Created at"));
	$xtpl->table_add_category(_("Last request at"));
	$xtpl->table_add_category(_("Closed at"));
	$xtpl->table_add_category(_("IP address"));
	$xtpl->table_add_category(_("Auth type"));
	$xtpl->table_add_category(_("Token"));

	if ($_SESSION['is_admin'])
		$xtpl->table_add_category(_("Admin"));
	
	$xtpl->table_add_category('');

	foreach ($sessions as $s) {
		$xtpl->table_td(tolocaltz($s->created_at));
		$xtpl->table_td($s->last_request_at ? tolocaltz($s->last_request_at) : '---');
		$xtpl->table_td($s->closed_at ? tolocaltz($s->closed_at) : '---');
		$xtpl->table_td($s->ip_addr);
		$xtpl->table_td($s->auth_type);
		$xtpl->table_td($s->auth_token_str
			? substr($s->auth_token_str, 0, 8).'...'
			: '---'
		);

		if ($_SESSION['is_admin']) {
			$xtpl->table_td($s->admin_id
				? '<a href="?page=adminm&action=edit&id='.$s->admin_id.'">'.$s->admin->login.'</a>'
				: '---'
			);
		}

		$color = false;

		if (!$s->closed_at && $s->auth_token_str == $api->getAuthenticationProvider()->getToken())
			$color = '#33CC00';

		elseif (!$s->closed_at)
			$color = '#66FF33';

		$xtpl->table_td('<a href="?page=transactions&user_session='.$s->id.'">Log</a>');

		$xtpl->table_tr($color);

		if (!$_GET['details'])
			continue;

		$xtpl->table_td(
			'<dl>'.
			'<dt>User agent:</dt><dd>'.$s->user_agent.'</dd>'.
			'<dt>Client version:</dt><dd>'.$s->client_version.'</dd>'.
			'<dt>Token:</dt><dd>'.$s->auth_token_str.'</dd>'.
			'<dl>'
		, false, false, '7');

		$xtpl->table_tr();
	}

	$xtpl->table_out();
	
	$xtpl->sbar_add('<br><img src="template/icons/m_edit.png"  title="'._("Back to user details").'" />'._('Back to user details'), "?page=adminm&action=edit&id=$user_id");
}

function approval_requests_list() {
	global $xtpl, $api;

	$xtpl->title(_("Requests for approval"));
	
	$xtpl->form_create('?page=adminm&section=members&action=approval_requests', 'get');
	
	$xtpl->table_td(_("Limit").':'.
		'<input type="hidden" name="page" value="adminm">'.
		'<input type="hidden" name="section" value="members">'.
		'<input type="hidden" name="action" value="approval_requests">'
	);
	$xtpl->form_add_input_pure('text', '30', 'limit', $_GET["limit"] ? $_GET["limit"] : 50);
	$xtpl->table_tr();
	
	$xtpl->form_add_select(_("Type").':', 'type', array(
		"registration" => _("registration"),
		"change" => _("change")
	), $_GET["type"]);
	$xtpl->form_add_select(_("State").':', 'state', array(
		"all" => _("all"),
		"awaiting" => _("awaiting"),
		"approved" => _("approved"),
		"denied" => _("denied"),
		"ignored" => _("ignored")
	), $_GET["state"] ? $_GET["state"] : "awaiting");
	
	$xtpl->form_add_input(_("IP address").':', 'text', '30', 'ip_addr', $_GET["ip_addr"]);
	$xtpl->form_add_input(_("User ID").':', 'text', '30', 'user', $_GET["user"]);
	$xtpl->form_add_input(_("Admin ID").':', 'text', '30', 'admin', $_GET["admin"]);
	
	$xtpl->form_out(_("Show"));

	if (!isset($_GET['type']))
		return;
	
	$xtpl->table_add_category('#');
	$xtpl->table_add_category('DATE');
	$xtpl->table_add_category('IP');
	$xtpl->table_add_category('STATE');
	$xtpl->table_add_category('ADMIN');
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');

	$params = array('limit' => $_GET['limit'],);

	if ($_GET['state'] != 'all')
		$params['state'] = $_GET['state'];

	foreach (array('ip_addr', 'user', 'admin') as $v) {
		if ($_GET[$v])
			$params[$v] = $_GET[$v];
	}

	$requests = $api->user_request->{$_GET['type']}->list($params);
	
	foreach ($requests as $r) {
		$xtpl->table_td('<a href="?page=adminm&action=request_details&id='.$r->id.'&type='.$_GET['type'].'">#'.$r->id.'</a>');
		$xtpl->table_td(tolocaltz($r->created_at));
		$xtpl->table_td($r->client_ip_addr ? $r->client_ip_addr : $r->api_ip_addr);
		$xtpl->table_td($r->state);
		$xtpl->table_td($r->admin_id ? ('<a href="?page=adminm&action=edit&id='.$r->admin_id.'&type='.$_GET['type'].'">'.$r->admin->login.'</a>') : '-');
		$xtpl->table_td('<a href="?page=adminm&action=request_details&id='.$r->id.'&type='.$_GET['type'].'"><img src="template/icons/m_edit.png"  title="'. _("Details") .'" /></a>');
		$xtpl->table_td('<a href="?page=adminm&action=request_process&id='.$r->id.'&type='.$_GET['type'].'&rule=approve">'._("approve").'</a>');
		$xtpl->table_td('<a href="?page=adminm&action=request_process&id='.$r->id.'&type='.$_GET['type'].'&rule=deny">'._("deny").'</a>');
		$xtpl->table_td('<a href="?page=adminm&action=request_process&id='.$r->id.'&type='.$_GET['type'].'&rule=ignore">'._("ignore").'</a>');
		
		$xtpl->table_tr();
	}
	
	$xtpl->table_out();

}

function approval_requests_details($type, $id) {
	global $xtpl, $api;
	
	$r = $api->user_request->{$type}->show($id);
	
	$xtpl->title(_("Request for approval details"));
	
	$xtpl->table_add_category(_("Request info"));
	$xtpl->table_add_category('');
	
	$xtpl->table_td(_("Created").':');
	$xtpl->table_td(tolocaltz($r->created_at));
	$xtpl->table_tr();
	
	$xtpl->table_td(_("Changed").':');
	$xtpl->table_td(tolocaltz($r->updated_at));
	$xtpl->table_tr();
	
	$xtpl->table_td(_("Type").':');
	$xtpl->table_td($type == "registration" ? _("registration") : _("change"));
	$xtpl->table_tr();
	
	$xtpl->table_td(_("State").':');
	$xtpl->table_td($r->state);
	$xtpl->table_tr();
	
	$xtpl->table_td(_("Applicant").':');
	$xtpl->table_td($r->user_id ? ('<a href="?page=adminm&action=edit&id='.$r->user_id.'">'.$r->user->login.'</a>') : '-');
	$xtpl->table_tr();
	
	$xtpl->table_td(_("Admin").':');
	$xtpl->table_td($r->admin_id ? ('<a href="?page=adminm&action=edit&id='.$r->admin_id.'">'.$r->admin->login.'</a>') : '-');
	$xtpl->table_tr();
	
	$xtpl->table_td(_("API IP Address").':');
	$xtpl->table_td($r->api_ip_addr);
	$xtpl->table_tr();
	
	$xtpl->table_td(_("API PTR").':');
	$xtpl->table_td($r->api_ip_ptr);
	$xtpl->table_tr();
	
	$xtpl->table_td(_("Client IP Address").':');
	$xtpl->table_td($r->client_ip_addr);
	$xtpl->table_tr();
	
	$xtpl->table_td(_("Client PTR").':');
	$xtpl->table_td($r->client_ip_ptr);
	$xtpl->table_tr();
	
	$xtpl->table_out();
	
	$xtpl->form_create('?page=adminm&action=request_process&id='.$r->id.'&type='.$type, 'post');
	$params = $r->resolve->getParameters('input');
	
	foreach ($params as $name => $desc) {
		api_param_to_form($name, $desc, post_val($name, $r->{$name}));
	}

	$xtpl->form_out(_('Close request'));
}
