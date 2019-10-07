<?php

use Endroid\QrCode\QrCode;

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
	$xtpl->form_add_input(_("Token").':', 'text', '40', 'session_token_str', get_val('session_token_str', ''), '');

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
			'session_token_str', 'admin');

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
		$xtpl->table_td(h($s->client_ip_addr ? $s->client_ip_addr : $s->api_ip_addr));
		$xtpl->table_td($s->auth_type);
		$xtpl->table_td($s->session_token_str
			? substr($s->session_token_str, 0, 8).'...'
			: '---'
		);

		if ($_SESSION['is_admin']) {
			$xtpl->table_td($s->admin_id
				? '<a href="?page=adminm&action=edit&id='.$s->admin_id.'">'.$s->admin->login.'</a>'
				: '---'
			);
		}

		$color = false;

		if (!$s->closed_at && $s->session_token_str == $api->getAuthenticationProvider()->getToken())
			$color = '#33CC00';

		elseif (!$s->closed_at)
			$color = '#66FF33';

		$xtpl->table_td('<a href="?page=transactions&user_session='.$s->id.'">Log</a>');

		$xtpl->table_tr($color);

		if (!$_GET['details'])
			continue;

		$xtpl->table_td(
			'<dl>'.
			'<dt>API IP address:</dt><dd>'.h($s->api_ip_addr).'</dd>'.
			'<dt>API IP PTR:</dt><dd>'.h($s->api_ip_ptr).'</dd>'.
			'<dt>Client IP address:</dt><dd>'.h($s->client_ip_addr).'</dd>'.
			'<dt>Client IP PTR:</dt><dd>'.h($s->client_ip_ptr).'</dd>'.
			'<dt>User agent:</dt><dd>'.h($s->user_agent).'</dd>'.
			'<dt>Client version:</dt><dd>'.h($s->client_version).'</dd>'.
			'<dt>Token:</dt><dd>'.$s->session_token_str.'</dd>'.
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
		"pending_correction" => _("pending correction"),
		"approved" => _("approved"),
		"denied" => _("denied"),
		"ignored" => _("ignored")
	), $_GET["state"] ? $_GET["state"] : "awaiting");

	$xtpl->form_add_input(_("IP address").':', 'text', '30', 'ip_addr', $_GET["ip_addr"]);
	$xtpl->form_add_input(_("Client IP PTR").':', 'text', '30', 'client_ip_ptr', $_GET["client_ip_ptr"]);
	$xtpl->form_add_input(_("User ID").':', 'text', '30', 'user', $_GET["user"]);
	$xtpl->form_add_input(_("Admin ID").':', 'text', '30', 'admin', $_GET["admin"]);

	$xtpl->form_out(_("Show"));

	if (!isset($_GET['type']))
		return;

	$xtpl->table_add_category('#');
	$xtpl->table_add_category('DATE');
	$xtpl->table_add_category('LABEL');
	$xtpl->table_add_category('IP');
	$xtpl->table_add_category('PTR');
	$xtpl->table_add_category('STATE');
	$xtpl->table_add_category('ADMIN');
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');

	$params = array('limit' => $_GET['limit'],);

	if ($_GET['state'] != 'all')
		$params['state'] = $_GET['state'];

	foreach (array('ip_addr', 'client_ip_ptr', 'user', 'admin') as $v) {
		if ($_GET[$v])
			$params[$v] = $_GET[$v];
	}

	$requests = $api->user_request->{$_GET['type']}->list($params);

	foreach ($requests as $r) {
		$xtpl->table_td('<a href="?page=adminm&action=request_details&id='.$r->id.'&type='.$_GET['type'].'">#'.$r->id.'</a>');
		$xtpl->table_td(tolocaltz($r->created_at));
		$xtpl->table_td(h($r->label));
		$xtpl->table_td(h($r->client_ip_addr ? $r->client_ip_addr : $r->api_ip_addr));
		$xtpl->table_td(h($r->client_ip_ptr));
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
	$xtpl->table_td(h($r->api_ip_addr));
	$xtpl->table_tr();

	$xtpl->table_td(_("API PTR").':');
	$xtpl->table_td(h($r->api_ip_ptr));
	$xtpl->table_tr();

	$xtpl->table_td(_("Client IP Address").':');
	$xtpl->table_td(h($r->client_ip_addr));
	$xtpl->table_tr();

	$xtpl->table_td(_("Client PTR").':');
	$xtpl->table_td(h($r->client_ip_ptr));
	$xtpl->table_tr();

	$xtpl->table_out();

	$xtpl->form_create('?page=adminm&action=request_process&id='.$r->id.'&type='.$type, 'post');
	$params = $r->resolve->getParameters('input');
	$request_attrs = $r->show->getParameters('output');

	foreach ($params as $name => $desc) {
		$v = null;

		if (property_exists($request_attrs, $name)) {
			switch ($request_attrs->{$name}->type) {
			case 'Resource':
				$v = $r->{"{$name}_id"};
				break;

			default:
				$v = $r->{$name};
			}
		}

		api_param_to_form(
			$name,
			$desc,
			post_val($name, $v)
		);
	}

	$xtpl->form_out(_('Close request'));
}

function user_payment_info($u) {
	global $xtpl;

	$dt = new DateTime($u->paid_until);
	$dt->setTimezone(new DateTimezone(date_default_timezone_get()));

	$t = $dt->getTimestamp();
	$paid = $t > time();
	$paid_until = date('Y-m-d', $t);

	if ($_SESSION["is_admin"]) {
		$td = '<a href="?page=adminm&action=payset&id='.$u->id.'" class="user-'.($paid ? 'paid' : 'unpaid').'">';
		$color = '';

		if ($paid) {
			if (($t - time()) >= 604800) {
				$td .= _("->") . ' ' . $paid_until;
				$color = '#66FF66';

			} else {
				$td .= _("->") . ' ' . $paid_until;
				$color = '#FFA500';
			}

		} else {
			$td .= '<strong>' . _("not paid!") . '</strong>';
			$color = '#B22222';

			if ($u->paid_until) {
				$td .= ' ('.ceil(($t - time()) / 86400).'d)';
			}
		}

		$td .= '</a>';
		$xtpl->table_td($td, $color);

		return;
	}

	if ($paid) {
		if (($t - time()) >= 604800) {
			$xtpl->table_td(_("->").' '.$paid_until, '#66FF66');

		} else {
			$xtpl->table_td(_("->").' '.$paid_until, '#FFA500');
		}

	} else {
		$xtpl->table_td('<b>'._("not paid!").'</b>', '#B22222');
	}
}

function user_payment_form($user_id) {
	global $xtpl, $api;

	try {
		$u = $api->user->find($user_id);

	} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
		$xtpl->perex_format_errors(_('User not found'), $e->getResponse());
		return;
	}

	$paidUntil = strtotime($u->paid_until);

	$xtpl->title(_("User payments"));

	$xtpl->table_td(_("Login").':');
	$xtpl->table_td($u->login);
	$xtpl->table_tr();

	$xtpl->table_td(_("Paid until").':');

	if ($paidUntil) {
		$lastPaidTo = date('Y-m-d', $paidUntil);

	} else {
		$lastPaidTo = _("Never been paid");
	}

	$xtpl->table_td($lastPaidTo);
	$xtpl->table_tr();

	$xtpl->table_td(_("Monthly payment").':');
	$xtpl->table_td($u->monthly_payment);
	$xtpl->table_tr();

	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	$xtpl->table_out();

	$xtpl->table_title(_('Set paid until date'));
	$xtpl->form_create('?page=adminm&action=payset2&id='.$u->id, 'post');
	$xtpl->form_add_input(
		_("Paid until").':', 'text', '30', 'paid_until', post_val('paid_until'),
		_('YYYY-MM-DD, e.g.').' '.date('Y-m-d')
	);
	$xtpl->form_out(_("Save"));

	$xtpl->table_title(_('Add payment'));
	$xtpl->form_create('?page=adminm&action=payset2&id='.$u->id, 'post');
	$xtpl->form_add_input(_("Amount").':', 'text', '30', 'amount', post_val('amount'));
	$xtpl->form_out(_("Save"));

	$xtpl->table_title(_('Payment log'));
	$xtpl->table_add_category("ACCEPTED AT");
	$xtpl->table_add_category("ACCOUNTED BY");
	$xtpl->table_add_category("AMOUNT");
	$xtpl->table_add_category("FROM");
	$xtpl->table_add_category("TO");
	$xtpl->table_add_category("PAYMENT");

	$payments = $api->user_payment->list(array(
		'user' => $u->id,
		'meta' => array('includes' => 'accounted_by'),
	));

	foreach ($payments as $payment) {
		$xtpl->table_td(tolocaltz($payment->created_at));
		$xtpl->table_td($payment->accounted_by_id ? $payment->accounted_by->login : '-');
		$xtpl->table_td($payment->amount, false, true);
		$xtpl->table_td(tolocaltz($payment->from_date, 'Y-m-d'));
		$xtpl->table_td(tolocaltz($payment->to_date, 'Y-m-d'));

		if ($payment->incoming_payment_id) {
			$xtpl->table_td(
				'<a href="?page=adminm&action=incoming_payment&id='.
				$payment->incoming_payment_id.'">'.
				'#'.$payment->incoming_payment_id.
				'</a>'
			);
		} else {
			$xtpl->table_td('-');
		}

		$xtpl->table_tr();
	}

	$xtpl->table_out();
}

function user_payment_history() {
	global $xtpl, $api;

	$xtpl->title(_('Payment history'));

	$xtpl->form_create('?page=adminm&action=payments_history', 'get');
	$xtpl->table_td(_("Limit").':'.
		'<input type="hidden" name="page" value="adminm">'.
		'<input type="hidden" name="action" value="payments_history">'
	);
	$xtpl->form_add_input_pure('text', '40', 'limit', get_val('limit', 25), '');
	$xtpl->table_tr();

	$xtpl->form_add_input(_("Admin ID").':', 'text', '40', 'accounted_by', get_val('accounted_by'));
	$xtpl->form_add_input(_("User ID").':', 'text', '40', 'user', get_val('user'));
	$xtpl->form_out(_("Show"));

	$params = array(
		'limit' => get_val('limit', 25),
		'meta' => array('includes' => 'user,accounted_by'),
	);

	foreach (array('accounted_by', 'user') as $filter) {
		if ($_GET[$filter])
			$params[$filter] = $_GET[$filter];
	}

	$payments = $api->user_payment->list($params);

	$xtpl->table_add_category("ACCEPTED AT");
	$xtpl->table_add_category("USER");
	$xtpl->table_add_category("ACCOUNTED BY");
	$xtpl->table_add_category("AMOUNT");
	$xtpl->table_add_category("FROM");
	$xtpl->table_add_category("TO");
	$xtpl->table_add_category("MONTHS");

	foreach ($payments as $p) {
		$xtpl->table_td(tolocaltz($p->created_at));
		$xtpl->table_td($p->user_id ? user_link($p->user) : '-');
		$xtpl->table_td($p->accounted_by_id ? user_link($p->accounted_by) : '-');
		$xtpl->table_td($p->amount, false, true);
		$xtpl->table_td(tolocaltz($p->from_date, 'Y-m-d'));
		$xtpl->table_td(tolocaltz($p->to_date, 'Y-m-d'));
		$xtpl->table_td(
			round((strtotime($p->to_date) - strtotime($p->from_date)) / 2629800),
			false, true
		);
		$xtpl->table_tr();
	}

	$xtpl->table_out();
}

function incoming_payments_list() {
	global $xtpl, $api;

	$xtpl->title(_('Incoming payments'));

	$xtpl->form_create('?page=adminm&action=incoming_payments', 'get');
	$xtpl->table_td(_("Limit").':'.
		'<input type="hidden" name="page" value="adminm">'.
		'<input type="hidden" name="action" value="incoming_payments">'
	);
	$xtpl->form_add_input_pure('text', '40', 'limit', get_val('limit', 25), '');
	$xtpl->table_tr();
	$xtpl->form_add_input(_('Offset').':', 'text', '40', 'offset', get_val('offset', 0), '');

	$input = $api->incoming_payment->list->getParameters('input');

	api_param_to_form(
		'state',
		$input->state,
		get_val('state')
	);

	$xtpl->form_out(_('Show'));

	$params = array(
		'limit' => get_val('limit', 25),
		'offset' => get_val('offset', 0),
	);

	if (isset($_GET['state']))
		$params['state'] = $_GET['state'];

	$payments = $api->incoming_payment->list($params);

	$xtpl->table_add_category("DATE");
	$xtpl->table_add_category("AMOUNT");
	$xtpl->table_add_category("STATE");
	$xtpl->table_add_category("FROM");
	$xtpl->table_add_category("MESSAGE");
	$xtpl->table_add_category("VS");
	$xtpl->table_add_category("COMMENT");
	$xtpl->table_add_category("");

	foreach ($payments as $p) {
		$xtpl->table_td(tolocaltz($p->date, 'Y-m-d'));
		$xtpl->table_td($p->amount."&nbsp;".$p->currency, false, true);
		$xtpl->table_td($p->state);
		$xtpl->table_td(h($p->account_name));
		$xtpl->table_td(h($p->user_message));
		$xtpl->table_td(h($p->vs));
		$xtpl->table_td(h($p->comment));
		$xtpl->table_td(
			'<a href="?page=adminm&action=incoming_payment&id='.$p->id.'">'.
			'<img src="template/icons/m_edit.png" title="'._('Details').'">'.
			'</a>'
		);

		$xtpl->table_tr();
	}

	$xtpl->table_out();
}

function incoming_payments_details($id) {
	global $xtpl, $api;

	$p = $api->incoming_payment->find($id);

	$xtpl->title(_("Incoming payment").' #'.$p->id);
	$xtpl->form_create('?page=adminm&action=incoming_payment_state&id='.$p->id, 'post');

	$xtpl->table_td(_('Transaction ID').':');
	$xtpl->table_td(h($p->transaction_id));
	$xtpl->table_tr();

	$xtpl->table_td(_('Date').':');
	$xtpl->table_td(tolocaltz($p->date, 'Y-m-d'));
	$xtpl->table_tr();

	$xtpl->table_td(_('Accepted at').':');
	$xtpl->table_td(tolocaltz($p->created_at));
	$xtpl->table_tr();

	$state_desc = $api->incoming_payment->update->getParameters('input')->state;

	api_param_to_form(
		'state',
		$state_desc,
		post_val('state', $p->state)
	);

	$xtpl->table_td(_('Type').':');
	$xtpl->table_td(h($p->transaction_type));
	$xtpl->table_tr();

	$xtpl->table_td(_('Amount').':');
	$xtpl->table_td($p->amount);
	$xtpl->table_tr();

	$xtpl->table_td(_('Currency').':');
	$xtpl->table_td(h($p->currency));
	$xtpl->table_tr();

	if ($p->src_amount) {
		$xtpl->table_td(_('Original amount').':');
		$xtpl->table_td($p->src_amount);
		$xtpl->table_tr();

		$xtpl->table_td(_('Original currency').':');
		$xtpl->table_td(h($p->src_currency));
		$xtpl->table_tr();
	}

	$xtpl->table_td(_('Account name').':');
	$xtpl->table_td(h($p->account_name));
	$xtpl->table_tr();

	$xtpl->table_td(_('User identification').':');
	$xtpl->table_td(h($p->user_ident));
	$xtpl->table_tr();

	$xtpl->table_td(_('User message').':');
	$xtpl->table_td(h($p->user_message));
	$xtpl->table_tr();

	$xtpl->table_td(_('VS').':');
	$xtpl->table_td(h($p->vs));
	$xtpl->table_tr();

	$xtpl->table_td(_('KS').':');
	$xtpl->table_td(h($p->ks));
	$xtpl->table_tr();

	$xtpl->table_td(_('SS').':');
	$xtpl->table_td(h($p->ss));
	$xtpl->table_tr();

	$xtpl->table_td(_('Comment').':');
	$xtpl->table_td(h($p->comment));
	$xtpl->table_tr();

	$xtpl->form_out(_('Set state'));

	if ($p->state != 'processed') {
		$xtpl->table_title(_('Assign payment'));
		$xtpl->form_create('?page=adminm&action=incoming_payment_assign&id='.$p->id, 'post');
		$xtpl->form_add_input(_('User ID').':', 'text', '30', 'user', post_val('user'));
		$xtpl->form_out(_('Assign'));
	}
}

function mail_template_recipient_form($user_id) {
	global $xtpl, $api;

	$u = $api->user->show($user_id);

	$xtpl->title(_('Mail template recipients'));

	$xtpl->form_create('?page=adminm&action=template_recipients&id='.$u->id, 'post');
	$xtpl->table_add_category(_('Templates'));
	$xtpl->table_add_category(_('E-mails'));

	$xtpl->table_td(
		_('E-mails configured here override role recipients. It is a comma separated list of e-mails, may contain line breaks.'),
		false, false, 2
	);
	$xtpl->table_tr();

	foreach ($u->mail_template_recipient->list() as $recp) {
		$xtpl->table_td(
			$recp->label ? $recp->label : $recp->id, false, false, 1,
			$recp->description ? 3 : 2
		);
		$xtpl->form_add_textarea_pure(
			50, 5,
			"to[{$recp->id}]",
			$_POST['to'][$recp->id] ? $_POST['to'][$recp->id] : str_replace(',', ",\n", $recp->to)
		);
		$xtpl->table_tr();

		$xtpl->form_add_checkbox_pure(
			"disable[{$recp->id}]",
			'1',
			isset($_POST['disable']) ? isset($_POST['disable'][$recp->id]) : !$recp->enabled,
			_("Do <strong>not</strong> send this e-mail")
		);
		$xtpl->table_tr();

		if ($recp->description) {
			$xtpl->table_td($recp->description);
			$xtpl->table_tr();
		}
	}

	$xtpl->form_out(_('Save'));
}

function sort_resource_packages ($pkgs) {
	$ret = [];
	$envs = [];

	foreach ($pkgs as $pkg) {
		$envs[$pkg->environment_id] = $pkg->environment;
	}

	usort($envs, function ($a, $b) {
		return $a->environment_id - $b->environment_id;
	});

	foreach ($envs as $env) {
		$env_pkgs = [];

		foreach ($pkgs as $pkg) {
			if ($pkg->environment_id == $env->id)
				$env_pkgs[] = $pkg;
		}

		$ret[] = [$env, $env_pkgs];
	}

	return $ret;
}

function resource_package_counts ($env_pkgs) {
	$ret = [];
	$tmp = [];

	foreach ($env_pkgs as $pkg) {
		if ($pkg->is_personal)
			continue;
		elseif (array_key_exists($pkg->label, $tmp))
			$tmp[$pkg->label] += 1;
		else
			$tmp[$pkg->label] = 1;
	}

	foreach ($tmp as $pkg_label => $count) {
		$pkg = null;

		foreach ($env_pkgs as $p) {
			if ($p->label == $pkg_label) {
				$pkg = $p;
				break;
			}
		}

		$ret[] = [$pkg, $count];
	}

	return $ret;
}

function list_user_resource_packages($user_id) {
	global $xtpl, $api;

	$convert = array('memory', 'swap', 'diskspace');

	$xtpl->title(_('User').' <a href="?page=adminm&action=edit&id='.$user_id.'">#'.$user_id.'</a>: '._('Cluster resource packages'));

	$pkgs = $api->user_cluster_resource_package->list([
		'user' => $user_id,
		'meta' => ['includes' => 'environment'],
	]);
	$sorted_pkgs = sort_resource_packages($pkgs);

	$xtpl->table_title(_('Summary'));
	$xtpl->table_add_category(_('Environment'));
	$xtpl->table_add_category(_('Package'));
	$xtpl->table_add_category(_('Count'));

	foreach ($sorted_pkgs as $v) {
		list($env, $env_pkgs) = $v;

		$pkg_counts = resource_package_counts($env_pkgs);
		$xtpl->table_td($env->label, false, false, '1', count($pkg_counts));

		foreach ($pkg_counts as $v) {
			list($pkg, $count) = $v;
			$xtpl->table_td($pkg->label);
			$xtpl->table_td($count."&times;");
			$xtpl->table_tr('#fff', '#fff', 'nohover');
		}
	}

	$xtpl->table_out();

	foreach ($sorted_pkgs as $v) {
		list($env, $env_pkgs) = $v;

		$xtpl->table_title(_('Environment').': '.$env->label);

		foreach ($env_pkgs as $pkg) {
			$xtpl->table_td(_('Package').':');
			$xtpl->table_td($pkg->label);

			if (isAdmin()) {
				$xtpl->table_td('<a href="?page=adminm&action=resource_packages_edit&id='.$user_id.'&pkg='.$pkg->id.'"><img src="template/icons/m_edit.png"  title="'._("Edit").'"></a>');

				if ($pkg->is_personal) {
					$xtpl->table_td('<a href="?page=cluster&action=resource_packages_edit&id='.$pkg->id.'"><img src="template/icons/tool.png"  title="'._("Configure resources").'"></a>');
				} else {
					$xtpl->table_td('<a href="?page=adminm&action=resource_packages_delete&id='.$user_id.'&pkg='.$pkg->id.'"><img src="template/icons/delete.png"  title="'._("Delete").'"></a>');
				}
			}

			$xtpl->table_tr();

			$xtpl->table_td(_('Resources').':');

			$items = $pkg->item->list(['meta' => ['includes' => 'cluster_resource']]);
			$s = '';

			foreach ($items as $it) {
				$s .= $it->cluster_resource->label.": ";

				if (in_array($it->cluster_resource->name, $convert))
					$s .= data_size_to_humanreadable($it->value);
				else
					$s .= $it->value;

				$s .= "<br>\n";
			}

			$xtpl->table_td($s);
			$xtpl->table_tr();

			$xtpl->table_td(_('Since').':');
			$xtpl->table_td(tolocaltz($pkg->created_at));
			$xtpl->table_tr();

			if (isAdmin()) {
				$xtpl->table_td(_('Added by').':');
				$xtpl->table_td($pkg->added_by_id ? user_link($pkg->added_by) : '-');
				$xtpl->table_tr();

				$xtpl->table_td(_('Comment').':');
				$xtpl->table_td($pkg->comment);
				$xtpl->table_tr();
			}

			$xtpl->table_out();
		}
	}

	$xtpl->sbar_add('<br><img src="template/icons/m_edit.png"  title="'._("Back to user details").'" />'._('Back to user details'), "?page=adminm&section=members&action=edit&id={$user_id}");

	if (isAdmin()) {
		$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Add package").'" />'._('Add package'), "?page=adminm&section=members&action=resource_packages_add&id={$user_id}");
	}
}

function user_resource_package_add_form($user_id) {
	global $xtpl, $api;

	$user = $api->user->show($user_id);
	$desc = $api->user_cluster_resource_package->create->getParameters('input');

	$xtpl->title(_('User').' <a href="?page=adminm&action=edit&id='.$user->id.'">#'.$user->id.'</a>: '._('Add cluster resource package'));
	$xtpl->form_create('?page=adminm&action=resource_packages_add&id='.$user->id, 'post');

	$xtpl->table_td('User'.':');
	$xtpl->table_td($user->id .' '. $user->login);
	$xtpl->table_tr();

	api_param_to_form('environment', $desc->environment);

	$xtpl->form_add_select(
		_('Package').':',
		'cluster_resource_package',
		resource_list_to_options($api->cluster_resource_package->list(['user' => null])),
		post_val('cluster_resource_package')
	);

	api_param_to_form('comment', $desc->comment);
	api_param_to_form('from_personal', $desc->from_personal);

	$xtpl->form_out(_('Add'));
}

function user_resource_package_edit_form($user_id, $pkg_id) {
	global $xtpl, $api;

	$user = $api->user->show($user_id);
	$pkg = $api->user_cluster_resource_package->show($pkg_id);
	$desc = $api->user_cluster_resource_package->update->getParameters('input');

	if ($user->id != $pkg->user_id)
		die('invalid user or package');

	$xtpl->title(_('User').' <a href="?page=adminm&action=edit&id='.$user->id.'">#'.$user->id.'</a>: '._('Edit cluster resource package'));
	$xtpl->form_create('?page=adminm&action=resource_packages_edit&id='.$user->id.'&pkg='.$pkg->id, 'post');

	$xtpl->table_td('User'.':');
	$xtpl->table_td($user->id .' '. $user->login);
	$xtpl->table_tr();

	$xtpl->table_td('Environment'.':');
	$xtpl->table_td($pkg->environment->label);
	$xtpl->table_tr();

	$xtpl->table_td('Package'.':');
	$xtpl->table_td($pkg->label);
	$xtpl->table_tr();

	api_param_to_form('comment', $desc->comment, $pkg->comment);

	$xtpl->form_out(_('Save'));

	if ($pkg->is_personal) {

	}

	$xtpl->sbar_add('<br><img src="template/icons/m_edit.png"  title="'._("Back").'" />'._('Back'), "?page=adminm&section=members&action=resource_packages&id={$user_id}");
	$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Edit resources").'" />'._('Edit resources'), "?page=cluster&action=resource_packages_edit&id={$pkg->cluster_resource_package_id}");
}

function user_resource_package_delete_form($user_id, $pkg_id) {
	global $xtpl, $api;

	$user = $api->user->show($user_id);
	$pkg = $api->user_cluster_resource_package->show($pkg_id);

	if ($user->id != $pkg->user_id)
		die('invalid user or package');

	$xtpl->title(_('Remove cluster resource package'));
	$xtpl->form_create('?page=adminm&action=resource_packages_delete&id='.$user->id.'&pkg='.$pkg->id, 'post');

	$xtpl->table_td('User'.':');
	$xtpl->table_td($user->id .' '. $user->login);
	$xtpl->table_tr();

	$xtpl->table_td('Environment'.':');
	$xtpl->table_td($pkg->environment->label);
	$xtpl->table_tr();

	$xtpl->table_td('Package'.':');
	$xtpl->table_td($pkg->label);
	$xtpl->table_tr();

	$xtpl->form_add_checkbox(_('Confirm').':', 'confirm', '1', false);

	$xtpl->form_out(_('Remove'));

	$xtpl->sbar_add('<br>'._("Back"), '?page=adminm&action=resource_packages&id='.$user->id);
}

function totp_devices_list_form($user) {
	global $xtpl, $api;

	$xtpl->table_title(_("TOTP devices"));
	$xtpl->table_add_category(_('Label'));
	$xtpl->table_add_category(_('Confirmed'));
	$xtpl->table_add_category(_('Enabled'));
	$xtpl->table_add_category(_('Use count'));
	$xtpl->table_add_category(_('Created at'));
	$xtpl->table_add_category(_('Last use'));
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');

	$devices = $user->totp_device->list();

	if ($devices->count() == 0) {
		$xtpl->table_td(
			'<a href="?page=adminm&action=totp_device_add&id='.$user->id.'">'.
			_('Add TOTP device').'</a>',
			false, false, '7'
		);
		$xtpl->table_tr();
	}

	foreach($devices as $dev) {
		$xtpl->table_td(h($dev->label));
		$xtpl->table_td(boolean_icon($dev->confirmed));
		$xtpl->table_td(boolean_icon($dev->enabled));
		$xtpl->table_td($dev->use_count.'&times;');
		$xtpl->table_td(tolocaltz($dev->created_at));
		$xtpl->table_td($dev->last_use_at ? tolocaltz($dev->last_use_at) : '-');

		$xtpl->table_td('<a href="?page=adminm&action=totp_device_toggle&id='.$user->id.'&dev='.$dev->id.'&toggle='.($dev->enabled ? 'disable' : 'enable').'&t='.csrf_token().'">'.($dev->enabled ? _('Disable') : _('Enable')).'</a>');
		$xtpl->table_td('<a href="?page=adminm&action=totp_device_edit&id='.$user->id.'&dev='.$dev->id.'"><img src="template/icons/m_edit.png"  title="'. _("Edit") .'" /></a>');
		$xtpl->table_td('<a href="?page=adminm&action=totp_device_del&id='.$user->id.'&dev='.$dev->id.'"><img src="template/icons/m_delete.png"  title="'. _("Delete") .'" /></a>');

		$xtpl->table_tr();
	}

	$xtpl->table_out();

	$xtpl->sbar_add('<br><img src="template/icons/m_edit.png"  title="'._("Add TOTP device").'" />'._('Add TOTP device'), "?page=adminm&action=totp_device_add&id={$user->id}");
	$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Back to user details").'" />'._('Back to user details'), "?page=adminm&action=edit&id={$user->id}");
}

function totp_device_add_form($user) {
	global $xtpl, $api;

	$xtpl->table_title(_("Add TOTP device"));
	$xtpl->form_create('?page=adminm&action=totp_device_add&id='.$user->id, 'post');

	$xtpl->table_td(
		_('Pick a name for your authentication device. It can be changed at any time.'),
		false, false, '2'
	);
	$xtpl->table_tr();

	$xtpl->form_add_input(_('Label').':', 'text', '40', 'label', post_val('label'));
	$xtpl->form_out(_('Continue'));

	$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Back to user details").'" />'._('Back to user details'), "?page=adminm&action=edit&id={$user->id}");
}

function totp_device_confirm_form($user, $dev) {
	global $xtpl, $api;

	$xtpl->table_title(_('Confirm TOTP device setup'));

	$xtpl->form_create('?page=adminm&action=totp_device_confirm&id='.$user->id.'&dev='.$dev->id, 'post');

	$xtpl->table_td(
		_('Install a TOTP authenticator application like FreeOTP or Google Authenticator '.
		  'and scan the QR code below, or enter the secret key manually.'),
		false, false, '2'
	);
	$xtpl->table_tr();

	$xtpl->table_td(_('Device').':');
	$xtpl->table_td(h($dev->label));
	$xtpl->table_tr();

	$qrCode = new QrCode($_SESSION['totp_setup']['provisioning_uri']);

	$xtpl->table_td(_('QR code').':');
	$xtpl->table_td(
		'<img src="'.$qrCode->writeDataUri().'">'
	);
	$xtpl->table_tr();

	$xtpl->table_td(_('Secret key').':');
	$xtpl->table_td(implode('&nbsp;', str_split($_SESSION['totp_setup']['secret'], 4)));
	$xtpl->table_tr();

	$xtpl->form_add_input(_('TOTP code').':', 'text', '30', 'code');

	$xtpl->table_td(
		_('Once enabled, this authentication device or any other configured '.
		  'device will be needed to log into your account without any '.
		  'exception. Two-factor authentication can be later turned off by '.
		  'disabling or removing all configured authentication devices.'),
		false, false, '2'
	);
	$xtpl->table_tr();

	$xtpl->form_out(_('Enable the device for two-factor authentication'));
}

function totp_device_configured_form($user, $dev, $recoveryCode) {
	global $xtpl;

	$xtpl->perex(
		_('The TOTP device was configured'),
		_('The device can now be used for authentication.')
	);
	$xtpl->table_title(_('Recovery code'));

	$xtpl->form_create('?page=adminm&action=edit&id='.$user->id, 'get');

	$xtpl->table_td(
		_('Two-factor authentication using TOTP is now enabled. In case you ever '.
		  'lose access to the TOTP authenticator device, you can use '.
		  'the recovery code below instead of the TOTP token to log in.').
		  '<input type="hidden" name="page" value="adminm">'.
		  '<input type="hidden" name="action" value="totp_devices">'.
		  '<input type="hidden" name="id" value="'.$user->id.'">',
		false, false, '2'
	);
	$xtpl->table_tr();

	$xtpl->table_td(_('Device').':');
	$xtpl->table_td(h($dev->label));
	$xtpl->table_tr();

	$xtpl->table_td(_('Recovery code').':');
	$xtpl->table_td($recoveryCode);
	$xtpl->table_tr();

	$xtpl->form_out(_('Go to TOTP device list'));
}

function totp_device_edit_form($user, $dev) {
	global $xtpl, $api;

	$xtpl->table_title(_("Edit TOTP device"));
	$xtpl->form_create('?page=adminm&action=totp_device_edit&id='.$user->id.'&dev='.$dev->id, 'post');
	$xtpl->form_add_input(_('Label').':', 'text', '40', 'label', post_val('label', $dev->label));
	$xtpl->form_out(_('Save'));

	$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Back to user details").'" />'._('Back to user details'), "?page=adminm&action=edit&id={$user->id}");
	$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Back to TOTP devices").'" />'._('Back to TOTP devices'), "?page=adminm&action=totp_devices&id={$user->id}");
}

function totp_device_del_form($user, $dev) {
	global $xtpl, $api;

	$xtpl->table_title(_('Confirm TOTP device deletion'));
	$xtpl->form_create('?page=adminm&action=totp_device_del&id='.$user->id.'&dev='.$dev->id, 'post');

	$xtpl->table_td('Device'.':');
	$xtpl->table_td(h($dev->label));
	$xtpl->table_tr();

	$xtpl->table_td(
		_('Two-factor authentication will be turned off when the last '.
		  'authentication device is either disabled or removed.'),
		false, false, '2'
	);
	$xtpl->table_tr();

	$xtpl->form_add_checkbox(_('Confirm').':', 'confirm', '1', false);

	$xtpl->form_out(_('Delete'));
}
