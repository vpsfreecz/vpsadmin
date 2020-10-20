<?php

function oom_reports_list() {
	global $xtpl, $api;

	$xtpl->title(_('Out-of-memory Reports'));

	$xtpl->table_title(_('Filters'));
	$xtpl->form_create('', 'get', 'user-session-filter', false);

	$xtpl->form_set_hidden_fields([
		'page' => 'oom_reports',
		'list' => '1',
	]);

	$input = $api->oom_report->list->getParameters('input');

	$xtpl->form_add_input(_('Limit').':', 'text', '40', 'limit', get_val('limit', '25'), '');
	$xtpl->form_add_input(_("Offset").':', 'text', '40', 'offset', get_val('offset', '0'), '');

	if (isAdmin())
		$xtpl->form_add_input(_("User").':', 'text', '40', 'user', get_val('user', ''), '');

	if (isAdmin())
		$xtpl->form_add_input(_("VPS").':', 'text', '40', 'vps', get_val('vps', ''), '');
	else
		api_param_to_form('vps', $input->vps, $_GET['vps']);

	api_param_to_form('node', $input->node, $_GET['node']);
	api_param_to_form('location', $input->location, $_GET['location']);
	api_param_to_form('environment', $input->environment, $_GET['environment']);
	api_param_to_form('since', $input->since, $_GET['since']);
	api_param_to_form('until', $input->until, $_GET['until']);

	$xtpl->form_out(_('Show'));

	if (!$_GET['list'])
		return;

	$params = [
		'limit' => get_val('limit', 25),
		'offset' => get_val('offset', 0),
	];

	$conds = ['user', 'vps', 'node', 'location', 'environment', 'since', 'until'];

	foreach ($conds as $c) {
		if ($_GET[$c])
			$params[$c] = $_GET[$c];
	}

	$params['meta'] = array(
		'includes' => 'vps__node,vps__user',
		'count' => true,
	);

	$reports = $api->oom_report->list($params);

	$xtpl->table_add_category(_("Time"));
	$xtpl->table_add_category(_("Node"));

	if (isAdmin())
		$xtpl->table_add_category(_("User"));

	$xtpl->table_add_category(_("VPS"));
	$xtpl->table_add_category(_("Killed process"));
	$xtpl->table_add_category('');

	foreach ($reports as $r) {
		$xtpl->table_td(tolocaltz($r->created_at), false, false, 1, 1, 'top');

		$xtpl->table_td($r->vps->node->domain_name);

		if (isAdmin())
			$xtpl->table_td(user_link($r->vps->user));

		$xtpl->table_td(vps_link($r->vps).' '.h($r->vps->hostname));
		$xtpl->table_td(h($r->killed_name));

		$xtpl->table_td(
			'<a href="?page=oom_reports&action=show&id='.$r->id.'&return_url='.urlencode($_SERVER['REQUEST_URI']).'"><img src="template/icons/vps_edit.png" alt="'._('Details').'" title="'._('Details').'"></a>'
		);

		$xtpl->table_tr();
	}

	$xtpl->table_out();

	$xtpl->table_td('Displayed reports:');
	$xtpl->table_td($reports->count());
	$xtpl->table_tr();
	$xtpl->table_td('Total reports:');
	$xtpl->table_td($reports->getTotalCount());
	$xtpl->table_tr();
	$xtpl->table_out();
}

function oom_reports_show($id) {
	global $xtpl, $api;

	$r = $api->oom_report->show($id, ['meta' => ['includes' => 'vps__node']]);

	if ($_GET['return_url']) {
		$xtpl->sbar_add(
			_('Back'),
			$_GET['return_url']
		);
	}

	$tasks = $r->task->list();
	$invokedByVpsPid = null;

	if ($r->killed_pid != $r->invoked_by_pid) {
		foreach ($tasks as $t) {
			if ($t->host_pid == $r->invoked_by_pid) {
				$invokedByVpsPid = $t->vps_pid;
				break;
			}
		}
	}

	$xtpl->title(_('Out-of-memory Reports for VPS').' '.$r->vps_id);

	$xtpl->table_td(_('Time').':');
	$xtpl->table_td(tolocaltz($r->created_at));
	$xtpl->table_tr();

	$xtpl->table_td(_('Node').':');
	$xtpl->table_td($r->vps->node->domain_name);
	$xtpl->table_tr();

	if (isAdmin()) {
		$xtpl->table_td(_('User').':');
		$xtpl->table_td(user_link($r->vps->user));
		$xtpl->table_tr();
	}

	$xtpl->table_td(_('VPS').':');
	$xtpl->table_td(vps_link($r->vps).' '.h($r->vps->hostname));
	$xtpl->table_tr();

	$xtpl->table_td(_('Invoked by').':');
	$xtpl->table_td(h($r->invoked_by_name).' (PID '.($invokedByVpsPid ? $invokedByVpsPid : _('unknown')).')');
	$xtpl->table_tr();

	$xtpl->table_td(_('Killed').':');
	$xtpl->table_td(h($r->killed_name).' '.($r->invoked_by_pid == $r->killed_pid ? '('._('same process').')' : ''));
	$xtpl->table_tr();

	$xtpl->table_out();

	$xtpl->table_title(_('Memory usage'));
	$xtpl->table_add_category(_('Type'));
	$xtpl->table_add_category(_('Usage'));
	$xtpl->table_add_category(_('Limit'));
	$xtpl->table_add_category(_('Fail count'));

	foreach ($r->usage->list() as $usage) {
		$xtpl->table_td($usage->memtype);
		$xtpl->table_td(data_size_to_humanreadable_kb($usage->usage), false, true);
		$xtpl->table_td(data_size_to_humanreadable_kb($usage->limit), false, true);
		$xtpl->table_td($usage->failcnt, false, true);
		$xtpl->table_tr();
	}

	$xtpl->table_out();

	$xtpl->table_title(_('Memory stats'));
	$xtpl->table_add_category(_('Parameter'));
	$xtpl->table_add_category(_('Value'));

	foreach ($r->stat->list() as $stat) {
		$xtpl->table_td($stat->parameter);
		$xtpl->table_td(data_size_to_humanreadable_b($stat->value), false, true);
		$xtpl->table_tr();
	}

	$xtpl->table_out();

	$xtpl->table_title(_('Tasks'));
	$xtpl->table_add_category(_('PID'));
	$xtpl->table_add_category(_('Name'));
	$xtpl->table_add_category(_('UID'));
	$xtpl->table_add_category(_('TGID'));
	$xtpl->table_add_category(_('VM'));
	$xtpl->table_add_category(_('RSS'));
	$xtpl->table_add_category(_('pgtables'));
	$xtpl->table_add_category(_('swapents'));
	$xtpl->table_add_category(_('oom_score_adj'));

	foreach ($r->task->list() as $stat) {
		$xtpl->table_td($stat->vps_pid ? $stat->vps_pid : '-', false, true);
		$xtpl->table_td(h($stat->name));
		$xtpl->table_td($stat->vps_uid === null ? '-' : $stat->vps_uid, false, true);
		$xtpl->table_td($stat->tgid, false, true);
		$xtpl->table_td(data_size_to_humanreadable_kb($stat->total_vm * 4), false, true);
		$xtpl->table_td(data_size_to_humanreadable_kb($stat->rss * 4), false, true);
		$xtpl->table_td(data_size_to_humanreadable_b($stat->pgtables_bytes), false, true);
		$xtpl->table_td(data_size_to_humanreadable_kb($stat->swapents * 4), false, true);
		$xtpl->table_td($stat->oom_score_adj, false, true);
		$xtpl->table_tr($stat->host_pid == $r->killed_pid ? '#FFCCCC' : false);
	}

	$xtpl->table_td(_('PID'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;');
	$xtpl->table_td(_('Name'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;');
	$xtpl->table_td(_('UID'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;');
	$xtpl->table_td(_('TGID'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;');
	$xtpl->table_td(_('VM'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;');
	$xtpl->table_td(_('RSS'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;');
	$xtpl->table_td(_('pgtables'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;');
	$xtpl->table_td(_('swapents'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;');
	$xtpl->table_td(_('oom_score_adj'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;');
	$xtpl->table_tr();

	$xtpl->table_out();
}
