<?php

function vps_incident_available($vps)
{
    $attrs = $vps instanceof \HaveAPI\Client\ResourceInstance
        ? $vps->attributes()
        : (array) $vps;
    return isset($attrs['incident_count_7d'], $attrs['incident_policy'])
        && is_numeric($attrs['incident_count_7d']) && is_string($attrs['incident_policy']);
}

function vps_incident_status_labels()
{
    return [
        'clear' => _('Below limits'),
        'near_limit' => _('Approaching a limit'),
        'warning' => _('Warning limit reached'),
        'stop_threshold' => _('Automatic shutdown limit reached'),
    ];
}

function vps_incident_status_label($vps)
{
    return vps_incident_status_labels()[$vps->incident_status] ?? _('Unknown');
}

function vps_incident_history_url($vps)
{
    return '?page=incidents&action=list&list=1&vps=' . (int) $vps->id . '&codename=' . rawurlencode($vps->incident_policy);
}

function vps_incident_indicator($vps)
{
    if (!vps_incident_available($vps)) {
        return '-';
    }

    $counts = sprintf(
        _('7 days: %1$d/%2$d; 30 days: %3$d/%4$d'),
        $vps->incident_count_7d,
        $vps->incident_warning_limit,
        $vps->incident_count_30d,
        $vps->incident_stop_limit
    );

    return '<a data-vpsadmin-doc-id="vps.oom-summary" href="?page=adminvps&action=info&veid='
        . (int) $vps->id . '&incident_policy=' . rawurlencode($vps->incident_policy)
        . '#incident-policy" title="' . h($vps->incident_policy_label . ': ' . vps_incident_status_label($vps)) . '">'
        . h($counts) . '</a><br>' . h(vps_incident_status_label($vps))
        . (!$vps->incident_enforcement_enabled ? '<br>' . h(_('Automatic shutdown exempt')) : '');
}

function vps_incident_read_params($action)
{
    $input = $action->getParameters('input');
    return isset($input->incident_policy) && array_key_exists('incident_policy', $_GET)
        ? ['incident_policy' => $_GET['incident_policy']]
        : [];
}

function vps_incident_list_filters($input)
{
    $params = [];
    if (isset($input->incident_policy) && array_key_exists('incident_policy', $_GET)) {
        $params['incident_policy'] = $_GET['incident_policy'];
    }
    $status = api_get('incident_status');
    if (isset($input->incident_status) && is_string($status) && isset(vps_incident_status_labels()[$status])) {
        $params['incident_status'] = $status;
    }

    $enabled = api_get('incident_enforcement_enabled');
    if (isset($input->incident_enforcement_enabled) && in_array($enabled, ['0', '1'], true)) {
        $params['incident_enforcement_enabled'] = $enabled === '1';
    }

    return $params;
}

function vps_incident_filter_form($input, $policy)
{
    global $xtpl;

    $xtpl->form_set_hidden_fields([
        'page' => 'adminvps', 'action' => 'list', 'incident_policy' => $policy,
    ]);
    if (isset($input->incident_status)) {
        $xtpl->form_add_select(_('Incident escalation') . ':', 'incident_status', ['' => _('All')] + vps_incident_status_labels(), get_val('incident_status'));
    }
    if (isset($input->incident_enforcement_enabled)) {
        $xtpl->form_add_select(_('Automatic shutdown permission') . ':', 'incident_enforcement_enabled', [
            '' => _('All'), '1' => _('Allowed'), '0' => _('Exempt'),
        ], get_val('incident_enforcement_enabled'));
    }
}

function vps_incident_row($label, $value)
{
    global $xtpl;
    $xtpl->table_td(h($label) . ':');
    $xtpl->table_td($value);
    $xtpl->table_tr();
}

function vps_incident_details($vps)
{
    global $xtpl, $api;

    if (!vps_incident_available($vps)) {
        return;
    }

    $xtpl->table_title('<span id="incident-policy">' . h(_('Incident escalation')) . '</span>', 'vps.oom-details');
    vps_incident_row(_('Incident type'), h($vps->incident_policy_label));
    vps_incident_row(_('Status'), h(vps_incident_status_label($vps)));
    vps_incident_row(_('Incidents in 7 days / warning limit'), (int) $vps->incident_count_7d . ' / ' . (int) $vps->incident_warning_limit);
    vps_incident_row(_('Incidents in 30 days / automatic shutdown limit'), (int) $vps->incident_count_30d . ' / ' . (int) $vps->incident_stop_limit);

    $modes = [
        'observe' => _('Observation only'),
        'notify' => _('Warnings only'),
        'enforce' => _('Warnings and automatic shutdown'),
    ];
    vps_incident_row(_('Global mode'), h($modes[$vps->incident_mode] ?? _('Unknown')));
    vps_incident_row(_('Automatic shutdown permission'), h($vps->incident_enforcement_enabled ? _('Allowed') : _('Exempt')));
    vps_incident_row(_('Automatic shutdown active'), h($vps->incident_stop_enforced ? _('Enabled') : _('Disabled')));

    foreach ([
        'incident_last_incident_at' => _('Last incident'),
        'incident_last_warning_at' => _('Last warning queued'),
        'incident_last_stop_at' => _('Last confirmed automatic shutdown'),
        'incident_accounting_since' => _('Incidents counted since ownership change'),
    ] as $field => $label) {
        vps_incident_row($label, $vps->{$field} ? h(tolocaltz($vps->{$field})) : '-');
    }

    $states = [
        'none' => _('No outstanding shutdown'),
        'pending' => _('Automatic shutdown pending'),
        'failed' => _('Automatic shutdown failed'),
        'uncertain' => _('Automatic shutdown outcome uncertain'),
    ];
    $state = h($states[$vps->incident_action_state] ?? _('Unknown'));
    if ($vps->incident_action_chain_id) {
        $state .= ' (<a href="?page=transactions&chain=' . (int) $vps->incident_action_chain_id . '">'
            . h(_('Transaction log')) . '</a>)';
    }
    vps_incident_row(_('Outstanding shutdown'), $state);
    vps_incident_row(_('Cooldown ends'), $vps->incident_next_stop_allowed_at ? h(tolocaltz($vps->incident_next_stop_allowed_at)) : '-');
    vps_incident_row(_('Incident reports'), '<a href="' . h(vps_incident_history_url($vps)) . '">' . h(_('List incident reports')) . '</a>');
    $xtpl->table_td(h(_('Counts use rolling 7-day and 30-day periods. Another incident at or after the cooldown ends is required for another automatic shutdown; no shutdown is scheduled for the cooldown end.')), false, false, 2);
    $xtpl->table_tr();
    $xtpl->table_td(h(_('An exemption disables automatic shutdowns by vpsAdmin for repeated incidents. Incident collection and warnings remain active.')), false, false, 2);
    $xtpl->table_tr();
    $xtpl->table_td(h(_('Automatic shutdown permission, the cooldown and any unfinished shutdown are shared across incident types for this VPS.')), false, false, 2);
    $xtpl->table_tr();
    if ($vps->incident_policy === 'oomd') {
        $xtpl->table_td(h(_("The node's memory protection remains active.")), false, false, 2);
        $xtpl->table_tr();
    }
    $xtpl->table_out();

    if (!isAdmin()) {
        return;
    }
    $input = $api->vps->update->getParameters('input');
    if (!isset($input->incident_policy, $input->incident_warning_limit_override, $input->incident_stop_limit_override, $input->incident_enforcement_enabled)) {
        return;
    }

    $xtpl->table_title(_('Incident settings'), 'vps.oom-settings');
    $xtpl->form_create('?page=adminvps&action=incident_policy&veid=' . (int) $vps->id . '&incident_policy=' . rawurlencode($vps->incident_policy), 'post', 'incident-policy');
    $xtpl->form_set_hidden_fields(['incident_policy' => $vps->incident_policy]);
    foreach ([
        'incident_warning_limit_override' => _('Warning limit override (7 days)'),
        'incident_stop_limit_override' => _('Automatic shutdown limit override (30 days)'),
    ] as $field => $label) {
        $xtpl->form_add_number(h($label) . ':', $field, post_val($field, $vps->{$field}) ?? '', 1, 0, 1);
    }
    $xtpl->form_add_select(_('Automatic shutdown permission') . ':', 'incident_enforcement_enabled', [
        '1' => _('Allowed'), '0' => _('Exempt'),
    ], post_val('incident_enforcement_enabled', $vps->incident_enforcement_enabled ? '1' : '0'));
    $xtpl->table_td(h(_('Leave an override empty to inherit the global default. Effective limits are shown above. The shutdown limit must be at least the warning limit.')), false, false, 2);
    $xtpl->table_tr();
    $xtpl->table_td(h(_('Changes apply to new incidents. An operation already running may still finish.')), false, false, 2);
    $xtpl->table_tr();
    $xtpl->form_out(_('Save incident settings'));

    $xtpl->form_create('?page=adminvps&action=incident_policy&veid=' . (int) $vps->id . '&incident_policy=' . rawurlencode($vps->incident_policy), 'post', 'incident-policy-reset');
    $xtpl->form_set_hidden_fields(['reset_limits' => '1', 'incident_policy' => $vps->incident_policy]);
    $xtpl->form_out(_('Reset limits to defaults'));
}

function vps_incident_update_params()
{
    $policy = api_post('incident_policy');
    if (!is_string($policy) || !preg_match('/\A[a-z][a-z0-9_]*\z/', $policy)) {
        throw new InvalidArgumentException(_('Incident settings unavailable'));
    }
    if (api_post('reset_limits') === '1') {
        return ['incident_policy' => $policy, 'incident_warning_limit_override' => null, 'incident_stop_limit_override' => null];
    }

    $params = ['incident_policy' => $policy];
    foreach (['incident_warning_limit_override', 'incident_stop_limit_override'] as $field) {
        $value = $_POST[$field] ?? '';
        if (is_string($value)) {
            $value = trim($value);
        }
        if (!is_string($value) || ($value !== '' && (!ctype_digit($value) || filter_var($value, FILTER_VALIDATE_INT) === false || (int) $value < 1))) {
            throw new InvalidArgumentException(_('Limits must be positive integers or empty to inherit defaults.'));
        }
        $params[$field] = $value === '' ? null : (int) $value;
    }
    $enabled = api_post('incident_enforcement_enabled');
    if (!in_array($enabled, ['0', '1'], true)) {
        throw new InvalidArgumentException(_('Select whether automatic shutdown is allowed.'));
    }
    $params['incident_enforcement_enabled'] = $enabled === '1';
    return $params;
}

function vps_incident_save($vps_id)
{
    global $xtpl, $api;
    if (!isAdmin() || ($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
        $xtpl->perex(_('Access forbidden'), '');
        return false;
    }

    csrf_check();
    try {
        $params = vps_incident_update_params();
        $input = $api->vps->show->getParameters('input');
        if (!isset($input->incident_policy)) {
            $xtpl->perex(_('Incident settings unavailable'), '');
            return false;
        }
        $vps = $api->vps->show($vps_id, ['incident_policy' => $params['incident_policy']]);
        if (!vps_incident_available($vps)) {
            $xtpl->perex(_('Incident settings unavailable'), '');
            return false;
        }
        $api->vps->update($vps_id, $params);
        $api->vps->show($vps_id, ['incident_policy' => $params['incident_policy']]);
        notify_user(_('Incident settings saved'), '');
        return true;
    } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
        $xtpl->perex_format_errors(_('Unable to save incident settings'), $e->getResponse());
    } catch (InvalidArgumentException $e) {
        $xtpl->perex(_('Unable to save incident settings'), h($e->getMessage()));
    }
    return false;
}
