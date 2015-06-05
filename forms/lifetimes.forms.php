<?php

function lifetimes_set_state_form($resource, $id) {
	global $xtpl, $api;
	
	$return = $_GET['return'] ? $_GET['return'] : urlencode($_SERVER['REQUEST_URI']);
	
	$xtpl->form_create('?page=lifetimes&action=set_state&resource='.$resource.'&id='.$id.'&return='.$return, 'post');
	$xtpl->table_add_category(_("Set object state"));
	$xtpl->table_add_category('&nbsp;');
	
	$p = $api[$resource]->update->getParameters('input');
	
	api_param_to_form('object_state', $p->object_state);
	api_param_to_form('expiration_date', $p->expiration_date);
	api_param_to_form('change_reason', $p->change_reason);
	
	$xtpl->form_out(_("Go >>"));
}
