<?php

function maintenance_to_entities () {
	if ($_SERVER['REQUEST_METHOD'] === 'POST')
		return $_POST;

	$ret = array(
		'cluster_wide' => false,
		'environments' => array(),
		'locations' => array(),
		'nodes' => array(),
	);

	switch ($_GET['type']) {
	case 'cluster':
		$ret['cluster_wide'] = true;
		break;

	case 'environment':
	case 'location':
	case 'node':
		$ret[$_GET['type'].'s'][] = $_GET['obj_id'];
		break;

	default:
	}

	return $ret;
}

function outage_entities_to_array ($outage) {
	$ret = array(
		'cluster' => false,
		'environments' => array(),
		'locations' => array(),
		'nodes' => array(),
	);
	$extra = array();

	foreach ($outage->entity->list() as $ent) {
		switch ($ent->name) {
		case 'Cluster':
			$ret['cluster'] = true;
			break;

		case 'Environment':
			$ret['environments'][] = $ent->entity_id;
			break;

		case 'Location':
			$ret['locations'][] = $ent->entity_id;
			break;

		case 'Node':
			$ret['nodes'][] = $ent->entity_id;
			break;

		default:
			$extra[] = $ent->name;
		}
	}

	$ret['additional'] = implode(',', $extra);

	return $ret;
}

function outage_report_form () {
	global $xtpl, $api;

	$input = $api->outage->create->getParameters('input');

	$xtpl->table_title(_('Outage Report'));

	$xtpl->form_create('?page=outage&action=report', 'post');

	$xtpl->form_add_input(_('Date and time').':', 'text', '30', 'begins_at', date('Y-m-d H:i'));
	$xtpl->form_add_number(_('Duration').':', 'duration', post_val('duration'), 0, 999999, 1, 'minutes');
	$xtpl->form_add_checkbox(_('Planned').':', 'planned', '1', post_val('planned'));
	api_param_to_form('type', $input->type);

	$entities = maintenance_to_entities();

	$xtpl->form_add_checkbox(
		_('Cluster-wide').':', 'cluster_wide', '1', $entities['cluster_wide']
	);
	$xtpl->form_add_select(
		_('Environments').':', 'environments[]',
		resource_list_to_options($api->environment->list(), 'id', 'label', false),
		$entities['environments'], '', true, 5
	);
	$xtpl->form_add_select(
		_('Locations').':', 'locations[]',
		resource_list_to_options($api->location->list(), 'id', 'label', false),
		$entities['locations'], '', true, 5
	);
	$xtpl->form_add_select(
		_('Nodes').':', 'nodes[]',
		resource_list_to_options($api->node->list(), 'id', 'domain_name', false),
		$entities['nodes'], '', true, 20
	);
	$xtpl->form_add_input(
		_('Additional systems').':', 'text', '70', 'entities', post_val('entities'),
		_('Comma separated list of other affected systems')
	);

	foreach ($api->language->list() as $lang) {
		$xtpl->form_add_input(
			$lang->label.' '._('summary').':', 'text', '70', $lang->code.'_summary',
			post_val($lang->code.'_summary')
		);
		$xtpl->form_add_textarea(
			$lang->label.' '._('description').':', 70, 8, $lang->code.'_description',
			post_val($lang->code.'_description')
		);
	}

	$xtpl->form_add_select(
		_('Handled by').':', 'handlers[]',
		resource_list_to_options($api->user->list(array('admin' => true)), 'id', 'full_name', false),
		post_val('handlers'), '', true, 10
	);

	$xtpl->form_out(_('Continue'));
}

function outage_edit_form ($id) {
	global $xtpl, $api;

	$outage = $api->outage->show($id);

	$xtpl->sbar_add(_('Back'), '?page=outage&action=show&id='.$outage->id);

	$xtpl->title(_('Outage').' #'.$outage->id);
	$xtpl->table_title(_('Edit affected entities and handlers'));
	$xtpl->form_create('?page=outage&action=edit&id='.$outage->id, 'post');

	$ents = outage_entities_to_array($outage);

	$xtpl->form_add_checkbox(
		_('Cluster-wide').':', 'cluster_wide', '1',
		post_val('cluster_wide', $ents['cluster'])
	);
	$xtpl->form_add_select(
		_('Environments').':', 'environments[]',
		resource_list_to_options($api->environment->list(), 'id', 'label', false),
		post_val('environments', $ents['environments']), '', true, 5
	);
	$xtpl->form_add_select(
		_('Locations').':', 'locations[]',
		resource_list_to_options($api->location->list(), 'id', 'label', false),
		post_val('locations', $ents['locations']), '', true, 5
	);
	$xtpl->form_add_select(
		_('Nodes').':', 'nodes[]',
		resource_list_to_options($api->node->list(), 'id', 'domain_name', false),
		post_val('nodes', $ents['nodes']), '', true, 20
	);
	$xtpl->form_add_input(
		_('Additional systems').':', 'text', '70', 'entities',
		post_val('entities', $ents['additional']),
		_('Comma separated list of other affected systems')
	);

	$xtpl->form_add_select(
		_('Handled by').':', 'handlers[]',
		resource_list_to_options($api->user->list(array('admin' => true)), 'id', 'full_name', false),
		post_val('handlers', array_map(
			function ($h) { return $h->user_id; },
			$outage->handler->list()->asArray()
		)), '', true, 10
	);

	$xtpl->form_out(_('Save'));
}

function outage_update_form ($id) {
	global $xtpl, $api;

	$input = $api->outage->create->getParameters('input');
	$outage = $api->outage->show($id);

	$xtpl->sbar_add(_('Back'), '?page=outage&action=show&id='.$outage->id);

	$xtpl->title(_('Outage').' #'.$id);
	$xtpl->table_title(_('Post update'));
	$xtpl->form_create('?page=outage&action=update&id='.$outage->id, 'post');

	$xtpl->form_add_input(
		_('Date and time').':', 'text', '30', 'begins_at',
		tolocaltz($outage->begins_at, 'Y-m-d H:i')
	);
	$xtpl->form_add_input(
		_('Finished at').':', 'text', '30', 'finished_at',
		$outage->finished_at ? tolocaltz($outage->finished_at, 'Y-m-d H:i') : ''
	);
	$xtpl->form_add_number(
		_('Duration').':', 'duration', post_val('duration', $outage->duration),
		0, 999999, 1, 'minutes'
	);
	api_param_to_form('type', $input->type, $outage->type);

	foreach ($api->language->list() as $lang) {
		$xtpl->form_add_input(
			$lang->label.' '._('summary').':', 'text', '70', $lang->code.'_summary',
			post_val($lang->code.'_summary')
		);
		$xtpl->form_add_textarea(
			$lang->label.' '._('description').':', 70, 8, $lang->code.'_description',
			post_val($lang->code.'_description')
		);
	}

	$xtpl->form_add_checkbox(
		_('Send mails').':', 'send_mail', '1',
		($_POST['state'] && !$_POST['send_mail']) ? false : true
	);

	$xtpl->form_out(_('Post update'));
}

function outage_state_form ($id) {
	global $xtpl, $api;

	$outage = $api->outage->show($id);

	$xtpl->sbar_add(_('Back'), '?page=outage&action=show&id='.$outage->id);

	$xtpl->title(_('Outage').' #'.$id);

	$xtpl->table_title(_('Change state'));
	$xtpl->form_create('?page=outage&action=set_state&id='.$id, 'post');
	$xtpl->form_add_select(_('State').':', 'state', array(
		'announce' => _('Announce'),
		'cancel' => _('Cancel'),
		'close' => _('Close'),
	), post_val('state'));

	if ($outage->state != 'staged') {
		foreach ($api->language->list() as $lang) {
			$xtpl->form_add_input(
				$lang->label.' '._('summary').':', 'text', '70', $lang->code.'_summary',
				post_val($lang->code.'_summary')
			);
			$xtpl->form_add_textarea(
				$lang->label.' '._('description').':', 70, 8, $lang->code.'_description',
				post_val($lang->code.'_description')
			);
		}
	}

	$xtpl->form_add_checkbox(
		_('Send mails').':', 'send_mail', '1',
		($_POST['state'] && !$_POST['send_mail']) ? false : true
	);

	$xtpl->form_out(_('Change'));
}

function outage_details ($id) {
	global $xtpl, $api;

	if ($_SESSION['is_admin']) {
		$xtpl->sbar_add(_('Edit'), '?page=outage&action=edit&id='.$id);
		$xtpl->sbar_add(_('Change state'), '?page=outage&action=set_state&id='.$id);
		$xtpl->sbar_add(_('Post update'), '?page=outage&action=update&id='.$id);
		$xtpl->sbar_add(_('Affected users'), '?page=outage&action=users&id='.$id);
	}

	$xtpl->sbar_add(_('Affected VPS'), '?page=outage&action=vps&id='.$id);

	$outage = $api->outage->show($id);
	$langs = $api->language->list();

	$xtpl->title(_('Outage').' #'.$id);

	if ($_SESSION['logged_in']) {
		$xtpl->table_title(_('Status'));

		if ($_SESSION['is_admin']) {
			if ($outage->state == 'staged') {
				$xtpl->table_td(_('Affected VPSes have not been checked yet.'));
				$xtpl->table_tr();

			} else {
				$xtpl->table_td(_('Affected users').':');
				$xtpl->table_td(
					'<a href="?page=outage&action=users&id='.$outage->id.'">'.
					$outage->affected_user_count.
					'</a>'
				);
				$xtpl->table_tr();

				$xtpl->table_td(_('Directly affected VPS').':');
				$xtpl->table_td(
					'<a href="?page=outage&action=vps&id='.$outage->id.'&direct=yes">'.
					$outage->affected_direct_vps_count.
					'</a>'
				);
				$xtpl->table_tr();

				$xtpl->table_td(_('Indirectly affected VPS').':');
				$xtpl->table_td(
					'<a href="?page=outage&action=vps&id='.$outage->id.'&direct=no">'.
					$outage->affected_indirect_vps_count.
					'</a>'
				);
				$xtpl->table_tr();
			}

		} else {
			$affected_vpses = $api->vps_outage->list(array(
				'outage' => $outage->id,
				'meta' => array(
					'includes' => 'vps',
				),
			));

			if ($affected_vpses->count()) {
				$s = '';
				if ($outage->state == 'closed'
					|| (strtotime($outage->begins_at) + $outage->duration) < time()
					|| ($outage->finished_at && strtotime($outage->finished_at) < time())
				) {
					$s .= '<strong>';
					$s .= _('This outage has been resolved and all systems should have recovered.');
					$s .= '</strong><br>';
				}

				$xtpl->table_td(_('Affected VPS').':');
				$s .= implode("\n<br>\n", array_map(
					function ($outage_vps) {
						$v = $outage_vps->vps;
						return vps_link($v).' - '.h($v->hostname).($outage_vps->direct ? '' : ' (indirectly)');

					}, $affected_vpses->asArray()
				));

				$xtpl->table_td($s);
				$xtpl->table_tr();

			} else {
				$xtpl->table_td('<strong>'._('You are not affected by this outage.').'</strong>');
				$xtpl->table_tr();
			}
		}

		$xtpl->table_out();
	}

	$xtpl->table_title(_('Information'));
	$xtpl->table_td(_('Begins at').':');
	$xtpl->table_td(tolocaltz($outage->begins_at, "Y-m-d H:i:s T"));
	$xtpl->table_tr();

	$xtpl->table_td(_('Duration').':');
	$xtpl->table_td($outage->duration.' '._('minutes'));
	$xtpl->table_tr();

	$xtpl->table_td(_('Planned').':');
	$xtpl->table_td(boolean_icon($outage->planned));
	$xtpl->table_tr();

	$xtpl->table_td(_('State').':');
	$xtpl->table_td($outage->state);
	$xtpl->table_tr();

	$xtpl->table_td(_('Type').':');
	$xtpl->table_td($outage->type);
	$xtpl->table_tr();

	$xtpl->table_td(_('Affected systems').':');
	$xtpl->table_td(implode("\n<br>\n", array_map(
		function ($ent) { return h($ent->label); },
		$outage->entity->list()->asArray()
	)));
	$xtpl->table_tr();

	$summary = array();

	foreach ($langs as $lang) {
		$name = $lang->code.'_summary';

		if (!$outage->{$name})
			continue;

		$summary[] = '<strong>'.h($lang->label).'</strong>: '.h($outage->{$name});
	}

	$xtpl->table_td(_('Summary').':');
	$xtpl->table_td(implode("\n<br><br>\n", $summary));
	$xtpl->table_tr();

	$desc = array();

	foreach ($langs as $lang) {
		$name = $lang->code.'_description';

		if (!$outage->{$name})
			continue;

		$desc[] = '<strong>'.h($lang->label).'</strong>: '.nl2br(h($outage->{$name}));
	}

	$xtpl->table_td(_('Description').':');
	$xtpl->table_td(implode("\n<br><br>\n", $desc));
	$xtpl->table_tr();

	$xtpl->table_td(_('Handled by').':');
	$xtpl->table_td(implode(', ', array_map(
		function ($h) { return h($h->full_name); },
		$outage->handler->list()->asArray()
	)));
	$xtpl->table_tr();
	$xtpl->table_out();

	if ($_SESSION['is_admin'] && $outage->state == 'staged') {
		$xtpl->table_title(_('Change state'));
		$xtpl->form_create('?page=outage&action=set_state&id='.$id, 'post');
		$xtpl->form_add_select(_('State').':', 'state', array(
			'announce' => _('Announce'),
			'cancel' => _('Cancel'),
			'close' => _('Close'),
		), post_val('state'));

		$xtpl->form_add_checkbox(
			_('Send mails').':', 'send_mail', '1',
			($_POST['state'] && !$_POST['send_mail']) ? false : true
		);

		$xtpl->form_out(_('Change'));
	}

	$xtpl->table_title(_('Updates'));
	$xtpl->table_add_category(_('Date'));
	$xtpl->table_add_category(_('Summary'));
	$xtpl->table_add_category(_('Reported by'));

	foreach ($api->outage_update->list(array('outage' => $outage->id)) as $update) {
		$xtpl->table_td(tolocaltz($update->created_at, "Y-m-d H:i:s T"));

		$summary = array();

		foreach ($langs as $lang) {
			$name = $lang->code.'_summary';

			if (!$update->{$name})
				continue;

			$summary[] = '<strong>'.h($lang->label).'</strong>: '.h($update->{$name});
		}

		$xtpl->table_td(implode("\n<br>\n", $summary));
		$xtpl->table_td($update->reporter_name);

		$changes = array();
		$check = array('begins_at', 'finished_at', 'state', 'type', 'duration');

		foreach ($check as $p) {
			if ($update->{$p}) {
				switch ($p) {
				case 'begins_at':
					$changes[] = _("Begins at:").' '.tolocaltz($update->begins_at, "Y-m-d H:i T");
					break;

				case 'finished_at':
					$changes[] = _("Finished at:").' '.tolocaltz($update->finished_at, "Y-m-d H:i T");
					break;

				case 'state':
					$changes[] = _("State:").' '.$update->state;
					break;

				case 'type':
					$changes[] = _("Outage type:").' '.$update->type;
					break;

				case 'duration':
					$changes[] = _("Duration:").' '.$update->duration.' '._('minutes');
					break;
				}
			}
		}

		$desc = array();

		foreach ($langs as $lang) {
			$name = $lang->code.'_description';

			if (!$update->{$name})
				continue;

			$desc[] = '<strong>'.h($lang->label).'</strong>: '.nl2br(h($update->{$name}));
		}

		$str = implode("\n<br><br>\n", array_filter(array(
			implode("\n<br>\n", $changes),
			implode("\n<br><br>\n", $desc),
		)));

		$xtpl->table_tr();

		if ($str) {
			$xtpl->table_td($str, false, false, 3);
			$xtpl->table_tr();
		}
	}

	$xtpl->table_out();
}

function outage_list () {
	global $xtpl, $api;

	$xtpl->title(_('Outage list'));
	$xtpl->table_title(_('Filters'));
	$xtpl->form_create('', 'get', 'outage-list', false);

	$xtpl->table_td(_("Limit").':'.
		'<input type="hidden" name="page" value="outage">'.
		'<input type="hidden" name="action" value="list">'
	);
	$xtpl->form_add_input_pure('text', '40', 'limit', get_val('limit', '25'), '');
	$xtpl->table_tr();

	$input = $api->outage->list->getParameters('input');

	$xtpl->form_add_select(_('Planned').':', 'planned', array(
		'' => '---',
		'yes' => _('Planned'),
		'no' => _('Unplanned'),
	), get_val('planned'));
	api_param_to_form('state', $input->state, null, null, true);
	api_param_to_form('type', $input->type, null, null, true);

	if ($_SESSION['logged_in']) {
		$xtpl->form_add_select(_('Affects me?'), 'affected', array(
			'' => '---',
			'yes' => _('Yes'),
			'no' => _('No'),
		), get_val('affected'));
	}

	if ($_SESSION['is_admin']) {
		$xtpl->form_add_input(_('User ID').':', 'text', '30', 'user', get_val('user'), '');
		$xtpl->form_add_input(_('Handled by').':', 'text', '30', 'handled_by', get_val('handled_by'), '');
	}

	if ($_SESSION['logged_in']) {
		$xtpl->form_add_input(_('VPS ID').':', 'text', '30', 'vps', get_val('vps'), '');
		$xtpl->form_add_select(
			_('Environment').':', 'environment',
			resource_list_to_options($api->environment->list()),
			get_val('environment')
		);
		$xtpl->form_add_select(
			_('Location').':', 'location',
			resource_list_to_options($api->location->list()),
			get_val('location')
		);
		$xtpl->form_add_select(
			_('Node').':', 'node',
			resource_list_to_options($api->node->list(), 'id', 'domain_name'),
			get_val('node')
		);
	}

	if ($_SESSION['is_admin']) {
		$xtpl->form_add_input(
			_('Entity name').':', 'text', '30', 'entity_name', get_val('entity_name'), ''
		);
		$xtpl->form_add_input(
			_('Entity ID').':', 'text', '30', 'entity_id', get_val('entity_id'), ''
		);
	}

	api_param_to_form('order', $input->order, $_GET['order']);

	$xtpl->form_out(_('Show'));

	$xtpl->table_add_category(_('Date'));
	$xtpl->table_add_category(_('Duration'));
	$xtpl->table_add_category(_('Planned'));
	$xtpl->table_add_category(_('State'));
	$xtpl->table_add_category(_('Systems'));
	$xtpl->table_add_category(_('Type'));
	$xtpl->table_add_category(_('Reason'));

	if ($_SESSION['is_admin']) {
		$xtpl->table_add_category(_('Users'));
		$xtpl->table_add_category(_('VPS'));

	} elseif ($_SESSION['logged_in'])
		$xtpl->table_add_category(_('Affects me?'));

	$xtpl->table_add_category('');

	$params = array(
		'limit' => get_val('limit', 25),
	);

	foreach (array('planned', 'affected') as $v) {
		if ($_GET[$v] === 'yes')
			$params[$v] = true;

		elseif ($_GET[$v] === 'no')
			$params[$v] = false;
	}

	$filters = array(
		'state', 'type', 'user', 'handled_by', 'vps', 'order',
		'environment', 'location', 'node', 'entity_name', 'entity_id'
	);

	foreach ($filters as $v) {
		if ($_GET[$v])
			$params[$v] = $_GET[$v];
	}

	$outages = $api->outage->list($params);

	foreach ($outages as $outage) {
		$xtpl->table_td(tolocaltz($outage->begins_at, 'Y-m-d H:i'));
		$xtpl->table_td($outage->duration, false, true);
		$xtpl->table_td(boolean_icon($outage->planned));
		$xtpl->table_td($outage->state);
		$xtpl->table_td(implode(', ', array_map(
			function ($v) { return h($v->label); },
			$outage->entity->list()->asArray()
		)));
		$xtpl->table_td($outage->type);
		$xtpl->table_td(h($outage->en_summary));

		if ($_SESSION['is_admin']) {
			if ($outage->state == 'staged') {
				$xtpl->table_td('-', false, true);
				$xtpl->table_td('-', false, true);

			} else {
				$xtpl->table_td(
					'<a href="?page=outage&action=users&id='.$outage->id.'">'.
					$outage->affected_user_count.
					'</a>',
					false, true
				);
				$xtpl->table_td(
					'<a href="?page=outage&action=vps&id='.$outage->id.'">'.
					$outage->affected_direct_vps_count.
					'</a>',
					false, true
				);
			}

		} elseif ($_SESSION['logged_in'])
			$xtpl->table_td(boolean_icon($outage->affected));

		$xtpl->table_td('<a href="?page=outage&action=show&id='.$outage->id.'"><img src="template/icons/m_edit.png"  title="'. _("Details") .'" /></a>');

		$xtpl->table_tr();
	}

	$xtpl->table_out();
}

function outage_affected_users ($id) {
	global $xtpl, $api;

	$outage = $api->outage->show($id);

	$xtpl->sbar_add(_('Back'), '?page=outage&action=show&id='.$outage->id);

	$xtpl->title(_('Outage').' #'.$outage->id);
	$xtpl->table_title(_('Affected users'));

	$users = $api->user_outage->list(array(
		'outage' => $outage->id,
		'meta' => array('includes' => 'user'),
	));

	$xtpl->table_add_category(_('Login'));
	$xtpl->table_add_category(_('Name'));
	$xtpl->table_add_category(_('VPS count'));

	foreach ($users as $out) {
		$xtpl->table_td(user_link($out->user));
		$xtpl->table_td(h($out->user->full_name));
		$xtpl->table_td(
			'<a href="?page=outage&action=vps&id='.$outage->id.'&user='.$out->user_id.'">'.
			$out->vps_count.
			'</a>',
			false, true
		);
		$xtpl->table_tr();
	}

	$xtpl->table_out();
}

function outage_affected_vps ($id) {
	global $xtpl, $api;

	$outage = $api->outage->show($id);

	$xtpl->sbar_add(_('Back'), '?page=outage&action=show&id='.$outage->id);

	$xtpl->title(_('Outage').' #'.$outage->id);

	if ($_SESSION['is_admin']) {
		$xtpl->table_title(_('Filters'));
		$xtpl->form_create('', 'get', 'outage-list', false);

		$xtpl->table_td(_("User ID").':'.
			'<input type="hidden" name="page" value="outage">'.
			'<input type="hidden" name="action" value="vps">'.
			'<input type="hidden" name="id" value="'.$outage->id.'">'
		);
		$xtpl->form_add_input_pure('text', '30', 'user', get_val('user'), '');
		$xtpl->table_tr();

		$xtpl->form_add_select(
			_('Environment').':', 'environment',
			resource_list_to_options($api->environment->list()),
			get_val('environment')
		);
		$xtpl->form_add_select(
			_('Location').':', 'location',
			resource_list_to_options($api->location->list()),
			get_val('location')
		);
		$xtpl->form_add_select(
			_('Node').':', 'node',
			resource_list_to_options($api->node->list(), 'id', 'domain_name'),
			get_val('node')
		);
		$xtpl->form_add_select(
			_('Direct').':', 'direct',
			array('' => '---', 'yes' => _('Yes'), 'no' => _('No')),
			get_val('direct')
		);

		$xtpl->form_out(_('Show'));
	}

	$xtpl->table_title(_('Affected VPS'));

	$params = array(
		'outage' => $outage->id,
		'meta' => array('includes' => 'vps,user,environment,location,node'),
	);

	foreach (array('user', 'environment', 'location', 'node') as $v) {
		if ($_GET[$v])
			$params[$v] = $_GET[$v];
	}

	if ($_GET['direct']) {
		$params['direct'] = $_GET['direct'] === 'yes';
	}

	$vpses = $api->vps_outage->list($params);

	$xtpl->table_add_category(_('VPS ID'));
	$xtpl->table_add_category(_('Hostname'));
	$xtpl->table_add_category(_('User'));
	$xtpl->table_add_category(_('Node'));
	$xtpl->table_add_category(_('Environment'));
	$xtpl->table_add_category(_('Location'));

	foreach ($vpses as $out) {
		$xtpl->table_td(vps_link($out->vps));
		$xtpl->table_td(h($out->vps->hostname));
		$xtpl->table_td(user_link($out->vps->user));
		$xtpl->table_td($out->node->domain_name);
		$xtpl->table_td($out->environment->label);
		$xtpl->table_td($out->location->label);
		$xtpl->table_tr();
	}

	$xtpl->table_out();
}
