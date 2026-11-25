<?php

function incident_notice_html($inc, $with_links = false)
{
    $attrs = $inc instanceof \HaveAPI\Client\ResourceInstance ? $inc->attributes() : (array) $inc;
    $kinds = ['warning' => _('Escalation warning decision'), 'stop_completed' => _('Confirmed escalation stop')];
    if (!isset($kinds[$attrs['notice_kind'] ?? ''])) {
        return '';
    }
    $states = [
        'pending' => _('Mail not yet queued'), 'queued' => _('Mail queued'),
        'sent' => _('Sent'),
        'failed' => _('Mail failed'), 'uncertain' => _('Mail outcome uncertain'),
        'suppressed' => _('Mail suppressed'),
    ];
    $text = h($kinds[$attrs['notice_kind']]) . '<br>' . h($states[$attrs['notice_mail_state'] ?? ''] ?? _('Unknown'));
    $key = $attrs['notice_policy_key'] ?? null;
    $label = $attrs['notice_policy_label'] ?? $key;
    if (is_string($label) && $label !== '') {
        $text .= '<br>' . h(_('Policy')) . ': ' . h($label);
        if ($with_links && is_string($key) && $key !== '') {
            $links = incident_policy_links(incident_policy_link_context($inc), $key);
            if ($links !== '') {
                $text .= '<br>' . $links;
            }
        }
    }
    if ($attrs['trigger_incident_report_id'] ?? null) {
        $text .= '<br><a href="?page=incidents&action=show&id=' . (int) $attrs['trigger_incident_report_id'] . '">'
            . h(_('Source incident')) . ' #' . (int) $attrs['trigger_incident_report_id'] . '</a>';
    }
    return $text;
}

function incident_policy_filter_form()
{
    global $api, $xtpl;
    $selected = api_get('policy_key');
    $selected = is_string($selected) ? $selected : '';
    try {
        if (!$api->incident_policy || !$api->incident_policy->index) {
            throw new RuntimeException();
        }
        $choices = ['' => _('All policies')];
        foreach ($api->incident_policy->index() as $policy) {
            // XTemplate escapes labels, but option values must be escaped here.
            $choices[h($policy->key)] = $policy->label;
        }
        if ($selected !== '' && !array_key_exists(h($selected), $choices)) {
            $choices[h($selected)] = $selected;
        }
        $xtpl->form_add_select(_('Policy') . ':', 'policy_key', $choices, h($selected));
        $xtpl->assign(
            'AJAX_SCRIPT',
            ($xtpl->vars['AJAX_SCRIPT'] ?? '') . <<<'HTML'
                <script type="text/javascript">
                $(document).on('change', 'form[name="incident-list"] select[name="policy_key"]', function() {
                    $(this).closest('form').find('[name="from_id"]').val('');
                });
                </script>
                HTML
        );
    } catch (\HaveAPI\Client\Exception\Base|RuntimeException $e) {
        // Keep a historical filter without replacing the form's routing fields.
        vps_incident_row(_('Policy'), h(_('Incident settings unavailable'))
            . '<input type="hidden" name="policy_key" value="' . h($selected) . '">');
    }
}

function incident_list()
{
    global $xtpl, $api;

    $pagination = new \Pagination\System(null, $api->incident_report->list);

    $xtpl->title(_('Incident reports'));
    $xtpl->table_title(_('Filters'));
    $xtpl->form_create('', 'get', 'incident-list', false);

    $xtpl->form_set_hidden_fields([
        'page' => 'incidents',
        'action' => 'list',
        'list' => '1',
    ]);

    $xtpl->form_add_input(_('Limit') . ':', 'text', '40', 'limit', get_val('limit', '25'), '');
    $xtpl->form_add_input(_('From ID') . ':', 'text', '40', 'from_id', get_val('from_id', ''), '');
    $xtpl->table_tr();

    $input = $api->incident_report->list->getParameters('input');

    if (isAdmin()) {
        $xtpl->form_add_input(_('User ID') . ':', 'text', '30', 'user', get_val('user'), '');
    }

    if (isAdmin()) {
        $xtpl->form_add_input(_('VPS ID') . ':', 'text', '30', 'vps', get_val('vps'), '');
    } else {
        api_param_to_form('vps', $input->vps, get_val('vps'));
    }

    if (isAdmin()) {
        $xtpl->form_add_input(_('Assignment ID') . ':', 'text', '30', 'ip_address_assignment', get_val('ip_address_assignment'), '');
    } else {
        api_param_to_form(
            'ip_address_assignment',
            $input->ip_address_assignment,
            $_GET['ip_address_assignment'],
            'ip_address_assignment_label'
        );
    }

    api_param_to_form('ip_addr', $input->ip_addr, get_val('ip_addr'));

    if (isAdmin()) {
        api_param_to_form('mailbox', $input->mailbox, get_val('mailbox'));
    }

    api_param_to_form('codename', $input->codename, get_val('codename'));
    if (isset($input->policy_key)) {
        incident_policy_filter_form();
    }

    $xtpl->form_out(_('Show'));

    if (!($_GET['list'] ?? false)) {
        return;
    }

    $params = [
        'limit' => api_get_uint('limit', 25),
        'meta' => ['includes' => 'user,vps,ip_address_assignment'],
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
    if ($vpsId !== null && $vpsId > 0) {
        $params['vps'] = $vpsId;
    }

    $assignmentId = api_get_uint('ip_address_assignment');
    if ($assignmentId !== null && $assignmentId > 0) {
        $params['ip_address_assignment'] = $assignmentId;
    }

    $ipAddr = api_get('ip_addr');
    if ($ipAddr !== null) {
        $params['ip_addr'] = $ipAddr;
    }

    $mailboxId = api_get_uint('mailbox');
    if ($mailboxId !== null && $mailboxId > 0) {
        $params['mailbox'] = $mailboxId;
    }

    $codename = api_get('codename');
    if ($codename !== null) {
        $params['codename'] = $codename;
    }

    $policyKey = api_get('policy_key');
    if (isset($input->policy_key) && is_string($policyKey) && $policyKey !== '') {
        $params['policy_key'] = $policyKey;
    }

    $incidents = $api->incident_report->list($params);
    $pagination->setResourceList($incidents);

    $xtpl->table_add_category(_('ID'));
    $xtpl->table_add_category(_('Detected at'));

    if (isAdmin()) {
        $xtpl->table_add_category(_('User'));
    }

    $xtpl->table_add_category(_('VPS'));
    $xtpl->table_add_category(_('IP address'));
    $xtpl->table_add_category(_('Subject'));
    $xtpl->table_add_category(_('Codename'));

    if (isAdmin()) {
        $xtpl->table_add_category(_('Admin'));
    }

    $xtpl->table_add_category('');

    foreach ($incidents as $inc) {
        $xtpl->table_td('<a href="?page=incidents&action=show&id=' . $inc->id . '">' . $inc->id . '</a>');
        $xtpl->table_td(tolocaltz($inc->detected_at));

        if (isAdmin()) {
            $xtpl->table_td($inc->user_id ? user_link($inc->user) : $inc->raw_user_id);
        }

        $xtpl->table_td($inc->vps_id ? vps_link($inc->vps) : $inc->raw_vps_id);
        $xtpl->table_td($inc->ip_address_assignment_id ? ($inc->ip_address_assignment->ip_addr . '/' . $inc->ip_address_assignment->ip_prefix) : '-');
        $notice = incident_notice_html($inc);
        $xtpl->table_td(h($inc->subject) . ($notice === '' ? '' : '<br>' . $notice));
        $xtpl->table_td(h($inc->codename));

        if (isAdmin()) {
            $xtpl->table_td($inc->filed_by_id ? user_link($inc->filed_by) : '-');
        }

        $xtpl->table_td(
            '<a href="?page=incidents&action=show&id=' . $inc->id . '"><img src="template/icons/vps_edit.png" alt="' . _('Details') . '" title="' . _('Details') . '"></a>'
        );
        $xtpl->table_tr();
    }

    $xtpl->table_pagination($pagination);
    $xtpl->table_out();
}

function incident_show($id)
{
    global $xtpl, $api;

    $inc = $api->incident_report->show($id, [
        'meta' => ['includes' => 'user,vps,ip_address_assignment'],
    ]);

    $xtpl->title(_('Incident report') . ' #' . $inc->id . ': ' . h($inc->subject));

    if (isAdmin()) {
        $xtpl->table_td(_('User') . ':');
        $xtpl->table_td($inc->user_id ? user_link($inc->user) : $inc->raw_user_id);
        $xtpl->table_tr();
    }

    $xtpl->table_td(_('VPS') . ':');
    $xtpl->table_td($inc->vps_id ? vps_link($inc->vps) : $inc->raw_vps_id);
    $xtpl->table_tr();

    $xtpl->table_td(_('IP address') . ':');
    $xtpl->table_td($inc->ip_address_assignment_id ? ($inc->ip_address_assignment->ip_addr . '/' . $inc->ip_address_assignment->ip_prefix) : '-');
    $xtpl->table_tr();

    $xtpl->table_td(_('Assignment') . ':');

    if ($inc->ip_address_assignment_id) {
        $xtpl->table_td(ip_address_assignment_label($inc->ip_address_assignment));
    } else {
        $xtpl->table_td('-');
    }

    $xtpl->table_tr();

    if (isAdmin()) {
        $xtpl->table_td(_('Filed by') . ':');
        $xtpl->table_td($inc->filed_by_id ? user_link($inc->filed_by) : '-');
        $xtpl->table_tr();

        $xtpl->table_td(_('Mailbox') . ':');
        $xtpl->table_td($inc->mailbox_id ? $inc->mailbox->label : '-');
        $xtpl->table_tr();
    }

    $xtpl->table_td(_('Detected at') . ':');
    $xtpl->table_td(tolocaltz($inc->detected_at));
    $xtpl->table_tr();

    $xtpl->table_td(_('Added at') . ':');
    $xtpl->table_td(tolocaltz($inc->created_at));
    $xtpl->table_tr();

    $xtpl->table_td(_('Reported at') . ':');
    $xtpl->table_td(tolocaltz($inc->reported_at));
    $xtpl->table_tr();

    $xtpl->table_td(_('Subject') . ':');
    $xtpl->table_td(h($inc->subject));
    $xtpl->table_tr();

    $xtpl->table_td(_('Codename') . ':');
    $xtpl->table_td(h($inc->codename));
    $xtpl->table_tr();

    $notice = incident_notice_html($inc, true);
    if ($notice !== '') {
        $xtpl->table_td(_('Escalation notice') . ':');
        $xtpl->table_td($notice);
        $xtpl->table_tr();
    }

    $xtpl->table_td(_('CPU limit') . ':');
    $xtpl->table_td($inc->cpu_limit ? ($inc->cpu_limit . '&nbsp;%') : '-');
    $xtpl->table_tr();

    $xtpl->table_td(_('VPS action') . ':');
    $xtpl->table_td($inc->vps_action);
    $xtpl->table_tr();

    $xtpl->table_td(_('Text') . ':');
    $xtpl->table_td('<pre><code>' . h($inc->text) . '</code></pre>');
    $xtpl->table_tr();

    $xtpl->table_out();
    incident_policy_evaluations($inc);
    incident_evidence_intervals($inc);
}

function incident_new($vps_id)
{
    global $xtpl, $api;

    $vps = $api->vps->show($vps_id);

    $xtpl->title(_('New incident report'));

    $xtpl->form_create('?page=incidents&action=new&vps=' . $vps->id, 'post');

    $xtpl->table_td(_('User') . ':');
    $xtpl->table_td(user_link($vps->user));
    $xtpl->table_tr();

    $xtpl->table_td(_('VPS') . ':');
    $xtpl->table_td(vps_link($vps));
    $xtpl->table_tr();

    $xtpl->form_add_select(
        _('IP address') . ':',
        'ip_address_assignment',
        resource_list_to_options(
            $api->ip_address_assignment->list([
                'vps' => $vps->id,
                'active' => true,
            ]),
            'id',
            'ip_addr',
            true,
            function ($as) {
                return $as->ip_addr . '/' . $as->ip_prefix;
            }
        ),
        post_val('ip_address_assignment')
    );

    $input = $api->incident_report->create->getParameters('input');

    api_param_to_form('subject', $input->subject);
    api_param_to_form('text', $input->text);
    api_param_to_form('codename', $input->codename);
    api_param_to_form('detected_at', $input->detected_at, post_val('detected_at', tolocaltz(date('c'))));

    $xtpl->form_add_number(
        _('CPU limit') . ':',
        'cpu_limit',
        post_val('cpu_limit'),
        0,
        10000,
        25,
        '%'
    );

    api_param_to_form('vps_action', $input->vps_action, post_val('vps_action'));

    $xtpl->form_out(_('Report'));
}


function incident_policy_link_context($incident)
{
    global $api;
    $context = ['vps' => null, 'active_keys' => [], 'history' => false];
    $attrs = vps_incident_attributes($incident);
    $association = $attrs['vps'] ?? null;
    $vps = is_object($association) ? vps_incident_attributes($association) : [];
    $meta = $api->getSettings('meta')->namespace;
    // Only the authorized, included association can supply a live VPS target.
    if (empty($vps[$meta]->resolved) || empty($vps['id'])) {
        return $context;
    }
    $context['vps'] = (object) ['id' => (int) $vps['id']];
    $history = $api->incident_report->index;
    $context['history'] = $history && isset($history->getParameters('input')->policy_key);
    $resource = vps_incident_resource($context['vps']->id);
    if ($resource) {
        try {
            foreach ($resource->index() as $policy) {
                $context['active_keys'][$policy->key] = true;
            }
        } catch (\HaveAPI\Client\Exception\Base $e) {
            // Optional live navigation must not disclose API failures.
        }
    }
    return $context;
}

function incident_policy_links($context, $key)
{
    if (!$context['vps'] || !is_string($key) || $key === '') {
        return '';
    }
    $links = [];
    if (vps_incident_key($key) && isset($context['active_keys'][$key])) {
        $links[] = '<a href="' . h(vps_incident_url($context['vps']->id) . '#incident-policy-' . rawurlencode($key))
            . '">' . h(_('Incident policies')) . '</a>';
    }
    if ($context['history']) {
        $links[] = '<a href="' . h(vps_incident_history_url($context['vps'], $key)) . '">'
            . h(_('Incident history')) . '</a>';
    }
    return implode(' | ', $links);
}

function incident_policy_evaluation_details($attrs, $context, $diagnostic = false)
{
    global $xtpl;
    $xtpl->table_title(h($attrs['label']), $diagnostic ? null : 'incident-report.policy');
    vps_incident_row(_('Policy evaluated at'), h(tolocaltz($attrs['evaluated_at'])));
    if ($diagnostic) {
        $matchedValue = $attrs['matched'] ?? null;
        $matched = $matchedValue === null ? _('Unknown') : ($matchedValue ? _('Yes') : _('No'));
        vps_incident_row(_('Matched'), h($matched));
        $states = ['recorded' => _('Recorded'), 'skipped' => _('Skipped'), 'error' => _('Failed'), 'audit_only' => _('Recorded')];
        vps_incident_row(_('State'), h($states[$attrs['state']] ?? _('Unknown')));
        foreach (['error_stage' => _('Error stage'), 'error_class' => _('Error class')] as $field => $label) {
            if (!empty($attrs[$field])) {
                vps_incident_row($label, h($attrs[$field]));
            }
        }
    } else {
        $xtpl->table_td(vps_incident_period_table($attrs), false, false, 2);
        $xtpl->table_tr();
        if (array_key_exists('effective_mode', $attrs)) {
            vps_incident_row(_('Mode'), h(vps_incident_mode_label($attrs['effective_mode'])));
        }
        $decisions = ['none' => _('No action'), 'warning' => vps_incident_gettext('incident-policy-action', 'Warning'), 'stop' => _('VPS stop')];
        vps_incident_row(_('Decision'), h($decisions[$attrs['decision']] ?? _('Unknown')));
    }
    $links = incident_policy_links($context, $attrs['policy_key']);
    if ($links !== '') {
        vps_incident_row(_('Details'), $links);
    }
    $xtpl->table_out();
}

function incident_policy_membership_message($known_empty = false)
{
    global $xtpl;
    $xtpl->table_title(_('Matched policies'), 'incident-report.policies');
    $xtpl->table_td(h($known_empty ? _('No matching policies') : _('Policy information is unavailable for this report.')));
    $xtpl->table_tr();
    $xtpl->table_out();
}

function incident_policy_evaluations($incident)
{
    global $api, $xtpl;
    $incidentAttrs = vps_incident_attributes($incident);
    if (in_array($incidentAttrs['notice_kind'] ?? null, ['warning', 'stop_completed'], true)) {
        return;
    }
    $resource = $api->incident_report->policy_evaluation;
    if (!$resource || !$resource->index) {
        incident_policy_membership_message();
        return;
    }
    $output = $resource->index->getParameters('output');
    foreach (['matched', 'warning_period_days', 'stop_period_days'] as $field) {
        if (!isset($output->{$field})) {
            incident_policy_membership_message();
            return;
        }
    }
    $matched = [];
    $diagnostics = [];
    $knownEmpty = isAdmin();
    try {
        foreach ($api->incident_report($incident->id)->policy_evaluation->index() as $evaluation) {
            $attrs = vps_incident_attributes($evaluation);
            if (($attrs['matched'] ?? null) !== false) {
                $knownEmpty = false;
            }
            if (($attrs['matched'] ?? null) === true && in_array($attrs['state'], ['recorded', 'audit_only'], true)) {
                $matched[] = $attrs;
            } elseif (isAdmin()) {
                $diagnostics[] = $attrs;
            }
        }
    } catch (\HaveAPI\Client\Exception\Base $e) {
        incident_policy_membership_message();
        return;
    }
    $context = $matched || $diagnostics ? incident_policy_link_context($incident) : null;
    $order = static fn($a, $b) => strcmp($a['policy_key'], $b['policy_key']);
    usort($matched, $order);
    usort($diagnostics, $order);
    if ($matched) {
        $xtpl->table_title(_('Matched policies'), 'incident-report.policies');
        $xtpl->table_td(h(_('These counts and limits were saved when this report was evaluated.')));
        $xtpl->table_tr();
        $xtpl->table_out();
        foreach ($matched as $attrs) {
            incident_policy_evaluation_details($attrs, $context);
        }
    }
    if (!$matched) {
        incident_policy_membership_message($knownEmpty);
    }
    if ($diagnostics) {
        $xtpl->table_title(_('Other policy evaluations'), 'incident-report.policy-diagnostics');
        $xtpl->table_out();
        foreach ($diagnostics as $attrs) {
            incident_policy_evaluation_details($attrs, $context, true);
        }
    }
}

function incident_evidence_seconds(int $microseconds): string
{
    $fraction = rtrim(str_pad((string) ($microseconds % 1000000), 6, '0', STR_PAD_LEFT), '0');
    return (string) intdiv($microseconds, 1000000) . ($fraction === '' ? '' : webui_decimal_separator() . $fraction);
}

function incident_evidence_quantity($value, $unit): ?string
{
    return $value !== null && $unit === 'microseconds'
        ? sprintf(_('%s s'), incident_evidence_seconds($value))
        : null;
}

function incident_evidence_measurement($measurement): ?string
{
    return ['rtnl_latency' => _('RTNL latency')][$measurement] ?? null;
}

function incident_evidence_intervals($incident)
{
    global $api, $xtpl;

    $resource = $api->incident_report($incident->id)->evidence_interval;
    if (!$resource || !$resource->index) {
        return;
    }
    $offset = filter_var($_GET['evidence_offset'] ?? 0, FILTER_VALIDATE_INT, ['options' => ['min_range' => 0]]);
    if ($offset === false) {
        $offset = 0;
    }
    try {
        $rows = $resource->index(['offset' => $offset, 'limit' => 25]);
        $meta = (array) $rows->getMeta();
    } catch (\HaveAPI\Client\Exception\Base $e) {
        $xtpl->perex(_('Evidence intervals'), _('The saved intervals could not be loaded.'));
        return;
    }
    if (($meta['available'] ?? false) !== true) {
        return;
    }
    $xtpl->table_title(_('Observed evidence intervals'), 'incident-report.evidence-intervals');
    $xtpl->table_td(h(sprintf(_('Showing %d of %d intervals.'), count($rows), $meta['total_count'])));
    $xtpl->table_tr();
    if (($meta['window_complete'] ?? false) !== true) {
        $xtpl->table_td(h(_('Some observations are missing, so the credited duration is a lower bound. Gaps do not establish that the condition was absent.')));
        $xtpl->table_tr();
    }
    if (($meta['condition_value'] ?? null) !== null) {
        $measurement = incident_evidence_measurement($meta['condition_measurement']);
        $quantity = incident_evidence_quantity($meta['condition_value'], $meta['condition_unit']);
        $operator = ['gt' => _('%s is greater than %s')][$meta['condition_operator']] ?? null;
        $condition = $measurement !== null && $quantity !== null && $operator !== null
            ? sprintf($operator, $measurement, $quantity)
            : _('Not available');
        $xtpl->table_td(h($condition));
        $xtpl->table_tr();
    }
    $xtpl->table_out();
    $xtpl->table_td(h(_('Interval start')));
    $xtpl->table_td(h(_('Interval end')));
    $xtpl->table_td(h(_('Credited duration')));
    $xtpl->table_td(h(_('Observed peak')));
    $xtpl->table_tr();
    foreach ($rows as $row) {
        $xtpl->table_td(h(tolocaltz($row->from_at, 'Y-m-d H:i:s.u P')));
        $xtpl->table_td(h(tolocaltz($row->to_at, 'Y-m-d H:i:s.u P')));
        $xtpl->table_td(h(sprintf(_('Credited time: %s s'), incident_evidence_seconds($row->credit_us))));
        $measurement = incident_evidence_measurement($row->measurement);
        $quantity = incident_evidence_quantity($row->peak_value, $row->peak_unit);
        $peak = $measurement !== null && $quantity !== null
            ? sprintf(_('%s: %s'), $measurement, ($row->peak_is_lower_bound ? '≥' : '') . $quantity)
            : _('Not available');
        $xtpl->table_td(h($peak));
        $xtpl->table_tr();
    }
    $xtpl->table_out();
    $links = [];
    foreach (['previous' => max(0, $offset - 25), 'next' => $meta['next_offset']] as $direction => $target) {
        if (($direction === 'previous' && $offset === 0) || $target === null) {
            continue;
        }
        $url = '?page=incidents&action=show&id=' . rawurlencode((string) $incident->id) . '&evidence_offset=' . rawurlencode((string) $target);
        $links[] = '<a href="' . h($url) . '">' . h($direction === 'previous' ? _('Previous') : _('Next')) . '</a>';
    }
    $xtpl->parsed_blocks['main.table'] .= '<p>' . implode(' | ', $links) . '</p>';
}
