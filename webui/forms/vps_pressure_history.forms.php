<?php

function vps_pressure_history_resource()
{
    global $api;
    $resource = $api->vps_pressure_history;
    if (!$resource || !$resource->index) {
        return null;
    }
    foreach (['id', 'from_at', 'to_at', 'recorded_us', 'partial_day'] as $field) {
        if (!isset($resource->index->getParameters('output')->{$field})) {
            return null;
        }
    }
    foreach (['vps', 'days'] as $field) {
        if (!isset($resource->index->getParameters('input')->{$field})) {
            return null;
        }
    }
    return $resource;
}

function vps_pressure_history_page($vps): void
{
    global $xtpl;
    $resource = vps_pressure_history_resource();
    if (!$resource) {
        $xtpl->parsed_blocks['main.table'] .= '<p>' . h(_('History is unavailable.')) . '</p>';
        return;
    }
    try {
        $days = $_GET['pressure_days'] ?? '7';
        if (!is_string($days) || !in_array($days, ['7', '30'], true)) {
            throw new InvalidArgumentException();
        }
        $rows = $resource->index(['vps' => (int) $vps->id, 'days' => (int) $days]);
        $meta = (array) $rows->getMeta();
        foreach (['available', 'timezone', 'total_recorded_us', 'ownership_limited'] as $field) {
            if (!array_key_exists($field, $meta)) {
                throw new RuntimeException();
            }
        }
        if ($meta['available'] !== true || $meta['timezone'] !== 'UTC') {
            $xtpl->parsed_blocks['main.table'] .= '<p>' . h(_('History is unavailable.')) . '</p>';
            return;
        }
        $xtpl->table_title(_('History'));
        $xtpl->form_create('', 'get', 'vps-pressure-history', false);
        $xtpl->form_set_hidden_fields(['page' => 'adminvps', 'action' => 'evidence', 'veid' => (int) $vps->id]);
        $xtpl->form_add_select(_('Period') . ':', 'pressure_days', ['7' => _('Last 7 days'), '30' => _('Last 30 days')], $days);
        $xtpl->form_out(_('Show'));
        $xtpl->table_title(_('History'));
        foreach ([_('Date (UTC)'), _('Recorded time'), _('Observation')] as $label) {
            $xtpl->table_add_category(h($label));
        }
        foreach ($rows as $item) {
            $row = vps_incident_attributes($item);
            $xtpl->table_td(h($row['id']));
            $xtpl->table_td($row['recorded_us'] === null ? h(_('No recorded data')) : vps_evidence_duration($row['recorded_us']));
            $xtpl->table_td($row['partial_day'] === true ? h(_('Today (partial day)')) : '');
            $xtpl->table_tr();
        }
        $xtpl->table_td(h(_('Recorded time')), false, false, 1);
        $xtpl->table_td($meta['total_recorded_us'] === null ? h(_('No recorded data')) : vps_evidence_duration($meta['total_recorded_us']), false, false, 2);
        $xtpl->table_tr();
        $xtpl->table_out();
        if ($meta['ownership_limited'] === true) {
            $xtpl->parsed_blocks['main.table'] .= '<p>' . h(_('History for the current owner')) . '</p>';
        }
    } catch (InvalidArgumentException $e) {
        $xtpl->perex(_('Invalid filter value.'), '');
    } catch (\HaveAPI\Client\Exception\Base|RuntimeException $e) {
        $xtpl->perex(_('History is unavailable.'), '');
    }
}
