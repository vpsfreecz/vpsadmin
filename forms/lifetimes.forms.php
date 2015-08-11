<?php

function lifetimes_set_state_form($resource, $id, $current_obj = null) {
	global $xtpl, $api;
	
	$return = $_GET['return'] ? $_GET['return'] : urlencode($_SERVER['REQUEST_URI']);
	
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
