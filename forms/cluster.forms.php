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
	
	$empty = array(0 => _('---'), 'unassigned' => 'unassigned');
	$users = $empty + resource_list_to_options($api->user->list(), 'id', 'login', false, user_label);
	$vpses = $empty + resource_list_to_options($api->vps->list(), 'id', 'hostname', false, vps_label);
	
	$xtpl->form_add_input(_("Offset").':', 'text', '40', 'offset', get_val('offset', '0'), '');
	$xtpl->form_add_select(_("Version").':', 'v', $versions, get_val('v', 0));
	$xtpl->form_add_select(_("User").':', 'user', $users, get_val('user'));
	$xtpl->form_add_select(_("VPS").':', 'vps', $vpses, get_val('vps'));
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
