<?php

function vps_incident_attributes($value)
{
    return $value instanceof \HaveAPI\Client\ResourceInstance ? $value->attributes() : (array) $value;
}

function vps_incident_available($vps)
{
    $attrs = vps_incident_attributes($vps);
    return isset($attrs['incident_warning_count'], $attrs['incident_stop_threshold_count'])
        && is_numeric($attrs['incident_warning_count']) && is_numeric($attrs['incident_stop_threshold_count']);
}

function vps_incident_resource($vps_id = null)
{
    global $api;
    $parent = $api->vps;
    if (!$parent || !$parent->incident_policy || !$parent->incident_policy->index) {
        return null;
    }
    $output = $parent->incident_policy->index->getParameters('output');
    foreach (['key', 'label', 'count_7d', 'count_30d', 'configuration_valid', 'warning_limit', 'stop_limit', 'warning_period_days', 'stop_period_days', 'status'] as $field) {
        if (!isset($output->{$field})) {
            return null;
        }
    }
    return $vps_id === null ? $parent->incident_policy : $api->vps($vps_id)->incident_policy;
}

function vps_incident_key($key)
{
    return is_string($key) && preg_match('/\A[a-zA-Z0-9_]{1,59}\z/', $key);
}

function vps_incident_url($vps_id)
{
    return '?page=adminvps&action=incidents&veid=' . (int) $vps_id;
}

function vps_incident_sidebar($vps, $return_url)
{
    global $xtpl;
    $xtpl->sbar_add(
        _('Incident reports'),
        '?page=incidents&action=list&list=1&vps=' . (int) $vps->id . '&return=' . $return_url,
        'vps.incident-reports.menu'
    );
    if (vps_incident_resource()) {
        $xtpl->sbar_add(_('Incident policies'), vps_incident_url($vps->id), 'vps.incidents.menu');
    }
}

function vps_incident_history_url($vps, $key = null)
{
    return '?page=incidents&action=list&list=1&vps=' . (int) $vps->id
        . ($key === null ? '' : '&policy_key=' . rawurlencode($key));
}

function vps_incident_status_labels()
{
    return ['clear' => _('Below limits'), 'near_limit' => _('Approaching a limit'),
        'warning' => _('Warning limit reached'), 'stop_threshold' => _('Shutdown limit reached')];
}

function vps_incident_threshold_label($vps)
{
    if (!vps_incident_available($vps)) {
        return null;
    }
    $attrs = vps_incident_attributes($vps);
    if ($attrs['incident_stop_threshold_count'] > 0) {
        return _('Too many incident reports: VPS shutdown limit reached');
    }
    return $attrs['incident_warning_count'] > 0 ? _('Too many incident reports: warning limit reached') : null;
}

function vps_incident_indicator($vps)
{
    $label = vps_incident_threshold_label($vps);
    return $label === null ? '' : '<a data-vpsadmin-doc-id="vps.incidents.warning" href="'
        . h(vps_incident_url($vps->id)) . '"><img src="template/icons/warning.png" alt="'
        . h($label) . '" title="' . h($label) . '"></a> ';
}

function vps_incident_overview_warning($vps)
{
    global $xtpl;
    $label = vps_incident_threshold_label($vps);
    if ($label !== null) {
        $xtpl->perex(
            '<img src="template/icons/warning.png" alt=""> ' . h($label),
            '<a href="' . h(vps_incident_url($vps->id)) . '">' . h(_('Incident policies')) . '</a>'
        );
    }
}

function vps_incident_read_params($action)
{
    $input = $action->getParameters('input');
    $key = api_get('incident_policy');
    return isset($input->incident_policy) && is_string($key) && $key !== '' ? ['incident_policy' => $key] : [];
}

function vps_incident_list_filters($input)
{
    $params = [];
    $key = api_get('incident_policy');
    if (isset($input->incident_policy) && is_string($key) && $key !== '') {
        $params['incident_policy'] = $key;
        $status = api_get('incident_status');
        if (isset($input->incident_status) && is_string($status) && isset(vps_incident_status_labels()[$status])) {
            $params['incident_status'] = $status;
        }
    }
    return $params;
}

function vps_incident_filter_form($input)
{
    global $xtpl, $api;
    if (!isset($input->incident_policy) || !$api->incident_policy || !$api->incident_policy->index) {
        return;
    }
    $choices = ['' => _('All')];
    foreach ($api->incident_policy->index() as $policy) {
        $choices[$policy->key] = $policy->label;
    }
    $xtpl->form_add_select(_('Policy') . ':', 'incident_policy', $choices, get_val('incident_policy'));
    if (isset($input->incident_status)) {
        $xtpl->form_add_select(_('Status') . ':', 'incident_status', ['' => _('All')] + vps_incident_status_labels(), get_val('incident_status'));
    }

}

function vps_incident_row($label, $value)
{
    global $xtpl;
    $xtpl->table_td(h($label) . ':');
    $xtpl->table_td($value);
    $xtpl->table_tr();
}

function vps_incident_gettext($context, $message)
{
    $key = $context . "\004" . $message;
    $translated = gettext($key);
    return $translated === $key ? $message : $translated;
}

function vps_incident_period_table($attrs, $current = false)
{
    $html = '<table class="table-style01"><thead><tr>';
    foreach ([_('Period'), vps_incident_gettext('incident-policy-column', 'Incidents'), _('Limit'), _('Action')] as $heading) {
        $html .= '<th>' . h($heading) . '</th>';
    }
    $html .= '</tr></thead><tbody>';
    foreach ([
        ['warning_period_days', 'count_7d', 'warning_limit', vps_incident_gettext('incident-policy-action', 'Warning')],
        ['stop_period_days', 'count_30d', 'stop_limit', _('VPS stop')],
    ] as [$period, $count, $limit, $action]) {
        $days = $attrs[$period] ?? null;
        $periodLabel = $days === null ? _('Unknown') : ($current
            ? format_ngettext('Last %d day', 'Last %d days', (int) $days, (int) $days)
            : format_ngettext('%d day', '%d days', (int) $days, (int) $days));
        $html .= '<tr><td>' . h($periodLabel) . '</td>';
        foreach ([$count, $limit] as $field) {
            $html .= '<td>' . h(($attrs[$field] ?? null) === null ? _('Unknown') : (int) $attrs[$field]) . '</td>';
        }
        $html .= '<td>' . h($action) . '</td></tr>';
    }
    return $html . '</tbody></table>';
}

function vps_incident_mode_label($mode)
{
    return ['observe' => _('Observation only'), 'notify' => _('Warnings only'),
        'enforce' => _('Warnings and automatic shutdown')][$mode] ?? _('Unknown');
}

function vps_incident_policy_details($vps, $policy)
{
    $attrs = vps_incident_attributes($policy);
    $details = '';
    foreach (['last_incident_at' => _('Last incident'), 'last_warning_at' => _('Last warning queued'),
        'evaluated_at' => _('Policy evaluated at')] as $field => $label) {
        if (!empty($attrs[$field])) {
            $details .= '<dt>' . h($label) . '</dt><dd>' . h(tolocaltz($attrs[$field])) . '</dd>';
        }
    }
    if (($attrs['evaluation_state'] ?? '') === 'error') {
        $details .= '<dt>' . h(_('Last policy evaluation')) . '</dt><dd>' . h(_('Policy evaluation failed')) . '</dd>';
    }
    if (!empty($attrs['evaluation_report_id'])) {
        $details .= '<dt>' . h(_('Incident report')) . '</dt><dd><a href="?page=incidents&action=show&id='
            . (int) $attrs['evaluation_report_id'] . '">#' . (int) $attrs['evaluation_report_id'] . '</a></dd>';
    }
    return '<dl>' . $details . '</dl><a href="'
        . h(vps_incident_history_url($vps, $policy->key)) . '">' . h(_('Incident history')) . '</a>';
}

function vps_incident_form_out()
{
    global $xtpl;
    $xtpl->form_out(_('Save'));
    // XTemplate retains form variables between tables; keep each policy isolated.
    foreach (['TABLE_FORM_BEGIN', 'TABLE_FORM_END', 'FORM_HIDDEN_FIELDS', 'FORM_CSRF_TOKEN'] as $field) {
        $xtpl->assign($field, '');
    }
}

function vps_incident_policy_form($vps, $policy, $resource)
{
    global $xtpl;
    if (!isAdmin() || !$resource->update) {
        return;
    }
    $input = $resource->update->getParameters('input');
    if (!isset($input->warning_limit_override, $input->stop_limit_override)) {
        return;
    }
    $attrs = vps_incident_attributes($policy);
    $draft = api_post('policy_key') === $policy->key;
    $xtpl->table_title(_('Policy settings'), 'vps.incidents.settings');
    $xtpl->form_create('?page=adminvps&action=incident_policy&veid=' . (int) $vps->id, 'post', 'incident-policy-' . $policy->key);
    $xtpl->form_set_hidden_fields(['policy_key' => $policy->key]);
    $xtpl->table_td(h(_('Leave a limit empty to use the default.')), false, false, 2);
    $xtpl->table_tr();
    foreach (['warning' => _('Warning limit'), 'stop' => _('Shutdown limit')] as $kind => $label) {
        $field = $kind . '_limit_override';
        $override = $attrs[$field] ?? null;
        $value = $draft ? ($_POST[$field] ?? '') : ($override ?? '');
        $value = is_string($value) || is_int($value) ? $value : '';
        $effective = $attrs[$kind . '_limit'] ?? null;
        // An existing override does not reveal the inherited target.
        $placeholder = $override === null && filter_var($effective, FILTER_VALIDATE_INT) !== false && $effective > 0
            ? ' placeholder="' . h($effective) . '"' : '';
        $days = $attrs[$kind . '_period_days'] ?? null;
        $period = $days === null ? _('Unknown') : format_ngettext('%d day', '%d days', (int) $days, (int) $days);
        $unit = static fn($count) => sprintf(_('%s in %s'), trim(str_replace('%d', '', ngettext('%d report', '%d reports', $count))), $period);
        $xtpl->table_td(h($label) . ':');
        $xtpl->table_td('<input type="number" name="' . $field . '" value="' . h($value) . '" min="1" step="1"'
            . $placeholder . '>&nbsp;<span data-incident-unit data-one="' . h($unit(1)) . '" data-other="'
            . h($unit(2)) . '">' . h($unit((int) $value)) . '</span>');
        $xtpl->table_tr();
    }
    vps_incident_form_out();
}

function vps_incident_shared_details($vps)
{
    global $xtpl, $api;
    $attrs = vps_incident_attributes($vps);
    $canEdit = isAdmin() && $api->vps->update
        && isset($api->vps->update->getParameters('input')->incident_enforcement_enabled);
    $xtpl->table_title(_('Automatic shutdown'), 'vps.incidents.permission');
    if ($canEdit) {
        $xtpl->form_create('?page=adminvps&action=incident_permission&veid=' . (int) $vps->id, 'post', 'incident-permission');
        $xtpl->form_add_select(
            _('Allow automatic shutdown') . ':',
            'incident_enforcement_enabled',
            ['1' => _('Allowed'), '0' => _('Exempt')],
            post_val('incident_enforcement_enabled', ($attrs['incident_enforcement_enabled'] ?? false) ? '1' : '0')
        );
    } elseif (array_key_exists('incident_enforcement_enabled', $attrs)) {
        vps_incident_row(_('Allow automatic shutdown'), h($attrs['incident_enforcement_enabled'] ? _('Allowed') : _('Exempt')));
    }
    if (!empty($attrs['incident_last_stop_at'])) {
        vps_incident_row(_('Last automatic shutdown'), h(tolocaltz($attrs['incident_last_stop_at'])));
    }
    $states = ['pending' => _('Automatic shutdown pending'), 'failed' => _('Automatic shutdown failed'),
        'uncertain' => _('Automatic shutdown outcome uncertain')];
    if (isset($states[$attrs['incident_action_state'] ?? ''])) {
        $value = h($states[$attrs['incident_action_state']]);
        if (!empty($attrs['incident_action_chain_id'])) {
            $value .= ' (<a href="?page=transactions&chain=' . (int) $attrs['incident_action_chain_id'] . '">' . h(_('Transaction log')) . '</a>)';
        }
        vps_incident_row(_('Outstanding shutdown'), $value);
    }
    if (!empty($attrs['incident_next_stop_allowed_at'])) {
        vps_incident_row(_('Cooldown ends'), h(tolocaltz($attrs['incident_next_stop_allowed_at'])));
    }
    if ($canEdit) {
        vps_incident_form_out();
    } else {
        $xtpl->table_out();
    }
}

function vps_incident_page($vps)
{
    global $xtpl;
    $resource = vps_incident_resource($vps->id);
    if (!$resource) {
        $xtpl->perex(_('Incident settings unavailable'), '');
        return;
    }
    $prefix = $xtpl->text('main.table');
    foreach ($resource->index() as $policy) {
        $attrs = vps_incident_attributes($policy);
        $xtpl->table_title('<span id="incident-policy-' . h($policy->key) . '">' . h($policy->label) . '</span>', 'vps.incidents.policy');
        if (!empty($attrs['description'])) {
            $xtpl->table_td(h($attrs['description']), false, false, 2);
            $xtpl->table_tr();
        }
        if (!$policy->configuration_valid) {
            vps_incident_row(_('Status'), h(_('Incident limits are misconfigured.')));
        } else {
            if (in_array($policy->status, ['warning', 'stop_threshold'], true)) {
                vps_incident_row(_('Status'), h($policy->label . ': ' . ($policy->status === 'stop_threshold'
                    ? _('Too many incident reports: VPS shutdown limit reached') : _('Too many incident reports: warning limit reached'))));
            }
        }
        $xtpl->table_td(vps_incident_period_table($attrs, true), false, false, 2);
        $xtpl->table_tr();
        if (array_key_exists('effective_mode', $attrs)) {
            vps_incident_row(_('Mode'), h(vps_incident_mode_label($attrs['effective_mode'])));
        }
        $xtpl->table_td(vps_incident_policy_details($vps, $policy), false, false, 2);
        $xtpl->table_tr();
        $xtpl->table_out();
        vps_incident_policy_form($vps, $policy, $resource);
    }
    vps_incident_shared_details($vps);
    $xtpl->parsed_blocks['main.table'] = $prefix . '<div data-vpsadmin-doc-id="vps.incidents.page">'
        . substr($xtpl->text('main.table'), strlen($prefix)) . '</div>';
}

function vps_incident_update_params()
{
    $params = [];
    foreach (['warning', 'stop'] as $kind) {
        $field = $kind . '_limit_override';
        $value = $_POST[$field] ?? '';
        if (is_string($value)) {
            $value = trim($value);
        }
        if ($value === '') {
            $params[$field] = null;
            continue;
        }
        if (!is_string($value) || !ctype_digit($value) || filter_var($value, FILTER_VALIDATE_INT) === false || (int) $value < 1) {
            throw new InvalidArgumentException(_('Enter a positive whole number, or leave the limit empty.'));
        }
        $params[$field] = (int) $value;
    }
    return $params;
}

function vps_incident_save($vps_id, $permission = false)
{
    global $xtpl, $api;
    if (!isAdmin() || ($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
        $xtpl->perex(_('Access forbidden'), '');
        return false;
    }
    csrf_check();
    try {
        $vps = $api->vps->show($vps_id);
        $resource = vps_incident_resource($vps_id);
        if (!$resource) {
            throw new InvalidArgumentException(_('Incident settings unavailable'));
        }
        if ($permission) {
            if (!$api->vps->update || !isset($api->vps->update->getParameters('input')->incident_enforcement_enabled)) {
                throw new InvalidArgumentException(_('Incident settings unavailable'));
            }
            $enabled = api_post('incident_enforcement_enabled');
            if (!in_array($enabled, ['0', '1'], true)) {
                throw new InvalidArgumentException(_('Select whether automatic shutdown is allowed.'));
            }
            $api->vps->update($vps_id, ['incident_enforcement_enabled' => $enabled === '1']);
            $api->vps->show($vps_id);
        } else {
            $key = api_post('policy_key');
            if (!vps_incident_key($key) || !$resource->show || !$resource->update) {
                throw new InvalidArgumentException(_('Incident settings unavailable'));
            }
            $resource->show($key);
            $params = vps_incident_update_params();
            $input = $resource->update->getParameters('input');
            if (!isset($input->warning_limit_override, $input->stop_limit_override)) {
                throw new InvalidArgumentException(_('Incident settings unavailable'));
            }
            $resource->update($key, $params);
            $resource->show($key);
        }
        notify_user(_('Changes saved'), '');
        return true;
    } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
        $xtpl->perex_format_errors(_('Unable to save changes'), $e->getResponse());
    } catch (InvalidArgumentException $e) {
        $xtpl->perex(_('Unable to save changes'), h($e->getMessage()));
    }
    return false;
}
