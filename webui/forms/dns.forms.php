<?php

function dns_submenu()
{
    global $xtpl;

    if (isAdmin()) {
        $xtpl->sbar_add(_('Servers'), '?page=dns&action=server_list');
        $xtpl->sbar_add(_('All zones'), '?page=dns&action=zone_list');
    }

    $xtpl->sbar_add(_('Reverse records'), '?page=dns&action=ptr_list');
    $xtpl->sbar_add(_('Primary zones'), '?page=dns&action=primary_zone_list');
    $xtpl->sbar_add(_('Secondary zones'), '?page=dns&action=secondary_zone_list');
    $xtpl->sbar_add(_('TSIG keys'), '?page=dns&action=tsig_key_list');
}

function dns_server_list()
{
    global $xtpl, $api;

    $xtpl->table_title(_('DNS servers'));

    $servers = $api->dns_server->list(['meta' => ['includes' => 'node']]);

    $xtpl->table_add_category(_('Node'));
    $xtpl->table_add_category(_('Name'));
    $xtpl->table_add_category(_('IPv4'));
    $xtpl->table_add_category(_('IPv6'));
    $xtpl->table_add_category(_('Hidden'));
    $xtpl->table_add_category(_('User zones'));

    foreach ($servers as $s) {
        $xtpl->table_td(node_link($s->node));
        $xtpl->table_td(h($s->name));
        $xtpl->table_td($s->ipv4_addr ? h($s->ipv4_addr) : '-');
        $xtpl->table_td($s->ipv6_addr ? h($s->ipv6_addr) : '-');
        $xtpl->table_td(boolean_icon($s->hidden));
        $xtpl->table_td(boolean_icon($s->enable_user_dns_zones));
        $xtpl->table_tr();
    }

    $xtpl->table_out();
}

function dns_zone_list($action, $filters = [], $onLastRow = null)
{
    global $xtpl, $api;

    $xtpl->table_title(_('Filters'));
    $xtpl->form_create('', 'get', 'user-session-filter', false);

    $xtpl->form_set_hidden_fields([
        'page' => 'dns',
        'action' => $action,
        'list' => '1',
    ]);

    $xtpl->form_add_input(_('Limit') . ':', 'text', '40', 'limit', get_val('limit', '25'), '');
    $xtpl->form_add_input(_("Offset") . ':', 'text', '40', 'offset', get_val('offset', '0'), '');

    if (isAdmin()) {
        $xtpl->form_add_input(_("User") . ':', 'text', '40', 'user', get_val('user', ''), '');
    }

    $xtpl->form_out(_('Show'));

    $params = [
        'limit' => get_val('limit', 25),
        'offset' => get_val('offset', 0),
    ];

    $params = array_merge($params, $filters);

    $conds = ['user'];

    foreach ($conds as $c) {
        if ($_GET[$c]) {
            $params[$c] = $_GET[$c];
        }
    }

    $params['meta'] = [
        'includes' => 'user',
    ];

    $zones = $api->dns_zone->list($params);

    if (isAdmin()) {
        $xtpl->table_add_category(_("User"));
    }

    $xtpl->table_add_category(_('Name'));

    if (isAdmin()) {
        $xtpl->table_add_category(_('Role'));
        $xtpl->table_add_category(_('Source'));
    }

    $xtpl->table_add_category(_('Enabled'));
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');

    foreach ($zones as $z) {
        if (isAdmin()) {
            $xtpl->table_td($z->user_id ? user_link($z->user) : '-');
        }

        $xtpl->table_td(h($z->name));

        if (isAdmin()) {
            $xtpl->table_td(zoneRoleLabel($z->role));
            $xtpl->table_td(zoneSourceLabel($z->source));
        }

        $xtpl->table_td(boolean_icon($z->enabled));

        $xtpl->table_td(
            '<a href="?page=dns&action=zone_show&id=' . $z->id . '&return_url=' . urlencode($_SERVER['REQUEST_URI']) . '"><img src="template/icons/vps_edit.png" alt="' . _('Details') . '" title="' . _('Details') . '"></a>'
        );


        $xtpl->table_td(
            '<a href="?page=dns&action=zone_delete&id=' . $z->id . '&return_url=' . urlencode($_SERVER['REQUEST_URI']) . '"><img src="template/icons/vps_delete.png" alt="' . _('Delete zone') . '" title="' . _('Delete zone') . '"></a>'
        );
        $xtpl->table_tr();
    }

    $cols = isAdmin() ? 7 : 4;

    if ($onLastRow) {
        $onLastRow($cols);
    } elseif ($zones->count() == 0) {
        $xtpl->table_td(
            _('No zones found.'),
            false,
            false,
            $cols
        );
        $xtpl->table_tr();
    }

    $xtpl->table_out();
}

function dns_zone_show($id)
{
    global $xtpl, $api;

    $zone = $api->dns_zone->show($id);

    $zoneTransfers = $api->dns_zone_transfer->list([
        'dns_zone' => $zone->id,
        'meta' => ['includes' => 'host_ip_address,dns_tsig_key'],
    ]);

    $xtpl->table_title(_('Zone') . ' ' . h($zone->name));
    $xtpl->form_create('?page=dns&action=zone_update&id=' . $zone->id, 'post');

    $updateInput = $api->dns_zone->update->getParameters('input');

    if (isAdmin()) {
        $xtpl->table_td(_('User') . ':');
        $xtpl->table_td($zone->user_id ? user_link($zone->user) : '-');
        $xtpl->table_tr();
    }

    $xtpl->table_td(_('Name') . ':');
    $xtpl->table_td(h($zone->name));
    $xtpl->table_tr();

    if (isAdmin()) {
        $xtpl->table_td(_('Source') . ':');
        $xtpl->table_td(zoneSourceLabel($zone->source));
        $xtpl->table_tr();

        $xtpl->table_td(_('Role') . ':');
        $xtpl->table_td(zoneRoleLabel($zone->role));
        $xtpl->table_tr();
    }

    if (isAdmin() && $zone->role == 'reverse_role' && $zone->reverse_network_address) {
        $xtpl->table_td(_('Reverse network') . ':');
        $xtpl->table_td($zone->reverse_network_address . '/' . $zone->reverse_network_prefix);
        $xtpl->table_tr();
    }

    if ($zone->source == 'internal_source') {

        api_param_to_form('default_ttl', $updateInput->default_ttl, $zone->default_ttl);
        api_param_to_form('email', $updateInput->email, $zone->email);

        $xtpl->form_add_checkbox(
            _('Enable DNSSEC') . ':',
            'dnssec_enabled',
            '1',
            post_val_issetto('dnssec_enabled', '1', $zone->dnssec_enabled),
            $zone->dnssec_enabled ? ('<a href="?page=dns&action=dnssec_records&id=' . $zone->id . '">' . _('View DNSKEY and DS records') . '</a>') : $updateInput->dnssec_enabled->description
        );
    }

    api_param_to_form('enabled', $updateInput->enabled, $zone->enabled);

    if ($zone->source == 'external_source' && $zoneTransfers->count() == 0) {
        $xtpl->table_td('<strong>' . _('Warning') . ':</strong');
        $xtpl->table_td(_('Add at least one primary DNS server for this zone to become active.'));
        $xtpl->table_tr();
    }

    $xtpl->form_out(_('Save'));

    $xtpl->table_title(_('Name servers'));

    $serverZones = $api->dns_server_zone->list([
        'dns_zone' => $zone->id,
        'meta' => ['includes' => 'dns_server'],
    ]);

    $xtpl->table_add_category(_('Server'));
    $xtpl->table_add_category(_('IPv4 address'));
    $xtpl->table_add_category(_('IPv6 address'));
    $xtpl->table_add_category(_('Serial'));
    $xtpl->table_add_category(_('Last loaded'));
    $xtpl->table_add_category(_('Next refresh'));
    $xtpl->table_add_category(_('Expires'));
    $xtpl->table_add_category(_('Last check'));

    if (isAdmin()) {
        $xtpl->table_add_category('');
    }

    foreach ($serverZones as $sz) {
        $xtpl->table_td(h($sz->dns_server->name));
        $xtpl->table_td($sz->dns_server->ipv4_addr ? h($sz->dns_server->ipv4_addr) : '-');
        $xtpl->table_td($sz->dns_server->ipv6_addr ? h($sz->dns_server->ipv6_addr) : '-');
        $xtpl->table_td(is_null($sz->serial) ? '-' : $sz->serial);
        $xtpl->table_td($sz->loaded_at ? tolocaltz($sz->loaded_at) : '-');
        $xtpl->table_td($sz->refresh_at ? tolocaltz($sz->refresh_at) : '-');
        $xtpl->table_td($sz->expires_at ? tolocaltz($sz->expires_at) : '-');
        $xtpl->table_td($sz->last_check_at ? tolocaltz($sz->last_check_at) : '-');

        if (isAdmin()) {
            $xtpl->table_td('<a href="?page=dns&action=server_zone_delete&id=' . $zone->id . '&server_zone=' . $sz->id . '&t=' . csrf_token() . '"><img src="template/icons/vps_delete.png" alt="' . _('Remove from server') . '" title="' . _('Remove from server') . '"></a>');
        };

        $xtpl->table_tr();
    }

    if (isAdmin()) {
        $xtpl->table_td(
            '<a href="?page=dns&action=server_zone_new&id=' . $zone->id . '">' . _('Add server') . '</a>',
            false,
            true,
            9
        );
        $xtpl->table_tr();
    }

    $xtpl->table_out();

    $xtpl->table_title($zone->source == 'internal_source' ? _('Secondary servers') : _('Primary servers'));

    $xtpl->table_add_category(_('Host IP address'));
    $xtpl->table_add_category(_('TSIG key'));
    $xtpl->table_add_category(_('TSIG algorithm'));
    $xtpl->table_add_category(_('TSIG secret'));
    $xtpl->table_add_category('');

    foreach ($zoneTransfers as $zt) {
        $xtpl->table_td($zt->host_ip_address->addr);

        if ($zt->dns_tsig_key_id) {
            $xtpl->table_td(h($zt->dns_tsig_key->name));
            $xtpl->table_td(h($zt->dns_tsig_key->algorithm));
            $xtpl->table_td('<code>' . h($zt->dns_tsig_key->secret) . '</code>');
        } else {
            $xtpl->table_td('-');
            $xtpl->table_td('-');
            $xtpl->table_td('-');
        }

        $xtpl->table_td('<a href="?page=dns&action=zone_transfer_delete&id=' . $zone->id . '&transfer=' . $zt->id . '&t=' . csrf_token() . '"><img src="template/icons/vps_delete.png" alt="' . _('Remove transfer') . '" title="' . _('Remove transfer') . '"></a>');
        $xtpl->table_tr();
    }

    $addText = $zone->source == 'internal_source' ? _('Add secondary server') : _('Add primary server');

    $xtpl->table_td(
        '<a href="?page=dns&action=zone_transfer_new&id=' . $zone->id . '">' . $addText . '</a>',
        false,
        true,
        5
    );
    $xtpl->table_tr();

    $xtpl->table_out();

    if ($zone->source == 'external_source') {
        foreach ($zoneTransfers as $zt) {
            dns_bind_primary_example($zone, $serverZones, $zt);
        }

        return;
    }

    dns_record_list($zone);
}

function dns_zone_delete($id)
{
    global $xtpl, $api;

    $zone = $api->dns_zone->show($id);

    $xtpl->table_title(_('Delete zone') . ' ' . h($zone->name));
    $xtpl->form_create('?page=dns&action=zone_delete2&id=' . $zone->id, 'post');

    $xtpl->form_set_hidden_fields([
        'return_url' => $_GET['return_url'] ?? $_POST['return_url'],
    ]);

    if (isAdmin()) {
        $xtpl->table_td(_('User') . ':');
        $xtpl->table_td($zone->user_id ? user_link($zone->user) : '-');
        $xtpl->table_tr();
    }

    $xtpl->table_td(_('Name') . ':');
    $xtpl->table_td(h($zone->name));
    $xtpl->table_tr();

    if (isAdmin()) {
        $xtpl->table_td(_('Source') . ':');
        $xtpl->table_td(zoneSourceLabel($zone->source));
        $xtpl->table_tr();

        $xtpl->table_td(_('Role') . ':');
        $xtpl->table_td(zoneRoleLabel($zone->role));
        $xtpl->table_tr();
    }

    if (isAdmin() && $zone->role == 'reverse_role' && $zone->reverse_network_address) {
        $xtpl->table_td(_('Reverse network') . ':');
        $xtpl->table_td($zone->reverse_network_address . '/' . $zone->reverse_network_prefix);
        $xtpl->table_tr();
    }

    $xtpl->form_add_checkbox(_('Confirm') . ':', 'confirm', '1');

    $xtpl->form_out(_('Delete'));
}

function dns_zone_server_new($id)
{
    global $xtpl, $api;

    $zone = $api->dns_zone->show($id);

    $xtpl->title(_('Add zone') . h($zone->name) . ' ' . _('to server'));
    $xtpl->form_create('?page=dns&action=server_zone_new2&id=' . $zone->id, 'post');

    $xtpl->table_td(_('DNS zone') . ':');
    $xtpl->table_td(h($zone->name));
    $xtpl->table_tr();

    $input = $api->dns_server_zone->create->getParameters('input');
    api_param_to_form('dns_server', $input->dns_server);
    api_param_to_form('type', $input->type);

    $xtpl->form_out(_('Add to server'));
}

function dns_zone_transfer_new($id)
{
    global $xtpl, $api;

    $zone = $api->dns_zone->show($id);

    $titleText = $zone->source == 'internal_source' ? _('Add secondary server to zone') : _('Add primary server to zone');

    $xtpl->title($titleText . ' ' . h($zone->name));

    $params = [
        'purpose' => 'vps',
        'routed' => true,
        'meta' => ['includes' => 'ip_address__network_interface__vps'],
    ];

    if (isAdmin() && $zone->user_id) {
        $params['user'] = $zone->user_id;
    }

    $hostIps = $api->host_ip_address->list($params);

    if ($hostIps->count() == 0) {
        $xtpl->table_td(_('No usable host IP address found.'));
        $xtpl->table_tr();
        $xtpl->table_out();
        return;
    }

    $xtpl->form_create('?page=dns&action=zone_transfer_new2&id=' . $zone->id, 'post');
    $xtpl->table_add_category('');
    $xtpl->table_add_category(_('VPS'));
    $xtpl->table_add_category(_('Hostname'));
    $xtpl->table_add_category(_('Interface'));
    $xtpl->table_add_category(_('IP address'));

    $array = $hostIps->asArray();

    usort($array, function ($a, $b) {
        return [$a->ip_address->network_interface->vps_id, $a->addr] <=> [$b->ip_address->network_interface->vps_id, $b->addr];
    });

    foreach ($array as $hostIp) {
        $netif = $hostIp->ip_address->network_interface;

        $xtpl->form_add_radio_pure('host_ip_address', $hostIp->id, $_POST['host_ip_address'] == $hostIp->id);
        $xtpl->table_td(vps_link($netif->vps));
        $xtpl->table_td(h($netif->vps->hostname));
        $xtpl->table_td(h($netif->name));
        $xtpl->table_td(h($hostIp->addr));
        $xtpl->table_tr();
    }

    if ($zone->source == 'internal_source') {
        $helpMsg = _('Select IP address on which your secondary DNS server is running.');
    } else {
        $helpMsg = _('Select IP address on which your primary DNS server is running.');
    }

    $xtpl->table_td($helpMsg, false, false, 5);
    $xtpl->table_tr();

    $xtpl->table_td(_('TSIG key') . ':');
    $xtpl->form_add_select_pure(
        'dns_tsig_key',
        resource_list_to_options(
            $api->dns_tsig_key->list(['user' => $zone->user_id]),
            'id',
            'name',
            true
        )
    );
    $xtpl->table_td(
        _('Optional signing key') . ', ' .
        '<a href="?page=dns&action=tsig_key_list">' . _('manage TSIG keys') . '</a>',
        false,
        false,
        3
    );
    $xtpl->table_tr();

    $xtpl->form_out(_('Add'));
}

function secondary_dns_zone_list()
{
    global $xtpl;

    $xtpl->title(_('Secondary DNS zones'));

    dns_zone_list(
        'secondary_zone_list',
        ['source' => 'external_source'],
        function ($cols) {
            global $xtpl;

            $xtpl->table_td(
                '<a href="?page=dns&action=secondary_zone_new">' . _('Create new secondary zone') . '</a>',
                false,
                true,
                $cols
            );
            $xtpl->table_tr();
        }
    );

    $xtpl->sbar_add(_('New secondary zone'), '?page=dns&action=secondary_zone_new');
    $xtpl->sbar_out(_('Secondary zones'));
}

function secondary_dns_zone_new()
{
    global $xtpl, $api;

    $xtpl->title(_('Create a new secondary DNS zone'));

    $xtpl->form_create('?page=dns&action=secondary_zone_new2', 'post');

    $input = $api->dns_zone->create->getParameters('input');

    if (isAdmin()) {
        $xtpl->form_add_input(_('User ID') . ':', 'text', '30', 'user', post_val('user'));
    }

    api_param_to_form('name', $input->name);

    $xtpl->form_out(_('Create zone'));
}

function primary_dns_zone_list()
{
    global $xtpl;

    $xtpl->title(_('Primary DNS zones'));

    dns_zone_list(
        'primary_zone_list',
        ['source' => 'internal_source'],
        function ($cols) {
            global $xtpl;

            $xtpl->table_td(
                '<a href="?page=dns&action=primary_zone_new">' . _('Create new primary zone') . '</a>',
                false,
                true,
                $cols
            );
            $xtpl->table_tr();
        }
    );

    $xtpl->sbar_add(_('New primary zone'), '?page=dns&action=primary_zone_new');
    $xtpl->sbar_out(_('Primary zones'));
}

function primary_dns_zone_new()
{
    global $xtpl, $api;

    $xtpl->title(_('Create a new primary DNS zone'));

    $xtpl->form_create('?page=dns&action=primary_zone_new2', 'post');

    $input = $api->dns_zone->create->getParameters('input');

    if (isAdmin()) {
        $xtpl->form_add_input(_('User ID') . ':', 'text', '30', 'user', post_val('user'));
    }

    api_param_to_form('name', $input->name);
    api_param_to_form('email', $input->email);
    api_param_to_form('dnssec_enabled', $input->dnssec_enabled);

    $xtpl->form_out(_('Create zone'));
}

function dnssec_records_list($zone_id)
{
    global $xtpl, $api;

    $zone = $api->dns_zone->show($zone_id);

    $xtpl->title(h($zone->name) . ': ' . _('DNSSEC records'));

    $records = $api->dnssec_record->list([
        'dns_zone' => $zone->id,
    ]);

    foreach ($records as $r) {
        $xtpl->table_title(_('Key') . ' ' . $r->keyid);

        $xtpl->table_td(_('Key ID') . ':');
        $xtpl->table_td($r->keyid);
        $xtpl->table_tr();

        $xtpl->table_td(_('Flags') . ':');
        $xtpl->table_td('257');
        $xtpl->table_tr();

        $xtpl->table_td(_('Protocol') . ':');
        $xtpl->table_td('3');
        $xtpl->table_tr();

        $xtpl->table_td(_('Algorithm') . ':');
        $xtpl->table_td($r->dnskey_algorithm);
        $xtpl->table_tr();

        $xtpl->table_td(_('Public key') . ':');
        $xtpl->table_td('<code>' . $r->dnskey_pubkey . '<code>');
        $xtpl->table_tr();

        $xtpl->table_td(_('DNSKEY record') . ':');
        $xtpl->table_td(
            '<textarea cols="70" rows="5" readonly>' .
            "{$zone->name} IN DNSKEY 257 3 {$r->dnskey_algorithm} {$r->dnskey_pubkey}" .
            '</textarea>'
        );
        $xtpl->table_tr();

        $xtpl->table_td(_('DS record') . ':');
        $xtpl->table_td(
            '<textarea cols="70" rows="5" readonly>' .
            "{$zone->name} IN DS {$r->keyid} {$r->ds_algorithm} {$r->ds_digest_type} {$r->ds_digest}" .
            '</textarea>'
        );
        $xtpl->table_tr();

        $xtpl->table_out();
    }

    $xtpl->sbar_add(_('Back to zone'), '?page=dns&action=zone_show&id=' . $zone->id);
    $xtpl->sbar_out(_('DNS zone'));
}

function tsig_key_list()
{
    global $xtpl, $api;

    $xtpl->title(_('TSIG keys'));
    $xtpl->table_title(_('Filters'));
    $xtpl->form_create('', 'get', 'user-session-filter', false);

    $xtpl->form_set_hidden_fields([
        'page' => 'dns',
        'action' => 'tsig_key_list',
    ]);

    $xtpl->form_add_input(_('Limit') . ':', 'text', '40', 'limit', get_val('limit', '25'), '');
    $xtpl->form_add_input(_("Offset") . ':', 'text', '40', 'offset', get_val('offset', '0'), '');

    if (isAdmin()) {
        $xtpl->form_add_input(_("User") . ':', 'text', '40', 'user', get_val('user', ''), '');
    }

    $xtpl->form_out(_('Show'));

    $params = [
        'limit' => get_val('limit', 25),
        'offset' => get_val('offset', 0),
    ];

    $conds = ['user'];

    foreach ($conds as $c) {
        if ($_GET[$c]) {
            $params[$c] = $_GET[$c];
        }
    }

    $params['meta'] = [
        'includes' => 'user',
    ];

    $keys = $api->dns_tsig_key->list($params);

    if (isAdmin()) {
        $xtpl->table_add_category(_("User"));
    }

    $xtpl->table_add_category(_('Name'));
    $xtpl->table_add_category(_('Algorithm'));
    $xtpl->table_add_category(_('Secret'));
    $xtpl->table_add_category('');

    $return_url = urlencode($_SERVER['REQUEST_URI']);

    foreach ($keys as $k) {
        if (isAdmin()) {
            $xtpl->table_td($k->user_id ? user_link($k->user) : '-');
        }

        $xtpl->table_td(h($k->name));
        $xtpl->table_td(h($k->algorithm));
        $xtpl->table_td('<code>' . h($k->secret) . '</code>');
        $xtpl->table_td(
            '<a href="?page=dns&action=tsig_key_delete&id=' . $k->id . '&return_url=' . $return_url . '"><img src="template/icons/vps_delete.png" alt="' . _('Delete key') . '" title="' . _('Delete key') . '"></a>'
        );
        $xtpl->table_tr();
    }

    $xtpl->table_td(
        '<a href="?page=dns&action=tsig_key_new">' . _('Create TSIG key') . '</a>',
        false,
        true,
        isAdmin() ? 5 : 4
    );
    $xtpl->table_tr();

    $xtpl->table_out();

    $xtpl->sbar_add(_('New TSIG key'), '?page=dns&action=tsig_key_new');
    $xtpl->sbar_out(_('TSIG keys'));
}

function tsig_key_new()
{
    global $xtpl, $api;

    $xtpl->title(_('Create a new TSIG key'));

    $xtpl->form_create('?page=dns&action=tsig_key_new2', 'post');

    $input = $api->dns_tsig_key->create->getParameters('input');

    if (isAdmin()) {
        $xtpl->form_add_input(_('User ID') . ':', 'text', '30', 'user', post_val('user'));
    }

    api_param_to_form('name', $input->name);
    api_param_to_form('algorithm', $input->algorithm);

    $xtpl->table_td(_('Secret') . ':');
    $xtpl->table_td(_('Will be generated.'));
    $xtpl->table_tr();

    $xtpl->form_out(_('Create key'));
}

function tsig_key_delete($id)
{
    global $xtpl, $api;

    $key = $api->dns_tsig_key->show($id);

    $xtpl->table_title(_('Delete TSIG key') . ' ' . h($key->name));
    $xtpl->form_create('?page=dns&action=tsig_key_delete2&id=' . $key->id, 'post');

    $xtpl->form_set_hidden_fields([
        'return_url' => $_GET['return_url'] ?? $_POST['return_url'],
    ]);

    if (isAdmin()) {
        $xtpl->table_td(_('User') . ':');
        $xtpl->table_td($key->user_id ? user_link($key->user) : '-');
        $xtpl->table_tr();
    }

    $xtpl->table_td(_('Name') . ':');
    $xtpl->table_td(h($key->name));
    $xtpl->table_tr();

    $xtpl->table_td(_('Algorithm') . ':');
    $xtpl->table_td(h($key->algorithm));
    $xtpl->table_tr();

    $xtpl->table_td(_('Secret') . ':');
    $xtpl->table_td('<code>' . h($key->secret) . '</code>');
    $xtpl->table_tr();

    $xtpl->form_add_checkbox(_('Confirm') . ':', 'confirm', '1');

    $xtpl->form_out(_('Delete key'));
}

function dns_ptr_list()
{
    global $xtpl, $api;

    $xtpl->title(_('Reverse records'));
    $xtpl->table_title(_('Filters'));
    $xtpl->form_create('', 'get', 'ip-filter', false);

    $xtpl->table_td(
        _("Limit") . ':' .
        '<input type="hidden" name="page" value="dns">' .
        '<input type="hidden" name="action" value="ptr_list">' .
        '<input type="hidden" name="list" value="1">'
    );
    $xtpl->form_add_input_pure('text', '40', 'limit', get_val('limit', '25'), '');
    $xtpl->table_tr();

    $versions = [
        0 => 'all',
        4 => '4',
        6 => '6',
    ];

    $xtpl->form_add_input(_("Offset") . ':', 'text', '40', 'offset', get_val('offset', '0'), '');
    $xtpl->form_add_select(_("Version") . ':', 'v', $versions, get_val('v', 0));

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

    $params = [
        'limit' => get_val('limit', 25),
        'offset' => get_val('offset', 0),
        'purpose' => 'vps',
        'routed' => true,
        'meta' => [
            'includes' => 'ip_address__user,ip_address__network_interface__vps,' .
                          'ip_address__network',
        ],
    ];

    if (isAdmin()) {
        if ($_GET['user']) {
            $params['user'] = $_GET['user'];
        }
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

    if ($_GET['v']) {
        $params['version'] = $_GET['v'];
    }

    $host_addrs = $api->host_ip_address->list($params);

    if (isAdmin()) {
        $xtpl->table_add_category(_('User'));
    } else {
        $xtpl->table_add_category(_('Owned'));
    }

    $xtpl->table_add_category('VPS');
    $xtpl->table_add_category('Interface');

    $xtpl->table_add_category(_("Host address"));
    $xtpl->table_add_category((_("Reverse record")));

    $xtpl->table_add_category('');

    $return_url = urlencode($_SERVER['REQUEST_URI']);

    foreach ($host_addrs as $host_addr) {
        $ip = $host_addr->ip_address;
        $netif = $ip->network_interface_id ? $ip->network_interface : null;
        $vps = $netif ? $netif->vps : null;

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

        $xtpl->table_td($host_addr->addr);
        $xtpl->table_td($host_addr->reverse_record_value ? h($host_addr->reverse_record_value) : '-');

        $xtpl->table_td(
            '<a href="?page=networking&action=hostaddr_ptr&id=' . $host_addr->id . '&return=' . $return_url . '">' .
            '<img src="template/icons/m_edit.png" alt="' . _('Set reverse record') . '" title="' . _('Set reverse record') . '">' .
            '</a>'
        );

        $xtpl->table_tr();
    }

    $xtpl->table_out();
}

function dns_bind_primary_example($zone, $serverZones, $zoneTransfer)
{
    global $xtpl;

    $xtpl->table_title(_('Example BIND configuration for server on ') . ' ' . $zoneTransfer->host_ip_address->addr);

    $zoneFile = '/etc/bind/zones/db.' . $zone->name;

    $secondaryIps = implode(
        ' ',
        array_map(function ($sz) {
            $ip = $sz->dns_server->ipv4_addr ? $sz->dns_server->ipv4_addr : $sz->dns_server->ipv6_addr;
            return $ip . ';';
        }, $serverZones->asArray())
    );

    $bindExample = <<<END
        # File /etc/bind/named.conf:

        END;

    if ($zoneTransfer->dns_tsig_key_id) {
        $bindExample .= <<<END
            key "{$zoneTransfer->dns_tsig_key->name}" {
                algorithm {$zoneTransfer->dns_tsig_key->algorithm};
                secret "{$zoneTransfer->dns_tsig_key->secret}";
            };


            END;
    }

    $secondaryIpArray = [];

    foreach ($serverZones as $sz) {
        $ips = [
            $sz->dns_server->ipv4_addr,
            $sz->dns_server->ipv6_addr,
        ];

        foreach ($ips as $ip) {
            if (!$ip) {
                continue;
            }

            $str = '      ';
            $str .= $ip;

            if ($zoneTransfer->dns_tsig_key_id) {
                $str .= ' key ' . $zoneTransfer->dns_tsig_key->name;
            }

            $str .= ';';

            $secondaryIpArray[] = $str;
        }
    }

    $secondaryIpStr = implode("\n", $secondaryIpArray);

    $bindExample .= <<<END
        zone "{$zone->name}" {
            type primary;
            file "$zoneFile";
            allow-transfer {
        $secondaryIpStr
            };
            notify yes;
            allow-query any;
        };


        END;

    $nameserverRecords = implode(
        "\n",
        array_map(function ($sz) {
            return "        IN NS    {$sz->dns_server->name}";
        }, $serverZones->asArray())
    );

    $bindExample .= <<<END

        # File $zoneFile:
        \$TTL 3600         ; Default TTL (1 hour)
        @       IN SOA   ns1.{$zone->name} hostmaster.{$zone->name} (
                        2023071201 ; Serial number (YYYYMMDDNN format)
                        3600       ; Refresh (1 hour)
                        1800       ; Retry (30 minutes)
                        1209600    ; Expire (2 weeks)
                        86400      ; Minimum TTL (1 day)
        )

        ; Name servers, be sure to set those
                IN NS    ns1.{$zone->name}
        $nameserverRecords

        ; A record for your name server
        ns1     IN A     ns1.{$zone->name}

        ; The following records are only examples and are not needed for the server
        ; to function.
        ;
        ; A and AAAA records for the website
        www     IN A     192.0.2.3
        www     IN AAAA  2001:db8::3

        ; MX record for mail server
        @       IN MX    10 mail.{$zone->name}
        mail    IN A     192.0.2.4
        END;

    $xtpl->table_td(
        '<textarea cols="80" rows="40" readonly>' . h($bindExample) . '</textarea>'
    );
    $xtpl->table_tr();
    $xtpl->table_out();
}

function dns_record_list($zone)
{
    global $xtpl, $api;

    $records = $api->dns_record->list(['dns_zone' => $zone->id]);
    $cols = 6;

    if (!$zone->managed) {
        $cols += 3;
    }

    $xtpl->table_title(_('Records'));
    $xtpl->table_add_category(_('Name'));
    $xtpl->table_add_category(_('TTL'));
    $xtpl->table_add_category(_('Type'));
    $xtpl->table_add_category(_('Priority'));
    $xtpl->table_add_category(_('Content'));

    if (!$zone->managed) {
        $xtpl->table_add_category(_('DDNS'));
    }

    $xtpl->table_add_category(_('Enabled'));

    if (!$zone->managed) {
        $xtpl->table_add_category('');
        $xtpl->table_add_category('');
    }

    foreach ($records as $r) {
        if ($r->comment) {
            $xtpl->table_td(_('Comment') . ': ' . nl2br(h($r->comment)), false, false, $cols);
            $xtpl->table_tr();
        }

        $xtpl->table_td(h($r->name));
        $xtpl->table_td($r->ttl ? $r->ttl : '-');
        $xtpl->table_td(h($r->type));
        $xtpl->table_td($r->priority ? $r->priority : '-');
        $xtpl->table_td(nl2br(h($r->content)));

        if (!$zone->managed) {
            $xtpl->table_td(boolean_icon($r->dynamic_update_enabled));
        }

        $xtpl->table_td(boolean_icon($r->enabled));

        if (!$zone->managed) {
            $xtpl->table_td('<a href="?page=dns&action=record_edit&id=' . $r->id . '"><img src="template/icons/vps_edit.png" alt="' . _('Edit') . '" title="' . _('Edit') . '"></a>');
            $xtpl->table_td('<a href="?page=dns&action=record_delete&id=' . $r->id . '&zone=' . $r->dns_zone_id . '&t=' . csrf_token() . '"><img src="template/icons/vps_delete.png" alt="' . _('Delete') . '" title="' . _('Delete') . '"></a>');
        }

        $xtpl->table_tr();
    }

    if (!$zone->managed) {
        $xtpl->table_td(
            '<a href="?page=dns&action=record_new&zone=' . $zone->id . '">' . _('Add record') . '</a>',
            false,
            true,
            $cols
        );
        $xtpl->table_tr();
    }

    $xtpl->table_out();
}

function dns_record_new($zone_id)
{
    global $xtpl, $api;

    $zone = $api->dns_zone->show($zone_id);

    $xtpl->title(_('Zone ') . h($zone->name) . ': ' . _('new record'));

    $xtpl->form_create('?page=dns&action=record_new2&zone=' . $zone->id, 'post');

    $input = $api->dns_record->create->getParameters('input');

    api_param_to_form('name', $input->name);
    api_param_to_form('type', $input->type);
    api_param_to_form('ttl', $input->ttl);
    api_param_to_form('priority', $input->priority);
    $xtpl->form_add_textarea(_('Content') . ':', 60, 1, 'content', post_val('content'), $input->content->description);
    $xtpl->form_add_textarea(_('Comment') . ':', 60, 1, 'comment', post_val('comment'), $input->comment->description);
    api_param_to_form('dynamic_update_enabled', $input->dynamic_update_enabled);
    api_param_to_form('enabled', $input->enabled);

    $xtpl->form_out(_('Add'));

    $xtpl->sbar_add(_('Back to zone'), '?page=dns&action=zone_show&id=' . $zone->id);
    $xtpl->sbar_out(_('DNS zone'));
}

function dns_record_edit($id)
{
    global $xtpl, $api;

    $record = $api->dns_record->show($id);

    $xtpl->title(_('Zone ') . h($record->dns_zone->name) . ': ' . _('update record'));

    $xtpl->form_create('?page=dns&action=record_edit2&id=' . $record->id, 'post');

    $input = $api->dns_record->update->getParameters('input');

    $xtpl->table_td(_('Name') . ':');
    $xtpl->table_td(h($record->name));
    $xtpl->table_tr();

    $xtpl->table_td(_('Type') . ':');
    $xtpl->table_td(h($record->type));
    $xtpl->table_tr();

    api_param_to_form('ttl', $input->ttl, $record->ttl);
    api_param_to_form('priority', $input->priority, $record->priority);
    $xtpl->form_add_textarea(_('Content') . ':', 60, 1, 'content', post_val('content', $record->content), $input->content->description);
    $xtpl->form_add_textarea(_('Comment') . ':', 60, 1, 'comment', post_val('comment', $record->comment), $input->comment->description);

    if ($record->type == 'A' || $record->type == 'AAAA') {
        api_param_to_form('dynamic_update_enabled', $input->dynamic_update_enabled, $record->dynamic_update_enabled);

        $xtpl->table_td(_('Dynamic update URL') . ':');

        if ($record->dynamic_update_enabled) {
            $xtpl->table_td('<textarea cols="70" rows="5" readonly>' . h($record->dynamic_update_url) . '</textarea>');
        } else {
            $xtpl->table_td(_('not enabled'));
        }

        $xtpl->table_tr();
    }

    api_param_to_form('enabled', $input->enabled, $record->enabled);

    $xtpl->form_out(_('Update'));

    $xtpl->sbar_add(_('Back to zone'), '?page=dns&action=zone_show&id=' . $record->dns_zone_id);
    $xtpl->sbar_out(_('DNS zone'));
}

function zoneRolelabel($role)
{
    switch ($role) {
        case 'forward_role':
            return _('Forward zone');
        case 'reverse_role':
            return _('Reverse zone');
        default:
            return _('Unknown');
    }
}

function zoneSourcelabel($source)
{
    switch ($source) {
        case 'internal_source':
            return _('Internal zone');
        case 'external_source':
            return _('External zone');
        default:
            return _('Unknown');
    }
}
