<?php
function cluster_header() {
	global $xtpl, $api;

	$xtpl->sbar_add(_("VPS overview"), '?page=cluster&action=vps');
	$xtpl->sbar_add(_("General settings"), '?page=cluster&action=general_settings');
	$xtpl->sbar_add(_("Register new node"), '?page=cluster&action=newnode');
	$xtpl->sbar_add(_("Manage OS templates"), '?page=cluster&action=templates');
	$xtpl->sbar_add(_("Manage configs"), '?page=cluster&action=configs');
	$xtpl->sbar_add(_("Manage networks"), '?page=cluster&action=networks');
	$xtpl->sbar_add(_("Manage IP addresses"), '?page=cluster&action=ip_addresses');
	$xtpl->sbar_add(_("Manage DNS servers"), '?page=cluster&action=dns');
	$xtpl->sbar_add(_("Manage environments"), '?page=cluster&action=environments');
	$xtpl->sbar_add(_("Manage locations"), '?page=cluster&action=locations');
	$xtpl->sbar_add(_("Integrity check"), '?page=cluster&action=integrity_check');
	$xtpl->sbar_add(_("Manage Payments"), '?page=cluster&action=payments_settings');
	$xtpl->sbar_add(_("Notice board & log"), '?page=cluster&action=noticeboard');
	$xtpl->sbar_add(_("Help boxes"), '?page=cluster&action=helpboxes');
	$xtpl->sbar_add(_("Edit vpsAdmin textfields"), '?page=cluster&action=fields');
	
	$xtpl->table_title(_("Summary"));
	
	$stats = $api->cluster->full_stats();
	
	$xtpl->table_td(_("Nodes").':');
	$xtpl->table_td($stats["nodes_online"] .' '._("online").' / '. $stats["node_count"] .' '._("total"), $stats["nodes_online"] < $stats["node_count"] ? '#FFA500' : '#66FF66');
	$xtpl->table_tr();
	
	$xtpl->table_td(_("VPS").':');
	$xtpl->table_td($stats["vps_running"] .' '._("running").' / '. $stats["vps_stopped"] .' '._("stopped").' / '. $stats["vps_suspended"] .' '._("suspended").' / '.
					$stats["vps_deleted"] .' '._("deleted").' / '. $stats["vps_count"] .' '._("total"));
	$xtpl->table_tr();
	
	$xtpl->table_td(_("Members").':');
	$xtpl->table_td($stats["user_active"] .' '._("active").' / '. $stats["user_suspended"] .' '._("suspended")
	                .' / '. $stats["user_deleted"] .' '._("deleted").' / '. $stats["user_count"] .' '._("total"));
	$xtpl->table_tr();
	
	$xtpl->table_td(_("IPv4 addresses").':');
	$xtpl->table_td($stats["ipv4_used"] .' '._("used").' / '. $stats["ipv4_count"] .' '._("total"));
	$xtpl->table_tr();
	
	$xtpl->table_out();
}

function node_overview() {
	global $xtpl, $api;
	
	$xtpl->table_title(_("Node list"));
	$xtpl->table_add_category('');
	$xtpl->table_add_category('#');
	$xtpl->table_add_category(_("Name"));
	$xtpl->table_add_category(_("VPS"));
	$xtpl->table_add_category(_("Up"));
	$xtpl->table_add_category(_("Load"));
	$xtpl->table_add_category(_("%iowait"));
	$xtpl->table_add_category(_("%idle"));
	$xtpl->table_add_category(_("Free mem"));
	$xtpl->table_add_category(_("ARC"));
	$xtpl->table_add_category(_("%hit"));
	$xtpl->table_add_category(_("Version"));
	$xtpl->table_add_category(_("Kernel"));
	$xtpl->table_add_category('<img title="'._("Toggle maintenance on node.").'" alt="'._("Toggle maintenance on node.").'" src="template/icons/maintenance_mode.png">');
	
	foreach ($api->node->overview_list() as $node) {
		// Availability icon
		$icons = "";
		$maintenance_toggle = $node->maintenance_lock == 'lock' ? 0 : 1;
	
		$t = new DateTime($node->last_report);
		$t->setTimezone(new DateTimeZone(date_default_timezone_get()));
		
		if (!$node->last_report || (time() - $t->getTimestamp()) > 150) {
			$icons .= '<img title="'._("The server is not responding").'" src="template/icons/error.png"/>';
		
		} else {
			$icons .= '<img title="'._("The server is online").'" src="template/icons/server_online.png"/>';
		}
		
		$icons = '<a href="?page=cluster&action='.($maintenance_toggle ? 'maintenance_lock' : 'set_maintenance_lock').'&type=node&obj_id='.$node->id.'&lock='.$maintenance_toggle.'">'.$icons.'</a>';
		
		$xtpl->table_td($icons, false, true);
		
		// Node ID, Name, IP, load
		$xtpl->table_td($node->id);
		$xtpl->table_td($node->domain_name);
		$xtpl->table_td($node->vps_running, false, true);
		$xtpl->table_td(sprintf('%.1f', $node->uptime / 60.0 / 60 / 24), false, true);
		$xtpl->table_td($node->loadavg, false, true);

		// CPU
		$xtpl->table_td(sprintf('%.2f', $node->cpu_iowait), false, true);
		$xtpl->table_td(sprintf('%.2f', $node->cpu_idle), false, true);

		// Memory
		$xtpl->table_td(
			sprintf('%.2f', ($node->total_memory - $node->used_memory) / 1024),
			false, true
		);

		// ARC
		$xtpl->table_td(sprintf('%.2f', $node->arc_size / 1024.0), false, true);
		$xtpl->table_td(sprintf('%.2f', $node->arc_hitpercent), false, true);

		// Daemon version
		$xtpl->table_td($node->version, false, true);
		
		// Kernel
		$xtpl->table_td(kernel_version($node->kernel));
		
		$xtpl->table_td(maintenance_lock_icon('node', $node));
		
		$xtpl->table_tr();
	}
	
	$xtpl->table_out('cluster_node_list');


}

function node_vps_overview() {
	global $xtpl, $api;

	$xtpl->table_title(_("Node list"));
	$xtpl->table_add_category('');
	$xtpl->table_add_category('#');
	$xtpl->table_add_category(_("Name"));
	$xtpl->table_add_category(_("Up"));
	$xtpl->table_add_category(_("Down"));
	$xtpl->table_add_category(_("Del"));
	$xtpl->table_add_category(_("Sum"));
	$xtpl->table_add_category(_("Free"));
	$xtpl->table_add_category(_("Max"));
	$xtpl->table_add_category(' ');
	
	foreach ($api->node->overview_list() as $node) {
		// Availability icon
		$icons = "";
		$maintenance_toggle = $node->maintenance_lock == 'lock' ? 0 : 1;
	
		$t = new DateTime($node->last_report);
		$t->setTimezone(new DateTimeZone(date_default_timezone_get()));
		
		if (!$node->last_report || (time() - $t->getTimestamp()) > 150) {
			$icons .= '<img title="'._("The server is not responding").'" src="template/icons/error.png"/>';
		
		} else {
			$icons .= '<img title="'._("The server is online").'" src="template/icons/server_online.png"/>';
		}
		
		$icons = '<a href="?page=cluster&action='.($maintenance_toggle ? 'maintenance_lock' : 'set_maintenance_lock').'&type=node&obj_id='.$node->id.'&lock='.$maintenance_toggle.'">'.$icons.'</a>';
		
		$xtpl->table_td($icons, false, true);
		
		// Node ID, Name, IP, load
		$xtpl->table_td($node->id);
		$xtpl->table_td($node->domain_name);
		
		// Up, down, del, sum
		$xtpl->table_td($node->vps_running, false, true);
		$xtpl->table_td($node->vps_stopped, false, true);
		$xtpl->table_td($node->vps_deleted, false, true);
		$xtpl->table_td($node->vps_total, false, true);
		
		// Free, max
		$xtpl->table_td($node->vps_free, false, true);
		$xtpl->table_td($node->vps_max, false, true);
		
		$xtpl->table_td('<a href="?page=cluster&action=node_edit&node_id='.$node->id.'"><img src="template/icons/edit.png" title="'._("Edit").'"></a>');
		
		
		$xtpl->table_tr();
	}
	
	$xtpl->table_out('cluster_node_list');
}

function networks_list($title) {
	global $xtpl, $api;
	
	$xtpl->title(_('Networks'));

	$xtpl->table_add_category(_('Network'));
	$xtpl->table_add_category(_('Label'));
	$xtpl->table_add_category(_('Location'));
	$xtpl->table_add_category(_('Public'));
	$xtpl->table_add_category(_('Managed'));
	$xtpl->table_add_category(_('Size'));
	$xtpl->table_add_category(_('Used'));
	$xtpl->table_add_category(_('Assigned'));
	$xtpl->table_add_category(_('Owned'));
	$xtpl->table_add_category(_('Free'));
	$xtpl->table_add_category(_('IPs'));

	$networks = $api->network->list(array(
		'meta' => array('includes' => 'location')
	));

	foreach ($networks as $n) {
		$xtpl->table_td($n->address .'/'. $n->prefix);
		$xtpl->table_td($n->label);
		$xtpl->table_td($n->location->label);
		$xtpl->table_td(boolean_icon($n->role === 'public_access'));
		$xtpl->table_td(boolean_icon($n->managed));
		$xtpl->table_td($n->size, false, true);
		$xtpl->table_td($n->used, false, true);
		$xtpl->table_td($n->assigned, false, true);
		$xtpl->table_td($n->owned, false, true);
		$xtpl->table_td(
			($n->used - max($n->assigned, $n->owned)).
			' ('.($n->size - max($n->assigned, $n->owned)).')',
			false, true
		);
		$xtpl->table_td(ip_list_link(
			'<img
				src="template/icons/vps_ip_list.png"
				title="'._('List IP addresses in this network').'">',
			array('network' => $n->id))
		);
		$xtpl->table_tr();
	}

	$xtpl->table_out();
}

function ip_list_link($text, $conds) {
	$str_conds = array();

	foreach ($conds as $k => $v)
		$str_conds[] = "$k=$v";

	$ret = '<a href="?page=cluster&action=ip_addresses&list=1&'.implode('&', $str_conds).'">';
	$ret .= $text;
	$ret .= '</a>';

	return $ret;
}

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
	
	$xtpl->form_add_input(_("Offset").':', 'text', '40', 'offset', get_val('offset', '0'), '');
	$xtpl->form_add_select(_("Version").':', 'v', $versions, get_val('v', 0));
	$xtpl->form_add_input(_("User ID").':', 'text', '40', 'user', get_val('user'), _("'unassigned' to list free addresses"));
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
	
	if ($_GET['user'] === 'unassigned')
		$params['user'] = null;
	elseif ($_GET['user'])
		$params['user'] = $_GET['user'];
	
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
	
	$ips = $api->ip_address->list($params);
	
	$xtpl->table_add_category(_("Network"));
	$xtpl->table_add_category(_("IP address"));
	$xtpl->table_add_category(_("Location"));
	$xtpl->table_add_category(_("TX"));
	$xtpl->table_add_category(_("RX"));
	$xtpl->table_add_category(_('User'));
	$xtpl->table_add_category('VPS');
	$xtpl->table_add_category('');

	$return_url = urlencode($_SERVER['REQUEST_URI']);
	
	foreach ($ips as $ip) {
		$xtpl->table_td($ip->network->address .'/'. $ip->network->prefix);
		$xtpl->table_td($ip->addr);
		$xtpl->table_td($ip->network->location->label);
		$xtpl->table_td(round($ip->max_tx * 8.0 / 1024 / 1024, 1), false, true);
		$xtpl->table_td(round($ip->max_rx * 8.0 / 1024 / 1024, 1), false, true);
		
		if ($ip->user_id)
			$xtpl->table_td('<a href="?page=adminm&action=edit&id='.$ip->user_id.'">'.$ip->user->login.'</a>');
		else
			$xtpl->table_td('---');
		
		if ($ip->vps_id)
			$xtpl->table_td('<a href="?page=adminvps&action=info&veid='.$ip->vps_id.'">'.$ip->vps_id.' ('.$ip->vps->hostname.')</a>');
		else
			$xtpl->table_td('---');

		$xtpl->table_td(
			'<a href="?page=cluster&action=ipaddr_edit&id='.$ip->id.'&return='.$return_url.'">'.
			'<img src="template/icons/m_edit.png" alt="'._('Edit').'" title="'._('Edit').'">'.
			'</a>'
		);
		
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
	$xtpl->form_add_select(
		_("Network").':',
		'network',
		resource_list_to_options(
			$api->network->list(),
			'id', 'label',
			true,
			network_label
		),
		$_POST['network']
	);
	$xtpl->form_add_select(_("User").':', 'user',
		resource_list_to_options($api->user->list(), 'id', 'login'), $_POST['user']);
	
	$xtpl->form_out(_("Add"));
}

function ip_edit_form($id) {
	global $xtpl, $api;

	$ip = $api->ip_address->show($id, array('meta' => array('includes' => 'network__location')));

	$xtpl->table_title($ip->network->location->label.': '.$ip->addr.'/'.$ip->network->prefix);
	$xtpl->sbar_add(
		_("Back"),
		$_GET['return'] ? $_GET['return'] : '?page=cluster&action=ip_addresses'
	);
	
	$xtpl->form_create(
		'?page=cluster&action=ipaddr_edit2&id='.$ip->id.'&return='.urlencode($_GET['return']),
		'post'
	);

	$xtpl->table_td(_('Max TX').':');
	$xtpl->form_add_number_pure(
		'max_tx',
		post_val('max_tx', $ip->max_tx / 1024.0 / 1024.0 * 8),
		0,
		999999999999,
		1,
		'Mbps'
	);
	$xtpl->table_tr();
	
	$xtpl->table_td(_('Max RX').':');
	$xtpl->form_add_number_pure(
		'max_rx',
		post_val('max_rx', $ip->max_rx / 1024.0 / 1024.0 * 8),
		0,
		999999999999,
		1,
		'Mbps'
	);
	$xtpl->table_tr();

	$xtpl->form_add_input(_('User ID').':', 'text', '30', 'user', post_val('user', $ip->user_id));

	$xtpl->form_out(_("Save"));
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

function integrity_check_list() {
	global $xtpl, $api;

	$xtpl->sbar_add(_("Back"), '?page=cluster');
	$xtpl->sbar_add(_("Checks"), '?page=cluster&action=integrity_check');
	$xtpl->sbar_add(_("Objects"), '?page=cluster&action=integrity_objects');
	$xtpl->sbar_add(_("Facts"), '?page=cluster&action=integrity_facts');

	$xtpl->title2(_('Integrity checks'));

	$xtpl->table_title(_('Filters'));
	$xtpl->form_create('', 'get', 'check-filter', false);
		
	$xtpl->table_td(_("Limit").':'.
		'<input type="hidden" name="page" value="cluster">'.
		'<input type="hidden" name="action" value="integrity_check">'.
		'<input type="hidden" name="list" value="1">'
	);
	$xtpl->form_add_input_pure('text', '40', 'limit', get_val('limit', '25'), '');
	$xtpl->table_tr();
	
	$xtpl->form_add_input(_("Offset").':', 'text', '40', 'offset', get_val('offset', '0'), '');


	$statuses = $api->integrity_check->list->getParameters('input')
		->status
		->validators
		->include
		->values;
	$empty = array('' => _('---'));
		
	$xtpl->form_add_select(
	 	_('Status').':',
		'status',
		$empty + $statuses,
		$_GET['status']
	);
		
	$xtpl->form_out(_('Show'));

	if (!$_GET['list'])
		return;

	$xtpl->table_add_category(_('Date'));
	$xtpl->table_add_category(_('Status'));
	$xtpl->table_add_category(_('Objects'));
	$xtpl->table_add_category(_('Integral objects'));
	$xtpl->table_add_category(_('Broken objects'));
	$xtpl->table_add_category(_('Facts'));
	$xtpl->table_add_category(_('True facts'));
	$xtpl->table_add_category(_('False facts'));

	$params = array(
		'limit' => get_val('limit', 25),
		'offset' => get_val('offset', 0)
	);

	if (isset($_GET['status']) && $_GET['status'] !== '')
		$params['status'] = $statuses[ $_GET['status'] ];

	if ($_GET['id'])
		$checks = array(
			$api->integrity_check->find($_GET['id'])
		);
	else
		$checks = $api->integrity_check->list($params);

	foreach ($checks as $c) {
		$xtpl->table_td(tolocaltz($c->created_at));
		$xtpl->table_td($c->status);
		$xtpl->table_td(
			'<a href="?page=cluster&action=integrity_objects&list=1&integrity_check='.$c->id.'">'.$c->checked_objects.'</a>',
			false, true
		);
		$xtpl->table_td(
			'<a href="?page=cluster&action=integrity_objects&list=1&integrity_check='.$c->id.'&status=1">'.$c->integral_objects.'</a>',
			false, true
		);
		$xtpl->table_td(
			'<a href="?page=cluster&action=integrity_objects&list=1&integrity_check='.$c->id.'&status=2">'.$c->broken_objects.'</a>',
			false, true
		);
		$xtpl->table_td(
			'<a href="?page=cluster&action=integrity_facts&list=1&integrity_check='.$c->id.'">'.$c->checked_facts.'</a>',
			false, true
		);
		$xtpl->table_td(
			'<a href="?page=cluster&action=integrity_facts&list=1&integrity_check='.$c->id.'&status=1">'.$c->true_facts.'</a>',
			false, true
		);
		$xtpl->table_td(
			'<a href="?page=cluster&action=integrity_facts&list=1&integrity_check='.$c->id.'&status=0">'.$c->false_facts.'</a>',
			false, true
		);

		$xtpl->table_tr();
	}

	$xtpl->table_out();
}

function integrity_object_list() {
	global $xtpl, $api;

	$xtpl->sbar_add(_("Back"), $_SERVER['HTTP_REFERER']);
	$xtpl->sbar_add(_("Checks"), '?page=cluster&action=integrity_check');
	$xtpl->sbar_add(_("Objects"), '?page=cluster&action=integrity_objects');
	$xtpl->sbar_add(_("Facts"), '?page=cluster&action=integrity_facts');

	$xtpl->title2(_('Integrity objects'));

	$xtpl->table_title(_('Filters'));
	$xtpl->form_create('', 'get', 'check-filter', false);
		
	$xtpl->table_td(_("Limit").':'.
		'<input type="hidden" name="page" value="cluster">'.
		'<input type="hidden" name="action" value="integrity_objects">'.
		'<input type="hidden" name="list" value="1">'
	);
	$xtpl->form_add_input_pure('text', '40', 'limit', get_val('limit', '25'), '');
	$xtpl->table_tr();
	
	$xtpl->form_add_input(_("Offset").':', 'text', '40', 'offset', get_val('offset', '0'), '');

	$check_param = $api->integrity_object->list->getParameters('input')->integrity_check;
	api_param_to_form(
		'integrity_check',
		$check_param,
		$_GET['integrity_check']
	);

	$xtpl->form_add_select(
		_('Node').':',
		'node',
		resource_list_to_options($api->node->list(), 'id', 'name', true),
		$_GET['node']
	);

	$xtpl->form_add_input(_("Class name").':', 'text', '30', 'class_name', get_val('class_name', ''), '');
	$xtpl->form_add_input(_("Row ID").':', 'text', '30', 'row_id', get_val('row_id', ''), '');

	$statuses = $api->integrity_object->list->getParameters('input')
		->status
		->validators
		->include
		->values;
	$empty = array('' => _('---'));
		
	$xtpl->form_add_select(
	 	_('Status').':',
		'status',
		$empty + $statuses,
		$_GET['status']
	);
		
	$xtpl->form_out(_('Show'));

	if (!$_GET['list'])
		return;

	$xtpl->table_add_category(_('Check'));
	$xtpl->table_add_category(_('Node'));
	$xtpl->table_add_category(_('Class name'));
	$xtpl->table_add_category(_('ID'));
	$xtpl->table_add_category(_('Status'));
	$xtpl->table_add_category(_('Facts'));
	$xtpl->table_add_category(_('True facts'));
	$xtpl->table_add_category(_('False facts'));

	$params = array(
		'limit' => get_val('limit', 25),
		'offset' => get_val('offset', 0),
		'meta' => array('includes' => 'node')
	);

	if ($_GET['integrity_check'])
		$params['integrity_check'] = $_GET['integrity_check'];
	
	if ($_GET['node'])
		$params['node'] = $_GET['node'];
	
	if ($_GET['class_name'])
		$params['class_name'] = $_GET['class_name'];

	if ($_GET['row_id'])
		$params['row_id'] = $_GET['row_id'];
	
	if (isset($_GET['status']) && $_GET['status'] !== '')
		$params['status'] = $statuses[ $_GET['status'] ];

	$objects = $api->integrity_object->list($params);

	foreach ($objects as $o) {
		$xtpl->table_td(
			'<a href="?page=cluster&action=integrity_check&list=1&id='.$o->integrity_check_id.'">'.tolocaltz($o->integrity_check->created_at).'</a>'
		);
		$xtpl->table_td(
			'<a href="?page=cluster&action=integrity_objects&node='.$o->node_id.'">'.$o->node->name.'</a>'
		);
		$xtpl->table_td($o->class_name);
		$xtpl->table_td($o->id);
		$xtpl->table_td(boolean_icon($o->status === 'integral'));
		$xtpl->table_td(
			'<a href="?page=cluster&action=integrity_facts&list=1&integrity_object='.$o->id.'">'.$o->checked_facts.'</a>',
			false, true
		);
		$xtpl->table_td(
			'<a href="?page=cluster&action=integrity_facts&list=1&integrity_object='.$o->id.'&status=1">'.$o->true_facts.'</a>',
			false, true
		);
		$xtpl->table_td(
			'<a href="?page=cluster&action=integrity_facts&list=1&integrity_object='.$o->id.'&status=0">'.$o->false_facts.'</a>',
			false, true
		);

		$xtpl->table_tr();
	}

	$xtpl->table_out();
}

function integrity_fact_list() {
	global $xtpl, $api;

	$xtpl->sbar_add(_("Back"), $_SERVER['HTTP_REFERER']);
	$xtpl->sbar_add(_("Checks"), '?page=cluster&action=integrity_check');
	$xtpl->sbar_add(_("Objects"), '?page=cluster&action=integrity_objects');
	$xtpl->sbar_add(_("Facts"), '?page=cluster&action=integrity_facts');

	$xtpl->title2(_('Integrity facts'));

	$xtpl->table_title(_('Filters'));
	$xtpl->form_create('', 'get', 'check-filter', false);
		
	$xtpl->table_td(_("Limit").':'.
		'<input type="hidden" name="page" value="cluster">'.
		'<input type="hidden" name="action" value="integrity_facts">'.
		'<input type="hidden" name="list" value="1">'
	);
	$xtpl->form_add_input_pure('text', '40', 'limit', get_val('limit', '25'), '');
	$xtpl->table_tr();
	
	$xtpl->form_add_input(_("Offset").':', 'text', '40', 'offset', get_val('offset', '0'), '');

	$input = $api->integrity_fact->list->getParameters('input');
	api_param_to_form(
		'integrity_check',
		$input->integrity_check,
		$_GET['integrity_check']
	);
	
	$xtpl->form_add_select(
		_('Node').':',
		'node',
		resource_list_to_options($api->node->list(), 'id', 'name', true),
		$_GET['node']
	);

	$xtpl->form_add_input(_("Class name").':', 'text', '30', 'class_name', get_val('class_name', ''), '');
	$xtpl->form_add_input(_('Object ID').':', 'text', '30', 'integrity_object', $_GET['integrity_object']);

	$statuses = $input->status->validators->include->values;
	$empty = array('' => _('---'));
		
	$xtpl->form_add_select(
	 	_('Status').':',
		'status',
		$empty + $statuses,
		$_GET['status']
	);

	$severities = $input->severity->validators->include->values;
	$xtpl->form_add_select(
	 	_('Severity').':',
		'severity',
		$empty + $severities,
		$_GET['severity']
	);
		
	$xtpl->form_out(_('Show'));

	if (!$_GET['list'])
		return;

	$xtpl->table_add_category(_('Node'));
	$xtpl->table_add_category(_('Object'));
	$xtpl->table_add_category(_('Name'));
	$xtpl->table_add_category(_('Status'));
	$xtpl->table_add_category(_('Severity'));

	$params = array(
		'limit' => get_val('limit', 25),
		'offset' => get_val('offset', 0),
		'meta' => array('includes' => 'integrity_object__node')
	);

	if ($_GET['integrity_check'])
		$params['integrity_check'] = $_GET['integrity_check'];
	
	if ($_GET['node'])
		$params['node'] = $_GET['node'];
	
	if ($_GET['class_name'])
		$params['class_name'] = $_GET['class_name'];

	if ($_GET['integrity_object'])
		$params['integrity_object'] = $_GET['integrity_object'];

	if (isset($_GET['status']) && $_GET['status'] !== '')
		$params['status'] = $statuses[ $_GET['status'] ];
	
	if (isset($_GET['severity']) && $_GET['severity'] !== '')
		$params['severity'] = $severities[ $_GET['severity'] ];

	$facts = $api->integrity_fact->list($params);

	foreach ($facts as $f) {
		$xtpl->table_td(
			'<a href="?page=cluster&action=integrity_facts&node='.$f->integrity_object->node_id.'">'.$f->integrity_object->node->name.'</a>'
		);
		$xtpl->table_td(
			'<a href="?page=cluster&action=integrity_objects&list=1&integrity_check='.$f->integrity_object->integrity_check_id.'&class_name='.$f->integrity_object->class_name.'&row_id='.$f->integrity_object->row_id.'">'.($f->integrity_object->class_name.' #'.$f->integrity_object->row_id).'</a>'
		);
		$xtpl->table_td($f->name);
		$xtpl->table_td(boolean_icon($f->status === 'true'));
		$xtpl->table_td($f->severity);

		$xtpl->table_tr();

		$xtpl->table_td(
			'<strong>'._('Expected value').":</strong>\n<br>".
			'<pre>'.htmlspecialchars($f->expected_value)."</pre>\n".
			'<strong>'._('Actual value').":</strong>\n<br>".
			'<pre>'.htmlspecialchars($f->actual_value)."</pre>\n".
			'<strong>'._('Message').":</strong>\n<br>".
			'<pre>'.$f->message."</pre>\n",
			false, false, '4'
		);
		$xtpl->table_tr();
	}

	$xtpl->table_out();
}
