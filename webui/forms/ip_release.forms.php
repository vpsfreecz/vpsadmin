<?php

const IP_RELEASE_MAX_ADDRESSES = 100;

function ip_release_url($action, $id = null)
{
    return '?page=ip_release&action=' . $action . ($id === null ? '' : '&id=' . (int) $id);
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

function ip_release_button($action, $id, $label, $fields = [])
{
    $html = '<form method="post" action="' . h(ip_release_url($action, $id)) . '">'
        . '<input type="hidden" name="csrf_token" value="' . h(csrf_token()) . '">';
    foreach ($fields as $name => $value) {
        $html .= '<input type="hidden" name="' . h($name) . '" value="' . h($value) . '">';
    }
    return $html . '<button type="submit">' . h($label) . '</button></form>';
}

function ip_release_list()
{
    global $api, $xtpl;

    $xtpl->title(_('IP release campaigns'));
    if (isAdmin()) {
        $xtpl->sbar_add(_('Create campaign'), ip_release_url('new'), 'ip-release.create');
        $action = $api->ip_release_campaign->list;
    } else {
        $action = $api->ip_release_request->list;
    }
    $rows = $action(['limit' => api_get_uint('limit', 25), 'from_id' => api_get_uint('from_id', 0)]);
    $pagination = new \Pagination\System($rows);
    $xtpl->table_title(_('IP release campaigns'), 'ip-release.list');
    foreach ([_('Campaign'), _('Planned release date'), _('User opt-outs'), _('State')] as $label) {
        $xtpl->table_td($label);
    }
    $xtpl->table_tr();
    foreach ($rows as $row) {
        $xtpl->table_td('<a href="' . h(ip_release_url(isAdmin() ? 'show' : 'request', $row->id)) . '">' . h($row->label) . '</a>');
        $xtpl->table_td(h(tolocaltz($row->deadline, 'Y-m-d H:i T')));
        $xtpl->table_td($row->allow_keep ? _('Allowed') : _('Disabled'));
        $xtpl->table_td($row->closed_at ? _('Closed') : _('Open'));
        $xtpl->table_tr();
    }
    $xtpl->table_pagination($pagination);
    $xtpl->table_out();
}

function ip_release_edit_fields($campaign = null)
{
    global $xtpl;

    $xtpl->form_add_input(_('Label'), 'text', 45, 'label', $_POST['label'] ?? $campaign?->label ?? '');
    $xtpl->form_add_input(
        _('Planned release date'),
        'text',
        30,
        'deadline',
        $_POST['deadline'] ?? ($campaign ? tolocaltz($campaign->deadline, 'Y-m-d H:i') : date('Y-m-d H:i', time() + 604800)),
        h(date_default_timezone_get())
    );
    $xtpl->form_add_checkbox(
        _('Allow user opt-outs'),
        'allow_keep',
        '1',
        $_SERVER['REQUEST_METHOD'] === 'POST' ? isset($_POST['allow_keep']) : ($campaign?->allow_keep ?? true)
    );
}

function ip_release_new()
{
    global $api, $xtpl;

    $xtpl->title(_('Create IP release campaign'));
    $xtpl->table_title(_('Filters'));
    $xtpl->form_create('', 'get', 'ip-release-filter', false);
    $xtpl->form_set_hidden_fields(['page' => 'ip_release', 'action' => 'new', 'preview' => '1']);
    $xtpl->form_add_select(_('IP version'), 'version', [4 => 'IPv4', 6 => 'IPv6'], get_val('version', 4));
    foreach (['user' => _('User ID'), 'network' => _('Network ID'), 'location' => _('Location ID')] as $key => $label) {
        $xtpl->form_add_input($label, 'text', 12, $key, get_val($key));
    }
    $xtpl->form_out(_('Preview addresses'));
    if (empty($_GET['preview'])) {
        return;
    }

    $limit = min(IP_RELEASE_MAX_ADDRESSES, max(1, api_get_uint('limit', IP_RELEASE_MAX_ADDRESSES)));
    $_GET['limit'] = $limit;
    $params = ['version' => (int) ($_GET['version'] ?? 4), 'limit' => $limit, 'from_id' => api_get_uint('from_id', 0)];
    foreach (['user', 'network', 'location'] as $key) {
        if (!empty($_GET[$key])) {
            $params[$key] = (int) $_GET[$key];
        }
    }
    $ips = $api->ip_release_campaign->candidates($params);
    $pagination = new \Pagination\System($ips);
    $xtpl->perex(_('Selection'), _('Each campaign can contain up to 100 allocations. Select addresses from this page; use another campaign for additional pages.'));
    $xtpl->table_title(_('Create campaign'));
    $xtpl->form_create(ip_release_url('create'), 'post', 'ip-release-create');
    ip_release_edit_fields();
    $count = 0;
    $units = 0;
    $users = [];
    foreach ($ips as $ip) {
        $count++;
        $units += $params['version'] === 4 ? $ip->size : 0;
        $users[$ip->user->id] = true;
        $xtpl->form_add_checkbox(
            h($ip->addr . '/' . $ip->prefix . ' (' . $ip->user->login . ')'),
            'addresses[]',
            $ip->id,
            true
        );
    }
    $xtpl->table_td('<input type="hidden" name="selection_complete" value="1">');
    $xtpl->table_tr();
    $xtpl->table_pagination($pagination);
    $xtpl->form_out(_('Create campaign'), 'ip-release-create');
    $xtpl->perex(_('Preview'), h(sprintf(_('Allocations: %d; users: %d; IPv4 addresses: %s'), $count, count($users), $units)));
}

function ip_release_show($id)
{
    global $api, $xtpl;

    $campaign = $api->ip_release_campaign->show($id);
    $xtpl->title(h($campaign->label));
    $xtpl->table_title(_('Campaign settings'));
    if (!$campaign->closed_at) {
        $xtpl->form_create(ip_release_url('update', $id), 'post', 'ip-release-edit');
        ip_release_edit_fields($campaign);
        $xtpl->form_out(_('Save changes'));
        $xtpl->perex(_('Notifications'), _('Saving changes does not send email. Policy changes apply to future release attempts.')
            . ip_release_button('notify', $id, _('Send initial notices'), ['event' => 'requested'])
            . ip_release_button('notify', $id, _('Send reminders'), ['event' => 'reminder']));
        $warning = strtotime($campaign->deadline) > time()
            ? '<p>' . _('The planned release date has not arrived. You can still release eligible addresses now.') . '</p>' : '';
        $xtpl->perex(_('Release campaign'), $warning
            . '<p>' . _('This action checks all addresses using the current policy. Assigned and admin-exempt addresses are retained.') . '</p>'
            . '<p>' . _('Addresses being released cannot be retained. If cleanup fails, ownership is kept and an admin can try again.') . '</p>'
            . ip_release_button('release', $id, _('Release eligible addresses')));
        $xtpl->perex(_('Close campaign'), ip_release_button('close', $id, _('Close campaign')));
    } else {
        $xtpl->perex(_('Closed'), h(tolocaltz($campaign->closed_at, 'Y-m-d H:i T')));
    }
    $requests = $api->ip_release_request->list([
        'ip_release_campaign' => $id,
        'limit' => api_get_uint('limit', 25),
        'from_id' => api_get_uint('from_id', 0),
    ]);
    foreach ($requests as $request) {
        ip_release_request_details($request);
    }
    $xtpl->table_title(_('Requests'));
    $xtpl->table_pagination(new \Pagination\System($requests));
    $xtpl->table_out();
}

function ip_release_request_details($request)
{
    global $api, $xtpl;

    $id = $request->id;
    $addresses = $api->ip_release_request($id)->address->list(['limit' => IP_RELEASE_MAX_ADDRESSES]);
    $title = isAdmin()
        ? h($request->user_login ?? sprintf(_('Deleted user #%d'), $request->original_user_id))
        : h($request->label);
    $xtpl->perex($title, _('Planned release date') . ': ' . h(tolocaltz($request->deadline, 'Y-m-d H:i T'))
        . '<br>' . _('Last notice queued') . ': ' . h(tolocaltz($request->notified_at, 'Y-m-d H:i T')));
    if (!$request->closed_at) {
        $xtpl->perex(_('Keeping IP addresses'), $request->allow_keep
            ? _('Assign an address to a VPS or select it below and enter a reason to keep it.')
            : _('Assign an address to a VPS to keep it. Keeping an unassigned address requires an admin exemption; user reasons do not prevent release under the current policy.'));
    }

    $canKeep = !isAdmin() && $request->allow_keep && !$request->closed_at;
    $xtpl->table_title(isAdmin() ? $title . ': ' . _('IP addresses') : _('IP addresses'), 'ip-release.addresses');
    if ($canKeep) {
        $xtpl->form_create(ip_release_url('keep', $id), 'post', 'ip-release-keep');
    }
    foreach ([_('IP address'), _('Current status'), _('User reason'), _('Admin exemption'), _('Last release result')] as $label) {
        $xtpl->table_td($label);
    }
    $xtpl->table_tr();
    foreach ($addresses as $item) {
        $address = h($item->address . '/' . $item->prefix);
        if ($canKeep && !$item->released_at && !in_array($item->protection, ['changed', 'releasing'], true)) {
            $address = '<label><input type="checkbox" name="addresses[]" value="' . (int) $item->id . '"> ' . $address . '</label>';
        }
        if (!$item->released_at && !in_array($item->protection, ['changed', 'assigned', 'releasing'], true) && $item->ip_address_id) {
            $address .= '<br><a href="?page=networking&action=route_assign&id=' . (int) $item->ip_address_id
                . '&return=' . rawurlencode(ip_release_url('request', $id)) . '">' . _('Assign to a VPS') . '</a>';
        }
        $xtpl->table_td($address);
        $status = ip_release_result_label($item->protection);
        if ($item->exclusion_reason) {
            $status .= '<br>' . ip_release_exclusion_label($item->exclusion_reason);
        }
        $xtpl->table_td($status);
        $xtpl->table_td(nl2br(h($item->keep_reason ?? '')));
        $exemption = nl2br(h($item->exemption_reason ?? ''));
        if (isAdmin() && !$request->closed_at && !$item->released_at && !in_array($item->protection, ['changed', 'releasing'], true)) {
            $exemption .= '<form method="post" action="' . h(ip_release_url('exempt', $id)) . '">'
                . '<input type="hidden" name="csrf_token" value="' . h(csrf_token()) . '">'
                . '<input type="hidden" name="address" value="' . (int) $item->id . '">'
                . '<textarea name="reason" maxlength="2000" aria-label="' . h(_('Admin exemption reason')) . '">' . h($item->exemption_reason ?? '') . '</textarea>'
                . '<button type="submit">' . _('Set exemption') . '</button>'
                . '<button type="submit" name="remove" value="1">' . _('Remove exemption') . '</button></form>';
        }
        $xtpl->table_td($exemption);
        $result = ip_release_result_label($item->last_result);
        if ($item->released_at) {
            $result .= '<br>' . h(tolocaltz($item->released_at, 'Y-m-d H:i T'));
        }
        if ($item->cleanup_state) {
            $result .= '<br>' . _('Cleanup') . ': ' . h($item->cleanup_state);
        }
        if (isAdmin()) {
            $result .= '<br>' . h($item->last_error ?? '');
            if ($item->release_chain_id) {
                $result .= '<br><a href="?page=transactions&chain=' . (int) $item->release_chain_id . '">' . _('Transaction chain') . '</a>';
            }
        }
        $xtpl->table_td($result);
        $xtpl->table_tr();
    }
    if ($canKeep) {
        $xtpl->form_add_textarea(_('Reason for keeping the selected IPs'), 60, 4, 'reason');
        $xtpl->table_td('<input type="hidden" name="selection_complete" value="1">');
        $xtpl->table_tr();
        $xtpl->form_out(_('Keep selected IPs'));
    } else {
        $xtpl->table_out();
    }

    $xtpl->perex(_('Notice history'), '<a href="' . h(ip_release_url('notices', $id)) . '">' . $title . ': ' . _('Notice history') . '</a>');
}

function ip_release_notice_history($request)
{
    global $api, $xtpl;

    $xtpl->title(h($request->label));
    $xtpl->sbar_add(_('IP release request'), ip_release_url('request', $request->id));
    $notices = $api->ip_release_request($request->id)->notice->list([
        'limit' => api_get_uint('limit', 25),
        'from_id' => api_get_uint('from_id', 0),
    ]);
    $xtpl->table_title(_('Notice history'), 'ip-release.notices');
    foreach ([_('Queued at'), _('Notice type'), _('Subject')] as $label) {
        $xtpl->table_td($label);
    }
    if (isAdmin()) {
        $xtpl->table_td(_('Queued by'));
    }
    $xtpl->table_tr();
    foreach ($notices as $notice) {
        $xtpl->table_td(h(tolocaltz($notice->created_at, 'Y-m-d H:i T')));
        $xtpl->table_td($notice->event === 'requested' ? _('Initial notice') : _('Reminder'));
        $xtpl->table_td(h($notice->subject));
        if (isAdmin()) {
            $xtpl->table_td(h($notice->created_by_login ?? _('Deleted user')));
        }
        $xtpl->table_tr();
    }
    $xtpl->table_pagination(new \Pagination\System($notices));
    $xtpl->table_out();
}
