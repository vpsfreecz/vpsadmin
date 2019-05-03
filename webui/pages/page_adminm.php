<?php
/*
    ./pages/page_adminm.php

    vpsAdmin
    Web-admin interface for OpenVZ (see http://openvz.org)
    Copyright (C) 2008-2011 Pavel Snajdr, snajpa@snajpa.net
*/
function print_newm() {
	global $xtpl, $cfg_privlevel, $config;

	$xtpl->title(_("Add a member"));
	$xtpl->table_add_category('&nbsp;');
	$xtpl->table_add_category('&nbsp;');
	$xtpl->table_add_category('&nbsp;');
	$xtpl->form_create('?page=adminm&section=members&action=new2', 'post');
	$xtpl->form_add_input(_("Nickname").':', 'text', '30', 'm_nick', $_POST["m_nick"], _("A-Z, a-z, dot, dash"), 63);
	$xtpl->form_add_select(_("Privileges").':', 'm_level', $cfg_privlevel, $_POST["m_level"] ? $_POST["m_level"] : '2',  ' ');

	$m_pass_uid  = $xtpl->form_add_input(_("Password").':', 'password', '30', 'm_pass', '', '', -8);
	$m_pass2_uid = $xtpl->form_add_input(_("Repeat password").':', 'password', '30', 'm_pass2', '', ' ');

	$xtpl->form_add_input('', 'button', '', 'g_pass', _("Generate password"), '', '', 'onClick="javascript:formSubmit()"');
	$xtpl->form_add_input(_("Full name").':', 'text', '30', 'm_name', $_POST["m_name"], _("A-Z, a-z, with diacritic"), 255);
	$xtpl->form_add_input(_("E-mail").':', 'text', '30', 'm_mail', $_POST["m_mail"], ' ');
	$xtpl->form_add_input(_("Postal address").':', 'text', '30', 'm_address', $_POST["m_address"], ' ');

	if (payments_enabled()) {
		$xtpl->form_add_input(_("Monthly payment").':', 'text', '30', 'm_monthly_payment', $_POST["m_monthly_payment"] ? $_POST["m_monthly_payment"] : '300', ' ');
	}

	$xtpl->form_add_checkbox(_("Enable vpsAdmin mailer").':', 'm_mailer_enable', '1', $_POST["m_nick"] ? $_POST["m_mailer_enable"] : true, $hint = '');

	$xtpl->form_add_textarea(_("Info").':', 28, 4, 'm_info', $_POST["m_info"], _("Note for administrators"));
	$xtpl->form_out(_("Add"));

	$xtpl->assign('SCRIPT', '
		<script type="text/javascript">
			<!--
				function randomPassword() {
					var length = 10;
					var chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890";
  					var pass = "";

  					for(x=0; x<length; x++) {
  						i = Math.floor(Math.random() * 62);
    					pass += chars.charAt(i);
    				}

  					return pass;
				}

				function formSubmit() {
					var randpwd = randomPassword(8);
  					$("#'.$m_pass_uid.'").val(randpwd);
  					$("#'.$m_pass2_uid.'").val(randpwd);

  					return false;
				}
			-->
		</script>
	');
}

function print_editm($u) {
	global $xtpl, $cfg_privlevel, $config, $api;

	$xtpl->title(_("Manage members"));

	$xtpl->table_add_category(_("Member"));
	$xtpl->table_add_category('&nbsp;');
	$xtpl->form_create('?page=adminm&section=members&action=edit_member&id='.$u->id, 'post');

	$xtpl->table_td("Created".':');
	$xtpl->table_td(tolocaltz($u->created_at));
	$xtpl->table_tr();

	$xtpl->table_td("State".':');
	$xtpl->table_td($u->object_state);
	$xtpl->table_tr();

	if ($u->expiration_date) {
		$xtpl->table_td("Expiration".':');
		$xtpl->table_td(tolocaltz($u->expiration_date));
		$xtpl->table_tr();
	}

	if (isAdmin()) {
		$xtpl->table_add_category('&nbsp;');

		$xtpl->form_add_input(_("Nickname").':', 'text', '30', 'm_nick', $u->login, _("A-Z, a-z, dot, dash"), 63);
		$xtpl->form_add_select(_("Privileges").':', 'm_level', $cfg_privlevel, $u->level,  '');

	} else {
		$xtpl->table_td(_("Nickname").':');
		$xtpl->table_td($u->login);
		$xtpl->table_tr();

		$xtpl->table_td(_("Privileges").':');
		$xtpl->table_td($cfg_privlevel[$u->level]);
		$xtpl->table_tr();
	}

	if (payments_enabled()) {
		$xtpl->table_td(_("Paid until").':');
		user_payment_info($u);
		$xtpl->table_tr();
	}

	if (isAdmin()) {
		$vps_count = $api->vps->list(array(
			'user' => $u->id,
			'limit' => 0,
			'meta' => array('count' => true)
		))->getTotalCount();

		$xtpl->table_td(_("VPS count").':');
		$xtpl->table_td("<a href='?page=adminvps&action=list&user=".$u->id."'>".$vps_count."</a>");
		$xtpl->table_tr();
	}

	$xtpl->form_add_checkbox(_("Enable mail notifications from vpsAdmin").':', 'm_mailer_enable', '1', $u->mailer_enabled, $hint = '');

	api_param_to_form(
		'language',
		$api->user->update->getParameters('input')->language,
		$u->language_id,
		null,
		false
	);

	if (isAdmin()) {
		$xtpl->form_add_input(_("Monthly payment").':', 'text', '30', 'm_monthly_payment', $u->monthly_payment, ' ');
		$xtpl->form_add_textarea(_("Info").':', 28, 4, 'm_info', $u->info, _("Note for administrators"));

		$xtpl->form_add_checkbox(_("Require password reset").':', 'm_password_reset', '1', $u->password_reset, $hint = '');
		$xtpl->form_add_checkbox(_("Lock-out").':', 'm_lockout', '1', $u->lockout, $hint = '');
	}

	$xtpl->form_out(_("Save"));

	$xtpl->table_add_category(_("Change password"));
	$xtpl->table_add_category('&nbsp;');
	$xtpl->table_add_category('&nbsp;');
	$xtpl->form_create('?page=adminm&section=members&action=passwd&id='.$u->id, 'post');

	if (!isAdmin())
		$xtpl->form_add_input(_("Current password").':', 'password', '30', 'password');

	$xtpl->form_add_input(_("New password").':', 'password', '30', 'new_password', '', '', -8);
	$xtpl->form_add_input(_("Repeat new password").':', 'password', '30', 'new_password2', '', '', -8);
	$xtpl->form_out(_("Save"));

	$xtpl->table_add_category(_("Personal information"));
	$xtpl->table_add_category('&nbsp;');
	$xtpl->table_add_category('&nbsp;');
	$xtpl->form_create('?page=adminm&section=members&action=edit_personal&id='.$u->id, 'post');
	$xtpl->form_add_input(_("Full name").':', 'text', '30', 'full_name', post_val('full_name', $u->full_name), _("A-Z, a-z, with diacritic"), 255);
	$xtpl->form_add_input(_("E-mail").':', 'text', '30', 'email', post_val('email', $u->email), ' ');
	$xtpl->form_add_input(_("Postal address").':', 'text', '30', 'address', post_val('address', $u->address), ' ');

	if(!isAdmin()) {
		$xtpl->form_add_input(_("Reason for change").':', 'text', '50', 'change_reason', isset($_POST['change_reason']) ? $_POST['change_reason'] : null);
		$xtpl->table_td(_("Request for change will be sent to administrators for approval.".
		                  "Changes will not take effect immediately. You will be informed about the result."), false, false, 3);
		$xtpl->table_tr();
	}

	$xtpl->form_out(isAdmin() ? _("Save") : _("Request change"));

	$xtpl->form_create('?page=adminm&action=role_recipients&id='.$u->id, 'post');
	$xtpl->table_add_category(_('E-mail roles'));
	$xtpl->table_add_category(_('E-mails'));

	$xtpl->table_td(
		_('E-mails configured here override the primary e-mail. It is a comma separated list of e-mails, may contain line breaks.'),
		false, false, 2
	);
	$xtpl->table_tr();

	foreach ($u->mail_role_recipient->list() as $recp) {
		$xtpl->table_td(
			$recp->label, false, false, 1,
			$recp->description ? 2 : 1
		);
		$xtpl->form_add_textarea_pure(
			50, 5,
			"to[{$recp->id}]",
			$_POST && $_POST['to'][$recp->id] ? $_POST['to'][$recp->id] : str_replace(',', ",\n", $recp->to)
		);
		$xtpl->table_tr();

		if ($recp->description) {
			$xtpl->table_td($recp->description);
			$xtpl->table_tr();
		}
	}

	$xtpl->table_td(
		'<a href="?page=adminm&action=template_recipients&id='.$u->id.'">'.
		_('Advanced configuration').
		'</a>'
	);
	$xtpl->table_td($xtpl->html_submit(_('Save')));
	$xtpl->table_tr();
	$xtpl->form_out_raw();

	if (isAdmin()) {
		lifetimes_set_state_form('user', $u->id, $u);

		$xtpl->sbar_add("<br><img src=\"template/icons/m_switch.png\"  title=". _("Switch context") ." /> Switch context", "?page=login&action=switch_context&m_id={$u->id}&next=".urlencode($_SERVER["REQUEST_URI"]));
		$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("State log").'" />'._('State log'), '?page=lifetimes&action=changelog&resource=user&id='.$u->id.'&return='. urlencode($_SERVER['REQUEST_URI']));
	}

	$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Advanced mail configuration").'" />'._('Advanced e-mail configuration'), "?page=adminm&section=members&action=template_recipients&id={$u->id}");
	$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Public keys").'" />'._('Public keys'), "?page=adminm&section=members&action=pubkeys&id={$u->id}");
	$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Authentication tokens").'" />'._('Authentication tokens'), "?page=adminm&section=members&action=auth_tokens&id={$u->id}");
	$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Session log").'" />'._('Session log'), "?page=adminm&action=user_sessions&id={$u->id}");
	$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Resource packages").'" />'._('Resource packages'), "?page=adminm&section=members&action=resource_packages&id={$u->id}");
	$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Cluster resources").'" />'._('Cluster resources'), "?page=adminm&section=members&action=cluster_resources&id={$u->id}");
	$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Environment configs").'" />'._('Environment configs'), "?page=adminm&section=members&action=env_cfg&id={$u->id}");
}

function print_deletem($u) {
	global $xtpl, $api;

	$xtpl->table_title(_("Delete member"));
	$xtpl->table_td(_("Full name").':');
	$xtpl->table_td($u->full_name);
	$xtpl->table_tr();
	$xtpl->form_create('?page=adminm&section=members&action=delete2&id='.$u->id, 'post');
	$xtpl->table_td(_("VPSes to be deleted").':');

	$vpses = '';

	foreach ($api->vps->list(array('user' => $u->id)) as $vps)
		$vpses .= '<a href="?page=adminvps&action=info&veid='.$vps->id.'">#'.$vps->id.' - '.$vps->hostname.'</a><br>';

	$xtpl->table_td($vpses);
	$xtpl->table_tr();

	$desc = $api->user->delete->getParameters('input')->object_state;
	api_param_to_form('object_state', $desc);

	$xtpl->form_out(_("Delete"));
}

function list_pubkeys() {
	global $api, $xtpl;

	$xtpl->table_title(_("Public keys"));
	$xtpl->table_add_category(_('Label'));
	$xtpl->table_add_category(_('Fingerprint'));
	$xtpl->table_add_category(_('Comment'));
	$xtpl->table_add_category(_('Auto add'));
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');

	$pubkeys = $api->user($_GET['id'])->public_key->list();

	if ($pubkeys->count() == 0) {
		$xtpl->table_td(
			'<a href="?page=adminm&section=members&action=pubkey_add&id='.$_GET['id'].'">'.
			_('Add a public key').'</a>',
			false, false, '7'
		);
		$xtpl->table_tr();
	}

	foreach($pubkeys as $k) {
		$xtpl->table_td(h($k->label));
		$xtpl->table_td($k->fingerprint);
		$xtpl->table_td(h($k->comment));
		$xtpl->table_td(boolean_icon($k->auto_add));

		$xtpl->table_td('<a href="?page=adminm&section=members&action=pubkey_edit&id='.$_GET['id'].'&pubkey_id='.$k->id.'"><img src="template/icons/m_edit.png"  title="'. _("Edit") .'" /></a>');
		$xtpl->table_td('<a href="?page=adminm&section=members&action=pubkey_del&id='.$_GET['id'].'&pubkey_id='.$k->id.'"><img src="template/icons/m_delete.png"  title="'. _("Delete") .'" /></a>');

		$xtpl->table_tr();
	}

	$xtpl->table_out();

	$xtpl->sbar_add('<br><img src="template/icons/m_edit.png"  title="'._("Add public key").'" />'._('Add public key'), "?page=adminm&section=members&action=pubkey_add&id={$_GET['id']}");
	$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Back to user details").'" />'._('Back to user details'), "?page=adminm&section=members&action=edit&id={$_GET['id']}");

}

function add_pubkey($user) {
	global $api, $xtpl;

	$xtpl->table_title(_('Add public key'));
	$xtpl->form_create('?page=adminm&section=members&action=pubkey_add&id='.$user.'&pubkey_id='.$id, 'post');

	$xtpl->form_add_input(_("Label").':', 'text', '30', 'label', post_val('label'));
	$xtpl->form_add_textarea(_("Public key").':', '80', '12', 'key', post_val('key'));
	$xtpl->form_add_checkbox(
		_("Auto add").':', 'auto_add', '1', post_val('auto_add', false), '',
		_('Add this key to newly created VPS')
	);

	$xtpl->form_out(_('Save'));

	$xtpl->sbar_add('<br><img src="template/icons/m_edit.png"  title="'._("Back to public keys").'" />'._('Back to public keys'), "?page=adminm&section=members&action=pubkeys&id={$user}");
}

function edit_pubkey($user, $id) {
	global $api, $xtpl;

	$k = $api->user($user)->public_key->find($id);

	$xtpl->table_title(_('Edit public key').' #'.$id);
	$xtpl->form_create('?page=adminm&section=members&action=pubkey_edit&id='.$user.'&pubkey_id='.$id, 'post');

	$xtpl->form_add_input(_("Label").':', 'text', '30', 'label', post_val('label', $k->label));
	$xtpl->form_add_textarea(_("Public key").':', '80', '12', 'key', post_val('key', $k->key));
	$xtpl->form_add_checkbox(
		_("Auto add").':', 'auto_add', '1', post_val('auto_add', $k->auto_add), '',
		_('Add this key to newly created VPS')
	);

	$xtpl->table_td(_('Fingerprint').':');
	$xtpl->table_td($k->fingerprint);
	$xtpl->table_tr();

	$xtpl->table_td(_('Comment').':');
	$xtpl->table_td(h($k->comment));
	$xtpl->table_tr();

	$xtpl->table_td(_('Created at').':');
	$xtpl->table_td(tolocaltz($k->created_at));
	$xtpl->table_tr();

	$xtpl->table_td(_('Updated at').':');
	$xtpl->table_td(tolocaltz($k->updated_at));
	$xtpl->table_tr();

	$xtpl->form_out(_('Save'));

	$xtpl->sbar_add('<br><img src="template/icons/m_edit.png"  title="'._("Back to public keys").'" />'._('Back to public keys'), "?page=adminm&section=members&action=pubkeys&id={$user}");
}

function list_auth_tokens() {
	global $api, $xtpl;

	$xtpl->table_title(_("Authentication tokens"));
	$xtpl->table_add_category(_('Token'));
	$xtpl->table_add_category(_('Valid to'));
	$xtpl->table_add_category(_('Label'));
	$xtpl->table_add_category(_('Use count'));
	$xtpl->table_add_category(_('Lifetime'));
	$xtpl->table_add_category(_('Interval'));
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');

	$token = array();

	if(isAdmin()) {
		$tokens = $api->auth_token->list(array('user' => $_GET['id']));
	} else {
		$tokens = $api->auth_token->list();
	}

	foreach($tokens as $t) {
		$xtpl->table_td(substr($t->token, 0, 8).'…');

		if($t->lifetime == 'permanent')
			$xtpl->table_td(_('Forever'), '#66FF66');
		else
			$xtpl->table_td($t->valid_to, strtotime($t->valid_to) > time() ? '#66FF66' : '#B22222');

		$xtpl->table_td(h($t->label));
		$xtpl->table_td($t->use_count."&times;");
		$xtpl->table_td($t->lifetime);
		$xtpl->table_td($t->interval._(' seconds'));

		$xtpl->table_td('<a href="?page=adminm&section=members&action=auth_token_edit&id='.$_GET['id'].'&token_id='.$t->id.'"><img src="template/icons/m_edit.png"  title="'. _("Edit") .'" /></a>');
		$xtpl->table_td('<a href="?page=adminm&section=members&action=auth_token_del&id='.$_GET['id'].'&token_id='.$t->id.'"><img src="template/icons/m_delete.png"  title="'. _("Delete") .'" /></a>');

		$xtpl->table_tr();
	}

	$xtpl->table_out();

	$xtpl->sbar_add('<br><img src="template/icons/m_edit.png"  title="'._("Back to user details").'" />'._('Back to user details'), "?page=adminm&section=members&action=edit&id={$_GET['id']}");
}

function edit_auth_token($id) {
	global $api, $xtpl;

	$t = $api->auth_token->find($id);

	$xtpl->table_title(_('Edit authentication token').' #'.$id);
	$xtpl->form_create('?page=adminm&section=members&action=auth_token_edit&id='.$_GET['id'].'&token_id='.$id, 'post');

	$xtpl->table_td(_('Token').':');
	$xtpl->table_td($t->token);
	$xtpl->table_tr();

	$xtpl->table_td(_('Valid to').':');

	if($t->lifetime == 'permanent')
		$xtpl->table_td(_('Forever'), '#66FF66');
	else
		$xtpl->table_td($t->valid_to, strtotime($t->valid_to) > time() ? '#66FF66' : '#B22222');

	$xtpl->table_tr();

	$xtpl->form_add_input(_("Label").':', 'text', '30', 'label', $t->label);

	$xtpl->table_td(_('Use count').':');
	$xtpl->table_td($t->use_count.'&times;');
	$xtpl->table_tr();

	$xtpl->table_td(_('Lifetime').':');
	$xtpl->table_td($t->lifetime);
	$xtpl->table_tr();

	$xtpl->table_td(_('Interval').':');
	$xtpl->table_td($t->interval._(' seconds'));
	$xtpl->table_tr();

	$xtpl->form_out(_('Save'));

	$xtpl->sbar_add('<br><img src="template/icons/m_edit.png"  title="'._("Back to authentication tokens").'" />'._('Back to authentication tokens'), "?page=adminm&section=members&action=auth_tokens&id={$_GET['id']}");
}

function list_cluster_resources() {
	global $xtpl, $api;

	$convert = array('memory', 'swap', 'diskspace');

	$xtpl->title(_('User').' <a href="?page=adminm&action=edit&id='.$_GET['id'].'">#'.$_GET['id'].'</a>: '._('Cluster resources'));

	$resources = $api->user($_GET['id'])->cluster_resource->list(array('meta' => array('includes' => 'environment,cluster_resource')));
	$by_env = array();

	foreach ($resources as $r) {
		if (!isset($by_env[$r->environment_id]))
			$by_env[$r->environment_id] = array();

		$by_env[$r->environment_id][] = $r;
	}

	foreach ($by_env as $res) {
		$xtpl->table_title(_('Environment').': '.$res[0]->environment->label);

		$xtpl->table_add_category(_("Resource"));
		$xtpl->table_add_category(_("Value"));
		$xtpl->table_add_category(_("Step size"));
		$xtpl->table_add_category(_("Used"));
		$xtpl->table_add_category(_("Free"));

		foreach ($res as $r) {
			$xtpl->table_td($r->cluster_resource->label);

			if (in_array($r->cluster_resource->name, $convert)) {
				$xtpl->table_td(data_size_to_humanreadable($r->value));
				$xtpl->table_td(data_size_to_humanreadable($r->cluster_resource->stepsize));
				$xtpl->table_td(data_size_to_humanreadable($r->used));
				$xtpl->table_td(data_size_to_humanreadable($r->free));

			} else {
				$xtpl->table_td(approx_number($r->value));
				$xtpl->table_td(approx_number($r->cluster_resource->stepsize));
				$xtpl->table_td(approx_number($r->used));
				$xtpl->table_td(approx_number($r->free));
			}

			$xtpl->table_tr();
		}

		$xtpl->table_out();
	}

	$xtpl->sbar_add('<br><img src="template/icons/m_edit.png"  title="'._("Back to user details").'" />'._('Back to user details'), "?page=adminm&section=members&action=edit&id={$_GET['id']}");
}

function request_approve() {
	global $xtpl, $api;

	if(!isAdmin())
		return;

	if (isset($_POST['action'])) {
		$params = client_params_to_api(
			$api->user_request->{$_GET['type']}->resolve,
			$_POST
		);

	} else {
		$params = array('action' => 'approve');
	}

	try {
		$api->user_request->{$_GET['type']}->resolve($_GET['id'], $params);

		notify_user(_("Request approved"), '');
		redirect('?page=adminm&section=members&action=approval_requests');

	} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
		$xtpl->perex_format_errors(_('Request approval failed'), $e->getResponse());
		approval_requests_details($_GET['type'], $_GET['id']);
	}
}

function request_deny() {
	global $xtpl, $api;

	if(!isAdmin())
		return;

	if (isset($_POST['action'])) {
		$params = client_params_to_api(
			$api->user_request->{$_GET['type']}->resolve,
			$_POST
		);

	} else {
		$params = array('action' => 'deny');
	}

	try {
		$api->user_request->{$_GET['type']}->resolve($_GET['id'], $params);

		notify_user(_("Request denied"), '');
		redirect('?page=adminm&section=members&action=approval_requests');

	} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
		$xtpl->perex_format_errors(_('Request denial failed'), $e->getResponse());
		approval_requests_details($_GET['type'], $_GET['id']);
	}
}

function request_ignore() {
	global $xtpl, $api;

	if(!isAdmin())
		return;

	if (isset($_POST['action'])) {
		$params = client_params_to_api(
			$api->user_request->{$_GET['type']}->resolve,
			$_POST
		);

	} else {
		$params = array('action' => 'ignore');
	}

	try {
		$api->user_request->{$_GET['type']}->resolve($_GET['id'], $params);

		notify_user(_("Request ignored"), '');
		redirect('?page=adminm&section=members&action=approval_requests');

	} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
		$xtpl->perex_format_errors(_('Request ignore failed'), $e->getResponse());
		approval_requests_details($_GET['type'], $_GET['id']);
	}
}

function request_correction() {
	global $xtpl, $api;

	if(!isAdmin())
		return;

	if (isset($_POST['action'])) {
		$params = client_params_to_api(
			$api->user_request->{$_GET['type']}->resolve,
			$_POST
		);

	} else {
		$params = array('action' => 'request_correction');
	}

	try {
		$api->user_request->{$_GET['type']}->resolve($_GET['id'], $params);

		notify_user(_("Request correction requested"), '');
		redirect('?page=adminm&section=members&action=approval_requests');

	} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
		$xtpl->perex_format_errors(_('Request correction request failed'), $e->getResponse());
		approval_requests_details($_GET['type'], $_GET['id']);
	}
}

function list_members() {
	global $xtpl, $api, $config;

	if (isAdmin()) {
		$xtpl->title(_("Manage members [Admin mode]"));

		$xtpl->table_title(_('Filters'));
		$xtpl->form_create('', 'get', 'user-filter', false);

		$xtpl->table_td(_("Limit").':'.
			'<input type="hidden" name="page" value="adminm">'.
			'<input type="hidden" name="action" value="list">'
		);
		$xtpl->form_add_input_pure('text', '40', 'limit', get_val('limit', '25'), '');
		$xtpl->table_tr();

		$xtpl->form_add_input(_("Offset").':', 'text', '40', 'offset', get_val('offset', '0'), '');
		$xtpl->form_add_input(_("Login").':', 'text', '40', 'login', get_val('login', ''), '');
		$xtpl->form_add_input(_("Full name").':', 'text', '40', 'full_name', get_val('full_name', ''), '');
		$xtpl->form_add_input(_("E-mail").':', 'text', '40', 'email', get_val('email', ''), '');
		$xtpl->form_add_input(_("Address").':', 'text', '40', 'address', get_val('address', ''), '');
		$xtpl->form_add_input(_("Access level").':', 'text', '40', 'level', get_val('level', ''), '');
		$xtpl->form_add_input(_("Info").':', 'text', '40', 'info', get_val('info', ''), '');
		$xtpl->form_add_input(_("Monthly payment").':', 'text', '40', 'monthly_payment', get_val('monthly_payment', ''), '');
		$xtpl->form_add_checkbox(_("Mailer enabled").':', 'mailer_enabled', 1, get_val('mailer_enabled', ''));

		$p = $api->vps->index->getParameters('input')->object_state;
		api_param_to_form('object_state', $p, $_GET['object_state']);

		$xtpl->form_out(_('Show'));

	} else {
		$xtpl->title(_("Manage members"));
	}

	if (!isAdmin() || $_GET['action'] == 'list') {
		$xtpl->table_add_category('ID');
		$xtpl->table_add_category(_("NICKNAME"));
		$xtpl->table_add_category(_("VPS"));

		if (payments_enabled()) {
			$xtpl->table_add_category(_("$"));
		}

		$xtpl->table_add_category(_("FULL NAME"));
		$xtpl->table_add_category(_("LAST ACTIVITY"));

		if (payments_enabled()) {
			$xtpl->table_add_category(_("PAYMENT"));
		}

		$xtpl->table_add_category('');
		$xtpl->table_add_category('');

		if (isAdmin()) {
			$params = array(
				'limit' => get_val('limit', 25),
				'offset' => get_val('offset', 0),
				'meta' => array('count' => true)
			);

			$filters = array(
				'login', 'full_name', 'email', 'address', 'level', 'info', 'monthly_payment',
				'mailer_enabled', 'object_state'
			);

			foreach ($filters as $f) {
				if ($_GET[$f])
					$params[$f] = $_GET[$f];
			}

			$users = $api->user->list($params);

		} else {
			$users = array($api->user->current());
		}

		foreach ($users as $u) {
			$last_activity = strtotime($u->last_activity_at);

			$xtpl->table_td($u->id);

			if ((isAdmin()) && ($u->id != $_SESSION["user"]["id"])) {
				$xtpl->table_td(
					'<a href="?page=login&action=switch_context&m_id='.$u->id.'&next='.urlencode($_SERVER["REQUEST_URI"]).'">'.
					'<img src="template/icons/m_switch.png" title="'._("Switch context").'"></a>'.
					$u->login
				);

			} else {
				$xtpl->table_td($u->login);
			}

			$vps_count = $api->vps->list(array(
				'user' => $u->id,
				'limit' => 0,
				'meta' => array('count' => true)
			))->getTotalCount();

			$xtpl->table_td('<a href="?page=adminvps&action=list&user='.$u->id.'">[ '.$vps_count.' ]</a>');

			if (payments_enabled())
				$xtpl->table_td($u->monthly_payment);

			$xtpl->table_td(h($u->full_name));

			if ($last_activity) {
				if (($last_activity + 2592000) < time()) {
					// Month
					$xtpl->table_td(date('Y-m-d H:i:s', $last_activity), '#FFF');

				} elseif (($last_activity + 604800) < time()) {
					// Week
					$xtpl->table_td(date('Y-m-d H:i:s', $last_activity), '#99FF66');

				} elseif (($last_activity + 86400) < time()) {
					// Day
					$xtpl->table_td(date('Y-m-d H:i:s', $last_activity), '#66FF33');
				} else {
					// Less
					$xtpl->table_td(date('Y-m-d H:i:s', $last_activity), '#33CC00');
				}

			} else {
				$xtpl->table_td("---", '#FFF');
			}

			if (payments_enabled())
				user_payment_info($u);

			$xtpl->table_td('<a href="?page=adminm&section=members&action=edit&id='.$u->id.'"><img src="template/icons/m_edit.png"  title="'. _("Edit") .'" /></a>');

			if (isAdmin()) {
				$xtpl->table_td('<a href="?page=adminm&section=members&action=delete&id='.$u->id.'"><img src="template/icons/m_delete.png"  title="'. _("Delete") .'" /></a>');

			} else {
				$xtpl->table_td('<img src="template/icons/vps_delete_grey.png"  title="'. _("Cannot delete yourself") .'" />');
			}

			if (isAdmin() && ($u->info != '')) {
				$xtpl->table_td('<img src="template/icons/info.png" title="'.$u->info.'"');
			}

			if ($u->level >= PRIV_SUPERADMIN) {
				$xtpl->table_tr('#22FF22');
			} elseif ($u->level >= PRIV_ADMIN) {
				$xtpl->table_tr('#66FF66');
			} elseif ($u->level >= PRIV_POWERUSER) {
				$xtpl->table_tr('#BBFFBB');
			} elseif ($u->object_state != "active") {
				$xtpl->table_tr('#A6A6A6');
			} else {
				$xtpl->table_tr();
			}
		}

		$xtpl->table_out();
	}
}

function payments_overview() {
	global $xtpl, $api;

	$xtpl->table_title(_('Payments overview'));

	$users = get_all_users();

	$totalIncome = 0;
	$thisMonthIncome = 0;
	$paidCnt = 0;
	$unpaidCnt = 0;
	$expiringCnt = 0;
	$payments = array();

	$thisMonth = mktime(0, 0, 0, date('n'), 1, date('Y'));
	$nextMonth = strtotime('+1 month', $thisMonth);
	$now = time();

	foreach ($users as $u) {
		$totalIncome += $u->monthly_payment;

		$paidUntil = strtotime($u->paid_until);

		if (!$paidUntil || ($paidUntil >= $thisMonth && $paidUntil < $nextMonth))
			$thisMonthIncome += $u->monthly_payment;

		if ($paidUntil < $now)
			$unpaidCnt++;
		elseif ($paidUntil - 7*24*60*60 < $now)
			$expiringCnt++;
		else
			$paidCnt++;

		if (array_key_exists($u->monthly_payment, $payments))
			$payments[$u->monthly_payment]++;
		else
			$payments[$u->monthly_payment] = 1;
	}

	$xtpl->table_td(_('Total monthly income').':');
	$xtpl->table_td(number_format($totalIncome));
	$xtpl->table_tr();

	$xtpl->table_td(_("Estimated this month's income").':');
	$xtpl->table_td(number_format($thisMonthIncome));
	$xtpl->table_tr();

	$xtpl->table_td(_('Paid user count').':');
	$xtpl->table_td(number_format($paidCnt));
	$xtpl->table_tr();

	$xtpl->table_td(_('Users nearing expiration').':');
	$xtpl->table_td(number_format($expiringCnt));
	$xtpl->table_tr();

	$xtpl->table_td(_('Unpaid user count').':');
	$xtpl->table_td(number_format($unpaidCnt));
	$xtpl->table_tr();

	$xtpl->table_out();


	$xtpl->table_title(_('Monthly payments'));
	$xtpl->table_add_category(_('Amount'));
	$xtpl->table_add_category(_('Count'));

	asort($payments);

	foreach (array_reverse($payments, true) as $amount => $count) {
		$xtpl->table_td(number_format($amount));
		$xtpl->table_td(number_format($count)."&times;");
		$xtpl->table_tr();
	}

	$xtpl->table_out();
}

function estimate_income () {
	global $xtpl, $api;

	$xtpl->table_title(_('Estimate income'));

	$xtpl->form_create('', 'get');

	$y = date('Y');
	$xtpl->table_td(
		_('Year').':'.
		'<input type="hidden" name="page" value="adminm">'.
		'<input type="hidden" name="action" value="estimate_income">'
	);
	$xtpl->form_add_number_pure('y', get_val('y', $y), $y);
	$xtpl->table_tr();

	$xtpl->form_add_number(_('Month').':', 'm', get_val('m', date('n')), 1, 12, 1);
	$xtpl->form_add_select(_('Select users').':', 's', [
		'exactly_until' => _('Having paid until exactly to the selected year/month'),
		'all_until' => _('Having paid until the selected year/month or before'),
	], get_val('s', 'exactly_until'));
	$xtpl->form_add_number(_('Payment for').':', 'd', get_val('d', 1), 1, 1000, 1, _('months'));
	$xtpl->form_out(_('Show'));

	if (!$_GET['y'] || !$_GET['m'] || !$_GET['d'])
		return;

	$income = $api->payment_stats->estimate_income([
		'year' => $_GET['y'],
		'month' => $_GET['m'],
		'select' => $_GET['s'],
		'duration' => $_GET['d'],
	]);

	$xtpl->table_td(_('Users').':');
	$xtpl->table_td(number_format($income['user_count']));
	$xtpl->table_tr();

	$xtpl->table_td(_('Estimated income').':');
	$xtpl->table_td(number_format($income['estimated_income']));
	$xtpl->table_tr();

	$xtpl->table_out();
}

if ($_SESSION["logged_in"]) {

	if (isAdmin()) {
		$xtpl->sbar_add('<img src="template/icons/m_add.png"  title="'._("New member").'" /> '._("New member"), '?page=adminm&section=members&action=new');

		if ($api->user_request)
			$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Requests for approval").'" /> '._("Requests for approval"), '?page=adminm&section=members&action=approval_requests');
	}

	$action = isset($_GET["action"]) ? $_GET["action"] : null;
	switch ($action) {
		case 'new':
			if (isAdmin()) {
				print_newm();
			}
			break;
		case 'new2':
			if (isAdmin()) {
				if ($_POST['m_pass'] != $_POST['m_pass2']) {
					$xtpl->perex(_("Passwords don't match"), _('The two passwords differ.'));
					print_newm();
					break;
				}

				try {
					$user = $api->user->create(array(
						'login' => $_POST['m_nick'],
						'password' => $_POST['m_pass'],
						'full_name' => $_POST['m_name'],
						'email' => $_POST['m_mail'],
						'address' => $_POST['m_address'],
						'level' => $_POST['m_level'],
						'info' => $_POST['m_info'],
						'monthly_payment' => $_POST['m_monthly_payment'],
						'mailer_enabled' => $_POST['m_mailer_enable']
					));

					notify_user(_('User created'), _('The user was successfully created.'));
					redirect('?page=adminm&action=edit&id='.$user->id);

				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('User creation failed'), $e->getResponse());
					print_newm();
				}
			}
			break;
		case 'delete':
			if (isAdmin() && ($u = $api->user->find($_GET["id"]))) {

				$xtpl->perex(_("Are you sure, you want to delete")
								.' '.$u->login.'?','');
				print_deletem($u);

			}
			break;
		case 'delete2':
			if (isAdmin() && ($u = $api->user->find($_GET["id"]))) {
				$xtpl->perex(_("Are you sure, you want to delete")
						.' '.$u->login.'?',
						'<a href="?page=adminm">'
						. strtoupper(_("No"))
						. '</a> | <a href="?page=adminm&section=members&action=delete3&id='.$u->id.'&&state='.$_REQUEST["object_state"].'">'
						. strtoupper(_("Yes")).'</a>');
				}
			break;
		case 'delete3':
			if (isAdmin() && ($u = $api->user->find($_GET["id"]))) {
				try {
					$u->delete(array(
						'object_state' => $_GET['object_state'],
					));

					notify_user(_("User deleted"), _('The user was successfully deleted.'));
					redirect('?page=adminm', 350);

				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('User deletion failed'), $e->getResponse());
					print_newm();
				}
			}
			break;
		case 'edit':
			print_editm(isAdmin() ? $api->user->find($_GET["id"]) : $api->user->current());
			break;
		case 'edit_member':
			try {
				$user = $api->user->show($_GET['id']);

				$params = array(
					'mailer_enabled' => isset($_POST['m_mailer_enable']),
					'language' => $_POST['language'],
				);

				if (isAdmin()) {
					$params['login'] = $_POST['m_nick'];
					$params['level'] = $_POST['m_level'];
					$params['info'] = $_POST['m_info'];
					$params['password_reset'] = isset($_POST['m_password_reset']);
					$params['lockout'] = isset($_POST['m_lockout']);
				}

				$user->update($params);

				if (isAdmin() && $user->monthly_payment != $_POST['m_monthly_payment']) {
					$api->user_account->update($user->id, array(
						'monthly_payment' => $_POST['m_monthly_payment'],
					));
				}

				notify_user(_('User updated'), _('The user was successfully updated.'));
				redirect('?page=adminm&action=edit&id='.$user->id);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('User update failed'), $e->getResponse());
				print_editm($api->user->find($_GET['id']));
			}

			break;
		case 'passwd':
			$u = $api->user->find($_GET["id"]);

			if ($_POST["new_password"] != $_POST["new_password2"]) {
				$xtpl->perex(_("Invalid entry").': '._("Password"), _("The two passwords do not match."));
				print_editm($u);

			} else {
				try {
					$params = array('new_password' => $_POST['new_password']);

					if (!isAdmin())
						$params['password'] = $_POST['password'];

					$u->update($params);

					notify_user(_("Password set"), _("The password was successfully changed."));
					redirect('?page=adminm&action=edit&id='.$u->id);

				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('Password change failed'), $e->getResponse());
					print_editm($u);
				}
			}

			break;
		case 'edit_personal':
			$u = $api->user->find($_GET["id"]);

			if(isAdmin()) {
				try {
					$u->update(array(
						'full_name' => $_POST['full_name'],
						'email' => $_POST['email'],
						'address' => $_POST['address'],
					));

					notify_user(_("Changes saved"), _('User personal information were updated.'));
					redirect('?page=adminm&action=edit&id='.$u->id);

				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('User update failed'), $e->getResponse());
					print_editm($u);
				}

			} elseif ($api->user_request->change) {
				try {
					$req = $api->user_request->change->create(array(
						'full_name' => $_POST['full_name'],
						'email' => $_POST['email'],
						'address' => $_POST['address'],
						'change_reason' => $_POST['change_reason'],
					));

					notify_user(
						_("Request").' #'.$req->id.' '._("was accepted"),
						_("Please wait for the administrator to approve or deny your request.")
					);
					redirect('?page=adminm&section=members&action=edit&id='.$u->id);

				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('Change request failed'), $e->getResponse());
					print_editm($u);
				}
			}

			break;

		case 'role_recipients':
			csrf_check();

			try {
				foreach ($_POST['to'] as $role => $emails) {
					$api->user($_GET['id'])->mail_role_recipient($role)->update(array(
						'to' => $emails,
					));
				}

				notify_user(_('Role e-mails updated'), _('The changes were successfully saved.'));
				redirect('?page=adminm&action=edit&id='.$_GET['id']);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Update failed'), $e->getResponse());
				print_editm($api->user->show($_GET['id']));
			}
			break;

		case 'template_recipients':
			$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Back to user details").'" />'._('Back to user details'), "?page=adminm&action=edit&id={$_GET['id']}");

			if (isset($_POST['to'])) {
				csrf_check();

				try {
					foreach ($_POST['to'] as $tpl => $emails) {
						$api->user($_GET['id'])->mail_template_recipient($tpl)->update(array(
							'to' => $emails,
							'enabled' => $_POST['disable'][$tpl] === '1' ? false : true,
						));
					}

					notify_user(_('Template e-mails updated'), _('The changes were successfully saved.'));
					redirect('?page=adminm&action=edit&id='.$_GET['id']);

				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('Update failed'), $e->getResponse());
					mail_template_recipient_form($_GET['id']);
				}

			} else {
				mail_template_recipient_form($_GET['id']);
			}
			break;

		case 'payset':
			if (!isAdmin())
				break;

			user_payment_form($_GET['id']);
			$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Back to user details").'" />'._('Back to user details'), "?page=adminm&action=edit&id={$_GET['id']}");
			break;

		case 'payset2':
			if (!isAdmin())
				break;

			try {
				if (isset($_POST['paid_until'])) {
					$api->user_account->update($_GET['id'], array(
						'paid_until' => $_POST['paid_until'],
					));

					notify_user(_("Paid until date set"), '');

				} elseif (isset($_POST['amount'])) {
					$api->user_payment->create(array(
						'user' => $_GET['id'],
						'amount' => $_POST['amount'],
					));

					notify_user(_("Payment accepted"), '');
				}

				redirect('?page=adminm&action=payset&id='.$_GET['id']);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Failed to add payment'), $e->getResponse());
				user_payment_form($_GET['id']);
			}

			break;

		case 'incoming_payments':
			if (!isAdmin())
				break;

			incoming_payments_list();
			break;

		case 'incoming_payment':
			if (!isAdmin())
				break;

			incoming_payments_details($_GET['id']);
			break;

		case 'incoming_payment_state':
			if (!isAdmin())
				break;

			try {
				$api->incoming_payment->update($_GET['id'], client_params_to_api(
					$api->incoming_payment->update
				));

				notify_user(_("State changed"), '');
				redirect('?page=adminm&action=incoming_payment&id='.$_GET['id']);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Unable to change state'), $e->getResponse());
				incoming_payments_details($_GET['id']);
			}

			break;

		case 'incoming_payment_assign':
			if (!isAdmin())
				break;

			try {
				$api->user_payment->create(array(
					'user' => $_POST['user'],
					'incoming_payment' => $_GET['id'],
				));

				notify_user(_("Payment assigned"), '');
				redirect('?page=adminm&action=payset&id='.$_POST['user']);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Failed to add payment'), $e->getResponse());
				incoming_payments_details($_GET['id']);
			}

			break;

		case 'payments_history':
			if (!isAdmin())
				break;

			user_payment_history();
			break;

		case 'payments_overview':
			if (isAdmin())
				payments_overview();
			break;

		case 'estimate_income':
			if (isAdmin())
				estimate_income();
			break;

		case 'pubkeys':
			list_pubkeys();
			break;

		case 'pubkey_add':
			if(isset($_POST['label'])) {
				try {
					$api->user($_GET['id'])->public_key->create(array(
						'label' => $_POST['label'],
						'key' => trim($_POST['key']),
						'auto_add' => isset($_POST['auto_add']),
					));

					notify_user(_('Public key saved'), '');
					redirect('?page=adminm&section=members&action=pubkeys&id='.$_GET['id']);

				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('Failed to save public key'), $e->getResponse());
					add_pubkey($_GET['id']);
				}

			} else {
				add_pubkey($_GET['id']);
			}

			break;

		case 'pubkey_edit':
			if(isset($_POST['label'])) {
				try {
					$api->user($_GET['id'])->public_key($_GET['pubkey_id'])->update(array(
						'label' => $_POST['label'],
						'key' => trim($_POST['key']),
						'auto_add' => isset($_POST['auto_add']),
					));

					notify_user(_('Public key updated'), '');
					redirect('?page=adminm&section=members&action=pubkeys&id='.$_GET['id']);

				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('Failed to edit public key'), $e->getResponse());
					edit_pubkey($_GET['id'], $_GET['pubkey_id']);
				}

			} else {
				edit_pubkey($_GET['id'], $_GET['pubkey_id']);
			}

			break;

		case 'pubkey_del':
			try {
				$api->user($_GET['id'])->public_key($_GET['pubkey_id'])->delete();

				notify_user(_('Public key deleted'), '');
				redirect('?page=adminm&section=members&action=pubkeys&id='.$_GET['id']);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('Failed to delete public key'), $e->getResponse());
					list_pubkeys();
				}

			break;

		case 'auth_tokens':
			list_auth_tokens();
			break;

		case 'auth_token_edit':
			if(isset($_POST['label'])) {
				try {
					$api->auth_token->update($_GET['token_id'], array('label' => $_POST['label']));

					notify_user(_('Authentication token updated'), '');
					redirect('?page=adminm&section=members&action=auth_tokens&id='.$_GET['id'].'&token_id='.$_GET['token_id']);

				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('Failed to edit authentication token'), $e->getResponse());
					edit_auth_token($_GET['token_id']);
				}

			} else {
				edit_auth_token($_GET['token_id']);
			}

			break;

		case 'auth_token_del':
			try {
				$api->auth_token->delete($_GET['token_id']);

				notify_user(_('Authentication token deleted'), '');
				redirect('?page=adminm&section=members&action=auth_tokens&id='.$_GET['id'].'&token_id='.$_GET['token_id']);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('Failed to delete authentication token'), $e->getResponse());
					edit_auth_token($_GET['token_id']);
				}

			break;

		case 'user_sessions':
			list_user_sessions($_GET['id']);
			break;

		case 'resource_packages':
			list_user_resource_packages($_GET['id']);
			break;

		case 'resource_packages_add':
			if (isAdmin()) {
				if ($_SERVER['REQUEST_METHOD'] === 'POST') {
					csrf_check();

					try {
						$api->user_cluster_resource_package->create([
							'environment' => $_POST['environment'],
							'user' => $_GET['id'],
							'cluster_resource_package' => $_POST['cluster_resource_package'],
							'comment' => $_POST['comment'],
							'from_personal' => isset($_POST['from_personal']),
						]);

						notify_user(_('Package added'), '');
						redirect('?page=adminm&action=resource_packages&id='.$_GET['id']);

					} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
						$xtpl->perex_format_errors(_('Failed to add package'), $e->getResponse());
						user_resource_package_add_form($_GET['id']);
					}
				} else {
					user_resource_package_add_form($_GET['id']);
				}
			}
			break;

		case 'resource_packages_edit':
			if (isAdmin()) {
				if (isset($_POST['comment'])) {
					csrf_check();

					try {
						$api->user_cluster_resource_package->update($_GET['pkg'], [
							'comment' => $_POST['comment'],
						]);

						notify_user(_('Package updated'), '');
						redirect('?page=adminm&action=resource_packages&id='.$_GET['id']);

					} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
						$xtpl->perex_format_errors(_('Failed to update package'), $e->getResponse());
						user_resource_package_edit_form($_GET['id'], $_GET['pkg']);
					}

				} else {
					user_resource_package_edit_form($_GET['id'], $_GET['pkg']);
				}
			}
			break;

		case 'resource_packages_delete':
			if (isAdmin()) {
				if ($_POST['confirm'] == '1') {
					csrf_check();

					try {
						$api->user_cluster_resource_package->delete($_GET['pkg']);

						notify_user(_('Package removed'), '');
						redirect('?page=adminm&action=resource_packages&id='.$_GET['id']);

					} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
						$xtpl->perex_format_errors(_('Failed to remove package'), $e->getResponse());
						user_resource_package_delete_form($_GET['id'], $_GET['pkg']);
					}

				} else {
					user_resource_package_delete_form($_GET['id'], $_GET['pkg']);
				}
			}
			break;

		case 'cluster_resources':
			list_cluster_resources();
			break;

		case 'env_cfg':
			environment_configs($_GET['id']);
			break;

		case 'env_cfg_edit':
			if (!isAdmin())
				break;

			if ($_SERVER['REQUEST_METHOD'] === 'POST') {
				csrf_check();

				try {
					$api->user($_GET['id'])->environment_config($_GET['cfg'])->update(array(
						'can_create_vps' => isset($_POST['can_create_vps']),
						'can_destroy_vps' => isset($_POST['can_destroy_vps']),
						'vps_lifetime' => $_POST['vps_lifetime'],
						'max_vps_count' => $_POST['max_vps_count'],
						'default' => isset($_POST['default'])
					));

					notify_user(_('Changes saved'), _('Environment configs was successfully updated.'));
					redirect('?page=adminm&action=env_cfg&id='.$_GET['id']);

				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('Update failed'), $e->getResponse());
					env_cfg_edit_form($_GET['id'], $_GET['cfg']);
				}

			} else {
				env_cfg_edit_form($_GET['id'], $_GET['cfg']);
			}

			break;

		case 'approval_requests':
			if(!isAdmin())
				break;

			approval_requests_list();
			break;

		case "request_details":
			if(!isAdmin())
				break;

			approval_requests_details($_GET['type'], $_GET['id']);
			break;

		case "request_process":
			if(!isAdmin())
				break;

			$action = null;

			if (isset($_POST['action']))
				$action = $_POST['action'];

			if($action == "approve" || $_GET["rule"] == "approve")
				request_approve();

			elseif($action == "deny" || $_GET["rule"] == "deny")
				request_deny();

			elseif($action == "ignore" || $_GET["rule"] == "ignore")
				request_ignore();

			elseif($action == "request_correction" || $_GET["rule"] == "request_correction")
				request_correction();

			break;

		default:
			list_members();
			break;
	}

	$xtpl->sbar_out(_("Manage members"));

	if (isAdmin() && payments_enabled()) {
		$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Incoming payments").'" /> '._("Incoming payments"), '?page=adminm&action=incoming_payments');
		$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Payments history").'" /> '._("Display history of payments"), '?page=adminm&section=members&action=payments_history');
		$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Payments overview").'" /> '._("Payments overview"), '?page=adminm&section=members&action=payments_overview');
		$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Estimate income").'" /> '._("Estimate income"), '?page=adminm&section=members&action=estimate_income');

		$xtpl->sbar_out(_('Payments'));
	}

} else $xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
