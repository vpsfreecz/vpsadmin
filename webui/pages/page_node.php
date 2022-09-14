<?php

if (isLoggedIn()) {
	$xtpl->sbar_add(_('Back to status'), '?page=');
	$xtpl->sbar_out(_('Node'));

	$node = $api->node->find(
		$_GET['id'],
		['meta' => ['includes' => 'location__environment']]
	);

	$xtpl->title(_('Node').' '.$node->domain_name);

	$xtpl->table_td(_('Location').':');
	$xtpl->table_td($node->location->label);
	$xtpl->table_tr();

	$xtpl->table_td(_('Environment').':');
	$xtpl->table_td($node->location->environment->label);
	$xtpl->table_tr();

	$xtpl->table_out();

	if ($node->hypervisor_type == 'vpsadminos') {
		$xtpl->table_title(_('Storage pools'));
		$xtpl->table_add_category(_('Name'));
		$xtpl->table_add_category(_('State'));
		$xtpl->table_add_category(_('Scan'));

		$pools = $api->pool->list([
			'node' => $node->id
		]);

		foreach ($pools as $pool) {
			$xtpl->table_td($pool->name);
			$xtpl->table_td($pool->state);
			$xtpl->table_td($pool->scan);

			if ($pool->state != 'online' || $pool->scan != 'none')
				$color = '#FFE27A';
			else
				$color = false;

			$xtpl->table_tr($color);
		}

		$xtpl->table_out();
	}

	$munin = new Munin($config);
	$munin->setGraphWidth(390);

	if ($munin->isEnabled()) {
		$xtpl->table_title(_('Graphs'));

		$xtpl->table_td($munin->linkHost(_('See all graphs in Munin'), $node->fqdn), false, false, '2');
		$xtpl->table_tr();

		$xtpl->table_td($munin->linkHostGraphPath($node->fqdn, 'cpu', 'day'));
		$xtpl->table_td($munin->linkHostGraphPath($node->fqdn, 'load', 'day'));
		$xtpl->table_tr();

		$xtpl->table_td($munin->linkHostGraphPath($node->fqdn, 'memory', 'day'));
		$xtpl->table_td($munin->linkHostGraphPath($node->fqdn, 'uptime', 'day'));
		$xtpl->table_tr();

		$xtpl->table_td($munin->linkHostGraphPath($node->fqdn, 'diskstats_utilization', 'day', true));
		$xtpl->table_td($munin->linkHostGraphPath($node->fqdn, 'diskstats_latency', 'day', true));
		$xtpl->table_tr();

		$xtpl->table_out();
	}


} else {
	$xtpl->perex(
		_("Access forbidden"),
		_("You have to log in to be able to access vpsadmin's functions")
	);
}
