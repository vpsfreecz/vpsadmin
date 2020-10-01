<?php

function print_newvps_page0() {
	global $xtpl, $api;

	$xtpl->title(_("Create a VPS: Select user (0/5)"));

	$xtpl->form_create('', 'get', 'newvps-step0', false);
	$xtpl->form_set_hidden_fields([
		'page' => 'adminvps',
		'action' => 'new-step-1',
	]);
	$xtpl->form_add_input(_('User ID').':', 'text', '30', 'user', $_GET['user']);
	$xtpl->form_out(_("Next"));
}

function print_newvps_page1($user_id) {
	global $xtpl, $api;

	$xtpl->title(_("Create a VPS: Select platform (1/5)"));

	if (isAdmin()) {
		$xtpl->sbar_add(
			_('Back to user selection'),
			'?page=adminvps&action=new-step-0&user='.$user_id.'&platform='.$platform
		);
	}

	$xtpl->form_create('', 'get', 'newvps-step1', false);
	$xtpl->form_set_hidden_fields([
		'page' => 'adminvps',
		'action' => 'new-step-2',
		'user' => $user_id,
	]);

	$xtpl->form_add_radio_pure(
		'platform',
		'vpsadminos',
		get_val_issetto('platform', 'vpsadminos', true)
	);
	$xtpl->table_td('<strong>'._('vpsAdminOS').'</strong>');
	$xtpl->table_tr();
	$xtpl->table_td('');
	$xtpl->table_td(_('
		vpsAdminOS is an in-house developed container-based
		virtualization platform that powers our VPS. For more information, see our
		<a href="https://kb.vpsfree.org/manuals/vps/vpsadminos" target="_blank">knowledge base</a>
		or project documentation at
		<a href="https://vpsadminos.org" target="_blank">vpsadminos.org</a>.
	'));
	$xtpl->table_tr();

	$xtpl->form_add_radio_pure(
		'platform',
		'openvz',
		get_val_issetto('platform', 'openvz')
	);
	$xtpl->table_td('<strong>'._('OpenVZ Legacy').'<strong>');
	$xtpl->table_tr();
	$xtpl->table_td('');
	$xtpl->table_td(_('
		OpenVZ Legacy is a container-based virtualization platform.
		We are in the process of migrating to a more up-to-date solution called
		vpsAdminOS, which is at this time available only in Prague
		(Praha). For more information, see our
		<a href="https://kb.vpsfree.org/manuals/vps/vpsadminos" target="_blank">knowledge base</a>.
	'));
	$xtpl->table_tr();

	$xtpl->form_out(_("Next"));
}

function format_available_resources($user, $environment) {
	$s = '<ul>';

	$user_resources = $user->cluster_resource->list([
		'environment' => $environment->id,
		'meta' => ['includes' => 'cluster_resource'],
	]);

	foreach ($user_resources as $ur) {
		if ($ur->free <= 0)
			continue;

		$s .= '<li>';
		$s .= $ur->cluster_resource->label.': ';
		$s .= approx_number($ur->free).' ';
		$s .= unit_for_cluster_resource($ur->cluster_resource->name);
		$s .= '</li>';
	}

	$s .= '</ul>';
	return $s;
}

function print_newvps_page2($user_id, $platform) {
	global $xtpl, $api;

	if (!$platform) {
		notify_user(
			_('Invalid platform'),
			_('Please select the desired platform.')
		);
		redirect('?page=adminvps&action=new-step-1');
	}

	$xtpl->title(_("Create a VPS: Select a location (2/5)"));
	$xtpl->sbar_add(
		_('Back to platform selection'),
		'?page=adminvps&action=new-step-1&user='.$user_id.'&platform='.$platform
	);

	$xtpl->table_title(_('Configuration'));

	if (isAdmin()) {
		try {
			$user = $api->user->show($user_id);
		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			notify_user(_('Invalid user'), _('Please select target user.'));
			redirect('?page=adminvps&action=new-step-0');
		}

		$xtpl->table_td(_('User').':');
		$xtpl->table_td(user_link($user));
		$xtpl->table_tr();
	}

	$xtpl->table_td(_('Platform').':');
	$xtpl->table_td(hypervisorTypeToLabel($platform));
	$xtpl->table_tr();

	$xtpl->table_out();

	$xtpl->table_title(_('Location'));
	$xtpl->form_create('', 'get', 'newvps-step2', false);
	$xtpl->form_set_hidden_fields([
		'page' => 'adminvps',
		'action' => 'new-step-3',
		'user' => $user_id,
		'platform' => $platform,
	]);

	$locations = $api->location->list([
		'has_hypervisor' => true,
		'hypervisor_type' => $platform,
		'meta' => ['includes' => 'environment'],
	]);

	if (!isAdmin())
		$user = $api->user->current();

	foreach ($locations as $loc) {
		$xtpl->form_add_radio_pure(
			'location',
			$loc->id,
			$_GET['location'] == $loc->id
		);
		$xtpl->table_td('<strong>'.$loc->label.'</strong>');
		$xtpl->table_tr();

		$xtpl->table_td('');
		$xtpl->table_td(
			'<p>'._('Environment').': '.$loc->environment->label.'</p>'.
			'<p>'.$loc->environment->description.'</p>'.
			'<p>'.$loc->description.'</p>'.
			'<h4>'._('Available resources').':</h4>'.
			format_available_resources($user, $loc->environment)
		);
		$xtpl->table_tr();
	}

	$xtpl->form_out(_("Next"));
}

function print_newvps_page3($user_id, $platform, $loc_id) {
	global $xtpl, $api;

	if (!$platform) {
		notify_user(
			_('Invalid platform'),
			_('Please select the desired platform.')
		);
		redirect('?page=adminvps&action=new-step-1');
	}

	$xtpl->title(_("Create a VPS: Select distribution (3/5)"));
	$xtpl->sbar_add(
		_('Back to location selection'),
		'?page=adminvps&action=new-step-2&user='.$user_id.'&platform='.$platform.'&location='.$loc_id
	);

	try {
		$loc = $api->location->show(
			$loc_id,
			['meta' => ['includes' => 'environment']]
		);

	} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
		notify_user(
			_('Invalid location'),
			_('Please select the desired location for your new VPS.')
		);
		redirect('?page=adminvps&action=new-step-2&platform='.$platform);
	}

	$xtpl->table_title(_('Configuration'));

	if (isAdmin()) {
		try {
			$user = $api->user->show($user_id);
		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			notify_user(_('Invalid user'), _('Please select target user.'));
			redirect('?page=adminvps&action=new-step-0');
		}

		$xtpl->table_td(_('User').':');
		$xtpl->table_td(user_link($user));
		$xtpl->table_tr();
	}

	$xtpl->table_td(_('Platform').':');
	$xtpl->table_td(hypervisorTypeToLabel($platform));
	$xtpl->table_tr();

	$xtpl->table_td(_('Environment').':');
	$xtpl->table_td($loc->environment->label);
	$xtpl->table_tr();

	$xtpl->table_td(_('Location').':');
	$xtpl->table_td($loc->label);
	$xtpl->table_tr();

	$xtpl->table_out();

	$xtpl->table_title(_('Distribution'));
	$xtpl->form_create('', 'get', 'newvps-step3', false);
	$xtpl->form_set_hidden_fields([
		'page' => 'adminvps',
		'action' => 'new-step-4',
		'user' => $user_id,
		'platform' => $platform,
		'location' => $loc_id,
	]);

	$tpls = $api->os_template->list(['hypervisor_type' => $platform]);

	foreach ($tpls as $t) {
		$xtpl->form_add_radio_pure(
			'os_template',
			$t->id,
			$_GET['os_template'] == $t->id
		);
		$xtpl->table_td('<strong>'.$t->label.'</strong>');
		$xtpl->table_tr();

		$xtpl->table_td('');
		$xtpl->table_td($t->info);
		$xtpl->table_tr();
	}

	$xtpl->form_out(_("Next"));
}

function print_newvps_page4($user_id, $platform, $loc_id, $tpl_id) {
	global $xtpl, $api;

	if (!$platform) {
		notify_user(
			_('Invalid platform'),
			_('Please select the desired platform.')
		);
		redirect('?page=adminvps&action=new-step-1');
	}

	$xtpl->title(_("Create a VPS: Specify parameters (4/5)"));
	$xtpl->sbar_add(
		_('Back to distribution selection'),
		'?page=adminvps&action=new-step-3&user='.$user_id.'&platform='.$platform.'&location='.$loc_id.'&os_template='.$tpl_id
	);

	try {
		$loc = $api->location->show(
			$loc_id,
			['meta' => ['includes' => 'environment']]
		);

	} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
		notify_user(
			_('Invalid location'),
			_('Please select the desired location for your new VPS.')
		);
		redirect('?page=adminvps&action=new-step-2&platform='.$platform);
	}

	try {
		$tpl = $api->os_template->show($tpl_id);

	} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
		notify_user(
			_('Invalid distribution'),
			_('Please select the desired distribution of your new VPS.'));
		redirect('?page=adminvps&action=new-step-3&platform='.$platform.'&location='.$loc_id);
	}

	$xtpl->table_title(_('Configuration'));

	if (isAdmin()) {
		try {
			$user = $api->user->show($user_id);
		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			notify_user(_('Invalid user'), _('Please select target user.'));
			redirect('?page=adminvps&action=new-step-0');
		}

		$xtpl->table_td(_('User').':');
		$xtpl->table_td(user_link($user));
		$xtpl->table_tr();
	}

	$xtpl->table_td(_('Platform').':');
	$xtpl->table_td(hypervisorTypeToLabel($platform));
	$xtpl->table_tr();

	$xtpl->table_td(_('Environment').':');
	$xtpl->table_td($loc->environment->label);
	$xtpl->table_tr();

	$xtpl->table_td(_('Location').':');
	$xtpl->table_td($loc->label);
	$xtpl->table_tr();

	$xtpl->table_td(_('Distribution').':');
	$xtpl->table_td($tpl->label);
	$xtpl->table_tr();

	$xtpl->table_out();

	$xtpl->table_title(_('Parameters'));
	$xtpl->table_add_category(_('Resource'));
	$xtpl->table_add_category(_('Available'));
	$xtpl->table_add_category(_('Value'));
	$xtpl->form_create('', 'get', 'newvps-step4', false);
	$xtpl->form_set_hidden_fields([
		'page' => 'adminvps',
		'action' => 'new-step-5',
		'user' => $user_id,
		'platform' => $platform,
		'location' => $loc_id,
		'os_template' => $tpl_id,
	]);

	$params = $api->vps->create->getParameters('input');
	$vps_resources = [
		'memory' => 4096,
		'cpu' => 8,
		'swap' => 0,
		'diskspace' => 120*1024,
	];

	$ips = [
		'ipv4' => 1,
		'ipv4_private' => 0,
		'ipv6' => 1,
	];

	if (!isAdmin())
		$user = $api->user->current();

	$user_resources = $user->cluster_resource->list([
		'environment' => $loc->environment_id,
		'meta' => ['includes' => 'environment,cluster_resource']
	]);
	$resource_map = array();

	foreach ($user_resources as $r) {
		$resource_map[ $r->cluster_resource->name ] = $r;
	}

	foreach ($vps_resources as $name => $default) {
		$p = $params->{$name};
		$r = $resource_map[$name];

		if (!isAdmin() && $r->value === 0)
			continue;

		$xtpl->table_td($p->label);
		$xtpl->table_td($r->free.' '.unit_for_cluster_resource($name));
		$xtpl->form_add_number_pure(
			$name,
			isset($_GET[$name]) ? $_GET[$name] : min($default, $r->free),
			$r->cluster_resource->min,
			isAdmin()
				? $r->cluster_resource->max
				: min($r->free, $r->cluster_resource->max),
			$r->cluster_resource->stepsize,
			unit_for_cluster_resource($name)
		);
		$xtpl->table_tr();
	}

	foreach ($ips as $name => $default) {
		$p = $params->{$name};
		$r = $resource_map[$name];

		if (!isAdmin() && $r->value === 0)
			continue;

		$xtpl->table_td($p->label);
		$xtpl->table_td(approx_number($r->free).' '.unit_for_cluster_resource($name));
		$xtpl->form_add_number_pure(
			$name,
			isset($_GET[$name]) ? $_GET[$name] : $default,
			0,
			$r->cluster_resource->max,
			$r->cluster_resource->stepsize,
			unit_for_cluster_resource($name)
		);
		$xtpl->table_tr();
	}

	$xtpl->table_td(
		_('Contact support if you need more').' <a href="?page=adminm&action=cluster_resources&id='.$user->id.'">'._('resources.').'</a>',
		false, false, '3'
	);
	$xtpl->table_tr();

	$xtpl->form_out(_("Next"));
}

function build_resource_uri_params() {
	$resources = [
		'cpu', 'memory', 'swap', 'diskspace', 'ipv4', 'ipv4_private', 'ipv6'
	];
	$params = [];

	foreach ($resources as $r) {
		if (isset($_GET[$r]))
			$params[] = $r.'='.$_GET[$r];
	}

	if (count($params) > 0)
		return '&'.implode('&', $params);
	else
		return '';
}

function print_newvps_page5($user_id, $platform, $loc_id, $tpl_id) {
	global $xtpl, $api;

	if (!$platform) {
		notify_user(
			_('Invalid platform'),
			_('Please select the desired platform.')
		);
		redirect('?page=adminvps&action=new-step-1');
	}

	$xtpl->title(_("Create a VPS: Final touches (5/5)"));
	$xtpl->sbar_add(
		_('Back to parameters'),
		'?page=adminvps&action=new-step-4&user='.$user_id.'&platform='.$platform.'&location='.$loc_id.'&os_template='.$tpl_id.build_resource_uri_params()
	);

	try {
		$loc = $api->location->show(
			$loc_id,
			['meta' => ['includes' => 'environment']]
		);

	} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
		notify_user(
			_('Invalid location'),
			_('Please select the desired location for your new VPS.')
		);
		redirect('?page=adminvps&action=new-step-2&platform='.$platform);
	}

	try {
		$tpl = $api->os_template->show($tpl_id);

	} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
		notify_user(
			_('Invalid distribution'),
			_('Please select the desired distribution of your new VPS.'));
		redirect('?page=adminvps&action=new-step-3&platform='.$platform.'&location='.$loc_id);
	}

	$xtpl->table_title(_('Configuration'));

	if (isAdmin()) {
		try {
			$user = $api->user->show($user_id);
		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			notify_user(_('Invalid user'), _('Please select target user.'));
			redirect('?page=adminvps&action=new-step-0');
		}

		$xtpl->table_td(_('User').':');
		$xtpl->table_td(user_link($user));
		$xtpl->table_tr();
	}

	$xtpl->table_td(_('Platform').':');
	$xtpl->table_td(hypervisorTypeToLabel($platform));
	$xtpl->table_tr();

	$xtpl->table_td(_('Environment').':');
	$xtpl->table_td($loc->environment->label);
	$xtpl->table_tr();

	$xtpl->table_td(_('Location').':');
	$xtpl->table_td($loc->label);
	$xtpl->table_tr();

	$xtpl->table_td(_('Distribution').':');
	$xtpl->table_td($tpl->label);
	$xtpl->table_tr();

	$xtpl->table_td(_('CPUs').':');
	$xtpl->table_td($_GET['cpu'].' '.unit_for_cluster_resource('cpu'));
	$xtpl->table_tr();

	$xtpl->table_td(_('Memory').':');
	$xtpl->table_td($_GET['memory'].' '.unit_for_cluster_resource('memory'));
	$xtpl->table_tr();

	if ($_GET['swap']) {
		$xtpl->table_td(_('Swap').':');
		$xtpl->table_td($_GET['swap'].' '.unit_for_cluster_resource('swap'));
		$xtpl->table_tr();
	}

	$xtpl->table_td(_('Disk').':');
	$xtpl->table_td($_GET['diskspace'].' '.unit_for_cluster_resource('diskspace'));
	$xtpl->table_tr();

	if ($_GET['ipv4']) {
		$xtpl->table_td(_('Public IPv4').':');
		$xtpl->table_td($_GET['ipv4'].' '.unit_for_cluster_resource('ipv4'));
		$xtpl->table_tr();
	}

	if ($_GET['ipv6']) {
		$xtpl->table_td(_('Public IPv6').':');
		$xtpl->table_td($_GET['ipv6'].' '.unit_for_cluster_resource('ipv6'));
		$xtpl->table_tr();
	}

	if ($_GET['ipv4_private']) {
		$xtpl->table_td(_('Private IPv4').':');
		$xtpl->table_td($_GET['ipv4_private'].' '.unit_for_cluster_resource('ipv4_private'));
		$xtpl->table_tr();
	}

	$xtpl->table_out();

	$xtpl->table_title(_('Finalize'));
	$xtpl->form_create(
		'?page=adminvps&action=new-submit&user='.$user_id.'&platform='.$platform.'&location='.$loc_id.'&os_template='.$tpl_id.build_resource_uri_params(),
		'post'
	);

	if (isAdmin()) {
		$xtpl->form_add_select(
			_("Node").':',
			'node',
			resource_list_to_options(
				$api->node->list([
					'location' => $loc->id,
					'hypervisor_type' => $platform,
				]),
				'id', 'domain_name',
				false
			),
			$_POST['node']
		);
	}

	$xtpl->form_add_input(
		_("Hostname").':',
		'text',
		'30',
		'hostname',
		$_POST['hostname'],
		_("A-z, a-z"),
		255
	);

	if (!isAdmin() && USERNS_PUBLIC) {
		// User namespace map
		$ugid_maps = resource_list_to_options($api->user_namespace_map->list());
		$ugid_maps[0] = _('None/auto');
		$xtpl->form_add_select(
			_('UID/GID map').':',
			'user_namespace_map',
			$ugid_maps,
			post_val('user_namespace_map')
		);
	}

	if (isAdmin()) {
		$xtpl->form_add_checkbox(
			_("Boot on create").':',
			'boot_after_create',
			'1',
			(isset($_POST['hostname']) && !isset($_POST['boot_after_create'])) ? false : true
		);
		$xtpl->form_add_textarea(
			_("Extra information about VPS").':',
			28, 4,
			'info',
			$_POST['info']
		);
	}

	$xtpl->table_tr();

	$xtpl->form_out(_("Create VPS"));
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

	if (isAdmin())
		$xtpl->sbar_add(_('Clone VPS'), '?page=adminvps&action=clone-step-0&veid='.$vps->id);
	else
		$xtpl->sbar_add(_('Clone VPS'), '?page=adminvps&action=clone-step-1&veid='.$vps->id);

	if ($vps->node->hypervisor_type == 'openvz')
		$xtpl->sbar_add(_('Swap VPS'), '?page=adminvps&action=swap&veid='.$vps->id);

	$return_url = urlencode($_SERVER['REQUEST_URI']);
	$xtpl->sbar_add(_('History'), '?page=history&list=1&object=Vps&object_id='.$vps->id.'&return_url='.$return_url);

	$xtpl->sbar_add(_('OOM reports'), '?page=oom_reports&action=list&vps='.$vps->id.'&list=1');

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

function vps_clone_form_step0($vps_id) {
	global $xtpl, $api;

	$vps = $api->vps->show(
		$vps_id,
		['meta' => ['includes' => 'node__location,user']]
	);

	$xtpl->title(_("Clone a VPS: Select user (0/3)"));

	$xtpl->table_title(_('Source VPS'));
	$xtpl->table_td(_('VPS:'));
	$xtpl->table_td(vps_link($vps).' '.$vps->hostname);
	$xtpl->table_tr();

	if (isAdmin()) {
		$xtpl->table_td(_('User:'));
		$xtpl->table_td(user_link($vps->user));
		$xtpl->table_tr();
	}

	$xtpl->table_td(_('Platform:'));
	$xtpl->table_td(hypervisorTypeToLabel($vps->node->hypervisor_type));
	$xtpl->table_tr();

	$xtpl->table_td(_('Location:'));
	$xtpl->table_td($vps->node->location->label);
	$xtpl->table_tr();

	$xtpl->table_td(_('Node:'));
	$xtpl->table_td($vps->node->domain_name);
	$xtpl->table_tr();
	$xtpl->table_out();

	$xtpl->table_title(_('Choose target user'));
	$xtpl->form_create('', 'get', 'clonevps-step0', false);
	$xtpl->form_set_hidden_fields([
		'page' => 'adminvps',
		'action' => 'clone-step-1',
		'veid' => $vps_id,
	]);
	$xtpl->form_add_input(_('User ID').':', 'text', '30', 'user', get_val('user', $vps->user_id));
	$xtpl->form_out(_("Next"));
}

function vps_clone_form_step1($vps_id, $user_id) {
	global $xtpl, $api;

	$xtpl->title(_("Clone a VPS: Select platform (1/3)"));

	if (isAdmin()) {
		$xtpl->sbar_add(
			_('Back to user selection'),
			'?page=adminvps&action=clone-step-0&veid='.$veid.'&user='.$user_id.'&platform='.$platform
		);
	}

	$vps = $api->vps->show(
		$vps_id,
		['meta' => ['includes' => 'node__location,user']]
	);

	$xtpl->table_title(_('Source VPS'));

	if (isAdmin()) {
		$xtpl->table_td(_('User:'));
		$xtpl->table_td(user_link($vps->user));
		$xtpl->table_tr();
	}

	$xtpl->table_td(_('VPS:'));
	$xtpl->table_td(vps_link($vps).' '.$vps->hostname);
	$xtpl->table_tr();

	$xtpl->table_td(_('Platform:'));
	$xtpl->table_td(hypervisorTypeToLabel($vps->node->hypervisor_type));
	$xtpl->table_tr();

	$xtpl->table_td(_('Location:'));
	$xtpl->table_td($vps->node->location->label);
	$xtpl->table_tr();

	$xtpl->table_td(_('Node:'));
	$xtpl->table_td($vps->node->domain_name);
	$xtpl->table_tr();
	$xtpl->table_out();

	if (isAdmin()) {
		try {
			$user = $api->user->show($user_id);
		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			notify_user(_('Invalid user'), _('Please select target user.'));
			redirect('?page=adminvps&action=new-step-0');
		}

		$xtpl->table_title(_('Target VPS'));

		$xtpl->table_td(_('User').':');
		$xtpl->table_td(user_link($user));
		$xtpl->table_tr();
		$xtpl->table_out();
	}

	$xtpl->table_title(_('Choose target platform'));
	$xtpl->form_create('', 'get', 'clonevps-step1', false);
	$xtpl->form_set_hidden_fields([
		'page' => 'adminvps',
		'action' => 'clone-step-2',
		'veid' => $vps_id,
		'user' => $user_id,
	]);

	$xtpl->form_add_radio_pure(
		'platform',
		'vpsadminos',
		get_val_issetto('platform', 'vpsadminos', true)
	);
	$xtpl->table_td('<strong>'._('vpsAdminOS').'</strong>');
	$xtpl->table_tr();
	$xtpl->table_td('');
	$xtpl->table_td(_('
		vpsAdminOS is an in-house developed container-based
		virtualization platform that powers our VPS. For more information, see our
		<a href="https://kb.vpsfree.org/manuals/vps/vpsadminos" target="_blank">knowledge base</a>
		or project documentation at
		<a href="https://vpsadminos.org" target="_blank">vpsadminos.org</a>.
	'));
	$xtpl->table_tr();

	$xtpl->form_add_radio_pure(
		'platform',
		'openvz',
		get_val_issetto('platform', 'openvz')
	);
	$xtpl->table_td('<strong>'._('OpenVZ Legacy').'<strong>');
	$xtpl->table_tr();
	$xtpl->table_td('');
	$xtpl->table_td(_('
		OpenVZ Legacy is a container-based virtualization platform.
		We are in the process of migrating to a more up-to-date solution called
		vpsAdminOS, which is at this time available only in Prague
		(Praha). For more information, see our
		<a href="https://kb.vpsfree.org/manuals/vps/vpsadminos" target="_blank">knowledge base</a>.
	'));
	$xtpl->table_tr();

	$xtpl->form_out(_("Next"));
}

function vps_clone_form_step2($vps_id, $user_id, $platform) {
	global $xtpl, $api;

	if (!$platform) {
		notify_user(
			_('Invalid platform'),
			_('Please select the desired platform.')
		);
		redirect('?page=adminvps&action=new-step-1&veid='.$vps_id.'&user='.$user_id);
	}

	$xtpl->title(_("Clone a VPS: Select a location (2/3)"));
	$xtpl->sbar_add(
		_('Back to platform selection'),
		'?page=adminvps&action=clone-step-1&veid='.$vps_id.'&user='.$user_id.'&platform='.$platform
	);

	$vps = $api->vps->show(
		$vps_id,
		['meta' => ['includes' => 'node__location,user']]
	);

	$xtpl->table_title(_('Source VPS'));

	if (isAdmin()) {
		$xtpl->table_td(_('User:'));
		$xtpl->table_td(user_link($vps->user));
		$xtpl->table_tr();
	}

	$xtpl->table_td(_('VPS:'));
	$xtpl->table_td(vps_link($vps).' '.$vps->hostname);
	$xtpl->table_tr();

	$xtpl->table_td(_('Platform:'));
	$xtpl->table_td(hypervisorTypeToLabel($vps->node->hypervisor_type));
	$xtpl->table_tr();

	$xtpl->table_td(_('Location:'));
	$xtpl->table_td($vps->node->location->label);
	$xtpl->table_tr();

	$xtpl->table_td(_('Node:'));
	$xtpl->table_td($vps->node->domain_name);
	$xtpl->table_tr();
	$xtpl->table_out();

	$xtpl->table_title(_('Target VPS'));

	if (isAdmin()) {
		try {
			$user = $api->user->show($user_id);
		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			notify_user(_('Invalid user'), _('Please select target user.'));
			redirect('?page=adminvps&action=new-step-0');
		}

		$xtpl->table_td(_('User').':');
		$xtpl->table_td(user_link($user));
		$xtpl->table_tr();
	}

	$xtpl->table_td(_('Platform').':');
	$xtpl->table_td(hypervisorTypeToLabel($platform));
	$xtpl->table_tr();
	$xtpl->table_out();

	$xtpl->table_title(_('Choose target location'));
	$xtpl->form_create('', 'get', 'clonevps-step2', false);
	$xtpl->form_set_hidden_fields([
		'page' => 'adminvps',
		'action' => 'clone-step-3',
		'veid' => $vps_id,
		'user' => $user_id,
		'platform' => $platform,
	]);

	$locations = $api->location->list([
		'has_hypervisor' => true,
		'hypervisor_type' => $platform,
		'meta' => ['includes' => 'environment'],
	]);

	if (!isAdmin())
		$user = $api->user->current();

	foreach ($locations as $loc) {
		$xtpl->form_add_radio_pure(
			'location',
			$loc->id,
			$_GET['location'] == $loc->id
		);
		$xtpl->table_td('<strong>'.$loc->label.'</strong>');
		$xtpl->table_tr();

		$xtpl->table_td('');
		$xtpl->table_td(
			'<p>'._('Environment').': '.$loc->environment->label.'</p>'.
			'<p>'.$loc->environment->description.'</p>'.
			'<p>'.$loc->description.'</p>'.
			'<h4>'._('Available resources').':</h4>'.
			format_available_resources($user, $loc->environment)
		);
		$xtpl->table_tr();
	}

	$xtpl->form_out(_("Next"));
}

function vps_clone_form_step3($vps_id, $user_id, $platform, $loc_id) {
	global $xtpl, $api;

	if (!$platform) {
		notify_user(
			_('Invalid platform'),
			_('Please select the desired platform.')
		);
		redirect('?page=adminvps&action=clone-step-1&veid='.$vps_id.'&user='.$user_id);
	}

	$xtpl->title(_("Clone a VPS: Final touches (3/3)"));
	$xtpl->sbar_add(
		_('Back to location'),
		'?page=adminvps&action=clone-step-2&veid='.$vps_id.'&user='.$user_id.'&platform='.$platform.'&location='.$loc_id
	);

	try {
		$loc = $api->location->show(
			$loc_id,
			['meta' => ['includes' => 'environment']]
		);

	} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
		notify_user(
			_('Invalid location'),
			_('Please select the desired location for your new VPS.')
		);
		redirect('?page=adminvps&action=clone-step-2&veid='.$vps_id.'&user='.$user_id.'&platform='.$platform);
	}

	$vps = $api->vps->show(
		$vps_id,
		['meta' => ['includes' => 'node__location,user']]
	);

	$xtpl->table_title(_('Source VPS'));

	if (isAdmin()) {
		$xtpl->table_td(_('User:'));
		$xtpl->table_td(user_link($vps->user));
		$xtpl->table_tr();
	}

	$xtpl->table_td(_('VPS:'));
	$xtpl->table_td(vps_link($vps).' '.$vps->hostname);
	$xtpl->table_tr();

	$xtpl->table_td(_('Platform:'));
	$xtpl->table_td(hypervisorTypeToLabel($vps->node->hypervisor_type));
	$xtpl->table_tr();

	$xtpl->table_td(_('Location:'));
	$xtpl->table_td($vps->node->location->label);
	$xtpl->table_tr();

	$xtpl->table_td(_('Node:'));
	$xtpl->table_td($vps->node->domain_name);
	$xtpl->table_tr();
	$xtpl->table_out();

	$xtpl->table_title(_('Target VPS'));

	if (isAdmin()) {
		try {
			$user = $api->user->show($user_id);
		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			notify_user(_('Invalid user'), _('Please select target user.'));
			redirect('?page=adminvps&action=new-step-0');
		}

		$xtpl->table_td(_('User').':');
		$xtpl->table_td(user_link($user));
		$xtpl->table_tr();
	}

	$xtpl->table_td(_('Platform').':');
	$xtpl->table_td(hypervisorTypeToLabel($platform));
	$xtpl->table_tr();

	$xtpl->table_td(_('Location').':');
	$xtpl->table_td($loc->label);
	$xtpl->table_tr();
	$xtpl->table_out();

	$xtpl->table_title(_('Finalize'));
	$xtpl->form_create(
		'?page=adminvps&action=clone-submit&veid='.$vps_id.'&user='.$user_id.'&platform='.$platform.'&location='.$loc_id,
		'post'
	);

	$input = $api->vps->clone->getParameters('input');

	if (isAdmin()) {
		$xtpl->form_add_select(
			_("Node").':',
			'node',
			resource_list_to_options(
				$api->node->list([
					'location' => $loc->id,
					'hypervisor_type' => $platform,
				]),
				'id', 'domain_name',
				false
			),
			$_POST['node']
		);
	}

	$xtpl->form_add_input(
		_("Hostname").':',
		'text',
		'30',
		'hostname',
		post_val('hostname', $vps->hostname.'-clone'),
		_("A-z, a-z"),
		255
	);

	api_param_to_form('subdatasets', $input->subdatasets);
	api_param_to_form('dataset_plans', $input->dataset_plans);
	api_param_to_form('resources', $input->resources);
	api_param_to_form('features', $input->features);
	api_param_to_form('stop', $input->stop);

	$xtpl->table_tr();

	$xtpl->form_out(_("Clone VPS"));
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
	$xtpl->form_create('?page=adminvps&action=iproute_select&veid='.$vps->id.'&netif='.$netif->id, 'post');

	foreach ($ips as $ip) {
		$xtpl->table_td(ip_label($ip));
		$xtpl->table_td(
			$ip->addr.'/'.$ip->prefix.
			($ip->route_via_id ? _(' via ').$ip->route_via->addr : '')
		);
		$xtpl->table_td(
			'<a href="?page=adminvps&action=iproute_del&id='.$ip->id.
			'&veid='.$vps->id.'&netif='.$netif->id.'&t='.csrf_token().'" title="'._('Remove').'">'.
			'<img src="template/icons/m_remove.png" alt="'._("Remove").'">'.
			'</a>'
		);
		$xtpl->table_tr();
	}

	$xtpl->form_add_select(
		_('Add route').':',
		'iproute_type',
		available_ip_options($vps),
		post_val('iproute_type')
	);

	$xtpl->form_out(_('Continue'));
}

function vps_netif_iproute_add_form() {
	global $xtpl, $api;

	$vps = $api->vps->show($_GET['veid']);
	$netif = $api->network_interface->show($_GET['netif']);

	$xtpl->title(_('Add route'));
	$xtpl->sbar_add(_('Back to details'), '?page=adminvps&action=info&veid='.$vps->id);

	$xtpl->form_create('?page=adminvps&action=iproute_add&veid='.$vps->id.'&netif='.$netif->id, 'post');

	switch ($_POST['iproute_type']) {
	case 'ipv4':
		$free = get_free_route_list('ipv4', $vps, 'public_access', 25);
		break;
	case 'ipv4_private':
		$free = get_free_route_list('ipv4_private', $vps, 'private_access', 25);
		break;
	case 'ipv6':
		$free = get_free_route_list('ipv6', $vps, null, 25);
		break;
	default:
		$xtpl->perex(_('Invalid IP route type'), '');
		return;
	}

	$via_addrs = resource_list_to_options(
		$api->host_ip_address->list([
			'network_interface' => $netif->id,
			'assigned' => true,
			'version' => $_POST['iproute_type'] == 'ipv6' ? 6 : 4,
		]),
		'id', 'addr',
		false
	);

	$via_addrs = [
		'' => _('host address from this network will be on '.$netif->name)
	] + $via_addrs;

	$xtpl->table_td(_('VPS').':');
	$xtpl->table_td($vps->id.' '.$vps->hostname);
	$xtpl->table_tr();

	$xtpl->table_td(_('Network interface').':');
	$xtpl->table_td($netif->name);
	$xtpl->table_tr();

	$xtpl->table_td(
		_('Address').':'.
		'<input type="hidden" name="iproute_type" value="'.$_POST['iproute_type'].'">'
	);
	$xtpl->form_add_select_pure('addr', $free, post_val('addr'));
	$xtpl->table_tr();

	$xtpl->form_add_select(_('Via').':', 'route_via', $via_addrs, post_val('route_via'));

	$xtpl->form_out(_('Add route'));
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

function vps_delete_form($vps_id) {
	global $xtpl, $api;
	$vps = $api->vps->find($vps_id);

	$xtpl->perex(_("Are you sure you want to delete VPS number").' '.$vps->id.'?', '');

	$xtpl->table_title(_("Delete VPS"));
	$xtpl->table_td(_("Hostname").':');
	$xtpl->table_td($vps->hostname);
	$xtpl->table_tr();
	$xtpl->form_create('?page=adminvps&section=vps&action=delete2&veid='.$vps->id, 'post');
	$xtpl->form_csrf();

	if(isAdmin()) {
		$xtpl->form_add_checkbox(_("Lazy delete").':', 'lazy_delete', '1', true,
			_("Do not delete VPS immediately, but after passing of predefined time."));
	}
	$xtpl->form_out(_("Delete"));
}
