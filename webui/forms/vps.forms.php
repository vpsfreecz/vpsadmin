<?php

function print_newvps_page1() {
	global $xtpl, $api;

	$xtpl->title(_("Create a VPS: Select a location (1/2)"));

	$xtpl->form_create('', 'get', 'newvps-step1', false);

	$xtpl->table_td(
		_('Location').':'.
		'<input type="hidden" name="page" value="adminvps">'.
		'<input type="hidden" name="action" value="new2">'
	);
	$xtpl->form_add_select_pure(
		'location',
		resource_list_to_options($api->location->list(array('has_hypervisor' => true))),
		$_GET['location'],
		''
	);
	$xtpl->table_tr();

	$xtpl->form_out(_("Next"));
}

function print_newvps_page2($loc_id) {
	global $xtpl, $api;

	if ($_SESSION['is_admin'])
		$xtpl->title(_("Create a VPS: Specify parameters"));
	else
		$xtpl->title(_("Create a VPS: Specify parameters (2/2)"));

	$xtpl->form_create('?page=adminvps&action=new2&location='.$loc_id, 'post');

	if (!$_SESSION['is_admin']) {
		try {
			$loc = $api->location->show(
				$loc_id,
				array('meta' => array('includes' => 'environment'))
			);

		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			notify_user(_('Invalid location'), _('Please select the desired location of your new VPS.'));
			redirect('?page=adminvps&action=new');
		}

		$xtpl->table_td(_('Environment').':');
		$xtpl->table_td($loc->environment->label);
		$xtpl->table_tr();

		$xtpl->table_td(_('Location').':');
		$xtpl->table_td($loc->label);
		$xtpl->table_tr();
	}

	$xtpl->form_add_input(_("Hostname").':', 'text', '30', 'vps_hostname', $_POST['vps_hostname'], _("A-z, a-z"), 255);

	if ($_SESSION["is_admin"]) {
		$xtpl->form_add_select(_("Node").':', 'vps_server', resource_list_to_options($api->node->list(), 'id', 'domain_name'), $_POST['vps_server'], '');
		$xtpl->form_add_select(_("Owner").':', 'm_id', resource_list_to_options($api->user->list(), 'id', 'login'), post_val('m_id', $_SESSION['user']['id']), '');
	}

	$xtpl->form_add_select(
		_("OS template").':',
		'vps_template',
		resource_list_to_options(
			$api->os_template->list(array(
				'location' => isAdmin() ? null : $loc_id,
			)),
			'id', 'label', false, function ($t) {
				$ret = '';

				switch ($t->hypervisor_type)
				{
				case 'openvz':
					$ret .= '[OpenVZ] ';
					break;

				case 'vpsadminos':
					$ret .= '[vpsAdminOS] ';
					break;

				default:
					$ret .= '[Unknown] ';
				}

				$ret .= $t->label;

				return $ret;
			}
		),
		$_POST['vps_template'],
		''
	);

	$params = $api->vps->create->getParameters('input');
	$vps_resources = array(
		'memory' => 4096,
		'cpu' => 8,
		'swap' => 0,
		'diskspace' => 120*1024,
	);

	$ips = array(
		'ipv4' => 1,
		'ipv4_private' => 0,
		'ipv6' => 1,
	);

	$user_resources = $api->user->current()->cluster_resource->list(array(
		'environment' => $loc->environment_id,
		'meta' => array('includes' => 'environment,cluster_resource')
	));
	$resource_map = array();

	foreach ($user_resources as $r) {
		$resource_map[ $r->cluster_resource->name ] = $r;
	}

	foreach ($vps_resources as $name => $default) {
		$p = $params->{$name};
		$r = $resource_map[$name];

		if (!$_SESSION['is_admin'] && $r->value === 0)
			continue;

		$xtpl->table_td($p->label.':');
		$xtpl->form_add_number_pure(
			$name,
			$_POST[$name] ? $_POST[$name] : min($default, $r->free),
			$r->cluster_resource->min,
			$_SESSION['is_admin']
				? $r->cluster_resource->max
				: min($r->free, $r->cluster_resource->max),
			$r->cluster_resource->stepsize,
			unit_for_cluster_resource($name)
		);
		$xtpl->table_td(_('You have').' '.$r->free.' '.unit_for_cluster_resource($name).' '._('available'));
		$xtpl->table_tr();
	}

	foreach ($ips as $name => $default) {
		$p = $params->{$name};
		$r = $resource_map[$name];

		if (!$_SESSION['is_admin'] && $r->value === 0)
			continue;

		$xtpl->table_td($p->label.':');
		$xtpl->form_add_number_pure(
			$name,
			$_POST[$name] ? $_POST[$name] : $default,
			0,
			$r->cluster_resource->max,
			$r->cluster_resource->stepsize,
			unit_for_cluster_resource($name)
		);
		$xtpl->table_tr();
	}

	if ($_SESSION["is_admin"]) {
		$xtpl->form_add_checkbox(_("Boot on create").':', 'boot_after_create', '1', (isset($_POST['vps_hostname']) && !isset($_POST['boot_after_create'])) ? false : true, $hint = '');
		$xtpl->form_add_textarea(_("Extra information about VPS").':', 28, 4, 'vps_info', $_POST['vps_info'], '');
	}

	$xtpl->table_td(
		_('Contact support if you need more').' <a href="?page=adminm&action=cluster_resources&id='.$_SESSION['user']['id'].'">'._('resources.').'</a>',
		false, false, '2'
	);
	$xtpl->table_tr();

	$xtpl->form_out(_("Create"));

	if ($_SESSION['is_admin'])
		$xtpl->sbar_add(_('Back'), '?page=adminvps');
	else
		$xtpl->sbar_add(_('Back'), '?page=adminvps&action=new2&environment='.$env_id.'&location='.$loc_id);
}

function vps_details_title($vps) {
	global $xtpl;

	$title = 'VPS <a href="?page=adminvps&action=info&veid='.$vps->id.'">#'.$vps->id.'</a> '._("details");

	if ($_SESSION["is_admin"])
		$xtpl->title($title.' '._("[Admin mode]"));
	else
		$xtpl->title($title.' '._("[User mode]"));
}

function vps_details_submenu($vps) {
	global $xtpl, $api;

	if ($_GET['action'] != 'info')
		$xtpl->sbar_add(_('Back to details'), '?page=adminvps&action=info&veid='.$vps->id);

	$xtpl->sbar_add(_('Backups'), '?page=backup&action=vps&list=1&vps='.$vps->id.'#ds-'.$vps->dataset_id);

	if ($_SESSION['is_admin']) {
		$xtpl->sbar_add(_('Migrate VPS'), '?page=adminvps&action=offlinemigrate&veid='.$vps->id);
		$xtpl->sbar_add(_('Change owner'), '?page=adminvps&action=chown&veid='.$vps->id);
	}

	$xtpl->sbar_add(_('Clone VPS'), '?page=adminvps&action=clone&veid='.$vps->id);
	$xtpl->sbar_add(_('Swap VPS'), '?page=adminvps&action=swap&veid='.$vps->id);

	$return_url = urlencode($_SERVER['REQUEST_URI']);
	$xtpl->sbar_add(_('History'), '?page=history&list=1&object=Vps&object_id='.$vps->id.'&return_url='.$return_url);

	if ($api->outage)
		$xtpl->sbar_add(_('Outages'), '?page=outage&action=list&vps='.$vps->id);
}

function vps_details_suite($vps) {
	vps_details_title($vps);
	vps_details_submenu($vps);
}

function vps_owner_form($vps) {
	global $xtpl, $api;

	$xtpl->table_title(_('VPS owner'));
	$xtpl->form_create('?page=adminvps&action=chown&veid='.$vps->id, 'post');
	$xtpl->form_add_select(_("Owner").':', 'm_id',
		resource_list_to_options($api->user->list(), 'id', 'login', false),
		$vps->user_id);
	$xtpl->form_out(_("Go >>"));

	vps_details_suite($vps);
}

function vps_migrate_form($vps) {
	global $xtpl;

	$xtpl->table_title(_('Offline migration'));
	$xtpl->form_create('?page=adminvps&action=offlinemigrate&veid='.$vps->id, 'post');
	api_params_to_form($vps->migrate, 'input');
	$xtpl->form_out(_("Go >>"));

	vps_details_suite($vps);
}

function vps_clone_form($vps) {
	global $xtpl, $api;

	$xtpl->table_title(_('Clone VPS'));
	$xtpl->form_create('?page=adminvps&action=clone&veid='.$vps->id, 'post');

	if ($_SESSION['is_admin']) {
		api_params_to_form($vps->clone, 'input', array(
			'vps' => function($vps) {
				return '#'.$vps->id.' '.$vps->hostname;
			},
			'node' => function($node) {
				return $node->domain_name;
			}
		));

	} else {
		$input = $vps->clone->getParameters('input');

		foreach ($input as $name => $desc) {
			if ($name === 'environment') {
				continue;

			} elseif ($name === 'location') {
				$xtpl->form_add_select(
					_('Location').':', 'location',
					resource_list_to_options($api->location->list(['has_hypervisor' => true])),
					post_val('location')
				);

			} else {
				api_param_to_form($name, $desc);
			}
		}
	}

	$xtpl->form_out(_("Go >>"));

	vps_details_suite($vps);
}

function vps_swap_form($vps) {
	global $xtpl;

	$xtpl->table_title(_('Swap VPS'));
	$xtpl->form_create('?page=adminvps&action=swap_preview&veid='.$vps->id, 'get', 'vps-swap', false);

	api_params_to_form($vps->swap_with, 'input', array('vps' => function($vps) {
		return '#'.$vps->id.' '.$vps->hostname;
	}));

	$xtpl->form_out(_("Preview"), null,
		'<input type="hidden" name="page" value="adminvps">'.
		'<input type="hidden" name="action" value="swap_preview">'.
		'<input type="hidden" name="veid" value="'.$vps->id.'">'
	);

	vps_details_suite($vps);
}

function format_swap_preview($vps, $hostname, $resources, $ips, $node, $expiration) {
	$ips_tmp = array();

	foreach ($ips as $ip) {
		$ips_tmp[] = $ip->addr;
	}

	$ips = implode(",<br>\n", $ips_tmp);
	$expiration_date = $expiration->expiration_date
		? tolocaltz($expiration->expiration_date, 'Y-m-d')
		: '---';

	$vps_link = vps_link($vps);

	$s = <<<EOT
	<h3>VPS {$vps_link}</h3>
	<dl>
		<dt>Hostname:</dt>
		<dd>$hostname</dd>
		<dt>Expiration:</dt>
		<dd>{$expiration_date}</dd>
		<dt>CPU:</dt>
		<dd>{$resources->cpu}</dd>
		<dt>Memory:</dt>
		<dd>{$resources->memory}</dd>
		<dt>Swap:</dt>
		<dd>{$resources->swap}</dd>
		<dt>IP addresses:</dt>
		<dd>$ips</dd>
	</dl>
EOT;
	return $s;
}

function format_swap_node_cell($node, $primary = false) {
	$outage_len = $primary ? _('minimal') : _('up to several hours');

	$s = <<<EOT
	<h3>{$node->domain_name}</h3>
	<dl>
		<dt>Environment:</dt>
		<dd>{$node->location->environment->label}</dd>
		<dt>Outage duration:</dt>
		<dd>{$outage_len}</dd>
	</dl>
EOT;

	return $s;
}

function vps_swap_preview_form($primary, $secondary, $opts) {
	global $xtpl, $api;

	$xtpl->table_title(_("Swap VPS ".vps_link($primary)." with ".vps_link($secondary)));
	$xtpl->form_create('?page=adminvps&action=swap&veid='.$primary->id, 'post');
	$xtpl->table_add_category(_('Node'));
	$xtpl->table_add_category(_('Now'));
	$xtpl->table_add_category("&rarr;");
	$xtpl->table_add_category(_('After swap'));

	$primary_ips = get_vps_ip_route_list($primary);
	$secondary_ips = get_vps_ip_route_list($secondary);

	if (!$_SESSION['is_admin'])
		$opts['expirations'] = true;

	$xtpl->table_td(format_swap_node_cell($primary->node, true));

	$xtpl->table_td(
		format_swap_preview(
			$primary,
			$primary->hostname,
			$primary,
			$primary_ips,
			$primary->node,
			$primary
		)
	);

	$xtpl->table_td(
		'<img src="template/icons/draw-arrow-forward.png" alt="will become">',
		false, false, '1', '1', 'middle'
	);

	$xtpl->table_td(
		format_swap_preview(
			$secondary,
			$opts['hostname'] ? $primary->hostname : $secondary->hostname,
			$opts['resources'] ? $primary : $secondary,
			$primary_ips,
			$primary->node,
			$opts['expirations'] ? $primary : $secondary
		)
	);

	$xtpl->table_tr();

	$xtpl->table_td(format_swap_node_cell($secondary->node));

	$xtpl->table_td(
		format_swap_preview(
			$secondary,
			$secondary->hostname,
			$secondary,
			$secondary_ips,
			$secondary->node,
			$secondary
		)
	);

	$xtpl->table_td(
		'<img src="template/icons/draw-arrow-forward.png" alt="will become">',
		false, false, '1', '1', 'middle'
	);

	$xtpl->table_td(
		format_swap_preview(
			$primary,
			$opts['hostname'] ? $secondary->hostname : $primary->hostname,
			$opts['resources'] ? $secondary : $primary,
			$secondary_ips,
			$secondary->node,
			$opts['expirations'] ? $secondary : $primary
		)
	);

	$xtpl->table_tr(false, 'notoddrow');

	$xtpl->table_td('');
	$xtpl->table_td($xtpl->html_submit(_('Cancel'), 'cancel'));
	$xtpl->table_td('');
	$xtpl->table_td(
		'<input type="hidden" name="vps" value="'.$secondary->id.'">'.
		($opts['hostname'] ? '<input type="hidden" name="hostname" value="1">' : '').
		($opts['resources'] ? '<input type="hidden" name="resources" value="1">' : '').
		($opts['configs'] ? '<input type="hidden" name="configs" value="1">' : '').
		($opts['expirations'] ? '<input type="hidden" name="expirations" value="1">' : '').
		$xtpl->html_submit(_('Go >>'), 'go'),
		false, false, '2'
	);

	$xtpl->table_tr();

	$xtpl->form_out_raw('vps_swap_preview');
}

function vps_netif_form($vps, $netif) {
	global $xtpl, $api;

	$xtpl->table_title(_('Network interface').' '.$netif->name);

	$xtpl->table_add_category(_('Interface'));
	$xtpl->table_add_category('');

	$xtpl->form_create('?page=adminvps&action=netif&veid='.$vps->id.'&id='.$netif->id, 'post');

	if ($vps->node->hypervisor_type == "vpsadminos") {
		$xtpl->form_add_input(_('Name').':', 'text', '30', 'name', $netif->name);
	} else {
		$xtpl->table_td(_('Name').':');
		$xtpl->table_td($netif->name);
		$xtpl->table_tr();
	}

	$xtpl->table_td(_('Type').':');
	$xtpl->table_td($netif->type);
	$xtpl->table_tr();

	if ($vps->node->hypervisor_type == "vpsadminos") {
		$xtpl->table_td(_('MAC address').':');
		$xtpl->table_td($netif->mac);
		$xtpl->table_tr();
	}

	if ($vps->node->hypervisor_type == "vpsadminos")
		$xtpl->form_out(_('Go >>'));
	else
		$xtpl->form_out_raw();

	if ($vps->node->hypervisor_type == 'vpsadminos') {
		vps_netif_iproutes_form($vps, $netif);
		vps_netif_ipaddrs_form($vps, $netif);
	} else {
		vps_netif_ip_joined_form($vps, $netif);
	}
}

function vps_netif_iproutes_form($vps, $netif) {
	global $xtpl, $api;

	$ips = $api->ip_address->list([
		'network_interface' => $netif->id,
		'meta' => ['includes' => 'network'],
	]);

	$xtpl->table_add_category(_('Routed addresses'));
	$xtpl->table_add_category('');
	$xtpl->form_create('?page=adminvps&action=iproute_add&veid='.$vps->id.'&netif='.$netif->id, 'post');

	foreach ($ips as $ip) {
		$xtpl->table_td(ip_label($ip));
		$xtpl->table_td($ip->addr.'/'.$ip->prefix);
		$xtpl->table_td(
			'<a href="?page=adminvps&action=iproute_del&id='.$ip->id.
			'&veid='.$vps->id.'&netif='.$netif->id.'&t='.csrf_token().'" title="'._('Remove').'">'.
			'<img src="template/icons/m_remove.png" alt="'._("Remove").'">'.
			'</a>'
		);
		$xtpl->table_tr();
	}

	$tmp = ['-------'];
	$free_4_pub = $tmp + get_free_route_list('ipv4', $vps, 'public_access', 25);
	$free_4_priv = $tmp + get_free_route_list('ipv4_private', $vps, 'private_access', 25);

	if ($vps->node->location->has_ipv6)
		$free_6 = $tmp + get_free_route_list('ipv6', $vps, null, 25);

	$xtpl->form_add_select(
		_("Add public IPv4 address").':',
		'iproute_public_v4',
		$free_4_pub,
		'', _('Add one IP address at a time')
	);

	$xtpl->form_add_select(
		_("Add private IPv4 address").':',
		'iproute_private_v4',
		$free_4_priv,
		'', _('Add one IP address at a time')
	);

	if ($vps->node->location->has_ipv6) {
		$xtpl->form_add_select(
			_("Add public IPv6 address").':',
			'iproute_public_v6',
			$free_6,
			'', _('Add one IP address at a time')
		);
	}
	$xtpl->form_out(_('Go >>'));

}

function vps_netif_ipaddrs_form($vps, $netif) {
	global $xtpl, $api;

	$ips = $api->host_ip_address->list([
		'network_interface' => $netif->id,
		'assigned' => true,
		'meta' => ['includes' => 'ip_address__network'],
	]);

	$xtpl->table_add_category(_('Interface addresses'));
	$xtpl->table_add_category('');
	$xtpl->form_create('?page=adminvps&action=hostaddr_add&veid='.$vps->id, 'post');

	foreach ($ips as $ip) {
		$xtpl->table_td(host_ip_label($ip));
		$xtpl->table_td($ip->addr.'/'.$ip->ip_address->prefix);
		$xtpl->table_td(
			'<a href="?page=adminvps&action=hostaddr_del&id='.$ip->id.
			'&veid='.$vps->id.'&t='.csrf_token().'" title="'._('Remove').'">'.
			'<img src="template/icons/m_remove.png" alt="'._("Remove").'">'.
			'</a>'
		);
		$xtpl->table_tr();
	}

	$tmp = ['-------'];
	$free_4_pub = $tmp + get_free_host_addr_list('ipv4', $vps, $netif, 'public_access', 25);
	$free_4_priv = $tmp + get_free_host_addr_list('ipv4_private', $vps, $netif, 'private_access', 25);

	if ($vps->node->location->has_ipv6)
		$free_6 = $tmp + get_free_host_addr_list('ipv6', $vps, null, null, 25);

	$xtpl->form_add_select(
		_("Add public IPv4 address").':',
		'hostaddr_public_v4',
		$free_4_pub,
		'', _('Add one IP address at a time')
	);

	$xtpl->form_add_select(
		_("Add private IPv4 address").':',
		'hostaddr_private_v4',
		$free_4_priv,
		'', _('Add one IP address at a time')
	);

	if ($vps->node->location->has_ipv6) {
		$xtpl->form_add_select(
			_("Add public IPv6 address").':',
			'hostaddr_public_v6',
			$free_6,
			'', _('Add one IP address at a time')
		);
	}
	$xtpl->form_out(_('Go >>'));
}

function vps_netif_ip_joined_form($vps, $netif) {
	global $xtpl, $api;

	$ips = $api->ip_address->list([
		'network_interface' => $netif->id,
		'meta' => ['includes' => 'network'],
	]);

	$xtpl->table_add_category(_('IP addresses'));
	$xtpl->table_add_category('');
	$xtpl->form_create('?page=adminvps&action=ipjoined_add&veid='.$vps->id.'&netif='.$netif->id, 'post');

	foreach ($ips as $ip) {
		$xtpl->table_td(ip_label($ip));
		$xtpl->table_td($ip->addr.'/'.$ip->prefix);
		$xtpl->table_td(
			'<a href="?page=adminvps&action=iproute_del&id='.$ip->id.
			'&veid='.$vps->id.'&netif='.$netif->id.'&t='.csrf_token().'" title="'._('Remove').'">'.
			'<img src="template/icons/m_remove.png" alt="'._("Remove").'">'.
			'</a>'
		);
		$xtpl->table_tr();
	}

	$tmp = ['-------'];
	$free_4_pub = $tmp + get_free_route_list('ipv4', $vps, 'public_access', 25);
	$free_4_priv = $tmp + get_free_route_list('ipv4_private', $vps, 'private_access', 25);

	if ($vps->node->location->has_ipv6)
		$free_6 = $tmp + get_free_route_list('ipv6', $vps, null, 25);

	$xtpl->form_add_select(
		_("Add public IPv4 address").':',
		'iproute_public_v4',
		$free_4_pub,
		'', _('Add one IP address at a time')
	);

	$xtpl->form_add_select(
		_("Add private IPv4 address").':',
		'iproute_private_v4',
		$free_4_priv,
		'', _('Add one IP address at a time')
	);

	if ($vps->node->location->has_ipv6) {
		$xtpl->form_add_select(
			_("Add public IPv6 address").':',
			'iproute_public_v6',
			$free_6,
			'', _('Add one IP address at a time')
		);
	}
	$xtpl->form_out(_('Go >>'));
}
