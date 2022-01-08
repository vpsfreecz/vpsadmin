<?php
/*
    ./pages/page_networking.php

    vpsAdmin
    Web-admin interface for OpenVZ (see http://openvz.org)
    Copyright (C) 2008-2011 Pavel Snajdr, snajpa@snajpa.net
*/

function year_list() {
	$now = date("Y");
	$ret = array('' => '---');

	for ($i = $now - 5; $i <= $now; $i++)
		$ret[$i] = $i;

	return $ret;
}

function month_list() {
	$ret = array('' => '---');

	for ($i = 1; $i <= 12; $i++) {
		$ret[$i] = $i;
	}

	return $ret;
}

if ($_SESSION["logged_in"]) {

switch($_GET['action']) {
	case 'ip_addresses':
		ip_address_list('networking');
		break;

	case 'host_ip_addresses':
		host_ip_address_list('networking');
		break;

	case "route_assign":
		route_assign_form($_GET['id']);
		break;

	case "route_assign2":
		csrf_check();

		try {
			if (isset($_POST['route-only'])) {
				$api->ip_address($_GET['id'])->assign([
					'network_interface' => $_POST['network_interface'],
					'route_via' => $_POST['route_via'] ? $_POST['route_via'] : null,
				]);

				notify_user(_('IP assigned'), '');
				redirect($_GET['return'] ? $_GET['return'] : '?page=networking&action=ip_addresses');

			} elseif (isset($_POST['route-and-host'])) {
				if ($_POST['route_via']) {
					$xtpl->perex(
						_('Invalid route'),
						_('When adding the address to the interface, it cannot be routed '.
						  'through another address: do not set the "Address" field')
					);
					route_assign_form($_GET['id']);

				} else {
					$api->ip_address($_GET['id'])->assign_with_host_address([
						'network_interface' => $_POST['network_interface'],
						'route_via' => $_POST['route_via'] ? $_POST['route_via'] : null,
					]);

					notify_user(_('IP assigned'), '');
					redirect($_GET['return'] ? $_GET['return'] : '?page=networking&action=ip_addresses');
				}
			} else {
				$xtpl->perex(_('Something went wrong'), _('Try again or contact support'));
				route_assign_form($_GET['id']);
			}

		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			$xtpl->perex_format_errors(_('Action failed'), $e->getResponse());
			route_assign_form($_GET['id']);
		}

		break;

	case "route_unassign":
		route_unassign_form($_GET['id']);
		break;

	case "route_unassign2":
		csrf_check();

		if (!$_POST['confirm']) {
			route_unassign_form($_GET['id']);
			break;
		}

		try {
			$ip = $api->ip_address->show($_GET['id']);

			if (isAdmin() && $_POST['disown'])
				$ip->update(['user' => null]);

			$ip->free();

			notify_user(_('IP removed'), '');
			redirect($_GET['return'] ? $_GET['return'] : '?page=networking&action=ip_addresses');

		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			$xtpl->perex_format_errors(_('Action failed'), $e->getResponse());
			route_unassign_form($_GET['id']);
		}

		break;

	case "hostaddr_assign":
		hostaddr_assign_form($_GET['id']);
		break;

	case "hostaddr_assign2":
		csrf_check();

		try {
			$api->host_ip_address($_GET['id'])->assign([
				'network_interface' => $_POST['network_interface'],
			]);

			notify_user(_('IP assigned'), '');
			redirect($_GET['return'] ? $_GET['return'] : '?page=networking&action=ip_addresses');

		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			$xtpl->perex_format_errors(_('Action failed'), $e->getResponse());
			ip_assign_form($_GET['id']);
		}

		break;

	case "hostaddr_unassign":
		hostaddr_unassign_form($_GET['id']);
		break;

	case "hostaddr_unassign2":
		csrf_check();

		if (!$_POST['confirm']) {
			hostaddr_unassign_form($_GET['id']);
			break;
		}

		try {
			$api->host_ip_address->free($_GET['id']);

			notify_user(_('IP removed'), '');
			redirect($_GET['return'] ? $_GET['return'] : '?page=networking&action=ip_addresses');

		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			$xtpl->perex_format_errors(_('Action failed'), $e->getResponse());
			ip_unassign_form($_GET['id']);
		}

		break;

	case 'traffic':
		$show_traffic = true;
		break;

	case 'user_top':
		$show_top = true;
		break;

	case 'live':
		$show_live = true;
		break;

	default:
		$show_traffic = true;
		break;
}

$xtpl->sbar_add(_("Routable addresses"), '?page=networking&action=ip_addresses');
$xtpl->sbar_add(_("Host addresses"), '?page=networking&action=host_ip_addresses');
$xtpl->sbar_add(_("List monthly traffic"), '?page=networking&action=traffic');
$xtpl->sbar_add(_("Live monitor"), '?page=networking&action=live');

if (isAdmin())
	$xtpl->sbar_add(_("User top"), '?page=networking&action=user_top');

$xtpl->sbar_out(_('Networking'));

if ($show_traffic) {
	$xtpl->title(_("Monthly traffic"));

	$xtpl->table_title(_('Filters'));
	$xtpl->form_create('', 'get', 'networking-filter', false);

	$xtpl->table_td(_("Limit").':'.
		'<input type="hidden" name="page" value="networking">'.
		'<input type="hidden" name="action" value="list">'
	);
	$xtpl->form_add_input_pure('text', '40', 'limit', get_val('limit', '25'), '');
	$xtpl->table_tr();

	$xtpl->form_add_select(_("Year").':', 'year', year_list(), get_val('year', date("Y")));
	$xtpl->form_add_select(_("Month").':', 'month', month_list(), get_val('month', date("n")));

	$xtpl->form_add_select(_('Category').':', 'role', array(
		'' => _('All'),
		'public' => _('Public'),
		'private' => _('Private'),
	), get_val('role'));

	$xtpl->form_add_select(_('Protocol').':', 'protocol', array(
		'sum' => _('Sum'),
		'' => _('All'),
		'tcp' => 'TCP',
		'udp' => 'UDP',
		'other' => 'Other',
	), get_val('protocol'));

	$xtpl->form_add_select(_('IP version').':', 'ip_version', array(
		0 => _('All'),
		4 => 'IPv4',
		6 => 'IPv6',
	), get_val('ip_version'));

	$xtpl->form_add_select(
		_("Environment").':',
		'environment',
		resource_list_to_options(
			$api->environment->list(array('has_hypervisor' => true))
		),
		get_val('environment')
	);
	$xtpl->form_add_select(
		_("Location").':',
		'location',
		resource_list_to_options(
			$api->location->list(array('has_hypervisor' => true))
		),
		get_val('location')
	);
	$xtpl->form_add_select(_("Network").':', 'network',
		resource_list_to_options($api->network->list(), 'id', 'label', true, 'network_label'), get_val('network'));

	$xtpl->form_add_select(_("Node").':', 'node',
		resource_list_to_options($api->node->list(), 'id', 'domain_name'), get_val('node'));
	$xtpl->form_add_input(_("VPS").':', 'text', '30', 'vps', get_val('vps'));

	if (isAdmin()) {
		$xtpl->form_add_input(_("IP address").':', 'text', '30', 'ip_address', get_val('ip_address'));
		$xtpl->form_add_input(_("User").':', 'text', '30', 'user', get_val('user'));
	}

	$xtpl->form_out(_('Show'));

	if ($_GET['action'] != 'list')
		return;

	$xtpl->table_title(_("Statistics"));

	$params = array(
		'offset' => get_val('offset', 0),
		'limit' => get_val('limit', 25),
		'accumulate' => 'monthly',
		'order' => 'descending',
		'meta' => array('includes' => 'user,ip_address'),
	);

	$conds = array(
		'year', 'month', 'role', 'ip_version', 'vps', 'node', 'location', 'environment',
		'network', 'protocol'
	);

	if (isAdmin()) {
		if ($_GET['ip_address']) {
			$ip_id = get_ip_address_id($_GET['ip_address']);

			if ($ip_id === false) {
				$xtpl->perex(
					_('IP address not found'),
					_('IP address').' '.$_GET['ip_address'].' '._('not found.')
				);

			} else {
				$params['ip_address'] = $ip_id;
			}
		}

		if ($_GET['user'])
			$params['user'] =  $_GET['user'];
	}

	foreach ($conds as $c) {
		if ($_GET[$c])
			$params[$c] = $_GET[$c];
	}

	$stats = $api->ip_traffic->list($params);

	$xtpl->table_add_category(_('IP address'));

	if (isAdmin())
		$xtpl->table_add_category(_('User'));

	$xtpl->table_add_category(_('VPS'));
	$xtpl->table_add_category(_('Category'));
	$xtpl->table_add_category(_('Date'));
	$xtpl->table_add_category(_('Protocol'));
	$xtpl->table_add_category(_('In'));
	$xtpl->table_add_category(_('Out'));
	$xtpl->table_add_category(_('Total'));

	foreach ($stats as $stat) {
		$xtpl->table_td($stat->ip_address->addr);

		if (isAdmin()) {
			if ($stat->user_id) {
				$xtpl->table_td(
					'<a href="?page=adminm&action=edit&id='.$stat->user_id.'">'.
					$stat->user->login.
					'</a>'
				);
			} else
				$xtpl->table_td('---');
		}

		if ($stat->ip_address->vps_id)
			$xtpl->table_td(
				'<a href="?page=adminvps&action=info&veid='.$stat->ip_address->vps_id.'">'.
				$stat->ip_address->vps_id.
				'</a>'
			);
		else
			$xtpl->table_td('---');

		$xtpl->table_td($stat->role);

		$t = new DateTime($stat->created_at);
		$xtpl->table_td($t->format('Y/m'));

		$xtpl->table_td($stat->protocol);
		$xtpl->table_td(data_size_to_humanreadable($stat->bytes_in/1024/1024), false, true);
		$xtpl->table_td(data_size_to_humanreadable($stat->bytes_out/1024/1024), false, true);
		$xtpl->table_td(data_size_to_humanreadable(($stat->bytes_in + $stat->bytes_out)/1024/1024), false, true);

		$xtpl->table_tr();
	}

	$xtpl->table_out();
}

if (isAdmin() && $show_top) {
	$xtpl->title(_("Top users"));

	$xtpl->table_title(_('Filters'));
	$xtpl->form_create('', 'get', 'networking-filter', false);

	$xtpl->table_td(_("Limit").':'.
		'<input type="hidden" name="page" value="networking">'.
		'<input type="hidden" name="action" value="user_top">'.
		'<input type="hidden" name="list" value="1">'
	);
	$xtpl->form_add_input_pure('text', '40', 'limit', get_val('limit', '25'), '');
	$xtpl->table_tr();

	$xtpl->form_add_select(_("Year").':', 'year', year_list(), get_val('year', date("Y")));
	$xtpl->form_add_select(_("Month").':', 'month', month_list(), get_val('month', date("n")));

	$xtpl->form_add_select(_('Category').':', 'role', array(
		'' => _('All'),
		'public' => _('Public'),
		'private' => _('Private'),
	), get_val('role'));

	$xtpl->form_add_select(_('Protocol').':', 'protocol', array(
		'' => _('All'),
		'tcp' => 'TCP',
		'udp' => 'UDP',
		'other' => 'Other',
	), get_val('protocol'));

	$xtpl->form_add_select(_('IP version').':', 'ip_version', array(
		0 => _('All'),
		4 => 'IPv4',
		6 => 'IPv6',
	), get_val('ip_version'));

	$xtpl->form_add_select(_("Environment").':', 'environment',
		resource_list_to_options($api->environment->list()), get_val('environment'));
	$xtpl->form_add_select(_("Location").':', 'location',
		resource_list_to_options($api->location->list()), get_val('location'));
	$xtpl->form_add_select(_("Network").':', 'network',
		resource_list_to_options($api->network->list(), 'id', 'label', true, 'network_label'), get_val('network'));
	$xtpl->form_add_select(_("Node").':', 'node',
		resource_list_to_options($api->node->list(), 'id', 'domain_name'), get_val('node'));

	$xtpl->form_out(_('Show'));

	if (!$_GET['list'])
		return;

	$xtpl->table_title(_("Statistics"));

	$params = array(
		'offset' => get_val('offset', 0),
		'limit' => get_val('limit', 25),
		'accumulate' => 'monthly',
		'meta' => array('includes' => 'user'),
	);

	$conds = array(
		'year', 'month', 'role', 'ip_version', 'node', 'location', 'environment',
		'network', 'protocol'
	);

	foreach ($conds as $c) {
		if ($_GET[$c])
			$params[$c] = $_GET[$c];
	}

	$stats = $api->ip_traffic->user_top($params);

	$xtpl->table_add_category(_('User'));
	$xtpl->table_add_category(_('Date'));
	$xtpl->table_add_category(_('In'));
	$xtpl->table_add_category(_('Out'));
	$xtpl->table_add_category(_('Total'));

	foreach ($stats as $stat) {
		$xtpl->table_td(
			'<a href="?page=networking&action=list&user='.$stat->user_id.'&year='.$_GET['year'].'&month='.$_GET['month'].'&protocol=sum">'.
			$stat->user->login.
			'</a>'
		);

		$t = new DateTime($stat->created_at);
		$xtpl->table_td($t->format('Y/m'));

		$xtpl->table_td(data_size_to_humanreadable($stat->bytes_in/1024/1024), false, true);
		$xtpl->table_td(data_size_to_humanreadable($stat->bytes_out/1024/1024), false, true);
		$xtpl->table_td(data_size_to_humanreadable(($stat->bytes_in + $stat->bytes_out)/1024/1024), false, true);

		$xtpl->table_tr();
	}

	$xtpl->table_out();
}


if ($show_live) {
	$xtpl->title(_('Live monitor'));

	$xtpl->form_create('?page=adminm&section=members&action=approval_requests', 'get');

	$xtpl->table_td(_("Limit").':'.
		'<input type="hidden" name="page" value="networking">'.
		'<input type="hidden" name="action" value="live">'
	);
	$xtpl->form_add_input_pure('text', '30', 'limit', get_val('limit', 25));
	$xtpl->table_tr();

	$xtpl->form_add_select(_('IP version').':', 'ip_version', array(
		0 => _('All'),
		4 => 'IPv4',
		6 => 'IPv6',
	), get_val('ip_version'));

	$xtpl->form_add_select(_("Environment").':', 'environment',
		resource_list_to_options($api->environment->list()), get_val('environment'));
	$xtpl->form_add_select(_("Location").':', 'location',
		resource_list_to_options($api->location->list()), get_val('location'));
	$xtpl->form_add_select(_("Network").':', 'network',
		resource_list_to_options($api->network->list(), 'id', 'label', true, 'network_label'), get_val('network'));
	$xtpl->form_add_select(_("Node").':', 'node',
		resource_list_to_options($api->node->list(), 'id', 'domain_name'), get_val('node'));

	$xtpl->form_add_input(_("IP address").':', 'text', '30', 'ip_address', get_val('ip_address'));
	$xtpl->form_add_input(_("VPS ID").':', 'text', '30', 'vps', get_val('vps'));

	if(isAdmin())
		$xtpl->form_add_input(_("User ID").':', 'text', '30', 'user', get_val('user'));

	$xtpl->form_add_checkbox(
		_('Refresh automatically').':',
		'refresh',
		'1',
		true,
		_('10 second interval')
	);

	$xtpl->table_td(_('Last update').':');
	$xtpl->table_td('
		<span id="monitor-last-update">
			'.date('Y-m-d H:i:s').'
			<noscript>
				JavaScript needs to be enabled for automated refreshing to work.
			</noscript>
		</span>'
	);
	$xtpl->table_tr();

	$xtpl->form_out(_("Show"), 'monitor-filters');

	$params = array(
		'limit' => get_val('limit', 25),
		'meta' => array('includes' => 'ip_address__network_interface'),
	);

	$conds = array(
		'ip_version', 'vps', 'node', 'location', 'environment',
		'network'
	);

	foreach ($conds as $c) {
		if ($_GET[$c])
			$params[$c] = $_GET[$c];
	}

	if ($_GET['ip_address']) {
		$ip_id = get_ip_address_id($_GET['ip_address']);

		if ($ip_id === false) {
			$xtpl->perex(
				_('IP address not found'),
				_('IP address').' '.$_GET['ip_address'].' '._('not found.')
			);

		} else {
			$params['ip_address'] = $ip_id;
		}
	}

	$traffic = $api->ip_traffic_monitor->list($params);

	$roles = array('public', 'private');

	$xtpl->table_td(_('VPS'), '#5EAFFF; color:#FFF; font-weight:bold;', false, '1', '2');
	$xtpl->table_td(_('IP'), '#5EAFFF; color:#FFF; font-weight:bold;', false, '1', '2');

	$xtpl->table_td(_('Public'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;', false, '3');
	$xtpl->table_td(_('Private'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;', false, '3');
	$xtpl->table_td(_('Total'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;', false, '3');
	$xtpl->table_tr();

	$xtpl->table_td(_('In'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;');
	$xtpl->table_td(_('Out'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;');
	$xtpl->table_td(_('Total'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;');

	$xtpl->table_td(_('In'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;');
	$xtpl->table_td(_('Out'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;');
	$xtpl->table_td(_('Total'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;');

	$xtpl->table_td(_('In'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;');
	$xtpl->table_td(_('Out'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;');
	$xtpl->table_td(_('Total'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;');
	$xtpl->table_tr();

	$xtpl->assign('AJAX_SCRIPT', $xtpl->vars['AJAX_SCRIPT'] . '
		<script type="text/javascript" src="js/network-monitor.js"></script>'
	);

	foreach ($traffic as $data) {
		$xtpl->table_td(
			'<a href="?page=adminvps&action=info&veid='.$data->ip_address->network_interface->vps_id.'">'.
			$data->ip_address->network_interface->vps_id.
			'</a>'
		);
		$xtpl->table_td($data->ip_address->addr);

		foreach ($roles as $role) {
			$xtpl->table_td(format_data_rate($data->{"${role}_bytes_in"} / $data->delta * 8, ''), false, true);
			$xtpl->table_td(format_data_rate($data->{"${role}_bytes_out"} / $data->delta * 8, ''), false, true);
			$xtpl->table_td(format_data_rate($data->{"${role}_bytes"} / $data->delta * 8, ''), false, true);
		}

		$xtpl->table_td(format_data_rate($data->bytes_in / $data->delta * 8, ''), false, true);
		$xtpl->table_td(format_data_rate($data->bytes_out / $data->delta * 8, ''), false, true);
		$xtpl->table_td(format_data_rate($data->bytes / $data->delta * 8, ''), false, true);

		$xtpl->table_tr();
	}

	$xtpl->table_out('live_monitor');
}

} else $xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
