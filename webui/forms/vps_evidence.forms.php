<?php

require_once __DIR__ . '/vps_pressure_history.forms.php';

function vps_evidence_resource($vps_id = null)
{
    global $api;
    $resource = $vps_id === null ? $api->vps_evidence : $api->vps->evidence;
    if (!$resource || !$resource->index) {
        return null;
    }
    foreach (['signal', 'credit_us', 'configuration_valid', 'observation_state'] as $field) {
        if (!isset($resource->index->getParameters('output')->{$field})) {
            return null;
        }
    }
    return $vps_id === null ? $resource : $api->vps($vps_id)->evidence;
}

function vps_evidence_url(array $params = []): string
{
    return '?' . http_build_query(['page' => 'vps_evidence'] + $params, '', '&', PHP_QUERY_RFC3986);
}

function vps_evidence_sidebar(): void
{
    global $xtpl;
    if (vps_evidence_resource()) {
        $xtpl->sbar_add(_('Memory pressure'), vps_evidence_url(), 'vps-evidence.menu');
    }
}

function vps_evidence_params($input = null): array
{
    $params = [];
    foreach (['user', 'vps', 'node', 'location', 'environment', 'offset', 'limit'] as $field) {
        if (!isset($_GET[$field]) || $_GET[$field] === '') {
            continue;
        }
        if (($input !== null && !isset($input->{$field})) || ($field === 'user' && !isAdmin())) {
            throw new InvalidArgumentException();
        }
        $value = $_GET[$field];
        if (!is_string($value) || !ctype_digit($value) || filter_var($value, FILTER_VALIDATE_INT) === false
            || (int) $value < ($field === 'offset' ? 0 : 1) || ($field === 'limit' && (int) $value > 100)) {
            throw new InvalidArgumentException();
        }
        $params[$field] = (int) $value;
    }
    if (isset($_GET['signal']) && $_GET['signal'] !== '') {
        if (($input !== null && !isset($input->signal)) || !is_string($_GET['signal']) || !preg_match('/\A[a-z][a-z0-9_]{0,63}\z/', $_GET['signal'])) {
            throw new InvalidArgumentException();
        }
        $params['signal'] = $_GET['signal'];
    }
    return $params;
}

function vps_evidence_date($value): string
{
    return $value === null ? h(_('Not available')) : h(tolocaltz($value, 'Y-m-d H:i:s.u P'));
}

function vps_evidence_bool($value): string
{
    return h($value === null ? _('Not available') : ($value ? _('Yes') : _('No')));
}

function vps_evidence_fact($label, $value): string
{
    return '<dt>' . h($label) . '</dt><dd>' . $value . '</dd>';
}

function vps_evidence_details(array $row): string
{
    $seconds = static fn($value) => $value === null ? h(_('Not available')) : h(sprintf(_('%s s'), $value));
    $credit = $row['credit_us'] === null ? h(_('Not available'))
        : h(sprintf(_('%s s'), incident_evidence_seconds($row['credit_us'])));
    $observation = ['no_data' => _('No observations'), 'fresh' => _('Fresh observation'), 'stale' => _('Stale observation')];
    $qualification = ['qualified' => _('Qualified'), 'ineligible' => _('Ineligible'), 'unknown' => _('Unknown')];
    $facts = vps_evidence_fact(_('Recorded time'), $credit)
        . vps_evidence_fact(_('Window start'), vps_evidence_date($row['window_from']))
        . vps_evidence_fact(_('Window end'), vps_evidence_date($row['window_to']))
        . vps_evidence_fact(_('Window length'), $seconds($row['window_seconds']))
        . vps_evidence_fact(_('Reporting threshold'), $seconds($row['threshold_seconds']))
        . vps_evidence_fact(_('Repeat period'), $seconds($row['repeat_seconds']))
        . vps_evidence_fact(_('Observation'), h($observation[$row['observation_state']] ?? _('Unknown')))
        . vps_evidence_fact(_('Qualification'), h($qualification[$row['qualification'] ?? 'unknown'] ?? _('Unknown')))
        . vps_evidence_fact(_('Last observed'), vps_evidence_date($row['last_observed_at']))
        . vps_evidence_fact(_('Observation age'), $seconds($row['observation_age_seconds']))
        . vps_evidence_fact(_('Incident reporting enabled'), vps_evidence_bool($row['reporting_enabled']))
        . vps_evidence_fact(_('Current observations meet reporting criteria'), vps_evidence_bool($row['report_eligible']))
        . vps_evidence_fact(_('Report due'), vps_evidence_bool($row['report_due']))
        . vps_evidence_fact(_('Last incident'), vps_evidence_date($row['last_incident_at']));
    $measurement = incident_evidence_measurement($row['measurement']);
    $quantity = incident_evidence_quantity($row['peak_value'], $row['peak_unit']);
    $peak = $measurement !== null && $quantity !== null
        ? sprintf(_('%s: %s'), $measurement, ($row['peak_is_lower_bound'] ? '≥' : '') . $quantity) : _('Not available');
    $facts .= vps_evidence_fact(_('Observed peak'), h($peak));
    $condition = incident_evidence_measurement($row['condition_measurement']);
    $quantity = incident_evidence_quantity($row['condition_value'], $row['condition_unit']);
    $operator = ['gt' => _('%s is greater than %s')][$row['condition_operator']] ?? null;
    $facts .= vps_evidence_fact(_('Condition'), h($condition !== null && $quantity !== null && $operator !== null
        ? sprintf($operator, $condition, $quantity) : _('Not available')));
    $vps = vps_incident_attributes($row['vps']);
    return '<details><summary>' . h(_('Details')) . '</summary><dl>' . $facts . '</dl></details>'
        . '<a href="' . h(vps_incident_history_url((object) ['id' => (int) $vps['id']])) . '">'
        . h(_('Incident history')) . '</a>';
}

function vps_evidence_duration($value): string
{
    return $value === null ? h(_('Unavailable'))
        : h(sprintf(_('%s s'), incident_evidence_seconds($value)));
}

function vps_evidence_period($seconds): string
{
    if ($seconds === null) {
        return h(_('Unavailable'));
    }
    return h($seconds % 86400 === 0
        ? format_ngettext('Last %s day', 'Last %s days', $seconds / 86400, $seconds / 86400)
        : sprintf(_('Last %s s'), $seconds));
}

function vps_evidence_threshold(array $row): string
{
    $threshold = $row['threshold_seconds'];
    if ($threshold === null || $threshold <= 0 || $row['credit_us'] === null || $row['configuration_valid'] !== true) {
        return h(_('Unavailable'));
    }
    $duration = incident_evidence_seconds($row['credit_us']);
    $label = sprintf(_('%s s recorded / %s s threshold; %s'), $duration, $threshold, strip_tags(vps_evidence_period($row['window_seconds'])));
    $ratio = min(1, max(0, $row['credit_us'] / ($threshold * 1000000)));
    return '<meter min="0" max="1" value="' . h((string) $ratio) . '" aria-label="' . h($label)
        . '" aria-valuetext="' . h($label) . '">' . h($label) . '</meter><br>' . vps_evidence_duration($threshold * 1000000);
}

function vps_evidence_cells(array $row): array
{
    $vps = vps_incident_attributes($row['vps']);
    $id = (int) $vps['id'];
    $cells = [vps_link((object) ['id' => $id]) . ' ' . h($row['hostname'])];
    if (isAdmin()) {
        $user = isset($row['user']) ? vps_incident_attributes($row['user']) : null;
        $node = isset($row['node']) ? vps_incident_attributes($row['node']) : null;
        $cells[] = $user ? user_link((object) ['id' => (int) $user['id'], 'login' => h($user['login'] ?? '')]) : '-';
        $cells[] = $node ? node_link((object) ['id' => (int) $node['id'], 'domain_name' => h($node['domain_name'] ?? '')]) : '-';
    }
    $cells[] = '<span data-vpsadmin-doc-id="vps-evidence.signal">' . h($row['signal'] === 'rtnl_latency' ? _('Memory pressure') : $row['label']) . '</span>';
    $cells[] = vps_evidence_duration($row['credit_us']);
    $cells[] = vps_evidence_period($row['window_seconds']);
    $cells[] = vps_evidence_threshold($row);
    $states = [];
    if ($row['configuration_valid'] !== true) {
        $states[] = _('Invalid configuration');
    } elseif ($row['credit_us'] === null) {
        $states[] = _('Unavailable');
    } else {
        $observations = ['no_data' => _('No observations'), 'fresh' => _('Fresh observation'), 'stale' => _('Stale observation')];
        $states[] = $observations[$row['observation_state']] ?? _('Unknown');
        if ($row['window_complete'] !== true) {
            $states[] = _('Incomplete observations');
        }
        if ($row['reporting_enabled'] === false) {
            $states[] = _('Reporting disabled');
        }
    }
    $cells[] = implode('<br>', array_map('h', $states)) . '<br>' . h(_('Last observed')) . ': ' . vps_evidence_date($row['last_observed_at']);
    $cells[] = '<a href="?page=adminvps&amp;action=evidence&amp;veid=' . $id . '">' . h(_('Details')) . '</a>'
        . vps_evidence_details($row);
    return $cells;
}

function vps_evidence_filter_form($input, array $params): void
{
    global $xtpl;
    $xtpl->table_title(_('Filters'));
    $xtpl->form_create('', 'get', 'vps-evidence-filter', false);
    $xtpl->form_set_hidden_fields(['page' => 'vps_evidence']);
    foreach (['user' => _('User ID'), 'vps' => _('VPS ID')] as $field => $label) {
        if (isset($input->{$field}) && ($field !== 'user' || isAdmin())) {
            $xtpl->form_add_input($label . ':', 'text', '30', $field, $params[$field] ?? '', '');
        }
    }
    foreach (['node', 'location', 'environment'] as $field) {
        if (isset($input->{$field})) {
            api_param_to_form($field, $input->{$field}, $params[$field] ?? null);
        }
    }
    if (isset($input->signal)) {
        $signal = clone $input->signal;
        $signal->label = _('Issue');
        $choices = api_param_choices($signal, null, true);
        if ($choices === null) {
            api_param_to_form('signal', $signal, $params['signal'] ?? null);
        } else {
            if (array_key_exists('rtnl_latency', $choices)) {
                $choices['rtnl_latency'] = _('Memory pressure');
            }
            $xtpl->form_add_select(_('Issue') . ':', 'signal', $choices, $params['signal'] ?? '');
        }
    }
    if (isset($input->limit)) {
        $xtpl->form_add_input(_('Limit') . ':', 'text', '30', 'limit', $params['limit'] ?? 25, '');
    }
    $xtpl->form_out(_('Show'));
}

// Offset metadata is authoritative; Pagination\System uses a different keyset contract.
function vps_evidence_footer(array $meta, array $params, int $columns): void
{
    global $xtpl;
    $links = [];
    if ($meta['offset'] > 0) {
        $links[] = '<a class="pagination-link" href="' . h(vps_evidence_url(array_replace($params, ['offset' => max(0, $meta['offset'] - $meta['limit'])]))) . '">' . h(_('Previous')) . '</a>';
    }
    if ($meta['next_offset'] !== null) {
        $links[] = '<a class="pagination-link" href="' . h(vps_evidence_url(array_replace($params, ['offset' => $meta['next_offset']]))) . '">' . h(_('Next')) . '</a>';
    }
    $xtpl->table_td('<div class="pagination-controls">' . h(sprintf(_('Total: %d'), $meta['total_count'])) . ' ' . implode(' | ', $links) . '</div>', false, false, $columns);
    $xtpl->table_tr(false, 'pagination-row', 'pagination-row');
}

function vps_evidence_page($vps = null): void
{
    global $xtpl;
    $xtpl->title(_('Memory pressure'));
    $resource = vps_evidence_resource($vps === null ? null : $vps->id);
    if (!$resource) {
        $xtpl->perex(_('Memory pressure data is unavailable.'), '');
        return;
    }
    try {
        $params = $vps === null ? vps_evidence_params($resource->index->getParameters('input')) : [];
        $rows = $resource->index($params);
        $meta = (array) $rows->getMeta();
        foreach (['read_at', 'configuration_valid', 'unavailable_signals'] as $field) {
            if (!array_key_exists($field, $meta)) {
                throw new RuntimeException();
            }
        }
        $xtpl->parsed_blocks['main.table'] = ($xtpl->parsed_blocks['main.table'] ?? '')
            . '<section data-vpsadmin-doc-id="' . ($vps === null ? 'vps-evidence.overview' : 'vps.evidence.page') . '">';
        if ($vps === null) {
            vps_evidence_filter_form($resource->index->getParameters('input'), $params);
        }
        $xtpl->table_title(_('Memory pressure'));
        $headers = [_('VPS')];
        if (isAdmin()) {
            $headers[] = _('User');
            $headers[] = _('Node');
        }
        array_push($headers, _('Issue'), _('Recorded time'), _('Period'), _('Reporting threshold'), _('Observation'), _('Details'));
        foreach ($headers as $label) {
            $xtpl->table_add_category(h($label));
        }
        foreach ($rows as $row) {
            foreach (vps_evidence_cells(vps_incident_attributes($row)) as $cell) {
                $xtpl->table_td($cell);
            }
            $xtpl->table_tr();
        }
        if (count($rows) === 0) {
            $xtpl->table_td(h($meta['configuration_valid'] === true ? _('No recorded time matches these filters.') : _('Invalid configuration')), false, false, count($headers));
            $xtpl->table_tr();
        }
        if ($vps === null) {
            vps_evidence_footer($meta, $params, count($headers));
        }
        $xtpl->table_out();
        $xtpl->parsed_blocks['main.table'] .= '<p>' . h(_('Read at')) . ': ' . vps_evidence_date($meta['read_at']) . '</p></section>';
        if ($vps !== null) {
            vps_pressure_history_page($vps);
        }
    } catch (InvalidArgumentException $e) {
        $xtpl->perex(_('Invalid filter value.'), '');
    } catch (\HaveAPI\Client\Exception\Base|RuntimeException $e) {
        $xtpl->perex(_('Unable to load memory pressure data.'), '');
    }
}
