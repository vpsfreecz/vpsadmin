<?php

function lifetimes_set_state_form($resource, $id, $current_obj = null) {
	global $xtpl, $api;

	$return = urlencode($_GET['return'] ? $_GET['return'] : $_SERVER['REQUEST_URI']);

	$xtpl->table_title(_('Object state'));
	$xtpl->form_create('?page=lifetimes&action=set_state&resource='.$resource.'&id='.$id.'&return='.$return, 'post');

	$p = $api[$resource]->update->getParameters('input');

	$state = null;
	$expiration = null;

	if ($current_obj) {
		if (!isset($_POST['object_state']))
			$state = $current_obj->object_state;

		if ($current_obj->expiration_date && !isset($_POST['expiration_date']))
			$expiration = tolocaltz($current_obj->expiration_date);
	}

	api_param_to_form('object_state', $p->object_state, $state);
	api_param_to_form('expiration_date', $p->expiration_date, $expiration);
	api_param_to_form('change_reason', $p->change_reason);

	$xtpl->form_out(_("Go >>"));
}

function lifetimes_reminder_form($resource, $id) {
	global $xtpl, $api;

	$xtpl->table_title(_('Set e-mail reminder'));
	$xtpl->form_create('?page=reminder&action=set&resource='.$resource.'&id='.$id, 'post');

	$p = $api[$resource]->update->getParameters('input');

	try {
		$obj = $api[$resource]->show($id);
	} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
		$xtpl->perex_format_errors(_('Unable to access resource'), $e->getResponse());
		return;
	}

	$xtpl->table_td(_(
		'E-mail reminders are sent daily before the expiration date. This form '.
		'can be used to silent the notifications until a given date.'
	), false, false, 3);
	$xtpl->table_tr();

	switch ($_GET['resource']) {
	case 'user':
		$xtpl->table_td(_('User').':');
		$xtpl->table_td(user_link($obj));
		$xtpl->table_tr();
		$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Back to user details").'" />'._('Back to user details'), "?page=adminm&section=members&action=edit&id={$obj->id}");
		break;
	case 'vps':
		$xtpl->table_td(_('VPS').':');
		$xtpl->table_td(vps_link($obj));
		$xtpl->table_tr();
		$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Back to user details").'" />'._('Back to VPS details'), "?page=adminvps&action=info&id={$obj->id}");
		break;
	default:
		break;
	}

	$xtpl->sbar_out(_("Reminders"));

	$xtpl->table_td(_('State').':');
	$xtpl->table_td($obj->object_state);
	$xtpl->table_tr();

	if ($obj->expiration_date) {
		$xtpl->table_td(_('Expiration date').':');
		$xtpl->table_td(tolocaltz($obj->expiration_date));
		$xtpl->table_tr();
	}

	if ($obj->remind_after_date) {
		$xtpl->table_td(_('Current remind after date').':');
		$xtpl->table_td(tolocaltz($obj->remind_after_date));
		$xtpl->table_tr();
	}

	$xtpl->table_td(_("Remind me in a week").':');
	$xtpl->form_add_radio_pure('remind_in', '1w', true);
	$xtpl->table_tr();

	$xtpl->table_td(_("Remind me in two weeks").':');
	$xtpl->form_add_radio_pure('remind_in', '2w', false);
	$xtpl->table_tr();

	$xtpl->table_td(_("Remind me after").':');
	$xtpl->form_add_radio_pure('remind_in', 'date', false);
	api_param_to_form_pure(
		'remind_after_date',
		$p->remind_after_date,
		tolocaltz($obj->remind_after_date ?? "now")
	);
	$xtpl->table_tr();

	$xtpl->table_td(_("Do not remind me").':');
	$xtpl->form_add_radio_pure('remind_in', 'never', false);
	$xtpl->table_tr();

	$xtpl->form_out(_("Go >>"));
}
