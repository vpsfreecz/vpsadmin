<?php

function ip_address_list($page)
{
    global $xtpl, $api;

    $pagination = new \Pagination\System(null, $api->ip_address->list);

    $xtpl->title(_('Routable IP Addresses'));
    $xtpl->table_title(_('Filters'));
    $xtpl->form_create('', 'get', 'ip-filter', false);

    $xtpl->form_set_hidden_fields([
        'page' => $page,
        'action' => 'ip_addresses',
        'list' => '1',
    ]);

    $xtpl->form_add_input(_("Limit") . ':', 'text', '40', 'limit', get_val('limit', '25'), '');

    $versions = [
        0 => 'all',
        4 => '4',
        6 => '6',
    ];

    $xtpl->form_add_input(_("From ID") . ':', 'text', '40', 'from_id', get_val('from_id', '0'), '');
    $xtpl->form_add_select(_("Version") . ':', 'v', $versions, get_val('v', 0));
    $xtpl->form_add_input(_("Prefix") . ':', 'text', '40', 'prefix', get_val('prefix'));

    if (isAdmin()) {
        $xtpl->form_add_input(_("User ID") . ':', 'text', '40', 'user', get_val('user'), _("'unassigned' to list free addresses"));
    }

    $xtpl->form_add_input(_("VPS") . ':', 'text', '40', 'vps', get_val('vps'), _("'unassigned' to list free addresses"));
    $xtpl->form_add_select(
        _("Network") . ':',
        'network',
        resource_list_to_options(
            $api->network->list(['purpose' => 'vps']),
            'id',
            'label',
            true,
            'network_label'
        ),
        get_val('network')
    );
    $xtpl->form_add_select(
        _("Location") . ':',
        'location',
        resource_list_to_options($api->location->list()),
        get_val('location')
    );

    $xtpl->form_out(_('Show'));

    if (!($_GET['list'] ?? false)) {
        return;
    }

    $params = [
        'limit' => get_val('limit', 25),
        'from_id' => get_val('from_id', 0),
        'purpose' => 'vps',
        'meta' => ['includes' => 'user,vps,network'],
    ];

    if (isAdmin()) {
        if ($_GET['user'] === 'unassigned') {
            $params['user'] = null;
        } elseif ($_GET['user']) {
            $params['user'] = $_GET['user'];
        }
    }

    if ($_GET['vps'] === 'unassigned') {
        $params['vps'] = null;
    } elseif ($_GET['vps']) {
        $params['vps'] = $_GET['vps'];
    }

    if ($_GET['network']) {
        $params['network'] = $_GET['network'];
    }

    if ($_GET['location']) {
        $params['location'] = $_GET['location'];
    }

    if ($_GET['v']) {
        $params['version'] = $_GET['v'];
    }

    if ($_GET['prefix']) {
        $params['prefix'] = $_GET['prefix'];
    }

    $ips = $api->ip_address->list($params);
    $pagination->setResourceList($ips);

    $xtpl->table_add_category(_("Network"));
    $xtpl->table_add_category(_("IP address"));
    $xtpl->table_add_category(_("Size"));

    if (isAdmin()) {
        $xtpl->table_add_category(_('User'));
    } else {
        $xtpl->table_add_category(_('Owned'));
    }

    $xtpl->table_add_category('VPS');
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');

    $return_url = urlencode($_SERVER['REQUEST_URI']);

    foreach ($ips as $ip) {
        $netif = $ip->network_interface_id ? $ip->network_interface : null;
        $vps = $netif ? $netif->vps : null;

        $xtpl->table_td($ip->network->address . '/' . $ip->network->prefix);
        $xtpl->table_td($ip->addr . '/' . $ip->prefix);
        $xtpl->table_td(approx_number($ip->size), false, true);

        if (isAdmin()) {
            if ($ip->user_id) {
                $xtpl->table_td('<a href="?page=adminm&action=edit&id=' . $ip->user_id . '">' . $ip->user->login . '</a>');
            } else {
                $xtpl->table_td('---');
            }
        } else {
            $xtpl->table_td(boolean_icon($ip->user_id));
        }

        if ($vps) {
            $xtpl->table_td('<a href="?page=adminvps&action=info&veid=' . $vps->id . '">' . $vps->id . ' (' . h($vps->hostname) . ')</a>');
        } else {
            $xtpl->table_td('---');
        }

        $xtpl->table_td('<a href="?page=incidents&action=list&list=1&ip_addr=' . $ip->addr . '&return=' . $return_url . '"><img src="template/icons/bug.png" alt="' . _('List incident reports') . '" title="' . _('List incident reports') . '"></a>');

        $xtpl->table_td('<a href="?page=networking&action=assignments&ip_addr=' . $ip->addr . '&ip_prefix=' . $ip->prefix . '&list=1"><img src="template/icons/vps_ip_list.png" alt="' . _('List assignments') . '" title="' . _('List assignments') . '"></a>');

        $xtpl->table_td(
            '<a href="?page=networking&action=route_edit&id=' . $ip->id . '&return=' . $return_url . '">' .
            '<img src="template/icons/m_edit.png" alt="' . _('Edit') . '" title="' . _('Edit') . '">' .
            '</a>'
        );

        if ($vps) {
            $xtpl->table_td(
                '<a href="?page=networking&action=route_unassign&id=' . $ip->id . '&return=' . $return_url . '">' .
                '<img src="template/icons/m_remove.png" alt="' . _('Remove from VPS') . '" title="' . _('Remove from VPS') . '">' .
                '</a>'
            );

        } else {
            $xtpl->table_td(
                '<a href="?page=networking&action=route_assign&id=' . $ip->id . '&return=' . $return_url . '">' .
                '<img src="template/icons/vps_add.png" alt="' . _('Add to a VPS') . '" title="' . _('Add to a VPS') . '">' .
                '</a>'
            );
        }

        // 		$xtpl->table_td('<a href="?page=cluster&action=ipaddr_delete&ip_id='.$ip->id.'"><img src="template/icons/m_delete.png"  title="'. _("Delete from cluster") .'" /></a>');

        $xtpl->table_tr();
    }

    $xtpl->table_pagination($pagination);
    $xtpl->table_out();
}

function host_ip_address_list($page)
{
    global $xtpl, $api;

    $pagination = new \Pagination\System(null, $api->host_ip_address->list);

    $xtpl->title(_('Host IP Addresses'));
    $xtpl->table_title(_('Filters'));
    $xtpl->form_create('', 'get', 'ip-filter', false);

    $xtpl->form_set_hidden_fields([
        'page' => $page,
        'action' => 'host_ip_addresses',
        'list' => '1',
    ]);

    $xtpl->form_add_input(_("Limit") . ':', 'text', '40', 'limit', get_val('limit', '25'), '');

    $versions = [
        0 => 'all',
        4 => '4',
        6 => '6',
    ];

    $xtpl->form_add_input(_("From ID") . ':', 'text', '40', 'from_id', get_val('from_id', '0'), '');
    $xtpl->form_add_select(_("Version") . ':', 'v', $versions, get_val('v', 0));
    $xtpl->form_add_input(_("Prefix") . ':', 'text', '40', 'prefix', get_val('prefix'));

    if (isAdmin()) {
        $xtpl->form_add_input(_("User ID") . ':', 'text', '40', 'user', get_val('user'), _("'unassigned' to list free addresses"));
    }

    $xtpl->form_add_input(_("VPS") . ':', 'text', '40', 'vps', get_val('vps'), _("'unassigned' to list free addresses"));
    $xtpl->form_add_select(_('Assigned') . ':', 'assigned', [
        'a' => _('All'),
        'y' => _('Yes'),
        'n' => _('No'),
    ], get_val('assigned'));
    $xtpl->form_add_select(
        _("Network") . ':',
        'network',
        resource_list_to_options(
            $api->network->list(['purpose' => 'vps']),
            'id',
            'label',
            true,
            'network_label'
        ),
        get_val('network')
    );
    $xtpl->form_add_select(
        _("Location") . ':',
        'location',
        resource_list_to_options($api->location->list()),
        get_val('location')
    );

    $xtpl->form_out(_('Show'));

    if (!$_GET['list']) {
        return;
    }

    $params = [
        'limit' => get_val('limit', 25),
        'from_id' => get_val('from_id', 0),
        'purpose' => 'vps',
        'meta' => [
            'includes' => 'ip_address__user,ip_address__network_interface__vps,' .
                          'ip_address__network',
        ],
    ];

    if (isAdmin()) {
        if ($_GET['user'] === 'unassigned') {
            $params['user'] = null;
        } elseif ($_GET['user']) {
            $params['user'] = $_GET['user'];
        }
    }

    if ($_GET['vps'] === 'unassigned') {
        $params['vps'] = null;
    } elseif ($_GET['vps']) {
        $params['vps'] = $_GET['vps'];
    }

    if ($_GET['assigned'] == 'y') {
        $params['assigned'] = true;
    } elseif ($_GET['assigned'] == 'n') {
        $params['assigned'] = false;
    }

    if ($_GET['network']) {
        $params['network'] = $_GET['network'];
    }

    if ($_GET['location']) {
        $params['location'] = $_GET['location'];
    }

    if ($_GET['v']) {
        $params['version'] = $_GET['v'];
    }

    if ($_GET['prefix']) {
        $params['prefix'] = $_GET['prefix'];
    }

    $host_addrs = $api->host_ip_address->list($params);
    $pagination->setResourceList($host_addrs);

    $xtpl->table_add_category(_("Network"));
    $xtpl->table_add_category(_("Routed address"));
    $xtpl->table_add_category(_("Host address"));
    $xtpl->table_add_category((_("Reverse record")));

    if (isAdmin()) {
        $xtpl->table_add_category(_('User'));
    } else {
        $xtpl->table_add_category(_('Owned'));
    }

    $xtpl->table_add_category('VPS');
    $xtpl->table_add_category('Interface');
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');

    $return_url = urlencode($_SERVER['REQUEST_URI']);

    foreach ($host_addrs as $host_addr) {
        $ip = $host_addr->ip_address;
        $netif = $ip->network_interface_id ? $ip->network_interface : null;
        $vps = $netif ? $netif->vps : null;

        $xtpl->table_td($ip->network->address . '/' . $ip->network->prefix);
        $xtpl->table_td($ip->addr . '/' . $ip->prefix);
        $xtpl->table_td($host_addr->addr);
        $xtpl->table_td($host_addr->reverse_record_value ? h($host_addr->reverse_record_value) : '-');

        if (isAdmin()) {
            if ($ip->user_id) {
                $xtpl->table_td('<a href="?page=adminm&action=edit&id=' . $ip->user_id . '">' . $ip->user->login . '</a>');
            } else {
                $xtpl->table_td('---');
            }
        } else {
            $xtpl->table_td(boolean_icon($ip->user_id));
        }

        if ($vps) {
            $xtpl->table_td('<a href="?page=adminvps&action=info&veid=' . $vps->id . '">' . $vps->id . ' (' . h($vps->hostname) . ')</a>');
        } else {
            $xtpl->table_td('---');
        }

        if ($netif) {
            $xtpl->table_td($host_addr->assigned ? $netif->name : ('<span style="color: #A6A6A6">' . $netif->name . '</span>'));
        } else {
            $xtpl->table_td('---');
        }

        $xtpl->table_td(
            '<a href="?page=networking&action=hostaddr_ptr&id=' . $host_addr->id . '&return=' . $return_url . '">' .
            '<img src="template/icons/m_edit.png" alt="' . _('Set reverse record') . '" title="' . _('Set reverse record') . '">' .
            '</a>'
        );

        if ($host_addr->assigned) {
            $xtpl->table_td(
                '<a href="?page=networking&action=hostaddr_unassign&id=' . $host_addr->id . '&return=' . $return_url . '">' .
                '<img src="template/icons/m_remove.png" alt="' . _('Remove from interface') . '" title="' . _('Remove from VPS') . '">' .
                '</a>'
            );

        } elseif ($netif) {
            $xtpl->table_td(
                '<a href="?page=networking&action=hostaddr_assign&id=' . $host_addr->id . '&return=' . $return_url . '">' .
                '<img src="template/icons/vps_add.png" alt="' . _('Add to a VPS') . '" title="' . _('Add to a VPS') . '">' .
                '</a>'
            );

        } else {
            $xtpl->table_td('---');
        }

        $xtpl->table_tr();
    }

    $xtpl->table_pagination($pagination);
    $xtpl->table_out();
}

function route_edit_form($id)
{
    global $xtpl, $api;

    $ip = $api->ip_address->show($id);
    $netif = $ip->network_interface_id ? $ip->network_interface : null;
    $vps = $netif ? $netif->vps : null;

    $return_url = urlencode($_SERVER['REQUEST_URI']);

    $xtpl->title(_('IP address') . ' ' . $ip->addr . '/' . $ip->prefix);

    $xtpl->sbar_add(
        _("Back"),
        $_GET['return'] ? $_GET['return'] : '?page=networking&action=ip_addresses'
    );

    $xtpl->sbar_add(_('List assignments'), '?page=networking&action=assignments&ip_addr=' . $ip->addr . '&ip_prefix=' . $ip->prefix . '&list=1');
    $xtpl->sbar_add(_('List incidents'), '?page=incidents&action=list&list=1&ip_addr=' . $ip->addr);

    if ($vps) {
        $xtpl->sbar_add(_('Remove from VPS'), '?page=networking&action=route_unassign&id=' . $ip->id . '&return=' . $return_url);

    } else {
        $xtpl->sbar_add(_('Add to a VPS'), '?page=networking&action=route_assign&id=' . $ip->id . '&return=' . $return_url);
    }

    $xtpl->sbar_out(_('Routed address'));

    $xtpl->table_title(_('Overview'));
    $xtpl->table_td(_('Network') . ':');
    $xtpl->table_td($ip->network->address . '/' . $ip->network->prefix);
    $xtpl->table_tr();

    $xtpl->table_td(_('IP address') . ':');
    $xtpl->table_td($ip->addr . '/' . $ip->prefix);
    $xtpl->table_tr();

    $xtpl->table_td(_('Size') . ':');
    $xtpl->table_td(approx_number($ip->size));
    $xtpl->table_tr();

    $xtpl->table_td(_('User') . ':');
    $xtpl->table_td($ip->user_id ? user_link($ip->user) : '-');
    $xtpl->table_tr();

    if ($vps) {
        $xtpl->table_td(_('VPS') . ':');
        $xtpl->table_td(vps_link($vps) . ' ' . h($vps->hostname));
        $xtpl->table_tr();

        $xtpl->table_td(_('Network interface') . ':');
        $xtpl->table_td($netif->name);
        $xtpl->table_tr();
    }

    $xtpl->table_out();

    if (isAdmin()) {
        $xtpl->table_title(_('Ownership'));
        $xtpl->form_create(
            '?page=networking&action=route_edit_user&id=' . $ip->id . '&return=' . urlencode($_GET['return']),
            'post'
        );

        $xtpl->table_add_category(_('Owner'));
        $xtpl->table_add_category('');

        $xtpl->form_add_input(_('User ID') . ':', 'text', '30', 'user', post_val('user', $ip->user_id));
        $xtpl->form_add_select(
            _('Environment') . ':',
            'environment',
            resource_list_to_options($api->environment->list()),
            post_val('environment')
        );

        $xtpl->form_out(_("Set owner"));
    }

    $host_addrs = $api->host_ip_address->list(['ip_address' => $ip->id]);

    $xtpl->table_title(_('Host addresses'));
    $xtpl->table_add_category(_("Host address"));
    $xtpl->table_add_category((_("Reverse record")));
    $xtpl->table_add_category(_('VPS'));
    $xtpl->table_add_category(_('Interface'));
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');

    foreach ($host_addrs as $host_addr) {
        $ip = $host_addr->ip_address;
        $netif = $ip->network_interface_id ? $ip->network_interface : null;
        $vps = $netif ? $netif->vps : null;

        $xtpl->table_td($host_addr->addr);
        $xtpl->table_td($host_addr->reverse_record_value ? h($host_addr->reverse_record_value) : '-');

        if ($vps) {
            $xtpl->table_td('<a href="?page=adminvps&action=info&veid=' . $vps->id . '">' . $vps->id . ' (' . h($vps->hostname) . ')</a>');
        } else {
            $xtpl->table_td('---');
        }

        if ($netif) {
            $xtpl->table_td($host_addr->assigned ? $netif->name : ('<span style="color: #A6A6A6">' . $netif->name . '</span>'));
        } else {
            $xtpl->table_td('---');
        }

        $xtpl->table_td(
            '<a href="?page=networking&action=hostaddr_ptr&id=' . $host_addr->id . '&return=' . $return_url . '">' .
            '<img src="template/icons/m_edit.png" alt="' . _('Set reverse record') . '" title="' . _('Set reverse record') . '">' .
            '</a>'
        );

        if ($host_addr->assigned) {
            $xtpl->table_td(
                '<a href="?page=networking&action=hostaddr_unassign&id=' . $host_addr->id . '&return=' . $return_url . '">' .
                '<img src="template/icons/m_remove.png" alt="' . _('Remove from interface') . '" title="' . _('Remove from VPS') . '">' .
                '</a>'
            );

        } elseif ($netif) {
            $xtpl->table_td(
                '<a href="?page=networking&action=hostaddr_assign&id=' . $host_addr->id . '&return=' . $return_url . '">' .
                '<img src="template/icons/vps_add.png" alt="' . _('Add to a VPS') . '" title="' . _('Add to a VPS') . '">' .
                '</a>'
            );

        } else {
            $xtpl->table_td('---');
        }

        if ($host_addr->user_created) {
            if ($host_addr->assigned) {
                $xtpl->table_td(
                    '<img src="template/icons/vps_delete_gray.png" alt="' . _('Delete address from vpsAdmin - address in use') . '" title="' . _('Delete address from vpsAdmin - address in use') . '">'
                );
            } else {
                $xtpl->table_td(
                    '<a href="?page=networking&action=hostaddr_delete&id=' . $host_addr->id . '&ip=' . $ip->id . '">' .
                    '<img src="template/icons/vps_delete.png" alt="' . _('Delete address from vpsAdmin') . '" title="' . _('Delete address from vpsAdmin') . '">' .
                    '</a>'
                );
            }
        } else {
            $xtpl->table_td('---');
        }

        $xtpl->table_tr();
    }

    $xtpl->table_td(
        '<a href="?page=networking&action=hostaddr_new&ip=' . $ip->id . '&returl_url=' . $return_url . '">' . _('Add host addresses') . '</a>',
        false,
        true,
        7
    );
    $xtpl->table_tr();

    $xtpl->table_out();
}

function route_assign_form($id)
{
    global $xtpl, $api;

    $ip = $api->ip_address->show($id, ['meta' => ['includes' => 'network']]);

    $xtpl->table_title(_('Route IP address to a VPS'));
    $xtpl->sbar_add(
        _("Back"),
        $_GET['return'] ? $_GET['return'] : '?page=networking&action=ip_addresses'
    );

    if ($_POST['vps']) {
        try {
            $vps = $api->vps->show($_POST['vps']);
        } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
            $vps = false;
        }
    } else {
        $vps = false;
    }

    if ($_POST['network_interface']) {
        try {
            $netif = $api->network_interface->show($_POST['network_interface']);
        } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
            $netif = false;
        }
    } else {
        $netif = false;
    }

    if ($vps && $netif) {
        $target = 'route_assign2';
    } else {
        $target = 'route_assign';
    }

    $xtpl->form_create(
        '?page=networking&action=' . $target . '&id=' . $ip->id . '&return=' . urlencode($_GET['return']),
        'post'
    );

    $xtpl->table_td('IP:');
    $xtpl->table_td($ip->addr . '/' . $ip->prefix);
    $xtpl->table_tr();

    if ($vps) {
        $xtpl->table_td(_('VPS') . ':');
        $xtpl->table_td($vps->id . ' (' . $vps->hostname . ')');
        $xtpl->table_tr();

        if ($netif) {
            $xtpl->table_td(_('Network interface') . ':');
            $xtpl->table_td($netif->name);
            $xtpl->table_tr();

            $via_addrs = resource_list_to_options(
                $api->host_ip_address->list([
                    'network_interface' => $netif->id,
                    'assigned' => true,
                    'version' => $ip->network->ip_version,
                ]),
                'id',
                'addr',
                false
            );

            $via_addrs = [
                '' => _('host address from this network will be on ' . $netif->name),
            ] + $via_addrs;

            $xtpl->table_td(
                _('Address') . ':' .
                '<input type="hidden" name="vps" value="' . $vps->id . '">' .
                '<input type="hidden" name="network_interface" value="' . $netif->id . '">'
            );
            $xtpl->form_add_select_pure('route_via', $via_addrs, post_val('route_via'));
            $xtpl->table_tr();

            $xtpl->table_td('');
            $xtpl->table_td(
                $xtpl->html_submit(_('Add only route'), 'route-only') .
                $xtpl->html_submit(_('Add route and an address to interface') . ' ' . h($netif->name), 'route-and-host')
            );
            $xtpl->table_tr();

            $xtpl->form_out_raw();

        } else {
            $netifs = $api->network_interface->list(['vps' => $_POST['vps']]);

            $xtpl->table_td(
                _('Network interface') . ':' .
                '<input type="hidden" name="vps" value="' . $vps->id . '">'
            );
            $xtpl->form_add_select_pure(
                'network_interface',
                resource_list_to_options($netifs, 'id', 'name', false),
                post_val('network_interface')
            );
            $xtpl->table_tr();

            $xtpl->form_out(_('Continue'));
        }

    } else {
        $xtpl->form_add_input(_('VPS ID') . ':', 'text', '30', 'vps', post_val('vps'));
        $xtpl->form_out(_('Continue'));
    }
}

function route_unassign_form($id)
{
    global $xtpl, $api;

    $ip = $api->ip_address->show($id, ['meta' => [
        'includes' => 'network,network_interface__vps',
    ]]);

    $xtpl->table_title(_('Remove route from VPS'));
    $xtpl->sbar_add(
        _("Back"),
        $_GET['return'] ? $_GET['return'] : '?page=networking&action=ip_addresses'
    );

    $xtpl->form_create(
        '?page=networking&action=route_unassign2&id=' . $ip->id . '&return=' . urlencode($_GET['return']),
        'post'
    );

    $vps = $ip->network_interface->vps;

    $xtpl->table_td(_('VPS') . ':');
    $xtpl->table_td(
        '<a href="?page=adminvps&action=info&veid=' . $vps->id . '">#' . $vps->id . '</a>' .
        ' ' . $vps->hostname
    );
    $xtpl->table_tr();

    $xtpl->table_td(_('Network interface') . ':');
    $xtpl->table_td($ip->network_interface->name);
    $xtpl->table_tr();

    $xtpl->table_td(_('IP') . ':');
    $xtpl->table_td($ip->network->location->label . ': ' . $ip->addr . '/' . $ip->network->prefix);
    $xtpl->table_tr();

    if (isAdmin()) {
        $xtpl->form_add_checkbox(_('Disown') . ':', 'disown', '1', false);
    }

    $xtpl->form_add_checkbox(_('Confirm') . ':', 'confirm', '1', false);

    $xtpl->form_out(_("Remove"));
}

function hostaddr_assign_form($id)
{
    global $xtpl, $api;

    $addr = $api->host_ip_address->show($id, ['meta' => [
        'includes' => 'ip_address__network',
    ]]);
    $ip = $addr->ip_address;

    $xtpl->table_title(_('Add host IP address to a VPS'));
    $xtpl->sbar_add(
        _("Back"),
        $_GET['return'] ? $_GET['return'] : '?page=networking&action=ip_addresses'
    );

    $xtpl->form_create(
        '?page=networking&action=hostaddr_assign2&id=' . $addr->id . '&return=' . urlencode($_GET['return']),
        'post'
    );

    $xtpl->table_td('IP:');
    $xtpl->table_td($ip->network->location->label . ': ' . $addr->addr . '/' . $ip->network->prefix);
    $xtpl->table_tr();

    $xtpl->table_td(_('VPS') . ':');
    $xtpl->table_td($ip->network_interface->vps_id . ' (' . $ip->network_interface->vps->hostname . ')');
    $xtpl->table_tr();

    $xtpl->table_td(_('Network interface') . ':');
    $xtpl->table_td($ip->network_interface->name);
    $xtpl->table_tr();

    $xtpl->form_out(_('Add address'));
}

function hostaddr_unassign_form($id)
{
    global $xtpl, $api;

    $addr = $api->host_ip_address->show($id, ['meta' => [
        'includes' => 'ip_address__network,ip_address__network_interface__vps',
    ]]);
    $ip = $addr->ip_address;

    $xtpl->table_title(_('Remove host IP from a VPS'));
    $xtpl->sbar_add(
        _("Back"),
        $_GET['return'] ? $_GET['return'] : '?page=networking&action=ip_addresses'
    );

    $xtpl->form_create(
        '?page=networking&action=hostaddr_unassign2&id=' . $addr->id . '&return=' . urlencode($_GET['return']),
        'post'
    );

    $vps = $ip->network_interface->vps;

    $xtpl->table_td(_('VPS') . ':');
    $xtpl->table_td(
        '<a href="?page=adminvps&action=info&veid=' . $vps->id . '">#' . $vps->id . '</a>' .
        ' ' . $vps->hostname
    );
    $xtpl->table_tr();

    $xtpl->table_td(_('Network interface') . ':');
    $xtpl->table_td($ip->network_interface->name);
    $xtpl->table_tr();

    $xtpl->table_td(_('IP') . ':');
    $xtpl->table_td($ip->network->location->label . ': ' . $ip->addr . '/' . $ip->network->prefix);
    $xtpl->table_tr();

    $xtpl->form_add_checkbox(_('Confirm') . ':', 'confirm', '1', false);

    $xtpl->form_out(_("Remove"));
}

function hostaddr_new_form($ipId)
{
    global $xtpl, $api;

    $ip = $api->ip_address->show($ipId);

    $xtpl->title(_('IP address') . ' ' . $ip->addr . '/' . $ip->prefix);
    $xtpl->sbar_add(
        _("Back"),
        '?page=networking&action=route_edit&id=' . $ip->id
    );

    $xtpl->form_create('?page=networking&action=hostaddr_new2&ip=' . $ip->id, 'post');

    $xtpl->form_set_hidden_fields([
        'returl_url' => $_GET['return_url'] ?? $_POST['return_url'],
    ]);

    $xtpl->form_add_textarea(
        _('Host addresses') . ':',
        40,
        10,
        'host_addresses',
        post_val('host_addresses'),
        _('One address per line')
    );

    $xtpl->form_out(_('Add addresses'));
}

function hostaddr_delete_form($hostId)
{
    global $xtpl, $api;

    $host = $api->host_ip_address->show($hostId);

    $xtpl->title(_('Host address') . ' ' . $host->addr);
    $xtpl->sbar_add(
        _("Back"),
        '?page=networking&action=route_edit&id=' . $host->ip_address_id
    );

    $xtpl->form_create('?page=networking&action=hostaddr_delete2&id=' . $host->id . '&ip=' . $host->ip_address_id, 'post');
    $xtpl->form_add_checkbox(_('Confirm') . ':', 'confirm', '1');
    $xtpl->form_out(_('Remove address from vpsAdmin'));
}

function ip_address_assignment_list_form()
{
    global $xtpl, $api;

    $pagination = new \Pagination\System(null, $api->ip_address_assignment->list);

    $xtpl->title(_('IP address assignments'));
    $xtpl->table_title(_('Filters'));
    $xtpl->form_create('', 'get', 'ip-filter', false);

    $xtpl->form_set_hidden_fields([
        'page' => $_GET['page'],
        'action' => 'assignments',
        'list' => '1',
    ]);

    $xtpl->form_add_input(_('Limit') . ':', 'text', '40', 'limit', get_val('limit', '25'), '');

    $versions = [
        0 => 'all',
        4 => '4',
        6 => '6',
    ];

    $xtpl->form_add_input(_("From ID") . ':', 'text', '40', 'from_id', get_val('from_id', '0'), '');
    $xtpl->form_add_select(_("Version") . ':', 'ip_version', $versions, get_val('ip_version', 0));
    $xtpl->form_add_input(_("IP address") . ':', 'text', '40', 'ip_addr', get_val('ip_addr'));
    $xtpl->form_add_input(_("Prefix") . ':', 'text', '40', 'ip_prefix', get_val('ip_prefix'));

    if (isAdmin()) {
        $xtpl->form_add_input(_("User ID") . ':', 'text', '40', 'user', get_val('user'));
    }

    $xtpl->form_add_input(_("VPS") . ':', 'text', '40', 'vps', get_val('vps'));
    $xtpl->form_add_select(
        _("Network") . ':',
        'network',
        resource_list_to_options(
            $api->network->list(['purpose' => 'vps']),
            'id',
            'label',
            true,
            'network_label'
        ),
        get_val('network')
    );
    $xtpl->form_add_select(
        _("Location") . ':',
        'location',
        resource_list_to_options($api->location->list()),
        get_val('location')
    );

    $xtpl->form_out(_('Show'));

    if (!($_GET['list'] ?? false)) {
        return;
    }

    $params = [
        'limit' => get_val('limit', 25),
        'from_id' => get_val('from_id', 0),
        'order' => 'newest',
        'meta' => ['includes' => 'user,vps,ip_address'],
    ];

    if (isAdmin() && $_GET['user']) {
        $params['user'] = $_GET['user'];
    }

    if ($_GET['vps']) {
        $params['vps'] = $_GET['vps'];
    }

    if ($_GET['network']) {
        $params['network'] = $_GET['network'];
    }

    if ($_GET['location']) {
        $params['location'] = $_GET['location'];
    }

    if ($_GET['ip_version']) {
        $params['ip_version'] = $_GET['ip_version'];
    }

    if ($_GET['ip_addr']) {
        $params['ip_addr'] = $_GET['ip_addr'];
    }

    if ($_GET['ip_prefix']) {
        $params['ip_prefix'] = $_GET['ip_prefix'];
    }

    $assignments = $api->ip_address_assignment->list($params);
    $pagination->setResourceList($assignments);

    $xtpl->table_add_category(_("IP address"));

    if (isAdmin()) {
        $xtpl->table_add_category(_('User'));
    }

    $xtpl->table_add_category('VPS');
    $xtpl->table_add_category(_('From'));
    $xtpl->table_add_category(_('To'));
    $xtpl->table_add_category(_('Assigned by'));
    $xtpl->table_add_category(_('Unassigned by'));
    $xtpl->table_add_category(_('Assigned at'));
    $xtpl->table_add_category(_('Verified'));
    $xtpl->table_add_category('');

    $return_url = urlencode($_SERVER['REQUEST_URI']);

    foreach ($assignments as $as) {
        $xtpl->table_td($as->ip_addr . '/' . $as->ip_prefix);

        if (isAdmin()) {
            $xtpl->table_td($as->user_id ? user_link($as->user) : $as->raw_user_id);
        }

        $xtpl->table_td($as->vps_id ? vps_link($as->vps) : $as->raw_vps_id);
        $xtpl->table_td(tolocaltz($as->from_date));
        $xtpl->table_td($as->to_date ? tolocaltz($as->to_date) : '-');
        $xtpl->table_td($as->assigned_by_chain_id ? ('<a href="?page=transactions&chain=' . $as->assigned_by_chain_id . '">' . $as->assigned_by_chain_id . '</a>') : '-');
        $xtpl->table_td($as->unassigned_by_chain_id ? ('<a href="?page=transactions&chain=' . $as->unassigned_by_chain_id . '">' . $as->unassigned_by_chain_id . '</a>') : '-');
        $xtpl->table_td(tolocaltz($as->created_at));
        $xtpl->table_td(boolean_icon(!$as->reconstructed));
        $xtpl->table_td('<a href="?page=incidents&action=list&list=1&ip_address_assignment=' . $as->id . '&return=' . $return_url . '"><img src="template/icons/bug.png" alt="' . _('List incident reports') . '" title="' . _('List incident reports') . '"></a>');
        $xtpl->table_tr();
    }

    $xtpl->table_pagination($pagination);
    $xtpl->table_out();
}

function hostaddr_reverse_record_form($id)
{
    global $xtpl, $api;

    $addr = $api->host_ip_address->show($id, ['meta' => [
        'includes' => 'ip_address__network,ip_address__network_interface__vps',
    ]]);

    $xtpl->table_title(_('Configure reverse record'));
    $xtpl->sbar_add(
        _("Back"),
        $_GET['return'] ? $_GET['return'] : '?page=networking&action=ip_addresses'
    );

    $xtpl->form_create(
        '?page=networking&action=hostaddr_ptr2&id=' . $addr->id . '&return=' . urlencode($_GET['return']),
        'post'
    );

    if ($addr->ip_address->network_interface_id) {
        $vps = $addr->ip_address->network_interface->vps;

        $xtpl->table_td(_('VPS') . ':');
        $xtpl->table_td(
            '<a href="?page=adminvps&action=info&veid=' . $vps->id . '">#' . $vps->id . '</a>' .
            ' ' . $vps->hostname
        );
        $xtpl->table_tr();

        $xtpl->table_td(_('Network interface') . ':');
        $xtpl->table_td($addr->ip_address->network_interface->name);
        $xtpl->table_tr();
    }

    $xtpl->table_td(_('IP address') . ':');
    $xtpl->table_td($addr->addr);
    $xtpl->table_tr();

    $xtpl->form_add_input(
        _('Reverse record') . ':',
        'text',
        '30',
        'reverse_record_value',
        post_val('reverse_record_value', $addr->reverse_record_value)
    );

    $xtpl->form_out(_("Set"));
}
