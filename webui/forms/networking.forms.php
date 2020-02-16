<?php

function ip_address_list($page) {
	global $xtpl, $api;

	$xtpl->title(_('Routable IP Addresses'));
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
		'meta' => array('includes' => 'user,vps,network')
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
		$netif = $ip->network_interface_id ? $ip->network_interface : null;
		$vps = $netif ? $netif->vps : null;

		$xtpl->table_td($ip->network->address .'/'. $ip->network->prefix);
		$xtpl->table_td($ip->addr.'/'.$ip->prefix);
		$xtpl->table_td(approx_number($ip->size), false, true);
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

		if ($vps)
			$xtpl->table_td('<a href="?page=adminvps&action=info&veid='.$vps->id.'">'.$vps->id.' ('.h($vps->hostname).')</a>');
		else
			$xtpl->table_td('---');

		if ($_SESSION['is_admin']) {
			$xtpl->table_td(
				'<a href="?page=cluster&action=ipaddr_edit&id='.$ip->id.'&return='.$return_url.'">'.
				'<img src="template/icons/m_edit.png" alt="'._('Edit').'" title="'._('Edit').'">'.
				'</a>'
			);
		}

		if ($vps) {
			$xtpl->table_td(
				'<a href="?page=networking&action=route_unassign&id='.$ip->id.'&return='.$return_url.'">'.
				'<img src="template/icons/m_remove.png" alt="'._('Remove from VPS').'" title="'._('Remove from VPS').'">'.
				'</a>'
			);

		} else {
			$xtpl->table_td(
				'<a href="?page=networking&action=route_assign&id='.$ip->id.'&return='.$return_url.'">'.
				'<img src="template/icons/vps_add.png" alt="'._('Add to a VPS').'" title="'._('Add to a VPS').'">'.
				'</a>'
			);
		}

// 		$xtpl->table_td('<a href="?page=cluster&action=ipaddr_delete&ip_id='.$ip->id.'"><img src="template/icons/m_delete.png"  title="'. _("Delete from cluster") .'" /></a>');

		$xtpl->table_tr();
	}

	$xtpl->table_out();
}

function host_ip_address_list($page) {
	global $xtpl, $api;

	$xtpl->title(_('Host IP Addresses'));
	$xtpl->table_title(_('Filters'));
	$xtpl->form_create('', 'get', 'ip-filter', false);

	$xtpl->table_td(_("Limit").':'.
		'<input type="hidden" name="page" value="'.$page.'">'.
		'<input type="hidden" name="action" value="host_ip_addresses">'.
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
	$xtpl->form_add_select(_('Assigned').':', 'assigned', [
		'a' => _('All'),
		'y' => _('Yes'),
		'n' => _('No'),
	], get_val('assigned'));
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
		'meta' => array(
			'includes' => 'ip_address__user,ip_address__network_interface__vps,'.
			              'ip_address__network'
		)
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

	if ($_GET['assigned'] == 'y')
		$params['assigned'] = true;
	elseif ($_GET['assigned'] == 'n')
		$params['assigned'] = false;

	if ($_GET['network'])
		$params['network'] = $_GET['network'];

	if ($_GET['location'])
		$params['location'] = $_GET['location'];

	if ($_GET['v'])
		$params['version'] = $_GET['v'];

	if ($_GET['prefix'])
		$params['prefix'] = $_GET['prefix'];

	$host_addrs = $api->host_ip_address->list($params);

	$xtpl->table_add_category(_("Network"));
	$xtpl->table_add_category(_("Routed address"));
	$xtpl->table_add_category(_("Host address"));

	if ($_SESSION['is_admin'])
		$xtpl->table_add_category(_('User'));
	else
		$xtpl->table_add_category(_('Owned'));

	$xtpl->table_add_category('VPS');
	$xtpl->table_add_category('Interface');
	$xtpl->table_add_category('');

	$return_url = urlencode($_SERVER['REQUEST_URI']);

	foreach ($host_addrs as $host_addr) {
		$ip = $host_addr->ip_address;
		$netif = $ip->network_interface_id ? $ip->network_interface : null;
		$vps = $netif ? $netif->vps : null;

		$xtpl->table_td($ip->network->address .'/'. $ip->network->prefix);
		$xtpl->table_td($ip->addr .'/'. $ip->prefix);
		$xtpl->table_td($host_addr->addr);

		if ($_SESSION['is_admin']) {
			if ($ip->user_id)
				$xtpl->table_td('<a href="?page=adminm&action=edit&id='.$ip->user_id.'">'.$ip->user->login.'</a>');
			else
				$xtpl->table_td('---');
		} else {
			$xtpl->table_td(boolean_icon($ip->user_id));
		}

		if ($vps)
			$xtpl->table_td('<a href="?page=adminvps&action=info&veid='.$vps->id.'">'.$vps->id.' ('.h($vps->hostname).')</a>');
		else
			$xtpl->table_td('---');

		if ($netif) {
			$xtpl->table_td($host_addr->assigned ? $netif->name : ('<span style="color: #A6A6A6">'.$netif->name.'</span>'));
		} else {
			$xtpl->table_td('---');
		}

		if ($host_addr->assigned) {
			$xtpl->table_td(
				'<a href="?page=networking&action=hostaddr_unassign&id='.$host_addr->id.'&return='.$return_url.'">'.
				'<img src="template/icons/m_remove.png" alt="'._('Remove from interface').'" title="'._('Remove from VPS').'">'.
				'</a>'
			);

		} elseif ($netif) {
			$xtpl->table_td(
				'<a href="?page=networking&action=hostaddr_assign&id='.$host_addr->id.'&return='.$return_url.'">'.
				'<img src="template/icons/vps_add.png" alt="'._('Add to a VPS').'" title="'._('Add to a VPS').'">'.
				'</a>'
			);

		} else {
			$xtpl->table_td('---');
		}

		$xtpl->table_tr();
	}

	$xtpl->table_out();
}

function route_assign_form($id) {
	global $xtpl, $api;

	$ip = $api->ip_address->show($id, array('meta' => array('includes' => 'network')));

	$xtpl->table_title(_('Route IP address to a VPS'));
	$xtpl->sbar_add(
		_("Back"),
		$_GET['return'] ? $_GET['return'] : '?page=networking&action=ip_addresses'
	);

	if ($_POST['vps']) {
		try {
			$vps = $api->vps->show($_POST['vps']);
		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			$vps = false;
		}
	} else {
		$vps = false;
	}

	if ($_POST['network_interface']) {
		try {
			$netif = $api->network_interface->show($_POST['network_interface']);
		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			$netif = false;
		}
	} else {
		$netif = false;
	}

	if ($vps && $netif)
		$target = 'route_assign2';
	else
		$target = 'route_assign';

	$xtpl->form_create(
		'?page=networking&action='.$target.'&id='.$ip->id.'&return='.urlencode($_GET['return']),
		'post'
	);

	$xtpl->table_td('IP:');
	$xtpl->table_td($ip->network->location->label.': '.$ip->addr.'/'.$ip->network->prefix);
	$xtpl->table_tr();

	if ($vps) {
		$xtpl->table_td(_('VPS').':');
		$xtpl->table_td($vps->id.' ('.$vps->hostname.')');
		$xtpl->table_tr();

		if ($netif) {
			$xtpl->table_td(_('Network interface').':');
			$xtpl->table_td($netif->name);
			$xtpl->table_tr();

			$via_addrs = resource_list_to_options(
				$api->host_ip_address->list([
					'network_interface' => $netif->id,
					'assigned' => true,
					'version' => $ip->network->ip_version,
				]),
				'id', 'addr',
				false
			);

			$via_addrs = [
				'' => _('host address from this network will be on '.$netif->name)
			] + $via_addrs;

			$xtpl->table_td(
				_('Address').':'.
				'<input type="hidden" name="vps" value="'.$vps->id.'">'.
				'<input type="hidden" name="network_interface" value="'.$netif->id.'">'
			);
			$xtpl->form_add_select_pure('route_via', $via_addrs, post_val('route_via'));
			$xtpl->table_tr();

			$xtpl->form_out(_('Add route'));

		} else {
			$netifs = $api->network_interface->list(['vps' => $_POST['vps']]);

			$xtpl->table_td(
				_('Network interface').':'.
				'<input type="hidden" name="vps" value="'.$vps->id.'">'
			);
			$xtpl->form_add_select_pure(
				'network_interface',
				resource_list_to_options($netifs, 'id', 'name', false),
				post_val('network_interface'));
			$xtpl->table_tr();

			$xtpl->form_out(_('Continue'));
		}

	} else {
		$xtpl->form_add_input(_('VPS ID').':', 'text', '30', 'vps', post_val('vps'));
		$xtpl->form_out(_('Continue'));
	}
}

function route_unassign_form($id) {
	global $xtpl, $api;

	$ip = $api->ip_address->show($id, ['meta' => [
		'includes' => 'network,network_interface__vps'
	]]);

	$xtpl->table_title(_('Remove route from VPS'));
	$xtpl->sbar_add(
		_("Back"),
		$_GET['return'] ? $_GET['return'] : '?page=networking&action=ip_addresses'
	);

	$xtpl->form_create(
		'?page=networking&action=route_unassign2&id='.$ip->id.'&return='.urlencode($_GET['return']),
		'post'
	);

	$vps = $ip->network_interface->vps;

	$xtpl->table_td(_('VPS').':');
	$xtpl->table_td(
		'<a href="?page=adminvps&action=info&veid='.$vps->id.'">#'.$vps->id.'</a>'.
		' '.$vps->hostname
	);
	$xtpl->table_tr();

	$xtpl->table_td(_('Network interface').':');
	$xtpl->table_td($ip->network_interface->name);
	$xtpl->table_tr();

	$xtpl->table_td(_('IP').':');
	$xtpl->table_td($ip->network->location->label.': '.$ip->addr.'/'.$ip->network->prefix);
	$xtpl->table_tr();

	if ($_SESSION['is_admin'])
		$xtpl->form_add_checkbox(_('Disown').':', 'disown', '1', false);

	$xtpl->form_add_checkbox(_('Confirm').':', 'confirm', '1', false);

	$xtpl->form_out(_("Remove"));
}

function hostaddr_assign_form($id) {
	global $xtpl, $api;

	$addr = $api->host_ip_address->show($id, ['meta' => [
		'includes' => 'ip_address__network',
	]]);
	$ip = $addr->ip_address;

	$xtpl->table_title(_('Add host IP address to a VPS'));
	$xtpl->sbar_add(
		_("Back"),
		$_GET['return'] ? $_GET['return'] : '?page=networking&action=ip_addresses'
	);

	$xtpl->form_create(
		'?page=networking&action=hostaddr_assign2&id='.$addr->id.'&return='.urlencode($_GET['return']),
		'post'
	);

	$xtpl->table_td('IP:');
	$xtpl->table_td($ip->network->location->label.': '.$addr->addr.'/'.$ip->network->prefix);
	$xtpl->table_tr();

	$xtpl->table_td(_('VPS').':');
	$xtpl->table_td($ip->network_interface->vps_id.' ('.$ip->network_interface->vps->hostname.')');
	$xtpl->table_tr();

	$xtpl->table_td(_('Network interface').':');
	$xtpl->table_td($ip->network_interface->name);
	$xtpl->table_tr();

	$xtpl->form_out(_('Add address'));
}

function hostaddr_unassign_form($id) {
	global $xtpl, $api;

	$addr = $api->host_ip_address->show($id, ['meta' => [
		'includes' => 'ip_address__network,ip_address__network_interface__vps'
	]]);
	$ip = $addr->ip_address;

	$xtpl->table_title(_('Remove host IP from a VPS'));
	$xtpl->sbar_add(
		_("Back"),
		$_GET['return'] ? $_GET['return'] : '?page=networking&action=ip_addresses'
	);

	$xtpl->form_create(
		'?page=networking&action=hostaddr_unassign2&id='.$addr->id.'&return='.urlencode($_GET['return']),
		'post'
	);

	$vps = $ip->network_interface->vps;

	$xtpl->table_td(_('VPS').':');
	$xtpl->table_td(
		'<a href="?page=adminvps&action=info&veid='.$vps->id.'">#'.$vps->id.'</a>'.
		' '.$vps->hostname
	);
	$xtpl->table_tr();

	$xtpl->table_td(_('Network interface').':');
	$xtpl->table_td($ip->network_interface->name);
	$xtpl->table_tr();

	$xtpl->table_td(_('IP').':');
	$xtpl->table_td($ip->network->location->label.': '.$ip->addr.'/'.$ip->network->prefix);
	$xtpl->table_tr();

	$xtpl->form_add_checkbox(_('Confirm').':', 'confirm', '1', false);

	$xtpl->form_out(_("Remove"));
}
