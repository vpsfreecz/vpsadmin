<?php

require_once __DIR__ . '/../lib/ip_release_selection.lib.php';

const IP_RELEASE_PAGE_SIZE = IpReleaseSelection::PAGE_SIZE;

function ip_release_url($action, $id = null)
{
    return '?page=ip_release&action=' . $action . ($id === null ? '' : '&id=' . (int) $id);
}

function ip_release_title($id)
{
    return sprintf(_('IP release campaign #%d'), $id);
}

function ip_release_clear_form_context()
{
    global $xtpl;

    $xtpl->assign('TABLE_FORM_BEGIN', '');
    $xtpl->assign('FORM_CSRF_TOKEN', '');
    $xtpl->assign('FORM_HIDDEN_FIELDS', '');
    $xtpl->assign('TABLE_FORM_END', '');
}

function ip_release_result_label($value)
{
    $labels = [
        'eligible' => _('Eligible for release'),
        'assigned' => _('Assigned to an interface'),
        'exported' => _('Used by an export'),
        'kept' => _('Kept with a reason'),
        'exempted' => _('Exempted by an admin'),
        'changed' => _('Excluded: owner or allocation changed'),
        'released' => _('Released'),
        'releasing' => _('Release in progress'),
        'failed' => _('Release failed'),
    ];
    return h($labels[$value] ?? $value ?? '-');
}

function ip_release_exclusion_label($reason)
{
    $labels = [
        'owner_deleted' => _('The original user was deleted.'),
        'address_missing' => _('The original IP allocation no longer exists.'),
        'owner_changed' => _('The IP address no longer belongs to the original user.'),
        'allocation_changed' => _('The original IP allocation changed.'),
    ];
    return h($labels[$reason] ?? $reason);
}

function ip_release_sbar($campaign = null, $request = null)
{
    global $xtpl;

    $xtpl->sbar_add(isAdmin() ? _('Cluster') : _('Networking'), isAdmin() ? '?page=cluster' : '?page=networking');
    $xtpl->sbar_add(isAdmin() ? _('IP release campaigns') : _('IP release requests'), ip_release_url('list'));
    if (isAdmin()) {
        $xtpl->sbar_add(_('Create campaign'), ip_release_url('new'), 'ip-release.create');
    }
    if ($campaign) {
        $xtpl->sbar_add(_('Campaign details'), ip_release_url('show', $campaign->id));
        $xtpl->sbar_add(_('Notice history'), ip_release_url('campaign_notices', $campaign->id));
    } elseif ($request) {
        $xtpl->sbar_add(_('IP release request'), ip_release_url('request', $request->id));
        $xtpl->sbar_add(_('Notice history'), ip_release_url('notices', $request->id));
    }
    $xtpl->sbar_out(_('Navigation'));
    if ($campaign && !$campaign->closed_at) {
        $xtpl->sbar_add(_('Edit campaign'), ip_release_url('edit', $campaign->id));
        if ($campaign->can_send_initial_notices) {
            $xtpl->sbar_add(_('Send initial notices'), ip_release_url('notify', $campaign->id));
        }
        if ($campaign->can_send_reminders) {
            $xtpl->sbar_add(_('Send reminders'), ip_release_url('notify', $campaign->id) . '&event=reminder');
        }
        if ($campaign->can_release) {
            $xtpl->sbar_add(_('Release eligible addresses'), ip_release_url('release', $campaign->id));
        }
        $xtpl->sbar_add(_('Close without releasing IPs'), ip_release_url('close', $campaign->id));
        $xtpl->sbar_out(ip_release_title($campaign->id));
    }
}

function ip_release_info($label, $value, $columns = 2)
{
    global $xtpl;

    $xtpl->table_td(h($label));
    $xtpl->table_td($value, false, false, $columns - 1);
    $xtpl->table_tr();
}

function ip_release_user($id, $login)
{
    if (!$id) {
        return '-';
    }
    if (!$login) {
        return h(sprintf(_('Deleted user #%d'), $id));
    }
    return '<a href="?page=adminm&action=edit&id=' . (int) $id . '">' . h($login) . '</a> (#' . (int) $id . ')';
}

function ip_release_list()
{
    global $api, $xtpl;

    $xtpl->title(isAdmin() ? _('IP release campaigns') : _('IP release requests'));
    $action = isAdmin() ? $api->ip_release_campaign->list : $api->ip_release_request->list;
    $rows = $action->call(['limit' => api_get_uint('limit', 25), 'from_id' => api_get_uint('from_id', 0)]);
    $xtpl->table_title(isAdmin() ? _('IP release campaigns') : _('IP release requests'), 'ip-release.list');
    foreach (isAdmin() ? [_('Campaign'), _('Planned release date'), _('User opt-outs'), _('State')] : [_('IP release request'), _('Planned release date')] as $label) {
        $xtpl->table_add_category($label);
    }
    foreach ($rows as $row) {
        $xtpl->table_td('<a href="' . h(ip_release_url(isAdmin() ? 'show' : 'request', $row->id)) . '">' . h(isAdmin() ? ip_release_title($row->id) : _('IP release request')) . '</a>');
        $xtpl->table_td(h(tolocaltz($row->deadline, 'Y-m-d H:i T')));
        if (isAdmin()) {
            $xtpl->table_td($row->allow_keep ? _('Allowed') : _('Disabled'));
            $xtpl->table_td($row->closed_at ? _('Closed') : _('Open'));
        }
        $xtpl->table_tr();
    }
    if (!count($rows)) {
        $xtpl->table_td(isAdmin() ? _('No IP release campaigns.') : _('No IP release requests.'), false, false, isAdmin() ? 4 : 2);
        $xtpl->table_tr();
    }
    $xtpl->table_pagination(new \Pagination\System($rows));
    $xtpl->table_out();
}

function ip_release_edit_fields($campaign = null, $saved = [])
{
    global $xtpl;

    $values = $_SERVER['REQUEST_METHOD'] === 'POST' ? $_POST : $saved;

    $xtpl->form_add_input(
        _('Planned release date'),
        'text',
        30,
        'deadline',
        $values['deadline'] ?? ($campaign ? tolocaltz($campaign->deadline, 'Y-m-d H:i') : date('Y-m-d H:i', time() + 604800)),
        h(date_default_timezone_get())
    );
    $xtpl->form_add_checkbox(
        _('Allow user opt-outs'),
        'allow_keep',
        '1',
        ($_SERVER['REQUEST_METHOD'] === 'POST' || isset($values['deadline'])) ? isset($values['allow_keep']) : ($campaign?->allow_keep ?? true)
    );
}

function ip_release_selection_header()
{
    return '<label><input type="checkbox" data-select-all> '
        . h(_('Select all')) . '</label>';
}

function ip_release_checkbox($id, $checked = false, $owner = null, $ipv4Size = 0)
{
    return '<input type="checkbox" name="addresses[]" value="' . (int) $id . '"' . ($checked ? ' checked' : '')
        . ($owner === null ? '' : ' data-owner="' . (int) $owner . '" data-ipv4-size="' . h((string) $ipv4Size) . '"')
        . ' aria-label="' . h(_('Select address')) . '">';
}

function ip_release_selected($id, $default = false)
{
    return $_SERVER['REQUEST_METHOD'] === 'POST'
        ? in_array((string) $id, array_map('strval', is_array($_POST['addresses'] ?? null) ? $_POST['addresses'] : []), true)
        : $default;
}

function ip_release_selection_end($columns)
{
    global $xtpl;

    // Keep this marker after the address inputs so truncated PHP submissions fail.
    $xtpl->table_td(<<<'HTML'
        <input type="hidden" name="selection_complete" value="1">
        <script>
        (() => {
            const form = document.currentScript.closest('form');
            const inputs = Array.from(form.querySelectorAll('input[name="addresses[]"]:not(:disabled)'));
            const all = form.querySelector('[data-select-all]');
            const update = () => {
                all.checked = inputs.length > 0 && inputs.every(input => input.checked);
                all.indeterminate = !all.checked && inputs.some(input => input.checked);
                const summary = form.querySelector('[data-ip-release-summary]');
                if (summary) {
                    const base = JSON.parse(summary.dataset.base);
                    const users = new Set(base.users.map(String));
                    let count = base.count;
                    let units = base.units;
                    inputs.filter(input => input.checked).forEach(input => {
                        count++;
                        users.add(input.dataset.owner);
                        units += Number(input.dataset.ipv4Size);
                    });
                    const values = [base.matches, count, users.size, units];
                    summary.textContent = summary.dataset.format.replace(/%[ds]/g, () => String(values.shift()));
                }
            };
            all.disabled = inputs.length === 0;
            all.addEventListener('change', () => {
                inputs.forEach(input => input.checked = all.checked);
                update();
            });
            inputs.forEach(input => input.addEventListener('change', update));
            update();
        })();
        </script>
        HTML, false, false, $columns);
    $xtpl->table_tr();
}

function ip_release_all_rows($action, $params = [])
{
    $rows = [];
    $from = 0;
    do {
        $page = $action->call(array_merge($params, ['limit' => IP_RELEASE_PAGE_SIZE, 'from_id' => $from]));
        foreach ($page as $row) {
            $rows[] = $row;
            $from = $row->id;
        }
    } while (count($page) === IP_RELEASE_PAGE_SIZE);
    return $rows;
}

function ip_release_candidate_params(array $filters): array
{
    // The pinned PHP client supports scalar GET parameters.
    foreach (['versions', 'networks', 'locations'] as $name) {
        $filters[$name] = implode(',', $filters[$name]);
    }
    return $filters;
}

function ip_release_filters()
{
    $filters = [];
    foreach (['versions' => [4], 'networks' => [], 'locations' => []] as $name => $default) {
        $values = $_GET['ip_release_' . $name] ?? $default;
        if (!is_array($values)) {
            throw new InvalidArgumentException(_('Invalid filter value.'));
        }
        foreach ($values as $value) {
            if ((!is_string($value) && !is_int($value)) || !ctype_digit((string) $value) || (int) $value <= 0) {
                throw new InvalidArgumentException(_('Invalid filter value.'));
            }
        }
        $filters[$name] = array_values(array_unique(array_map('intval', $values)));
    }
    // An empty multi-select is omitted by the browser: both versions means all.
    if (isset($_GET['preview']) && !isset($_GET['ip_release_versions'])) {
        $filters['versions'] = [4, 6];
    }
    $filters['access'] = $_GET['access'] ?? 'public_access';
    if (!is_string($filters['access']) || !in_array($filters['access'], ['public_access', 'private_access', 'all'], true)) {
        throw new InvalidArgumentException(_('Invalid filter value.'));
    }
    if (isset($_GET['user']) && $_GET['user'] !== '') {
        if (!is_string($_GET['user']) || !ctype_digit($_GET['user']) || (int) $_GET['user'] <= 0) {
            throw new InvalidArgumentException(_('Enter a positive user ID.'));
        }
        $filters['user'] = (int) $_GET['user'];
    }
    return $filters;
}

function &ip_release_preview()
{
    $token = $_GET['selection'] ?? '';
    if (!is_string($token) || !isset($_SESSION['ip_release_previews'][$token])
        || $_SESSION['ip_release_previews'][$token]['owner'] !== (int) $_SESSION['user']['id']) {
        throw new InvalidArgumentException(_('This address selection is no longer available. Preview the addresses again.'));
    }
    return $_SESSION['ip_release_previews'][$token];
}

function ip_release_new()
{
    global $api, $xtpl;

    $xtpl->title(_('Create IP release campaign'));
    $state = isset($_GET['selection']) ? ip_release_preview() : null;
    $filters = $state ? $state['filters'] : ip_release_filters();
    $networks = ip_release_all_rows($api->network->list);
    $networkById = [];
    foreach ($networks as $network) {
        $networkById[$network->id] = $network;
    }
    $xtpl->table_title(_('Filters'));
    $xtpl->form_create('', 'get', 'ip-release-filter', false);
    $xtpl->form_set_hidden_fields(['page' => 'ip_release', 'action' => 'new', 'preview' => '1']);
    $xtpl->form_add_select(_('IP versions'), 'ip_release_versions[]', [4 => 'IPv4', 6 => 'IPv6'], $filters['versions'], '', true, 2);
    $xtpl->form_add_input(_('User ID'), 'text', 12, 'user', $filters['user'] ?? '');
    $xtpl->form_add_select(_('Networks'), 'ip_release_networks[]', resource_list_to_options($networks, 'id', 'label', false, 'network_label'), $filters['networks'], _('Leave empty to include all networks.'), true, 8);
    $xtpl->form_add_select(_('Locations'), 'ip_release_locations[]', resource_list_to_options(ip_release_all_rows($api->location->list), 'id', 'label', false), $filters['locations'], _('Leave empty to include all locations.'), true, 5);
    $xtpl->form_add_select(_('Access'), 'access', ['public_access' => _('Public'), 'private_access' => _('Private'), 'all' => _('Both')], $filters['access']);
    ip_release_info(_('Selection'), h(_('Only user-owned, unassigned addresses not used by other services are included.')));
    $xtpl->form_out(_('Preview addresses'));
    ip_release_clear_form_context();
    if (!$state && empty($_GET['preview'])) {
        return;
    }
    if (!$state) {
        $rows = [];
        foreach (ip_release_all_rows($api->ip_release_campaign->candidates, ip_release_candidate_params($filters)) as $ip) {
            $network = $networkById[$ip->network_id];
            $rows[] = ['id' => (int) $ip->id, 'address' => $ip->addr . '/' . $ip->prefix,
                'version' => $network->ip_version, 'size' => $ip->size,
                'user_id' => $ip->user->id, 'user_login' => $ip->user->login,
                'network' => network_label($network), 'location' => $network->primary_location?->label ?? '-'];
        }
        $token = bin2hex(random_bytes(16));
        $_SESSION['ip_release_previews'] ??= [];
        // Bound abandoned previews in this browser session, not campaign size.
        while (count($_SESSION['ip_release_previews']) >= 10) {
            array_shift($_SESSION['ip_release_previews']);
        }
        $_SESSION['ip_release_previews'][$token] = IpReleaseSelection::create($rows, $filters, (int) $_SESSION['user']['id']);
        redirect(ip_release_url('new') . '&selection=' . $token);
        return;
    }
    $page = min(api_get_uint('preview_page', 0), max(0, (int) ceil(count($state['rows']) / IP_RELEASE_PAGE_SIZE) - 1));
    $selectionUrl = '&selection=' . rawurlencode($_GET['selection']) . '&preview_page=' . $page;
    $xtpl->table_title(_('Campaign settings'));
    $xtpl->form_create(ip_release_url('create') . $selectionUrl, 'post', 'ip-release-create');
    ip_release_edit_fields(null, $state['settings']);
    ip_release_info(_('Notices'), h(_('Creating a campaign does not send email. Send initial notices from the campaign sidebar.')));
    $xtpl->table_out();
    ip_release_clear_form_context();
    $xtpl->table_title(_('IP addresses'));
    $xtpl->table_add_category('');
    foreach ([_('IP address'), _('User'), _('Network'), _('Location')] as $label) {
        $xtpl->table_add_category($label);
    }
    $selectionAction = h(ip_release_url('selection') . $selectionUrl);
    $xtpl->table_td(ip_release_selection_header() . ' <button type="submit" name="selection_action" value="all" formaction="' . $selectionAction . '">' . _('Select all matches') . '</button> '
        . '<button type="submit" name="selection_action" value="none" formaction="' . $selectionAction . '">' . _('Clear selection') . '</button>', false, false, 5);
    $xtpl->table_tr();
    $pageRows = IpReleaseSelection::page($state, $page);
    foreach ($pageRows as $ip) {
        $xtpl->table_td(ip_release_checkbox($ip['id'], isset($state['selected'][$ip['id']]), $ip['user_id'], $ip['version'] == 4 ? $ip['size'] : 0));
        $xtpl->table_td(h($ip['address']));
        $xtpl->table_td(ip_release_user($ip['user_id'], $ip['user_login']));
        $xtpl->table_td(h($ip['network']));
        $xtpl->table_td(h($ip['location']));
        $xtpl->table_tr();
    }
    if (!$state['rows']) {
        $xtpl->table_td(_('No eligible addresses match these filters.'), false, false, 5);
        $xtpl->table_tr();
    }
    $base = ['matches' => count($state['rows']), 'count' => 0, 'users' => [], 'units' => 0];
    $selectedUsers = [];
    $selectedUnits = 0;
    $pageIds = array_fill_keys(array_column($pageRows, 'id'), true);
    foreach ($state['rows'] as $row) {
        if (!isset($state['selected'][$row['id']])) {
            continue;
        }
        $selectedUsers[$row['user_id']] = true;
        $selectedUnits += $row['version'] == 4 ? $row['size'] : 0;
        if (!isset($pageIds[$row['id']])) {
            $base['count']++;
            $base['users'][] = (int) $row['user_id'];
            $base['units'] += $row['version'] == 4 ? $row['size'] : 0;
        }
    }
    $base['users'] = array_values(array_unique($base['users']));
    $summaryFormat = _('Matching allocations: %d; selected: %d; users: %d; IPv4 addresses: %s');
    ip_release_info(_('Preview'), '<span data-ip-release-summary data-base="' . h(json_encode($base)) . '" data-format="' . h($summaryFormat) . '">' . h(sprintf($summaryFormat, count($state['rows']), count($state['selected']), count($selectedUsers), $selectedUnits)) . '</span>', 5);
    $pages = (int) ceil(count($state['rows']) / IP_RELEASE_PAGE_SIZE);
    if ($pages > 1) {
        $links = [];
        for ($i = 0; $i < $pages; $i++) {
            $links[] = '<button type="submit" name="next_page" value="' . $i . '" formaction="' . $selectionAction . '"' . ($i === $page ? ' disabled' : '') . '>' . ($i + 1) . '</button>';
        }
        $xtpl->table_td(implode(' ', $links), false, false, 5);
        $xtpl->table_tr();
    }
    ip_release_selection_end(5);
    $xtpl->form_out(_('Create campaign'), 'ip-release-create', '', 4);
    ip_release_clear_form_context();
}

function ip_release_summary($record)
{
    global $xtpl;

    $xtpl->table_title(_('Campaign settings'));
    ip_release_info(_('Planned release date'), h(tolocaltz($record->deadline, 'Y-m-d H:i T')));
    ip_release_info(_('User opt-outs'), $record->allow_keep ? _('Allowed') : _('Disabled'));
    ip_release_info(_('State'), $record->closed_at ? _('Closed') . ' (' . h(tolocaltz($record->closed_at, 'Y-m-d H:i T')) . ')' : _('Open'));
    $xtpl->table_out();
}

function ip_release_edit($campaign)
{
    global $xtpl;

    $xtpl->title(h(ip_release_title($campaign->id)));
    $xtpl->table_title(_('Edit campaign'));
    $xtpl->form_create(ip_release_url('update', $campaign->id), 'post', 'ip-release-edit');
    ip_release_edit_fields($campaign);
    ip_release_info(_('Policy'), h(_('Saving changes does not send email. Policy changes apply to future release attempts.')));
    $xtpl->form_out(_('Save changes'));
    ip_release_clear_form_context();
}

function ip_release_action_form($campaign, $action)
{
    global $xtpl;

    $xtpl->title(h(ip_release_title($campaign->id)));
    ip_release_summary($campaign);
    $event = ($_POST['event'] ?? $_GET['event'] ?? 'requested') === 'reminder' ? 'reminder' : 'requested';
    if ($action === 'notify') {
        $label = $event === 'reminder' ? _('Send reminders') : _('Send initial notices');
        $description = $event === 'reminder'
            ? _('Send another notice to previously notified users who still have eligible addresses. The reminder uses the current planned release date and policy.')
            : _('Send initial notices to users who have eligible addresses and have not yet been notified.');
    } elseif ($action === 'release') {
        $label = _('Release eligible addresses');
        $description = _('This action checks all addresses using the current policy. Assigned and admin-exempt addresses are retained.');
    } else {
        $label = _('Close without releasing IPs');
        $description = _('Remaining IP addresses stay owned. Closing ends notices, edits, exemptions, user reasons and further release attempts. History is retained, and unreleased addresses can enter another campaign.');
    }
    $xtpl->table_title($label);
    $xtpl->form_create(ip_release_url($action, $campaign->id), 'post', 'ip-release-' . $action);
    if ($action === 'notify') {
        $xtpl->form_set_hidden_fields(['event' => $event]);
    }
    ip_release_info(_('Action'), h($description));
    if ($action === 'release') {
        if (strtotime($campaign->deadline) > time()) {
            ip_release_info(_('Planned release date'), '<strong>' . h(_('The planned release date has not arrived. You can still release eligible addresses now.')) . '</strong>');
        }
        ip_release_info(_('Cleanup'), h(_('Addresses being released cannot be retained. If cleanup fails, ownership is kept and an admin can try again.')));
    } elseif ($action === 'close') {
        ip_release_info(_('Releases in progress'), h(_('Closing does not cancel a release already in progress or undo a completed release. A closed campaign cannot be reopened.')));
    }
    $xtpl->form_out($label);
    ip_release_clear_form_context();
}

function ip_release_reason($reason, $time, $actorId = null, $actorLogin = null)
{
    if ($reason === null) {
        return '';
    }
    $html = nl2br(h($reason));
    if (isAdmin()) {
        $html .= '<br>' . ip_release_user($actorId, $actorLogin);
    }
    return $html . '<br>' . h(tolocaltz($time, 'Y-m-d H:i T'));
}

function ip_release_addresses($record, $addresses, $request = null)
{
    global $xtpl;

    $editable = isAdmin() ? !$record->closed_at : $request->can_keep;
    $columns = (isAdmin() ? 6 : 4) + ($editable ? 1 : 0);
    $xtpl->table_title(_('IP addresses'), 'ip-release.addresses');
    if ($editable) {
        $xtpl->form_create(ip_release_url(isAdmin() ? 'exempt' : 'keep', $record->id) . '&from_id=' . api_get_uint('from_id', 0), 'post', isAdmin() ? 'ip-release-exempt' : 'ip-release-keep');
        $xtpl->table_add_category('');
    }
    $xtpl->table_add_category(_('IP address'));
    if (isAdmin()) {
        $xtpl->table_add_category(_('Original owner'));
    }
    foreach ([_('Current status'), _('User reason'), _('Admin exemption')] as $label) {
        $xtpl->table_add_category($label);
    }
    if (isAdmin()) {
        $xtpl->table_add_category(_('Last release result'));
    }
    if ($editable) {
        $xtpl->table_td(ip_release_selection_header(), false, false, $columns);
        $xtpl->table_tr();
    }
    foreach ($addresses as $item) {
        $selectable = !in_array($item->protection, ['changed', 'releasing', 'released'], true);
        if ($editable) {
            $xtpl->table_td($selectable ? ip_release_checkbox($item->id, ip_release_selected($item->id)) : '');
        }
        $address = h($item->address . '/' . $item->prefix);
        if ($item->location_label) {
            $address .= '<br>(' . h($item->location_label) . ')';
        }
        if ($request && $request->can_assign && $selectable && $item->protection !== 'assigned' && $item->assign_ip_address_id) {
            $address .= '<br><a href="?page=networking&action=route_assign&id=' . (int) $item->assign_ip_address_id
                . '&return=' . rawurlencode(ip_release_url('request', $request->id)) . '">' . _('Assign to a VPS') . '</a>';
        }
        $xtpl->table_td($address);
        if (isAdmin()) {
            $xtpl->table_td(ip_release_user($item->original_user_id, $item->user_login));
        }
        $status = ip_release_result_label($item->protection);
        if (isAdmin() && $item->exclusion_reason) {
            $status .= '<br>' . ip_release_exclusion_label($item->exclusion_reason);
        }
        $xtpl->table_td($status);
        $xtpl->table_td(ip_release_reason($item->keep_reason, $item->kept_at, isAdmin() ? $item->kept_by_id : null, isAdmin() ? $item->kept_by_login : null));
        $xtpl->table_td(ip_release_reason($item->exemption_reason, $item->exempted_at, isAdmin() ? $item->exempted_by_id : null, isAdmin() ? $item->exempted_by_login : null));
        if (isAdmin()) {
            $result = ip_release_result_label($item->last_result);
            if ($item->released_at) {
                $result .= '<br>' . h(tolocaltz($item->released_at, 'Y-m-d H:i T'));
            }
            if ($item->cleanup_state) {
                $result .= '<br>' . _('Cleanup') . ': ' . h($item->cleanup_state);
            }
            $result .= '<br>' . h($item->last_error ?? '');
            if ($item->release_chain_id) {
                $result .= '<br><a href="?page=transactions&chain=' . (int) $item->release_chain_id . '">' . _('Transaction chain') . '</a>';
            }
            $xtpl->table_td($result);
        }
        $xtpl->table_tr();
    }
    $xtpl->table_pagination(new \Pagination\System($addresses, null, ['defaultLimit' => IP_RELEASE_PAGE_SIZE]));
    if ($editable) {
        $placeholder = isAdmin() ? _('Reason for exempting the selected IPs') : _('Reason for keeping the selected IPs');
        $xtpl->table_td('<textarea name="reason" class="ip-release-reason" rows="4" maxlength="2000" placeholder="' . h($placeholder)
            . '" aria-label="' . h(_('Reason')) . '">' . h($_POST['reason'] ?? '') . '</textarea>', false, false, $columns);
        $xtpl->table_tr();
        ip_release_selection_end($columns);
        if (isAdmin()) {
            $xtpl->table_td('<button type="submit">' . _('Set exemption') . '</button> '
                . '<button type="submit" name="remove" value="1">' . _('Remove exemption') . '</button>', false, false, $columns);
            $xtpl->table_tr();
            $xtpl->form_out_raw();
        } else {
            $xtpl->form_out(_('Keep selected IPs'), null, '', $columns - 1);
        }
        ip_release_clear_form_context();
    } else {
        $xtpl->table_out();
    }
}

function ip_release_show($campaign)
{
    global $api, $xtpl;

    $xtpl->title(h(ip_release_title($campaign->id)));
    ip_release_summary($campaign);
    $addresses = $api->ip_release_campaign($campaign->id)->address->list(['limit' => api_get_uint('limit', IP_RELEASE_PAGE_SIZE), 'from_id' => api_get_uint('from_id', 0)]);
    ip_release_addresses($campaign, $addresses);
}

function ip_release_request_details($request, $campaign = null)
{
    global $api, $xtpl;

    $xtpl->title(isAdmin() ? h(ip_release_title($campaign->id)) : _('IP release request'));
    if (isAdmin()) {
        ip_release_summary($campaign);
    }
    $xtpl->table_title(_('IP release request'));
    if (isAdmin()) {
        ip_release_info(_('Original owner'), ip_release_user($request->original_user_id, $request->user_login));
    } else {
        ip_release_info(_('Planned release date'), h(tolocaltz($request->deadline, 'Y-m-d H:i T')));
    }
    if ($request->can_assign) {
        ip_release_info(_('Keeping IP addresses'), h($request->can_keep
            ? _('Assign an address to a VPS or select it below and enter a reason to keep it.')
            : _('Assign an address to a VPS to keep it.')));
    }
    $xtpl->table_out();
    $addresses = $api->ip_release_request($request->id)->address->list(['limit' => api_get_uint('limit', IP_RELEASE_PAGE_SIZE), 'from_id' => api_get_uint('from_id', 0)]);
    ip_release_addresses($campaign ?? $request, $addresses, $request);
}

function ip_release_notice_history($record, $campaign = false)
{
    global $api, $xtpl;

    $xtpl->title($campaign ? h(ip_release_title($record->id)) : _('IP release request'));
    $source = $campaign ? $api->ip_release_campaign($record->id) : $api->ip_release_request($record->id);
    $notices = $source->notice->list(['limit' => api_get_uint('limit', 25), 'from_id' => api_get_uint('from_id', 0)]);
    $xtpl->table_title(_('Notice history'), 'ip-release.notices');
    foreach ([_('Queued at'), _('Notice type'), _('Subject')] as $label) {
        $xtpl->table_add_category($label);
    }
    if (isAdmin()) {
        $xtpl->table_add_category(_('Recipient'));
        $xtpl->table_add_category(_('Queued by'));
    }
    $xtpl->table_td(h(_('Initial notices and reminders queued for this campaign.')), false, false, isAdmin() ? 5 : 3);
    $xtpl->table_tr();
    foreach ($notices as $notice) {
        $xtpl->table_td(h(tolocaltz($notice->created_at, 'Y-m-d H:i T')));
        $xtpl->table_td($notice->event === 'requested' ? _('Initial notice') : _('Reminder'));
        $xtpl->table_td(h($notice->subject));
        if (isAdmin()) {
            $xtpl->table_td(ip_release_user($notice->original_user_id, $notice->user_login));
            $xtpl->table_td(ip_release_user($notice->created_by_id, $notice->created_by_login));
        }
        $xtpl->table_tr();
    }
    if (!count($notices)) {
        $xtpl->table_td(_('No notices have been queued.'), false, false, isAdmin() ? 5 : 3);
        $xtpl->table_tr();
    }
    $xtpl->table_pagination(new \Pagination\System($notices));
    $xtpl->table_out();
}
