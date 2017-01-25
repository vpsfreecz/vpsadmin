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

	if ($config->get("webui", "payments_enabled")) {
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

	if ($_SESSION["is_admin"]) {
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
	
	if ($config->get("webui", "payments_enabled")) {
		$xtpl->table_td(_("Paid until").':');

		$dt = new DateTime($u->paid_until);
		$dt->setTimezone(new DateTimezone(date_default_timezone_get()));

		$t = $dt->getTimestamp();
		$paid = $t > time();
		$paid_until = date('Y-m-d', $t);
		
		if ($_SESSION["is_admin"]) {
			if ($paid) {
				if (($t - time()) >= 604800) {
						$xtpl->table_td('<a href="?page=adminm&section=members&action=payset&id='
										. $u->id
										. '">' . _("->") . ' ' . $paid_until . '</a>', '#66FF66');
				} else {
						$xtpl->table_td('<a href="?page=adminm&section=members&action=payset&id='
										. $u->id
										. '">' . _("->") . ' ' . $paid_until . '</a>', '#FFA500');
				}
				
			} else {
				$xtpl->table_td('<a href="?page=adminm&section=members&action=payset&id='
								. $u->id
								. '"><b>' . _("not paid!") . '</b></a>', '#B22222');
			}
			
		} else {
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
	}
	$xtpl->table_tr();
	
	if ($_SESSION["is_admin"]) {
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
		$u->language_id
	);
	
	if ($_SESSION["is_admin"]) {
		$xtpl->form_add_input(_("Monthly payment").':', 'text', '30', 'm_monthly_payment', $u->monthly_payment, ' ');
		$xtpl->form_add_textarea(_("Info").':', 28, 4, 'm_info', $u->info, _("Note for administrators"));
	}
	
	$xtpl->form_out(_("Save"));
	
	$xtpl->table_add_category(_("Change password"));
	$xtpl->table_add_category('&nbsp;');
	$xtpl->table_add_category('&nbsp;');
	$xtpl->form_create('?page=adminm&section=members&action=passwd&id='.$u->id, 'post');
	$xtpl->form_add_input(_("Password").':', 'password', '30', 'm_pass', '', '', -8);
	$xtpl->form_add_input(_("Repeat password").':', 'password', '30', 'm_pass2', '', '', -8);
	$xtpl->form_out(_("Save"));
	
	$xtpl->table_add_category(_("Personal information"));
	$xtpl->table_add_category('&nbsp;');
	$xtpl->table_add_category('&nbsp;');
	$xtpl->form_create('?page=adminm&section=members&action=edit_personal&id='.$u->id, 'post');
	$xtpl->form_add_input(_("Full name").':', 'text', '30', 'full_name', post_val('full_name', $u->full_name), _("A-Z, a-z, with diacritic"), 255);
	$xtpl->form_add_input(_("E-mail").':', 'text', '30', 'email', post_val('email', $u->email), ' ');
	$xtpl->form_add_input(_("Postal address").':', 'text', '30', 'address', post_val('address', $u->address), ' ');

	if(!$_SESSION["is_admin"]) {
		$xtpl->form_add_input(_("Reason for change").':', 'text', '50', 'change_reason', $_POST['change_reason']);
		$xtpl->table_td(_("Request for change will be sent to administrators for approval.".
		                  "Changes will not take effect immediately. You will be informed about the result."), false, false, 3);
		$xtpl->table_tr();
	}
	
	$xtpl->form_out($_SESSION["is_admin"] ? _("Save") : _("Request change"));
	
	if ($_SESSION["is_admin"]) {
		lifetimes_set_state_form('user', $u->id, $u);
		
		$xtpl->sbar_add("<br><img src=\"template/icons/m_switch.png\"  title=". _("Switch context") ." /> Switch context", "?page=login&action=switch_context&m_id={$u->id}&next=".urlencode($_SERVER["REQUEST_URI"]));
		$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("State log").'" />'._('State log'), '?page=lifetimes&action=changelog&resource=user&id='.$u->id.'&return='. urlencode($_SERVER['REQUEST_URI']));
	}
	
	$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Public keys").'" />'._('Public keys'), "?page=adminm&section=members&action=pubkeys&id={$u->id}");
	$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Authentication tokens").'" />'._('Authentication tokens'), "?page=adminm&section=members&action=auth_tokens&id={$u->id}");
	$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Session log").'" />'._('Session log'), "?page=adminm&action=user_sessions&id={$u->id}");
	$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Cluster resources").'" />'._('Cluster resources'), "?page=adminm&section=members&action=cluster_resources&id={$u->id}");
	$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Environment configs").'" />'._('Environment configs'), "?page=adminm&section=members&action=env_cfg&id={$u->id}");
}

function print_deletem($u) {
	global $db, $xtpl, $api;
	
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
		$xtpl->table_td($k->label);
		$xtpl->table_td($k->fingerprint);
		$xtpl->table_td($k->comment);
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
	$xtpl->table_td($k->comment);
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
	
	if($_SESSION['is_admin']) {
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
			
		$xtpl->table_td($t->label);
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
	
	$xtpl->title(_('User').' <a href="?page=adminm&action=edit&id='.$_GET['id'].'">#'.$_GET['id'].'</a>: '._('Cluster resources'));
	
	$resources = $api->user($_GET['id'])->cluster_resource->list(array('meta' => array('includes' => 'environment,cluster_resource')));
	$by_env = array();
	
	$convert = array('memory', 'swap', 'diskspace');
	
	foreach ($resources as $r) {
		if (!isset($by_env[$r->environment_id]))
			$by_env[$r->environment_id] = array();
		
		$by_env[$r->environment_id][] = $r;
	}
	
	foreach ($by_env as $res) {
		$xtpl->table_title($res[0]->environment->label);
		
		$xtpl->table_add_category(_("Resource"));
		$xtpl->table_add_category(_("Value"));
		$xtpl->table_add_category(_("Step size"));
		$xtpl->table_add_category(_("Used"));
		$xtpl->table_add_category(_("Free"));
		
		if ($_SESSION['is_admin'])
			$xtpl->table_add_category('');
		
		foreach ($res as $r) {
			$xtpl->table_td($r->cluster_resource->label);
			
			if (in_array($r->cluster_resource->name, $convert)) {
				$xtpl->table_td(data_size_to_humanreadable($r->value));
				$xtpl->table_td(data_size_to_humanreadable($r->cluster_resource->stepsize));
				$xtpl->table_td(data_size_to_humanreadable($r->used));
				$xtpl->table_td(data_size_to_humanreadable($r->free));
				
			} else {
				$xtpl->table_td($r->value);
				$xtpl->table_td($r->cluster_resource->stepsize);
				$xtpl->table_td($r->used);
				$xtpl->table_td($r->free);
			}
			
			if ($_SESSION['is_admin'])
				$xtpl->table_td('<a href="?page=adminm&section=members&action=cluster_resource_edit&id='.$_GET['id'].'&resource='.$r->id.'"><img src="template/icons/m_edit.png"  title="'._("Edit").'"></a>');
			
			$xtpl->table_tr();
		}
		
		$xtpl->table_out();
	}
	
	$xtpl->sbar_add('<br><img src="template/icons/m_edit.png"  title="'._("Back to user details").'" />'._('Back to user details'), "?page=adminm&section=members&action=edit&id={$_GET['id']}");
}

function cluster_resource_edit_form() {
	global $xtpl, $api;
	
	$r = $api->user($_GET['id'])->cluster_resource($_GET['resource'])->show(
		array('meta' => array('includes' => 'environment,cluster_resource'))
	);
	
	$xtpl->table_title(_('Change cluster resource').' '.$r->cluster_resource->label.' '._('of user').' #'.$_GET['id']);
	$xtpl->form_create('?page=adminm&section=members&action=cluster_resource_edit&id='.$_GET['id'].'&resource='.$_GET['resource'], 'post');
	
	$xtpl->table_td(_('Environment').':');
	$xtpl->table_td($r->environment->label);
	$xtpl->table_tr();
	
	$xtpl->table_td(_('Resource').':');
	$xtpl->table_td($r->cluster_resource->label);
	$xtpl->table_tr();
	
	$xtpl->table_td(_('Used').':');
	$xtpl->table_td($r->used);
	$xtpl->table_tr();
	
	$xtpl->table_td(_('Free').':');
	$xtpl->table_td($r->free);
	$xtpl->table_tr();
	
	$xtpl->table_td(_('Step size').':');
	$xtpl->table_td($r->cluster_resource->stepsize);
	$xtpl->table_tr();
	
	$xtpl->table_td(_('Value').':');
	$xtpl->form_add_number_pure(
		'value',
		$r->value,
		0,
		10 * 1024 * 1024,
		$r->cluster_resource->stepsize,
		unit_for_cluster_resource($r->cluster_resource->name)
	);
	$xtpl->table_tr();
	
	$xtpl->form_out(_('Save'));
	
	$xtpl->sbar_add('<br><img src="template/icons/m_edit.png"  title="'._("Back").'" /> '._('Back'), "?page=adminm&section=members&action=cluster_resources&id=".$_GET['id']);
}

function request_approve() {
	global $xtpl, $api;
	
	if(!$_SESSION["is_admin"])
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
	
	if(!$_SESSION["is_admin"])
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
	
	if(!$_SESSION["is_admin"])
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

function list_members() {
	global $xtpl, $api, $config;
	
	if ($_SESSION["is_admin"]) {
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
		
		api_param_to_form('object_state', $p,
			$p->validators->include->values[ $_GET['object_state'] ]);
		
		$xtpl->form_out(_('Show'));
	
	} else {
		$xtpl->title(_("Manage members"));
	}
	
	if (!$_SESSION['is_admin'] || $_GET['action'] == 'list') {
		$xtpl->table_add_category('ID');
		$xtpl->table_add_category(_("NICKNAME"));
		$xtpl->table_add_category(_("VPS"));
		
		if ($config->get("webui", "payments_enabled")) {
			$xtpl->table_add_category(_("$"));
		}
		
		$xtpl->table_add_category(_("FULL NAME"));
		$xtpl->table_add_category(_("LAST ACTIVITY"));
		
		if ($config->get("webui", "payments_enabled")) {
			$xtpl->table_add_category(_("PAYMENT"));
		}
		
		$xtpl->table_add_category('');
		$xtpl->table_add_category('');
		
		if ($_SESSION['is_admin']) {
			$params = array(
				'limit' => get_val('limit', 25),
				'offset' => get_val('offset', 0),
				'meta' => array('count' => true)
			);
			
			$filters = array('login', 'full_name', 'email', 'address', 'level', 'info', 'monthly_payment',
			                 'mailer_enabled');
			
			foreach ($filters as $f) {
				if ($_GET[$f])
					$params[$f] = $_GET[$f];
			}
			
			if ($_GET['object_state']) {
				$params['object_state'] = $api->user->index->getParameters('input')
					->object_state
					->validators
					->include
					->values[(int) $_GET['object_state']];
			}
			
			$users = $api->user->list($params);
			
		} else {
			$users = array($api->user->current());
		}
		
		foreach ($users as $u) {
			$paid_until = strtotime($u->paid_until);
			$last_activity = strtotime($u->last_activity_at);
			
			$xtpl->table_td($u->id);
			
			if (($_SESSION["is_admin"]) && ($u->id != $_SESSION["user"]["id"])) {
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
			
			if ($config->get("webui", "payments_enabled"))
				$xtpl->table_td($u->monthly_payment);
			
			$xtpl->table_td($u->full_name);
			
			$paid = $paid_until > time();
			
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
			
			if ($config->get("webui", "payments_enabled")) {
				if ($paid_until)
					$paid_until_str = date('Y-m-d', $paid_until);
				else
					$paid_until_str = "Never been paid";
				
				if ($_SESSION["is_admin"]) {
					if ($paid) {
						if (($paid_until - time()) >= 604800) {
								$xtpl->table_td('<a href="?page=adminm&section=members&action=payset&id='.$u->id.'">'._("->").' '.$paid_until_str.'</a>', '#66FF66');
						} else {
								$xtpl->table_td('<a href="?page=adminm&section=members&action=payset&id='.$u->id.'">'._("->").' '.$paid_until_str.'</a>', '#FFA500');
						}
						
					} else {
						$table_td = '<b><a href="?page=adminm&section=members&action=payset&id='.$u->id.'" title="'.$paid_until_str.'">'.
							_("not paid!").
							'</a></b>';
						
						if ($u->paid_until) {
							$table_td .= ' '.ceil(($paid_until - time()) / 86400).'d';
						}
						
						$xtpl->table_td($table_td, '#B22222');
					}
					
				} else {
					if ($paid) {
						if (($paid_until - time()) >= 604800) {
							$xtpl->table_td(_("->").' '.$paid_until_str, '#66FF66');
							
						} else {
							$xtpl->table_td(_("->").' '.$paid_until_str, '#FFA500');
						}
						
					} else {
						$xtpl->table_td('<b>'._("not paid!").' (->'.$paid_until_str.')</b>', '#B22222');
					}
				}
			}
			
			$xtpl->table_td('<a href="?page=adminm&section=members&action=edit&id='.$u->id.'"><img src="template/icons/m_edit.png"  title="'. _("Edit") .'" /></a>');
			
			if ($_SESSION["is_admin"]) {
				$xtpl->table_td('<a href="?page=adminm&section=members&action=delete&id='.$u->id.'"><img src="template/icons/m_delete.png"  title="'. _("Delete") .'" /></a>');
				
			} else {
				$xtpl->table_td('<img src="template/icons/vps_delete_grey.png"  title="'. _("Cannot delete yourself") .'" />');
			}
			
			if ($_SESSION["is_admin"] && ($u->info != '')) {
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

if ($_SESSION["logged_in"]) {

	if ($_SESSION["is_admin"]) {
		$xtpl->sbar_add('<img src="template/icons/m_add.png"  title="'._("New member").'" /> '._("New member"), '?page=adminm&section=members&action=new');

		if ($api->user_request)
			$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Requests for approval").'" /> '._("Requests for approval"), '?page=adminm&section=members&action=approval_requests');

		$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Export e-mails").'" /> '._("Export e-mails"), '?page=adminm&section=members&action=export_mails');
		$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Export e-mails of non-payers").'" /> '._("Export e-mails of non-payers"), '?page=adminm&section=members&action=export_notpaid_mails');
		if ($config->get("webui", "payments_enabled")) {
			$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Payments history").'" /> '._("Display history of payments"), '?page=adminm&section=members&action=payments_history');
			$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Payments overview").'" /> '._("Payments overview"), '?page=adminm&section=members&action=payments_overview');
		}
	}

	switch ($_GET["action"]) {
		case 'new':
			if ($_SESSION["is_admin"]) {
				print_newm();
			}
			break;
		case 'new2':
			if ($_SESSION["is_admin"]) {
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
			if ($_SESSION["is_admin"] && ($u = $api->user->find($_GET["id"]))) {

				$xtpl->perex(_("Are you sure, you want to delete")
								.' '.$u->login.'?','');
				print_deletem($u);

			}
			break;
		case 'delete2':
			if ($_SESSION["is_admin"] && ($u = $api->user->find($_GET["id"]))) {
				$xtpl->perex(_("Are you sure, you want to delete")
						.' '.$u->login.'?',
						'<a href="?page=adminm">'
						. strtoupper(_("No"))
						. '</a> | <a href="?page=adminm&section=members&action=delete3&id='.$u->id.'&&state='.$_REQUEST["object_state"].'">'
						. strtoupper(_("Yes")).'</a>');
				}
			break;
		case 'delete3':
			if ($_SESSION["is_admin"] && ($u = $api->user->find($_GET["id"]))) {
				try {
					$choices = $api->user->delete->getParameters('input')
						->object_state
						->validators
						->include
						->values;
					$state = $choices[(int) $_GET['object_state']];
					
					$u->delete(array(
						'object_state' => $state
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
			print_editm($_SESSION['is_admin'] ? $api->user->find($_GET["id"]) : $api->user->current());
			break;
		case 'edit_member':
			try {
				$params = array(
					'mailer_enabled' => isset($_POST['m_mailer_enable']),
					'language' => $_POST['language'],
				);
				
				if ($_SESSION['is_admin']) {
					$params['login'] = $_POST['m_nick'];
					$params['level'] = $_POST['m_level'];
					$params['info'] = $_POST['m_info'];
					$params['monthly_payment'] = $_POST['m_monthly_payment'];
				}
				
				$user = $api->user($_GET['id'])->update($params);
				
				notify_user(_('User updated'), _('The user was successfully updated.'));
				redirect('?page=adminm&action=edit&id='.$user->id);
				
			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('User update failed'), $e->getResponse());
				print_editm($api->user->find($_GET['id']));
			}
			
			break;
		case 'passwd':
			$u = $api->user->find($_GET["id"]);
			
			if ($_POST["m_pass"] != $_POST["m_pass2"]) {
				$xtpl->perex(_("Invalid entry").': '._("Password"), _("The two passwords do not match."));
				print_editm($u);
				
			} else {
				try {
					$u->update(array('password' => $_POST['m_pass']));
					
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
			
			if($_SESSION["is_admin"]) {
				try {
					$u->update(array(
						'full_name' => $_POST['m_name'],
						'email' => $_POST['m_mail'],
						'address' => $_POST['m_address']
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
		case 'payset':
			if (!$_SESSION['is_admin'])
				break;
			
			try {
				$u = $api->user->find($_GET['id']);
				
			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('User not found'), $e->getResponse());
				break;
			}
			
			$paidUntil = strtotime($u->paid_until);
			
			$xtpl->title(_("Edit payments"));
			$xtpl->form_create('?page=adminm&section=members&action=payset2&id='.$u->id, 'post');
			
			$xtpl->table_td(_("Paid until").':');
			
			if ($paidUntil) {
				$lastPaidTo = date('Y-m-d', $paidUntil);
				
			} else {
				$lastPaidTo = _("Never been paid");
			}
			
			$xtpl->table_td($lastPaidTo);
			$xtpl->table_tr();
			
			$xtpl->table_td(_("Login").':');
			$xtpl->table_td($u->login);
			$xtpl->table_tr();
			
			$xtpl->table_td(_("Monthly payment").':');
			$xtpl->table_td($u->monthly_payment);
			$xtpl->table_tr();
			
			$xtpl->form_add_input(_("Newly paid until").':', 'text', '30', 'paid_until', '', 'Y-m-d, eg. 2009-05-01');

			$xtpl->table_td(_("Months to add").':');
			$xtpl->form_add_input_pure('text', '30', 'months_to_add', '');
			$xtpl->form_add_select_pure('add_from', array(
				'from_last_paid' => _('From last paid date'),
				'from_now' => _('From now')
			));
			$xtpl->table_tr();
			
			$xtpl->table_add_category('');
			$xtpl->table_add_category('');
			
			$xtpl->form_out(_("Save"));
			
			$xtpl->table_add_category("ID");
			$xtpl->table_add_category("MEMBER");
			$xtpl->table_add_category("CHANGED");
			$xtpl->table_add_category("FROM");
			$xtpl->table_add_category("TO");
			
			while ($hist = $db->find("members_payments", "m_id = {$u->id}", "id DESC", 30)) {
				$acct_m = $db->findByColumnOnce("users", "id", $hist["acct_m_id"]);
				
				$xtpl->table_td($hist["id"]);
				$xtpl->table_td($acct_m["login"]);
				$xtpl->table_td(date('Y-m-d H:i', $hist["timestamp"]));
				$xtpl->table_td(date('Y-m-d', $hist["change_from"]));
				$xtpl->table_td(date('Y-m-d', $hist["change_to"]));
				
				$xtpl->table_tr();
			}
			
			$xtpl->table_out();
			
			break;
		case 'payset2':
			if (!$_SESSION['is_admin'])
				break;
			
			try {
				$u = $api->user->find($_GET['id']);
				
			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('User not found'), $e->getResponse());
				break;
			}
			
			$log["m_id"] = $u->id;
			$log["acct_m_id"] = $_SESSION["user"]["id"];
			$log["timestamp"] = time();
			$log["change_from"] = strtotime($u->paid_until);
			
			try {
				if ($_POST["paid_until"]) {
					$t = strtotime($_POST['paid_until']);
					$log["change_to"] = $t;
					
					$u->update(array('paid_until' => date('c', $t)));
				
				} elseif ($_POST["months_to_add"]) {
					if ($_POST['add_from'] == 'from_now')
						$from = time();

					else
						$from = strtotime($u->paid_until ? $u->paid_until : $u->created_at);

					$t = strtotime('+'.$_POST['months_to_add'].' month', $from);
					$log["change_to"] = $t;
					
					$u->update(array('paid_until' => date('c', $t)));
					
				} else {
					notify_user(_("Payment not set"), _('Provide a new date or months to add.'));
					redirect('?page=adminm&action=payset&id='.$u->id);
				}
				
			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Failed to add payment'), $e->getResponse());
				break;
			}
			
			$sql = "INSERT INTO members_payments
			        SET m_id    = '". $db->check($log["m_id"]) ."',
			        acct_m_id   = '". $db->check($log["acct_m_id"]) ."',
			        timestamp   = '". $db->check($log["timestamp"]) ."',
			        change_from = '". $db->check($log["change_from"]) ."',
			        change_to   = '". $db->check($log["change_to"]) ."'";
			
			$db->query($sql);
			
			notify_user(_("Payment successfully set"), '');
			redirect('?page=adminm&action=payset&id='.$u->id);
			
			break;
		
		case 'export_mails':
			if ($_SESSION["is_admin"]) {
				$xtpl->table_add_category('');
				
				$mails = array();
				
				foreach (get_all_users() as $u) {
					$mails[$u->email] = $u->email;
				}
				
				$xtpl->table_td(implode(', ', $mails));
				$xtpl->table_tr();
				
				$xtpl->table_out();
			}
			break;
			
		case 'export_notpaid_mails':
			if ($_SESSION["is_admin"]) {
				$xtpl->table_add_category('');
				
				$mails = array();
				$now = time();
				
				foreach (get_all_users() as $u) {
					$paid = strtotime($u->paid_until);
					
					if (!$paid || $paid < $now)
						$mails[$u->email] = $u->email;
				}
				
				$xtpl->table_td(implode(', ', $mails));
				$xtpl->table_tr();
				
				$xtpl->table_out();
			}
			break;
		case 'payments_history':
			if (!$_SESSION['is_admin'])
				break;
			
			$whereCond = array();
			$whereCond[] = 1;
			
			if ($_REQUEST["acct_m_id"] != "") {
				$whereCond[] = 'acct_m_id = "'.$db->check($_REQUEST["acct_m_id"]).'"';
			}
			
			if ($_REQUEST["m_id"] != "") {
				$whereCond[] = 'm_id = "'.$db->check($_REQUEST["m_id"]).'"';
			}
			
			if ($_REQUEST["limit"] != "") {
				$limit = $_REQUEST["limit"];
			} else {
				$limit = 50;
			}
			
			$xtpl->form_create('?page=adminm&filter=yes&action=payments_history', 'post');
			$xtpl->form_add_input(_("Limit").':', 'text', '40', 'limit', $limit, '');
			$xtpl->form_add_input(_("Changed by member ID").':', 'text', '40', 'acct_m_id', $_REQUEST["acct_m_id"], '');
			$xtpl->form_add_input(_("Changed to member ID").':', 'text', '40', 'm_id', $_REQUEST["m_id"], '');
			$xtpl->form_out(_("Show"));
			
			$xtpl->table_add_category("ID");
			$xtpl->table_add_category("CHANGED BY");
			$xtpl->table_add_category("CHANGED TO");
			$xtpl->table_add_category("CHANGED");
			$xtpl->table_add_category("FROM");
			$xtpl->table_add_category("TO");
			$xtpl->table_add_category("MONTHS");
			
			while ($hist = $db->find("members_payments", $whereCond, "id DESC", $limit)) {
				$acct_m = $db->findByColumnOnce("users", "id", $hist["acct_m_id"]);
				$m = $db->findByColumnOnce("users", "id", $hist["m_id"]);
				
				$xtpl->table_td($hist["id"]);
				$xtpl->table_td($acct_m["m_id"].' '.$acct_m["m_nick"]);
				$xtpl->table_td($m["id"].' '.$m["login"]);
				$xtpl->table_td(date('Y-m-d H:i', $hist["timestamp"]));
				$xtpl->table_td(date('<- Y-m-d', $hist["change_from"]));
				$xtpl->table_td(date('-> Y-m-d', $hist["change_to"]));
				
				if ($hist["change_from"]) {
					$xtpl->table_td(round(($hist["change_to"]-$hist["change_from"])/2629800), false, true);
				} else {
					$xtpl->table_td('---', false, true);
				}
				$xtpl->table_tr();
			}
			
			$xtpl->table_out();
			break;
			
		case 'payments_overview':
			if ($_SESSION['is_admin'])
				payments_overview();
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
			
		case 'cluster_resources':
			list_cluster_resources();
			break;
			
		case 'cluster_resource_edit':
			if (isset($_POST['value'])) {
				csrf_check();
				
				try {
					$api->user($_GET['id'])->cluster_resource($_GET['resource'])->update(
						array('value' => $_POST['value'])
					);
					
					notify_user(_('Cluster resource changed'), '');
					redirect('?page=adminm&section=members&action=cluster_resources&id='.$_GET['id']);
					
				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('Failed to change user\'s cluster resource'), $e->getResponse());
					cluster_resource_edit_form();
				}
				
			} else {
				cluster_resource_edit_form();
			}
			
			break;
		
		case 'env_cfg':
			environment_configs($_GET['id']);
			break;
		
		case 'env_cfg_edit':
			if (!$_SESSION['is_admin'])
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
			if(!$_SESSION["is_admin"])
				break;
			
			approval_requests_list();	
			break;
			
		case "request_details":
			if(!$_SESSION["is_admin"])
				break;
			
			approval_requests_details($_GET['type'], $_GET['id']);	
			break;
		
		case "request_process":
			if(!$_SESSION["is_admin"])
				break;

			$action = null;

			if (isset($_POST['action']))
				$action = $api->user_request->{$_GET['type']}->resolve->getParameters('input')->action->validators->include->values[(int) $_POST['action']];

			if($action == "approve" || $_GET["rule"] == "approve")
				request_approve();
			
			elseif($action == "deny" || $_GET["rule"] == "deny")
				request_deny();
			
			elseif($action == "ignore" || $_GET["rule"] == "ignore")
				request_ignore();
			
			break;
		
		default:
			list_members();
			break;
	}
	
	$xtpl->sbar_out(_("Manage members"));

} else $xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
?>
