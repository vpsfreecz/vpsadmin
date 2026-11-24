<?php

function admin_incidents_action()
{
    return $_GET['action'] ?? (isAdmin() ? 'overview' : null);
}

function admin_incidents_menu()
{
    global $xtpl;
    if (isAdmin()) {
        $xtpl->menu_add(_('Incidents'), '?page=incidents&action=overview', ($_GET['page'] ?? '') === 'incidents', false, 'admin.incidents.menu');
    }
}

function admin_incidents_layout($action)
{
    global $xtpl;
    if (isAdmin() && in_array($action, ['overview', 'history'], true)) {
        $xtpl->assign('VIEWPORT', 'width=device-width, initial-scale=1');
        $xtpl->assign('SCRIPT', ($xtpl->vars['SCRIPT'] ?? '') . '<link rel="stylesheet" href="template/css/admin-incidents.css">');
        $xtpl->assign('SCRIPT_BODY', ($xtpl->vars['SCRIPT_BODY'] ?? '') . ' data-admin-incidents="true"');
    }
}

function admin_incidents_sidebar($action)
{
    global $xtpl;
    if (!isAdmin() || !in_array($action, ['overview', 'list', 'history'], true)) {
        return;
    }
    foreach (['overview' => _('Overview'), 'list' => _('Reports'), 'history' => _('History')] as $view => $label) {
        $xtpl->sbar_add(
            $view === $action ? '<strong aria-current="page">' . h($label) . '</strong>' : h($label),
            '?page=incidents&action=' . $view . ($view === 'list' ? '&list=1' : ''),
            'admin.incidents.' . $view
        );
    }
}

function admin_incidents_fields($history)
{
    if ($history) {
        return explode(' ', 'id incident_report_id vps_id user_id hostname user_login policy_key label evaluated_at detected_at matched state warning_period_days stop_period_days count_7d count_30d warning_limit stop_limit effective_mode stop_enforced threshold_status decision action_id action_kind action_state action_created_at action_updated_at transaction_chain_id physical_stop_action_id stop_completed_at notice_report_id mail_state mail_queued_at mail_finished_at');
    }
    return explode(' ', 'id vps user node policy_key label owner_active transfer_pending count_7d count_30d warning_period_days stop_period_days warning_limit stop_limit warning_remaining stop_remaining configuration_valid status global_mode effective_mode warning_permitted stop_enforced last_incident_at last_warning_at next_warning_allowed_at last_stop_at next_stop_allowed_at accounting_since outstanding_stop_state outstanding_stop_action_id outstanding_stop_chain_id latest_action_id latest_action_chain_id latest_notice_report_id latest_action_kind latest_action_state latest_mail_state latest_stop_completed_at');
}

function admin_incidents_resource($history)
{
    global $api;
    if (!isAdmin()) {
        return null;
    }
    $name = $history ? 'incident_policy_evaluation' : 'incident_policy_exposure';
    $resource = $api->{$name};
    if (!$resource || !$resource->index) {
        return null;
    }
    $description = $resource->getDescription()->actions->index;
    if (!$history) {
        foreach (['vps' => 'hostname', 'user' => 'login', 'node' => 'domain_name'] as $name => $label) {
            $field = $description->output->parameters->{$name} ?? null;
            if (!$field || $field->type !== 'Resource' || $field->value_id !== 'id' || $field->value_label !== $label) {
                return null;
            }
        }
    }
    foreach (admin_incidents_fields($history) as $field) {
        if (!isset($description->output->parameters->{$field})) {
            return null;
        }
    }
    foreach (array_merge(['offset', 'limit', 'as_of', 'policy_key'], $history
        ? ['direction', 'vps_id', 'user_id', 'scope', 'from', 'to', 'decision', 'action_kind', 'action_state', 'mail_state']
        : ['sort', 'direction', 'vps', 'user', 'node', 'status', 'effective_mode', 'stop_enforced']) as $field) {
        if (!isset($description->input->parameters->{$field})) {
            return null;
        }
    }
    foreach (array_merge(['total_count', 'offset', 'limit', 'next_offset', 'as_of', 'read_at'], $history ? ['from', 'to'] : []) as $field) {
        if (!isset($description->meta->global->output->parameters->{$field})) {
            return null;
        }
    }
    return $resource;
}

function admin_incidents_params($history)
{
    $params = [];
    $fields = array_merge(['offset', 'limit', 'as_of', 'policy_key'], $history
        ? ['direction', 'vps_id', 'user_id', 'scope', 'from', 'to', 'decision', 'action_kind', 'action_state', 'mail_state']
        : ['sort', 'direction', 'vps', 'user', 'node', 'status', 'effective_mode', 'stop_enforced']);
    foreach ($fields as $field) {
        if (!isset($_GET[$field]) || $_GET[$field] === '') {
            continue;
        }
        if (!is_string($_GET[$field])) {
            throw new InvalidArgumentException();
        }
        $value = trim($_GET[$field]);
        if ($value === '') {
            continue;
        }
        if (in_array($field, ['offset', 'limit', 'vps_id', 'user_id', 'vps', 'user', 'node'], true)) {
            if (!ctype_digit($value) || filter_var($value, FILTER_VALIDATE_INT) === false
                || (int) $value < ($field === 'offset' ? 0 : 1) || ($field === 'limit' && (int) $value > 100)) {
                throw new InvalidArgumentException();
            }
            $value = (int) $value;
        } elseif ($field === 'stop_enforced') {
            if (!in_array($value, ['0', '1'], true)) {
                throw new InvalidArgumentException();
            }
            $value = $value === '1';
        }
        $params[$field] = $value;
    }
    if ($history && ($params['scope'] ?? '') === 'outstanding') {
        unset($params['from'], $params['to']);
    }
    return $params;
}

function admin_incidents_url($history, $params)
{
    return '?' . http_build_query(['page' => 'incidents', 'action' => $history ? 'history' : 'overview'] + $params);
}

function admin_incidents_filter_form($history, $params)
{
    global $xtpl;
    $xtpl->table_title(_('Filters'));
    $xtpl->form_create('', 'get', 'admin-incident-filter', false);
    $xtpl->form_set_hidden_fields(['page' => 'incidents', 'action' => $history ? 'history' : 'overview', 'as_of' => $params['as_of'] ?? null]);
    incident_policy_filter_form();
    foreach ($history ? ['vps_id' => _('VPS ID'), 'user_id' => _('User ID')] : ['vps' => _('VPS ID'), 'user' => _('User ID'), 'node' => _('Node ID')] as $field => $label) {
        $xtpl->form_add_input(h($label) . ':', 'text', '12', $field, $params[$field] ?? '');
    }
    if ($history) {
        $xtpl->form_add_select(_('Scope') . ':', 'scope', ['violations' => _('Reached thresholds and actions'), 'matched' => _('Matched evaluations'), 'all' => _('All evaluations'), 'outstanding' => _('Outstanding actions')], $params['scope'] ?? 'violations');
        $disabled = ($params['scope'] ?? '') === 'outstanding';
        foreach (['from' => _('From'), 'to' => _('To')] as $field => $label) {
            $xtpl->table_td(h($label) . ' (UTC):');
            $xtpl->table_td('<input type="text" name="' . $field . '" value="' . h($params[$field] ?? '') . '"' . ($disabled ? ' disabled' : '') . '>');
            $xtpl->table_tr();
        }
        foreach (['decision' => ['none' => _('No action'), 'warning' => vps_incident_gettext('incident-policy-action', 'Warning'), 'stop' => _('VPS stop')], 'action_kind' => ['warning' => vps_incident_gettext('incident-policy-action', 'Warning'), 'stop' => _('VPS stop')]] as $field => $choices) {
            $xtpl->form_add_select(($field === 'decision' ? _('Decision') : _('Action')) . ':', $field, ['' => _('All')] + $choices, $params[$field] ?? '');
        }
        foreach (['action_state' => _('Action state'), 'mail_state' => _('Mail state')] as $field => $label) {
            $xtpl->form_add_input(h($label) . ':', 'text', '16', $field, $params[$field] ?? '');
        }
        $xtpl->assign('AJAX_SCRIPT', ($xtpl->vars['AJAX_SCRIPT'] ?? '') . <<<'HTML'
            <script>
            $(document).on('change', 'form[name="admin-incident-filter"] select[name="scope"]', function() {
                $(this).closest('form').find('[name="from"], [name="to"]').prop('disabled', this.value === 'outstanding');
            });
            </script>
            HTML);
    } else {
        $xtpl->form_add_select(_('Status') . ':', 'status', ['' => _('All')] + vps_incident_status_labels() + ['invalid' => _('Invalid configuration')], $params['status'] ?? '');
        $xtpl->form_add_select(_('Mode') . ':', 'effective_mode', ['' => _('All'), 'observe' => _('Observation only'), 'notify' => _('Warnings only'), 'enforce' => _('Warnings and automatic shutdown')], $params['effective_mode'] ?? '');
        $xtpl->form_add_select(_('Automatic shutdown') . ':', 'stop_enforced', ['' => _('All'), '1' => _('Allowed'), '0' => _('Not allowed')], isset($params['stop_enforced']) ? ($params['stop_enforced'] ? '1' : '0') : '');
        $sorts = ['severity' => _('Severity'), 'vps_id' => _('VPS ID'), 'user_login' => _('User'), 'policy_key' => _('Policy'),
            'count_7d' => _('7-day incident count'), 'count_30d' => _('30-day incident count'), 'warning_remaining' => _('Reports until warning threshold'),
            'stop_remaining' => _('Reports until shutdown threshold'), 'last_incident_at' => _('Last incident')];
        $xtpl->form_add_select(_('Sort by') . ':', 'sort', $sorts, $params['sort'] ?? 'severity');
    }
    $xtpl->form_add_select(_('Direction') . ':', 'direction', ['desc' => _('Descending'), 'asc' => _('Ascending')], $params['direction'] ?? ((!$history && ($params['sort'] ?? 'severity') !== 'severity') ? 'asc' : 'desc'));
    $xtpl->form_add_number(_('Limit') . ':', 'limit', $params['limit'] ?? 25, 1, 100);
    $xtpl->form_out(_('Show'));
    foreach (['TABLE_FORM_BEGIN', 'TABLE_FORM_END', 'FORM_HIDDEN_FIELDS', 'FORM_CSRF_TOKEN'] as $field) {
        $xtpl->assign($field, '');
    }
}

function admin_incidents_value($value)
{
    return h($value === null ? _('Unknown') : (string) $value);
}

function admin_incidents_bool($value)
{
    return h($value === null ? vps_incident_gettext('incident-policy-boolean', 'Unknown')
        : ($value ? vps_incident_gettext('incident-policy-boolean', 'Yes') : vps_incident_gettext('incident-policy-boolean', 'No')));
}

function admin_incidents_date($value)
{
    return $value === null ? h(_('Unknown')) : h(tolocaltz($value));
}

function admin_incidents_enum($value, $kind)
{
    $labels = match ($kind) {
        'evaluation' => ['recorded' => _('Recorded'), 'skipped' => _('Skipped'), 'error' => _('Failed'), 'audit_only' => _('Recorded for audit')],
        'decision' => ['none' => _('No action'), 'warning' => vps_incident_gettext('incident-policy-action', 'Warning'), 'stop' => _('VPS stop')],
        'mail' => ['pending' => _('Mail not yet queued'), 'queued' => _('Mail queued'), 'sent' => _('Accepted by mail server'), 'failed' => _('Mail failed'), 'uncertain' => _('Mail outcome uncertain'), 'suppressed' => _('Mail suppressed')],
        default => ['none' => _('None'), 'pending' => _('Pending'), 'queued' => _('Queued'), 'completed' => _('Completed'), 'failed' => _('Failed'), 'uncertain' => _('Uncertain'), 'suppressed' => _('Suppressed')],
    };
    return h($labels[$value] ?? _('Unknown'));
}

function admin_incidents_fact($label, $value)
{
    return '<div><dt>' . h($label) . '</dt><dd>' . $value . '</dd></div>';
}

function admin_incidents_identity($row, $withUser = true)
{
    $vps = $row['vps_id'] === null ? admin_incidents_value(null) : h(_('VPS')) . ' #' . (int) $row['vps_id'];
    if ($row['vps_id'] !== null && $row['hostname'] !== null) {
        $vps = '<a href="?page=adminvps&amp;action=info&amp;veid=' . (int) $row['vps_id'] . '">#' . (int) $row['vps_id'] . ' ' . h($row['hostname']) . '</a>';
    }
    if (!$withUser) {
        return $vps;
    }
    return $vps . '<br>' . h(_('User')) . ': ' . admin_incidents_user($row);
}

function admin_incidents_user($row)
{
    if ($row['user_id'] !== null && $row['user_login'] !== null) {
        return '<a href="?page=adminm&amp;action=edit&amp;id=' . (int) $row['user_id'] . '">' . h($row['user_login']) . '</a>';
    }
    return admin_incidents_value($row['user_id']);
}

function admin_incidents_counts($row, $remaining = false)
{
    $html = '<div class="admin-incident-counts">';
    foreach ([['warning_period_days', 'count_7d', 'warning_limit', 'warning_remaining'], ['stop_period_days', 'count_30d', 'stop_limit', 'stop_remaining']] as [$period, $count, $limit, $left]) {
        $periodLabel = $remaining
            ? format_ngettext('Last %d day', 'Last %d days', (int) $row[$period], (int) $row[$period])
            : format_ngettext('%d day', '%d days', (int) $row[$period], (int) $row[$period]);
        $actionLabel = $count === 'count_7d' ? vps_incident_gettext('incident-policy-action', 'Warning') : _('VPS stop');
        $html .= '<p data-incident-count="' . $count . '"><strong>' . h($actionLabel) . ':</strong> '
            . '<span data-count>' . admin_incidents_value($row[$count]) . '</span> / <span data-limit>' . admin_incidents_value($row[$limit]) . '</span>'
            . ' <span data-period>(' . h($periodLabel) . ')</span>';
        if ($remaining) {
            $html .= ' <span data-remaining>' . h(_('Reports remaining')) . ': '
                . ($row[$left] === null ? h(_('Unknown')) : ((int) $row[$left] === 0 ? h(_('Threshold reached')) : h((int) $row[$left]))) . '</span>';
        }
        $html .= '</p>';
    }
    return $html . '</div>';
}

function admin_incidents_outcome($row, $history)
{
    $prefix = $history ? '' : 'latest_';
    $id = $row[$prefix . 'action_id'];
    if ($id === null) {
        return h(_('No recorded action'));
    }
    $html = '<dl class="admin-incident-facts">' . admin_incidents_fact(_('Action'), '#' . (int) $id . ' ' . admin_incidents_enum($row[$prefix . 'action_kind'], 'decision'))
        . admin_incidents_fact(_('Action state'), admin_incidents_enum($row[$prefix . 'action_state'], 'action'))
        . admin_incidents_fact(_('Mail state'), admin_incidents_enum($row[$history ? 'mail_state' : 'latest_mail_state'], 'mail'));
    foreach ($history ? ['action_created_at' => _('Action created'), 'action_updated_at' => _('Action updated'), 'mail_queued_at' => _('Mail queued'), 'mail_finished_at' => _('Mail attempt finished'), 'stop_completed_at' => _('Confirmed shutdown')] : ['latest_stop_completed_at' => _('Confirmed shutdown')] as $field => $label) {
        if ($row[$field] !== null) {
            $html .= admin_incidents_fact($label, admin_incidents_date($row[$field]));
        }
    }
    if ($history && $row['physical_stop_action_id'] !== null) {
        $html .= admin_incidents_fact(_('Shared shutdown action'), '#' . (int) $row['physical_stop_action_id']);
    }
    $chain = $row[$history ? 'transaction_chain_id' : 'latest_action_chain_id'];
    if ($chain !== null) {
        $html .= admin_incidents_fact(_('Transaction log'), '<a href="?page=transactions&amp;chain=' . (int) $chain . '">#' . (int) $chain . '</a>');
    }
    $notice = $row[$history ? 'notice_report_id' : 'latest_notice_report_id'];
    if ($notice !== null) {
        $html .= admin_incidents_fact(_('Incident report'), '<a href="?page=incidents&amp;action=show&amp;id=' . (int) $notice . '">#' . (int) $notice . '</a>');
    }
    return $html . '</dl>';
}

function admin_incidents_outcome_summary($row, $history)
{
    $prefix = $history ? '' : 'latest_';
    if ($row[$prefix . 'action_id'] === null) {
        return h(_('No recorded action'));
    }
    $completedAt = $row[$history ? 'stop_completed_at' : 'latest_stop_completed_at'];
    $state = $row[$prefix . 'action_state'] === 'completed' && $completedAt === null
        ? h(_('Request completed')) : admin_incidents_enum($row[$prefix . 'action_state'], 'action');
    $html = admin_incidents_enum($row[$prefix . 'action_kind'], 'decision') . ': ' . $state
        . ' · ' . h(_('Mail state')) . ': ' . admin_incidents_enum($row[$history ? 'mail_state' : 'latest_mail_state'], 'mail');
    if ($completedAt !== null) {
        $html .= '<br>' . h(_('Confirmed shutdown')) . ': ' . admin_incidents_date($completedAt);
    }
    return $html;
}

function admin_incidents_exposure_row($row)
{
    // Read included partial values directly: ResourceInstance getters may resolve them.
    foreach (['vps' => 'hostname', 'user' => 'login', 'node' => 'domain_name'] as $name => $label) {
        $reference = (array) $row[$name];
        if (!isset($reference['id'], $reference[$label])) {
            throw new RuntimeException();
        }
        $row[$name . '_id'] = $reference['id'];
        $row[$name === 'vps' ? 'hostname' : ($name === 'user' ? 'user_login' : 'node_name')] = $reference[$label];
    }
    $html = '<article class="admin-incident-entry"><header><h3>' . admin_incidents_identity($row) . '</h3><p><a href="'
        . h(vps_incident_url($row['vps_id']) . '#incident-policy-' . rawurlencode($row['policy_key'])) . '">' . h($row['label']) . '</a>'
        . ' · <a href="' . h(admin_incidents_url(true, ['vps_id' => $row['vps_id'], 'policy_key' => $row['policy_key']])) . '">' . h(_('History')) . '</a></p></header>'
        . admin_incidents_counts($row, true)
        . '<p><strong>' . h($row['configuration_valid'] ? (vps_incident_status_labels()[$row['status']] ?? _('Unknown')) : _('Invalid configuration')) . '</strong></p>';
    foreach (['outstanding_stop_state' => _('Outstanding shutdown')] as $field => $label) {
        if ($row[$field] !== 'none') {
            $html .= '<p><strong>' . h($label) . ': ' . admin_incidents_enum($row[$field], 'action') . '</strong></p>';
        }
    }
    if (in_array($row['effective_mode'], ['observe', 'notify'], true) || $row['effective_mode'] === null) {
        $html .= '<p>' . h(_('Mode')) . ': ' . h(vps_incident_mode_label($row['effective_mode'])) . '</p>';
    }
    if ($row['stop_enforced'] !== true) {
        $html .= '<p>' . h(_('Automatic shutdown')) . ': ' . admin_incidents_bool($row['stop_enforced']) . '</p>';
    }
    $html .= '<p>' . admin_incidents_outcome_summary($row, false) . '</p>';
    $facts = admin_incidents_fact(_('Node'), '<a href="?page=node&amp;id=' . (int) $row['node_id'] . '">' . h($row['node_name']) . '</a>')
        . admin_incidents_fact(_('Mode'), h(vps_incident_mode_label($row['effective_mode'])))
        . admin_incidents_fact(_('Global mode'), h(vps_incident_mode_label($row['global_mode'])))
        . admin_incidents_fact(_('Warning emails allowed'), admin_incidents_bool($row['warning_permitted']))
        . admin_incidents_fact(_('Automatic shutdown'), admin_incidents_bool($row['stop_enforced']))
        . admin_incidents_fact(_('Owner active'), admin_incidents_bool($row['owner_active']))
        . admin_incidents_fact(_('Ownership transfer pending'), admin_incidents_bool($row['transfer_pending']))
        . admin_incidents_fact(_('Outstanding shutdown'), admin_incidents_enum($row['outstanding_stop_state'], 'action'));
    foreach (['last_incident_at' => _('Last incident'), 'next_warning_allowed_at' => _('Warning cooldown ends'), 'next_stop_allowed_at' => _('Shutdown cooldown ends'), 'last_warning_at' => _('Last warning queued'), 'last_stop_at' => _('Last confirmed shutdown'), 'accounting_since' => _('Counting since')] as $field => $label) {
        $facts .= admin_incidents_fact($label, admin_incidents_date($row[$field]));
    }
    if ($row['outstanding_stop_action_id'] !== null) {
        $facts .= admin_incidents_fact(_('Action'), '#' . (int) $row['outstanding_stop_action_id']);
    }
    if ($row['outstanding_stop_chain_id'] !== null) {
        $facts .= admin_incidents_fact(_('Transaction log'), '<a href="?page=transactions&amp;chain=' . (int) $row['outstanding_stop_chain_id'] . '">#' . (int) $row['outstanding_stop_chain_id'] . '</a>');
    }
    return $html . '<details><summary>' . h(_('Details')) . '</summary><dl class="admin-incident-facts">' . $facts . '</dl>'
        . admin_incidents_outcome($row, false) . '</details></article>';
}

function admin_incidents_history_row($row)
{
    $html = '<article class="admin-incident-entry"><header><h3>' . admin_incidents_date($row['evaluated_at'])
        . ' · <a href="?page=incidents&amp;action=show&amp;id=' . (int) $row['incident_report_id'] . '">' . h(_('Incident report')) . ' #' . (int) $row['incident_report_id'] . '</a></h3>'
        . '<p>' . admin_incidents_identity($row, false) . ' · ' . h($row['label']) . '</p></header>'
        . '<section data-incident-saved><h4>' . h(_('Decision at the time')) . '</h4><p><strong>' . admin_incidents_enum($row['decision'], 'decision') . '</strong></p>'
        . admin_incidents_counts($row) . '<p>' . h(vps_incident_status_labels()[$row['threshold_status']] ?? _('Unknown')) . '</p>';
    if ($row['state'] !== 'recorded' || $row['matched'] !== true) {
        $html .= '<p>' . h(_('State')) . ': ' . admin_incidents_enum($row['state'], 'evaluation')
            . ' · ' . h(_('Matched')) . ': ' . admin_incidents_bool($row['matched']) . '</p>';
    }
    $html .= '</section><section data-incident-current><h4>' . h(_('Current outcome')) . '</h4><p>' . admin_incidents_outcome_summary($row, true) . '</p></section>';
    $facts = admin_incidents_fact(_('User'), admin_incidents_user($row))
        . admin_incidents_fact(_('Policy key'), h($row['policy_key']))
        . admin_incidents_fact(_('Detected at'), admin_incidents_date($row['detected_at']))
        . admin_incidents_fact(_('Matched'), admin_incidents_bool($row['matched']))
        . admin_incidents_fact(_('State'), admin_incidents_enum($row['state'], 'evaluation'))
        . admin_incidents_fact(_('Mode'), h(vps_incident_mode_label($row['effective_mode'])))
        . admin_incidents_fact(_('Automatic shutdown'), admin_incidents_bool($row['stop_enforced']));
    return $html . '<details><summary>' . h(_('Details')) . '</summary><dl class="admin-incident-facts">' . $facts . '</dl>'
        . admin_incidents_outcome($row, true) . '</details></article>';
}

function admin_incidents_page($history = false)
{
    global $xtpl;
    if (!isAdmin()) {
        $xtpl->perex(_('Access forbidden'), '');
        return;
    }
    $xtpl->title(_('Incidents') . ': ' . ($history ? _('History') : _('Overview')));
    $resource = admin_incidents_resource($history);
    if (!$resource) {
        $xtpl->perex(_('Incident overview and history are unavailable on this API.'), '');
        return;
    }
    try {
        $params = admin_incidents_params($history);
        $rows = $resource->index($params);
        $meta = (array) $rows->getMeta();
        foreach (array_merge(['total_count', 'offset', 'limit', 'next_offset', 'as_of', 'read_at'], $history ? ['from', 'to'] : []) as $field) {
            if (!array_key_exists($field, $meta)) {
                throw new RuntimeException();
            }
        }
        $params = array_replace($params, array_intersect_key($meta, array_flip(['as_of', 'limit', 'from', 'to'])));
        admin_incidents_filter_form($history, $params);
        $html = '<section id="admin-incidents-projection" class="admin-incidents-view"><h2>'
            . h($history ? _('History') : _('All with current matches')) . '</h2>'
            . '<p>' . h(_('Report cutoff')) . ': ' . admin_incidents_date($meta['as_of']) . '</p>';
        foreach ($rows as $row) {
            $attrs = vps_incident_attributes($row);
            $html .= $history ? admin_incidents_history_row($attrs) : admin_incidents_exposure_row($attrs);
        }
        if (count($rows) === 0) {
            $html .= '<p>' . h($history ? _('No recorded evaluations for these filters.') : _('No current matches for these filters.')) . '</p>';
        }
        $html .= '<details class="admin-incident-page-details"><summary>' . h(_('Read details')) . '</summary><dl class="admin-incident-facts">'
            . admin_incidents_fact(_('Report cutoff'), admin_incidents_date($meta['as_of']))
            . admin_incidents_fact(_('Loaded at'), admin_incidents_date($meta['read_at'])) . '</dl></details></section>';
        $xtpl->parsed_blocks['main.table'] .= $html;
        $links = [];
        if ((int) $meta['offset'] > 0) {
            $links[] = '<a href="' . h(admin_incidents_url($history, array_replace($params, ['offset' => max(0, $meta['offset'] - $meta['limit'])]))) . '">' . h(_('Previous')) . '</a>';
        }
        if ($meta['next_offset'] !== null) {
            $links[] = '<a href="' . h(admin_incidents_url($history, array_replace($params, ['offset' => $meta['next_offset']]))) . '">' . h(_('Next')) . '</a>';
        }
        $refresh = $params;
        unset($refresh['offset'], $refresh['as_of']);
        $links[] = '<a href="' . h(admin_incidents_url($history, $refresh)) . '">' . h(_('Refresh')) . '</a>';
        $xtpl->parsed_blocks['main.table'] .= '<p>' . h(sprintf(_('Total: %d'), $meta['total_count'])) . ' ' . implode(' | ', $links) . '</p>';
    } catch (InvalidArgumentException $e) {
        $xtpl->perex(_('Invalid filter value.'), '');
    } catch (\HaveAPI\Client\Exception\Base|RuntimeException $e) {
        $xtpl->perex(_('Unable to load incident overview or history.'), '');
    }
}
