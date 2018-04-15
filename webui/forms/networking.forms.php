<?php

function ip_address_list($page) {
	global $xtpl, $api;

	$xtpl->title(_('IP Addresses'));
	$xtpl->table_title(_('Filters'));
	$xtpl->form_create('', 'get', 'ip-filter', false);

	$xtpl->table_td(_("Limit").':'.
		'<input type="hidden" name="page" value="'.$page.'">'.
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
	$xtpl->form_add_input(_("Prefix").':', 'text', '40', 'prefix', get_val('prefix'));

	if ($_SESSION['is_admin']) {
		$xtpl->form_add_input(_("User ID").':', 'text', '40', 'user', get_val('user'), _("'unassigned' to list free addresses"));
	}

	$xtpl->form_add_input(_("VPS").':', 'text', '40', 'vps', get_val('vps'), _("'unassigned' to list free addresses"));
	$xtpl->form_add_select(
		_("Network").':',
		'network',
		resource_list_to_options(
			$api->network->list(),
			'id', 'label',
			true,
			network_label
		),
		get_val('network')
	);
	$xtpl->form_add_select(_("Location").':', 'location',
		resource_list_to_options($api->location->list()), get_val('location'));

	$xtpl->form_out(_('Show'));

	if (!$_GET['list'])
		return;

	$params = array(
		'limit' => get_val('limit', 25),
		'offset' => get_val('offset', 0),
		'meta' => array('includes' => 'user,vps,network__location')
	);

	if ($_SESSION['is_admin']) {
		if ($_GET['user'] === 'unassigned')
			$params['user'] = null;
		elseif ($_GET['user'])
			$params['user'] = $_GET['user'];
	}

	if ($_GET['vps'] === 'unassigned')
		$params['vps'] = null;
	elseif ($_GET['vps'])
		$params['vps'] = $_GET['vps'];

	if ($_GET['network'])
		$params['network'] = $_GET['network'];

	if ($_GET['location'])
		$params['location'] = $_GET['location'];

	if ($_GET['v'])
		$params['version'] = $_GET['v'];

	if ($_GET['prefix'])
		$params['prefix'] = $_GET['prefix'];

	$ips = $api->ip_address->list($params);

	$xtpl->table_add_category(_("Location"));
	$xtpl->table_add_category(_("Network"));
	$xtpl->table_add_category(_("IP address"));
	$xtpl->table_add_category(_("Size"));
	$xtpl->table_add_category(_("TX"));
	$xtpl->table_add_category(_("RX"));

	if ($_SESSION['is_admin'])
		$xtpl->table_add_category(_('User'));
	else
		$xtpl->table_add_category(_('Owned'));

	$xtpl->table_add_category('VPS');

	if ($_SESSION['is_admin'])
		$xtpl->table_add_category('');

	$xtpl->table_add_category('');

	$return_url = urlencode($_SERVER['REQUEST_URI']);

	foreach ($ips as $ip) {
		$xtpl->table_td($ip->network->location->label);
		$xtpl->table_td($ip->network->address .'/'. $ip->network->prefix);
		$xtpl->table_td($ip->addr.'/'.$ip->prefix);
		$xtpl->table_td($ip->size, false, true);
		$xtpl->table_td(round($ip->max_tx * 8.0 / 1024 / 1024, 1), false, true);
		$xtpl->table_td(round($ip->max_rx * 8.0 / 1024 / 1024, 1), false, true);

		if ($_SESSION['is_admin']) {
			if ($ip->user_id)
				$xtpl->table_td('<a href="?page=adminm&action=edit&id='.$ip->user_id.'">'.$ip->user->login.'</a>');
			else
				$xtpl->table_td('---');
		} else {
			$xtpl->table_td(boolean_icon($ip->user_id));
		}

		if ($ip->vps_id)
			$xtpl->table_td('<a href="?page=adminvps&action=info&veid='.$ip->vps_id.'">'.$ip->vps_id.' ('.h($ip->vps->hostname).')</a>');
		else
			$xtpl->table_td('---');

		if ($_SESSION['is_admin']) {
			$xtpl->table_td(
				'<a href="?page=cluster&action=ipaddr_edit&id='.$ip->id.'&return='.$return_url.'">'.
				'<img src="template/icons/m_edit.png" alt="'._('Edit').'" title="'._('Edit').'">'.
				'</a>'
			);
		}

		if ($ip->vps_id) {
			$xtpl->table_td(
				'<a href="?page=networking&action=ipaddr_unassign&id='.$ip->id.'&return='.$return_url.'">'.
				'<img src="template/icons/m_remove.png" alt="'._('Remove from VPS').'" title="'._('Remove from VPS').'">'.
				'</a>'
			);

		} else {
			$xtpl->table_td(
				'<a href="?page=networking&action=ipaddr_assign&id='.$ip->id.'&return='.$return_url.'">'.
				'<img src="template/icons/vps_add.png" alt="'._('Add to a VPS').'" title="'._('Add to a VPS').'">'.
				'</a>'
			);
		}

// 		$xtpl->table_td('<a href="?page=cluster&action=ipaddr_delete&ip_id='.$ip->id.'"><img src="template/icons/m_delete.png"  title="'. _("Delete from cluster") .'" /></a>');

		$xtpl->table_tr();
	}

	$xtpl->table_out();
}

function ip_assign_form($id) {
	global $xtpl, $api;

	$ip = $api->ip_address->show($id, array('meta' => array('includes' => 'network__location')));

	$xtpl->table_title(_('Add IP to a VPS'));
	$xtpl->sbar_add(
		_("Back"),
		$_GET['return'] ? $_GET['return'] : '?page=networking&action=ip_addresses'
	);

	$xtpl->form_create(
		'?page=networking&action=ipaddr_assign2&id='.$ip->id.'&return='.urlencode($_GET['return']),
		'post'
	);

	$xtpl->table_td('IP:');
	$xtpl->table_td($ip->network->location->label.': '.$ip->addr.'/'.$ip->network->prefix);
	$xtpl->table_tr();

	$xtpl->form_add_input(_('VPS ID').':', 'text', '30', 'vps', post_val('vps'));

	$xtpl->form_out(_("Add"));
}

function ip_unassign_form($id) {
	global $xtpl, $api;

	$ip = $api->ip_address->show($id, array('meta' => array('includes' => 'network__location')));

	$xtpl->table_title(_('Remove IP from a VPS'));
	$xtpl->sbar_add(
		_("Back"),
		$_GET['return'] ? $_GET['return'] : '?page=networking&action=ip_addresses'
	);

	$xtpl->form_create(
		'?page=networking&action=ipaddr_unassign2&id='.$ip->id.'&return='.urlencode($_GET['return']),
		'post'
	);

	$xtpl->table_td(_('VPS').':');
	$xtpl->table_td(
		'<a href="?page=adminvps&action=info&veid='.$ip->vps_id.'">#'.$ip->vps_id.'</a>'.
		' '.$ip->vps->hostname
	);
	$xtpl->table_tr();

	$xtpl->table_td(_('IP').':');
	$xtpl->table_td($ip->network->location->label.': '.$ip->addr.'/'.$ip->network->prefix);
	$xtpl->table_tr();

	if ($_SESSION['is_admin'])
		$xtpl->form_add_checkbox(_('Disown').':', 'disown', '1', false);

	$xtpl->form_add_checkbox(_('Confirm').':', 'confirm', '1', false);

	$xtpl->form_out(_("Remove"));
}
