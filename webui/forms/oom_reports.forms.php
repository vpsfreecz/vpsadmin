<?php

function oom_reports_list()
{
    global $xtpl, $api;

    $pagination = new \Pagination\System(null, $api->oom_report->list);

    $xtpl->title(_('Out-of-memory Reports'));

    $xtpl->table_title(_('Filters'));
    $xtpl->form_create('', 'get', 'user-session-filter', false);

    $xtpl->form_set_hidden_fields([
        'page' => 'oom_reports',
        'list' => '1',
    ]);

    $input = $api->oom_report->list->getParameters('input');

    $xtpl->form_add_input(_('Limit') . ':', 'text', '40', 'limit', get_val('limit', '25'), '');
    $xtpl->form_add_input(_("From ID") . ':', 'text', '40', 'from_id', get_val('from_id'), '');

    if (isAdmin()) {
        $xtpl->form_add_input(_("User") . ':', 'text', '40', 'user', get_val('user', ''), '');
    }

    if (isAdmin()) {
        $xtpl->form_add_input(_("VPS") . ':', 'text', '40', 'vps', get_val('vps', ''), '');
    } else {
        api_param_to_form('vps', $input->vps, get_val('vps'));
    }

    api_param_to_form('node', $input->node, get_val('node'), function ($node) {
        return $node->domain_name;
    });
    api_param_to_form('location', $input->location, get_val('location'));
    api_param_to_form('environment', $input->environment, get_val('environment'));
    $xtpl->form_add_input(_('Rule ID') . ':', 'text', '40', 'oom_report_rule', get_val('oom_report_rule'));
    api_param_to_form('since', $input->since, get_val('since'));
    api_param_to_form('until', $input->until, get_val('until'));

    $xtpl->form_out(_('Show'));

    if (!($_GET['list'] ?? false)) {
        return;
    }

    $params = [
        'limit' => api_get_uint('limit', 25),
    ];

    $fromId = api_get_uint('from_id');
    if ($fromId !== null && $fromId > 0) {
        $params['from_id'] = $fromId;
    }

    $userId = api_get_uint('user');
    if ($userId !== null) {
        $params['user'] = $userId;
    }

    $vpsId = api_get_uint('vps');
    if ($vpsId !== null) {
        $params['vps'] = $vpsId;
    }

    $nodeId = api_get_uint('node');
    if ($nodeId !== null && $nodeId > 0) {
        $params['node'] = $nodeId;
    }

    $locationId = api_get_uint('location');
    if ($locationId !== null && $locationId > 0) {
        $params['location'] = $locationId;
    }

    $environmentId = api_get_uint('environment');
    if ($environmentId !== null && $environmentId > 0) {
        $params['environment'] = $environmentId;
    }

    $ruleId = api_get_uint('oom_report_rule');
    if ($ruleId !== null) {
        $params['oom_report_rule'] = $ruleId;
    }

    $since = api_get('since');
    if ($since !== null) {
        $params['since'] = $since;
    }

    $until = api_get('until');
    if ($until !== null) {
        $params['until'] = $until;
    }

    $params['meta'] = [
        'includes' => 'vps__node,vps__user',
    ];

    $reports = $api->oom_report->list($params);
    $pagination->setResourceList($reports);

    $xtpl->table_add_category(_("Time"));
    $xtpl->table_add_category(_("Node"));

    if (isAdmin()) {
        $xtpl->table_add_category(_("User"));
    }

    $xtpl->table_add_category(_("VPS"));
    $xtpl->table_add_category(_("Killed process"));
    $xtpl->table_add_category(_("Count"));
    $xtpl->table_add_category('');

    foreach ($reports as $r) {
        $xtpl->table_td(tolocaltz($r->created_at), false, false, 1, 1, 'top');

        $xtpl->table_td($r->vps->node->domain_name);

        if (isAdmin()) {
            $xtpl->table_td(user_link($r->vps->user));
        }

        $xtpl->table_td(vps_link($r->vps) . ' ' . h($r->vps->hostname));
        $xtpl->table_td($r->killed_name ? h($r->killed_name) : _('nothing killed'));
        $xtpl->table_td($r->count);

        $xtpl->table_td(
            '<a href="?page=oom_reports&action=show&id=' . $r->id . '&return_url=' . urlencode($_SERVER['REQUEST_URI']) . '"><img src="template/icons/vps_edit.png" alt="' . _('Details') . '" title="' . _('Details') . '"></a>'
        );

        $xtpl->table_tr();
    }

    $xtpl->table_pagination($pagination);
    $xtpl->table_out();
}

function oom_reports_show($id)
{
    global $xtpl, $api;

    $r = $api->oom_report->show($id, ['meta' => ['includes' => 'vps__node,oom_report_rule']]);

    if ($_GET['return_url']) {
        $xtpl->sbar_add(
            _('Back'),
            $_GET['return_url']
        );
    }

    $xtpl->sbar_add(_('Configure rules'), '?page=oom_reports&action=rule_list&vps=' . $r->vps->id);

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

    $xtpl->title(_('Out-of-memory Reports for VPS') . ' ' . $r->vps_id);

    $xtpl->table_td(_('Time') . ':');
    $xtpl->table_td(tolocaltz($r->created_at));
    $xtpl->table_tr();

    $xtpl->table_td(_('Node') . ':');
    $xtpl->table_td($r->vps->node->domain_name);
    $xtpl->table_tr();

    if (isAdmin()) {
        $xtpl->table_td(_('User') . ':');
        $xtpl->table_td(user_link($r->vps->user));
        $xtpl->table_tr();
    }

    $xtpl->table_td(_('VPS') . ':');
    $xtpl->table_td(vps_link($r->vps) . ' ' . h($r->vps->hostname));
    $xtpl->table_tr();

    $xtpl->table_td(_('Cgroup') . ':');
    $xtpl->table_td('<code>' . h($r->cgroup) . '</code>');
    $xtpl->table_tr();

    $xtpl->table_td(_('Rule') . ':');

    if ($r->oom_report_rule_id) {
        $xtpl->table_td($r->oom_report_rule->action . ' ' . '<code>' . h(truncateString($r->oom_report_rule->cgroup_pattern, 40)) . '</code>');
    } else {
        $xtpl->table_td('-');
    }

    $xtpl->table_tr();

    $xtpl->table_td(_('Invoked by') . ':');
    $xtpl->table_td(h($r->invoked_by_name) . ' (PID ' . ($invokedByVpsPid ? $invokedByVpsPid : _('unknown')) . ')');
    $xtpl->table_tr();

    $xtpl->table_td(_('Killed') . ':');

    if ($r->killed_name) {
        $xtpl->table_td(h($r->killed_name) . ' ' . ($r->invoked_by_pid == $r->killed_pid ? '(' . _('same process') . ')' : ''));
    } else {
        $xtpl->table_td(_('nothing killed'));
    }
    $xtpl->table_tr();

    $xtpl->table_td(_('Count') . ':');
    $xtpl->table_td($r->count);
    $xtpl->table_tr();

    $xtpl->table_out();

    $xtpl->table_title(_('Memory usage of cgroup') . ' <code>' . h($r->cgroup) . '</code>');
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

    $xtpl->table_title(_('Memory stats of cgroup') . ' <code>' . h($r->cgroup) . '</code>');
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
    $xtpl->table_add_category(_('anon'));
    $xtpl->table_add_category(_('file'));
    $xtpl->table_add_category(_('shmem'));
    $xtpl->table_add_category(_('pgtables'));
    $xtpl->table_add_category(_('swapents'));
    $xtpl->table_add_category(_('oom_score_adj'));

    $vm_sum = 0;
    $rss_sum = 0;
    $rss_anon_sum = 0;
    $rss_file_sum = 0;
    $rss_shmem_sum = 0;
    $pgtables_sum = 0;
    $swapents_sum = 0;

    foreach ($r->task->list() as $stat) {
        $vm_sum += $stat->total_vm;
        $rss_sum += $stat->rss;

        if ($stat->rss_anon) {
            $rss_anon_sum += $stat->rss_anon;
        }

        if ($stat->rss_file) {
            $rss_file_sum += $stat->rss_file;
        }

        if ($stat->rss_shmem) {
            $rss_shmem_sum += $stat->rss_shmem;
        }

        $pgtables_sum += $stat->pgtables_bytes;
        $swapents_sum += $stat->swapents;

        $xtpl->table_td($stat->vps_pid ? $stat->vps_pid : '-', false, true);
        $xtpl->table_td(h($stat->name));
        $xtpl->table_td($stat->vps_uid === null ? '-' : $stat->vps_uid, false, true);
        $xtpl->table_td($stat->tgid, false, true);
        $xtpl->table_td(data_size_to_humanreadable_kb($stat->total_vm * 4), false, true);
        $xtpl->table_td(data_size_to_humanreadable_kb($stat->rss * 4), false, true);
        $xtpl->table_td($stat->rss_anon === null ? '-' : data_size_to_humanreadable_kb($stat->rss_anon * 4), false, true);
        $xtpl->table_td($stat->rss_file === null ? '-' : data_size_to_humanreadable_kb($stat->rss_file * 4), false, true);
        $xtpl->table_td($stat->rss_shmem === null ? '-' : data_size_to_humanreadable_kb($stat->rss_shmem * 4), false, true);
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
    $xtpl->table_td(_('anon'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;');
    $xtpl->table_td(_('file'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;');
    $xtpl->table_td(_('shmem'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;');
    $xtpl->table_td(_('pgtables'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;');
    $xtpl->table_td(_('swapents'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;');
    $xtpl->table_td(_('oom_score_adj'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;');
    $xtpl->table_tr();

    $xtpl->table_td(_('Sum') . ':', false, false, '2');
    $xtpl->table_td('');
    $xtpl->table_td('');
    $xtpl->table_td(data_size_to_humanreadable_kb($vm_sum * 4), false, true);
    $xtpl->table_td(data_size_to_humanreadable_kb($rss_sum * 4), false, true);
    $xtpl->table_td(data_size_to_humanreadable_kb($rss_anon_sum * 4), false, true);
    $xtpl->table_td(data_size_to_humanreadable_kb($rss_file_sum * 4), false, true);
    $xtpl->table_td(data_size_to_humanreadable_kb($rss_shmem_sum * 4), false, true);
    $xtpl->table_td(data_size_to_humanreadable_b($pgtables_sum), false, true);
    $xtpl->table_td(data_size_to_humanreadable_kb($swapents_sum * 4), false, true);
    $xtpl->table_td('');
    $xtpl->table_tr();

    $xtpl->table_out();
}

function oom_reports_rules_list($vps_id)
{
    global $xtpl, $api;

    $vps = $api->vps->show($vps_id);

    $rules = $api->oom_report_rule->list(['vps' => $vps->id]);
    $input = $api->oom_report_rule->create->getParameters('input');

    $xtpl->table_title(_('OOM report rules for VPS ') . $vps->id . ' ' . h($vps->hostname));
    $xtpl->table_add_category(_('Action'));
    $xtpl->table_add_category(_('Cgroup path pattern'));
    $xtpl->table_add_category(_('Hit count'));
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');

    foreach ($rules as $rule) {
        $xtpl->table_td(h($rule->action));
        $xtpl->table_td('<code>' . h(truncateString($rule->cgroup_pattern, 60)) . '</code>');
        $xtpl->table_td('<a href="?page=oom_reports&action=list&oom_report_rule=' . $rule->id . '&list=1">' . $rule->hit_count, false, true);
        $xtpl->table_td('<a href="?page=oom_reports&action=rule_edit&vps=' . $vps->id . '&id=' . $rule->id . '"><img src="template/icons/vps_edit.png"  title="' . _("Edit") . '"/></a>');
        $xtpl->table_td('<a href="?page=oom_reports&action=rule_delete&vps=' . $vps->id . '&id=' . $rule->id . '&t=' . csrf_token() . '"><img src="template/icons/vps_delete.png" title="' . _("Delete") . '"/></a>');
        $xtpl->table_tr();
    }

    if ($rules->count() == 0) {
        $xtpl->table_td(
            _('No rules are configured, notifications are sent for all OOM reports.'),
            false,
            false,
            5
        );
        $xtpl->table_tr();
    } else {
        $xtpl->table_td('notify');
        $xtpl->table_td('<code>**/**</code> (implicit rule)');
        $xtpl->table_td($vps->implicit_oom_report_rule_hit_count, false, true);
        $xtpl->table_td('');
        $xtpl->table_td('');
        $xtpl->table_tr();

        $xtpl->table_td(
            '<ul>'
            . '<li>' . _('Rules are evaluated top to bottom') . '</li>'
            . '<li>' . _('Patterns are matched using Ruby\'s <a href="https://www.rubydoc.info/stdlib/core/File.fnmatch" target="_blank">File.fnmatch</a> method with <code>File::FNM_PATHNAME | File::FNM_EXTGLOB</code>') . '</li>'
            . '<li>' . _('Matches are done against full cgroup path without <code>/sys/fs/cgroup</code>, see') . ' <a href="?page=oom_reports&list=1">' . _('existing reports') . '</a>' . '</li>'
            . '<li>' . _('The first matching rule determines the action') . '</li>'
            . '<li>' . _('Out-of-memory situations are considered a configuration error and can result in VPS being restarted or stopped') . '</li>'
            . '</ul>',
            false,
            false,
            5
        );
        $xtpl->table_tr();
    }

    $xtpl->table_out();

    $xtpl->table_title(_('Add rule'));
    $xtpl->form_create('?page=oom_reports&action=rule_new&vps=' . $vps->id, 'post');

    api_param_to_form('action', $input->action);
    api_param_to_form('cgroup_pattern', $input->cgroup_pattern);
    $xtpl->form_out(_('Add'));

    $xtpl->sbar_add(_('Back to VPS details'), '?page=adminvps&action=info&veid=' . $vps->id);
}

function oom_reports_rules_edit($vps_id, $rule_id)
{
    global $xtpl, $api;

    $vps = $api->vps->show($vps_id);
    $rule = $api->oom_report_rule->show($rule_id);
    $input = $api->oom_report_rule->create->getParameters('input');

    $xtpl->table_title(_('Update OOM report rule'));
    $xtpl->form_create('?page=oom_reports&action=rule_edit&vps=' . $vps->id . '&id=' . $rule->id, 'post');

    $xtpl->table_td(_('VPS') . ':');
    $xtpl->table_td(vps_link($vps));
    $xtpl->table_tr();

    api_param_to_form('action', $input->action, $rule->action);
    api_param_to_form('cgroup_pattern', $input->cgroup_pattern, $rule->cgroup_pattern);

    $xtpl->form_out(_('Save'));

    $xtpl->sbar_add(_('Back to rule list'), '?page=oom_reports&action=rule_list&vps=' . $vps->id);
}
