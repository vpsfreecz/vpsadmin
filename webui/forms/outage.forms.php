<?php

function maintenance_to_entities()
{
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        return $_POST;
    }

    $ret = [
        'vpsadmin' => [],
        'cluster_wide' => false,
        'environments' => [],
        'locations' => [],
        'nodes' => [],
    ];

    switch ($_GET['type']) {
        case 'vpsadmin':
            $ret['vpsadmin'][] = $_GET['obj_id'];
            break;

        case 'cluster':
            $ret['cluster_wide'] = true;
            break;

        case 'environment':
        case 'location':
        case 'node':
            $ret[$_GET['type'] . 's'][] = $_GET['obj_id'];
            break;

        default:
    }

    return $ret;
}

function outage_entities_to_array($outage)
{
    $ret = [
        'vpsadmin' => [],
        'cluster' => false,
        'environments' => [],
        'locations' => [],
        'nodes' => [],
    ];
    $extra = [];

    foreach ($outage->entity->list() as $ent) {
        switch ($ent->name) {
            case 'vpsAdmin':
                $ret['vpsadmin'][] = $ent->entity_id;
                break;

            case 'Cluster':
                $ret['cluster'] = true;
                break;

            case 'Environment':
                $ret['environments'][] = $ent->entity_id;
                break;

            case 'Location':
                $ret['locations'][] = $ent->entity_id;
                break;

            case 'Node':
                $ret['nodes'][] = $ent->entity_id;
                break;

            default:
                $extra[] = $ent->name;
        }
    }

    $ret['additional'] = implode(',', $extra);

    return $ret;
}

function outage_report_form()
{
    global $xtpl, $api;

    $input = $api->outage->create->getParameters('input');

    $xtpl->table_title(_('Outage Report'));

    $xtpl->form_create('?page=outage&action=report', 'post');

    $xtpl->form_add_input(_('Date and time') . ':', 'text', '30', 'begins_at', date('Y-m-d H:i'));
    $xtpl->form_add_number(_('Duration') . ':', 'duration', post_val('duration'), 0, 999999, 1, 'minutes');
    api_param_to_form('type', $input->type, post_val('type', 'outage'));
    api_param_to_form('impact', $input->impact);
    api_param_to_form('auto_resolve', $input->auto_resolve);

    $entities = maintenance_to_entities();

    $xtpl->form_add_select(
        _('vpsAdmin') . ':',
        'vpsadmin[]',
        resource_list_to_options($api->component->list(), 'id', 'label', false),
        $entities['vpsadmin'],
        '',
        true,
        5
    );
    $xtpl->form_add_checkbox(
        _('Cluster-wide') . ':',
        'cluster_wide',
        '1',
        $entities['cluster_wide']
    );
    $xtpl->form_add_select(
        _('Environments') . ':',
        'environments[]',
        resource_list_to_options($api->environment->list(), 'id', 'label', false),
        $entities['environments'],
        '',
        true,
        5
    );
    $xtpl->form_add_select(
        _('Locations') . ':',
        'locations[]',
        resource_list_to_options($api->location->list(), 'id', 'label', false),
        $entities['locations'],
        '',
        true,
        5
    );
    $xtpl->form_add_select(
        _('Nodes') . ':',
        'nodes[]',
        resource_list_to_options($api->node->list(), 'id', 'domain_name', false),
        $entities['nodes'],
        '',
        true,
        20
    );
    $xtpl->form_add_input(
        _('Additional systems') . ':',
        'text',
        '70',
        'entities',
        post_val('entities'),
        _('Comma separated list of other affected systems')
    );

    foreach ($api->language->list() as $lang) {
        $xtpl->form_add_input(
            $lang->label . ' ' . _('summary') . ':',
            'text',
            '70',
            $lang->code . '_summary',
            post_val($lang->code . '_summary')
        );
        $xtpl->form_add_textarea(
            $lang->label . ' ' . _('description') . ':',
            70,
            8,
            $lang->code . '_description',
            post_val($lang->code . '_description')
        );
    }

    $xtpl->form_add_select(
        _('Handled by') . ':',
        'handlers[]',
        resource_list_to_options($api->user->list(['admin' => true]), 'id', 'full_name', false),
        post_val('handlers'),
        '',
        true,
        10
    );

    $xtpl->form_out(_('Continue'));
}

function outage_edit_attrs_form($id)
{
    global $xtpl, $api;

    $input = $api->outage->update->getParameters('input');
    $outage = $api->outage->show($id);

    $xtpl->sbar_add(_('Back'), '?page=outage&action=show&id=' . $outage->id);

    $xtpl->title(_('Outage') . ' #' . $outage->id);
    $xtpl->table_title(_('Edit original report'));
    $xtpl->form_create('?page=outage&action=edit_attrs&id=' . $outage->id, 'post');

    $xtpl->form_add_input(
        _('Date and time') . ':',
        'text',
        '30',
        'begins_at',
        tolocaltz($outage->begins_at, 'Y-m-d H:i')
    );
    $xtpl->form_add_input(
        _('Finished at') . ':',
        'text',
        '30',
        'finished_at',
        $outage->finished_at ? tolocaltz($outage->finished_at, 'Y-m-d H:i') : ''
    );
    $xtpl->form_add_number(
        _('Duration') . ':',
        'duration',
        post_val('duration', $outage->duration),
        0,
        999999,
        1,
        'minutes'
    );

    api_param_to_form('type', $input->type, $outage->type);
    api_param_to_form('impact', $input->impact, $outage->impact);
    api_param_to_form('auto_resolve', $input->auto_resolve, $outage->auto_resolve);

    foreach ($api->language->list() as $lang) {
        $xtpl->form_add_input(
            $lang->label . ' ' . _('summary') . ':',
            'text',
            '70',
            $lang->code . '_summary',
            post_val($lang->code . '_summary', $outage->{$lang->code . '_summary'})
        );
        $xtpl->form_add_textarea(
            $lang->label . ' ' . _('description') . ':',
            70,
            8,
            $lang->code . '_description',
            post_val($lang->code . '_description', $outage->{$lang->code . '_description'})
        );
    }

    $xtpl->table_td(
        _('<strong>This form is used to edit the original report.</strong>') .
        ' ' .
        '<a href="?page=outage&action=update&id=' . $outage->id . '">' . _('Post an update') . '</a>' .
        ' ' .
        _('instead') . '?',
        false,
        false,
        '2'
    );
    $xtpl->table_tr();

    $xtpl->form_out(_('Save'));
}

function outage_edit_systems_form($id)
{
    global $xtpl, $api;

    $outage = $api->outage->show($id);

    $xtpl->sbar_add(_('Back'), '?page=outage&action=show&id=' . $outage->id);

    $xtpl->title(_('Outage') . ' #' . $outage->id);
    $xtpl->table_title(_('Edit affected entities and handlers'));
    $xtpl->form_create('?page=outage&action=edit_systems&id=' . $outage->id, 'post');

    $ents = outage_entities_to_array($outage);

    $xtpl->form_add_select(
        _('vpsAdmin') . ':',
        'vpsadmin[]',
        resource_list_to_options($api->component->list(), 'id', 'label', false),
        post_val('vpsadmin', $ents['vpsadmin']),
        '',
        true,
        5
    );
    $xtpl->form_add_checkbox(
        _('Cluster-wide') . ':',
        'cluster_wide',
        '1',
        post_val('cluster_wide', $ents['cluster'])
    );
    $xtpl->form_add_select(
        _('Environments') . ':',
        'environments[]',
        resource_list_to_options($api->environment->list(), 'id', 'label', false),
        post_val('environments', $ents['environments']),
        '',
        true,
        5
    );
    $xtpl->form_add_select(
        _('Locations') . ':',
        'locations[]',
        resource_list_to_options($api->location->list(), 'id', 'label', false),
        post_val('locations', $ents['locations']),
        '',
        true,
        5
    );
    $xtpl->form_add_select(
        _('Nodes') . ':',
        'nodes[]',
        resource_list_to_options($api->node->list(), 'id', 'domain_name', false),
        post_val('nodes', $ents['nodes']),
        '',
        true,
        20
    );
    $xtpl->form_add_input(
        _('Additional systems') . ':',
        'text',
        '70',
        'entities',
        post_val('entities', $ents['additional']),
        _('Comma separated list of other affected systems')
    );

    $xtpl->form_add_select(
        _('Handled by') . ':',
        'handlers[]',
        resource_list_to_options($api->user->list(['admin' => true]), 'id', 'full_name', false),
        post_val('handlers', array_map(
            function ($h) { return $h->user_id; },
            $outage->handler->list()->asArray()
        )),
        '',
        true,
        10
    );

    $xtpl->form_out(_('Save'));
}

function outage_update_form($id)
{
    global $xtpl, $api;

    $input = $api->outage->create->getParameters('input');
    $outage = $api->outage->show($id);

    $xtpl->sbar_add(_('Back'), '?page=outage&action=show&id=' . $outage->id);

    $xtpl->title(_('Outage') . ' #' . $id);
    $xtpl->table_title(_('Post update'));
    $xtpl->form_create('?page=outage&action=update&id=' . $outage->id, 'post');

    $xtpl->form_add_input(
        _('Date and time') . ':',
        'text',
        '30',
        'begins_at',
        tolocaltz($outage->begins_at, 'Y-m-d H:i')
    );
    $xtpl->form_add_input(
        _('Finished at') . ':',
        'text',
        '30',
        'finished_at',
        $outage->finished_at ? tolocaltz($outage->finished_at, 'Y-m-d H:i') : ''
    );
    $xtpl->form_add_number(
        _('Duration') . ':',
        'duration',
        post_val('duration', $outage->duration),
        0,
        999999,
        1,
        'minutes'
    );
    api_param_to_form('impact', $input->impact, $outage->impact);

    $xtpl->form_add_select(_('State') . ':', 'state', [
        'staged' => _('staged'),
        'announced' => _('announced'),
        'cancelled' => _('cancelled'),
        'resolved' => _('resolved'),
    ], post_val('state', $outage->state));

    foreach ($api->language->list() as $lang) {
        $xtpl->form_add_input(
            $lang->label . ' ' . _('summary') . ':',
            'text',
            '70',
            $lang->code . '_summary',
            post_val($lang->code . '_summary')
        );
        $xtpl->form_add_textarea(
            $lang->label . ' ' . _('description') . ':',
            70,
            8,
            $lang->code . '_description',
            post_val($lang->code . '_description')
        );
    }

    $xtpl->form_add_checkbox(
        _('Send mails') . ':',
        'send_mail',
        '1',
        ($_POST['state'] && !$_POST['send_mail']) ? false : true
    );

    $xtpl->form_out(_('Post update'));
}

function outage_details($id)
{
    global $xtpl, $api;

    if (isAdmin()) {
        $xtpl->sbar_add(_('Edit outage'), '?page=outage&action=edit_attrs&id=' . $id);
        $xtpl->sbar_add(_('Edit affected systems & handlers'), '?page=outage&action=edit_systems&id=' . $id);
        $xtpl->sbar_add(_('Post update'), '?page=outage&action=update&id=' . $id);
        $xtpl->sbar_add(_('Affected users'), '?page=outage&action=users&id=' . $id);
    }

    $xtpl->sbar_add(_('Affected VPS'), '?page=outage&action=vps&id=' . $id);

    $outage = $api->outage->show($id);
    $langs = $api->language->list();

    $xtpl->title(_('Outage') . ' #' . $id);

    if (isLoggedIn()) {
        $xtpl->table_title(_('Status'));

        if (isAdmin()) {
            if ($outage->state == 'staged') {
                $xtpl->table_td(_('Affected VPSes have not been checked yet.'));
                $xtpl->table_tr();

            } else {
                $xtpl->table_td(_('Affected users') . ':');
                $xtpl->table_td(
                    '<a href="?page=outage&action=users&id=' . $outage->id . '">' .
                    $outage->affected_user_count .
                    '</a>'
                );
                $xtpl->table_tr();

                $xtpl->table_td(_('Directly affected VPS') . ':');
                $xtpl->table_td(
                    '<a href="?page=outage&action=vps&id=' . $outage->id . '&direct=yes">' .
                    $outage->affected_direct_vps_count .
                    '</a>'
                );
                $xtpl->table_tr();

                $xtpl->table_td(_('Indirectly affected VPS') . ':');
                $xtpl->table_td(
                    '<a href="?page=outage&action=vps&id=' . $outage->id . '&direct=no">' .
                    $outage->affected_indirect_vps_count .
                    '</a>'
                );
                $xtpl->table_tr();

                $xtpl->table_td(_('Affected exports') . ':');
                $xtpl->table_td(
                    '<a href="?page=outage&action=exports&id=' . $outage->id . '">' .
                    $outage->affected_export_count .
                    '</a>'
                );
                $xtpl->table_tr();
            }

        } else {
            $affected_vpses = $api->vps_outage->list([
                'outage' => $outage->id,
                'meta' => [
                    'includes' => 'vps',
                ],
            ]);

            $affected_exports = $api->export_outage->list([
                'outage' => $outage->id,
                'meta' => [
                    'includes' => 'export',
                ],
            ]);

            if ($affected_vpses->count() || $affected_exports->count()) {
                if ($affected_vpses->count()) {
                    $xtpl->table_td(_('Affected VPS') . ':');
                    $s = implode("\n<br>\n", array_map(
                        function ($outage_vps) {
                            $v = $outage_vps->vps;
                            return vps_link($v) . ' - ' . h($v->hostname) . ($outage_vps->direct ? '' : ' (indirectly)');

                        },
                        $affected_vpses->asArray()
                    ));

                    $xtpl->table_td($s);
                    $xtpl->table_tr();
                }

                if ($affected_exports->count()) {
                    $xtpl->table_td(_('Affected exports') . ':');
                    $s = implode("\n<br>\n", array_map(
                        function ($outage_ex) {
                            $e = $outage_ex->export;
                            return export_link($e) . ' - ' . h($e->path);

                        },
                        $affected_exports->asArray()
                    ));

                    $xtpl->table_td($s);
                    $xtpl->table_tr();
                }

            } else {
                $xtpl->table_td('<strong>' . _('You are not affected by this outage.') . '</strong>');
                $xtpl->table_tr();
            }
        }

        $xtpl->table_out();
    }

    $xtpl->table_title(_('Information'));
    $xtpl->table_td(_('Begins at') . ':');
    $xtpl->table_td(tolocaltz($outage->begins_at, "Y-m-d H:i:s T"));
    $xtpl->table_tr();

    $xtpl->table_td(_('Duration') . ':');
    $xtpl->table_td($outage->duration . ' ' . _('minutes'));
    $xtpl->table_tr();

    $xtpl->table_td(_('Type') . ':');
    $xtpl->table_td($outage->type);
    $xtpl->table_tr();

    $xtpl->table_td(_('State') . ':');
    $xtpl->table_td($outage->state);
    $xtpl->table_tr();

    $xtpl->table_td(_('Impact') . ':');
    $xtpl->table_td($outage->impact);
    $xtpl->table_tr();

    if (isAdmin()) {
        $xtpl->table_td(_('Auto-resolve') . ':');
        $xtpl->table_td(boolean_icon($outage->auto_resolve));
        $xtpl->table_tr();
    }

    $xtpl->table_td(_('Affected systems') . ':');
    $xtpl->table_td(implode("\n<br>\n", array_map(
        function ($ent) { return h($ent->label); },
        $outage->entity->list()->asArray()
    )));
    $xtpl->table_tr();

    $xtpl->table_td(_('Summary') . ':', false, false, '1', $langs->count() + 1);
    $xtpl->table_tr();

    foreach ($langs as $lang) {
        $name = $lang->code . '_summary';

        $xtpl->table_td('<strong>' . h($lang->label) . '</strong>: ' . h($outage->{$name}));
        $xtpl->table_tr();
    }

    $xtpl->table_td(_('Description') . ':', false, false, '1', $langs->count() + 1);
    $xtpl->table_tr();

    foreach ($langs as $lang) {
        $name = $lang->code . '_description';

        $xtpl->table_td('<strong>' . h($lang->label) . '</strong>: ' . nl2br(h($outage->{$name})));
        $xtpl->table_tr();
    }

    $xtpl->table_td(_('Handled by') . ':');
    $xtpl->table_td(implode(', ', array_map(
        function ($h) { return h($h->full_name); },
        $outage->handler->list()->asArray()
    )));
    $xtpl->table_tr();
    $xtpl->table_out();

    if (isAdmin() && $outage->state == 'staged') {
        $xtpl->table_title(_('Change state'));
        $xtpl->form_create('?page=outage&action=set_state&id=' . $id, 'post');
        $xtpl->form_add_select(_('State') . ':', 'state', [
            'announced' => _('Announce'),
            'cancelled' => _('Cancel'),
            'resolved' => _('Resolve'),
        ], post_val('state'));

        $xtpl->form_add_checkbox(
            _('Send mails') . ':',
            'send_mail',
            '1',
            ($_POST['state'] && !$_POST['send_mail']) ? false : true
        );

        $xtpl->form_out(_('Change'));
    }

    $xtpl->table_title(_('Updates'));
    $xtpl->table_add_category(_('Date'));
    $xtpl->table_add_category(_('Summary'));
    $xtpl->table_add_category(_('Reported by'));

    foreach ($api->outage_update->list(['outage' => $outage->id]) as $update) {
        $xtpl->table_td(tolocaltz($update->created_at, "Y-m-d H:i:s T"));

        $summary = [];

        foreach ($langs as $lang) {
            $name = $lang->code . '_summary';

            if (!$update->{$name}) {
                continue;
            }

            $summary[] = '<strong>' . h($lang->label) . '</strong>: ' . h($update->{$name});
        }

        $xtpl->table_td(implode("\n<br>\n", $summary));
        $xtpl->table_td($update->reporter_name);

        $changes = [];
        $check = ['begins_at', 'finished_at', 'state', 'type', 'duration'];

        foreach ($check as $p) {
            if ($update->{$p}) {
                switch ($p) {
                    case 'begins_at':
                        $changes[] = _("Begins at:") . ' ' . tolocaltz($update->begins_at, "Y-m-d H:i T");
                        break;

                    case 'finished_at':
                        $changes[] = _("Finished at:") . ' ' . tolocaltz($update->finished_at, "Y-m-d H:i T");
                        break;

                    case 'state':
                        $changes[] = _("State:") . ' ' . $update->state;
                        break;

                    case 'impact':
                        $changes[] = _("Impact type:") . ' ' . $update->impact;
                        break;

                    case 'duration':
                        $changes[] = _("Duration:") . ' ' . $update->duration . ' ' . _('minutes');
                        break;
                }
            }
        }

        $desc = [];

        foreach ($langs as $lang) {
            $name = $lang->code . '_description';

            if (!$update->{$name}) {
                continue;
            }

            $desc[] = '<strong>' . h($lang->label) . '</strong>: ' . nl2br(h($update->{$name}));
        }

        $str = implode("\n<br><br>\n", array_filter([
            implode("\n<br>\n", $changes),
            implode("\n<br><br>\n", $desc),
        ]));

        $xtpl->table_tr();

        if ($str) {
            $xtpl->table_td($str, false, false, 3);
            $xtpl->table_tr();
        }
    }

    $xtpl->table_out();
}

function outage_list()
{
    global $xtpl, $api;

    if (isAdmin()) {
        $xtpl->sbar_add(_('New report'), '?page=outage&action=report&t=' . csrf_token());
    }

    $xtpl->title(_('Outage list'));
    $xtpl->table_title(_('Filters'));
    $xtpl->form_create('', 'get', 'outage-list', false);

    $xtpl->table_td(
        _("Limit") . ':' .
        '<input type="hidden" name="page" value="outage">' .
        '<input type="hidden" name="action" value="list">'
    );
    $xtpl->form_add_input_pure('text', '40', 'limit', get_val('limit', '25'), '');
    $xtpl->table_tr();

    $input = $api->outage->list->getParameters('input');

    api_param_to_form('type', $input->type, $_GET['type'], null, true);
    api_param_to_form('state', $input->state, $_GET['state'], null, true);
    api_param_to_form('impact', $input->impact, $_GET['impact'], null, true);

    if (isLoggedIn()) {
        $xtpl->form_add_select(_('Affects me?'), 'affected', [
            '' => '---',
            'yes' => _('Yes'),
            'no' => _('No'),
        ], get_val('affected'));
    }

    if (isAdmin()) {
        $xtpl->form_add_input(_('User ID') . ':', 'text', '30', 'user', get_val('user'), '');
        $xtpl->form_add_input(_('Handled by') . ':', 'text', '30', 'handled_by', get_val('handled_by'), '');
    }

    if (isLoggedIn()) {
        $xtpl->form_add_input(_('VPS ID') . ':', 'text', '30', 'vps', get_val('vps'), '');
        $xtpl->form_add_input(_('Export ID') . ':', 'text', '30', 'export', get_val('export'), '');
        $xtpl->form_add_select(
            _('Environment') . ':',
            'environment',
            resource_list_to_options($api->environment->list()),
            get_val('environment')
        );
        $xtpl->form_add_select(
            _('Location') . ':',
            'location',
            resource_list_to_options($api->location->list()),
            get_val('location')
        );
        $xtpl->form_add_select(
            _('Node') . ':',
            'node',
            resource_list_to_options($api->node->list(), 'id', 'domain_name'),
            get_val('node')
        );
        $xtpl->form_add_select(
            _('vpsAdmin') . ':',
            'vpsadmin',
            resource_list_to_options($api->component->list()),
            get_val('vpsadmin')
        );
    }

    if (isAdmin()) {
        $xtpl->form_add_input(
            _('Entity name') . ':',
            'text',
            '30',
            'entity_name',
            get_val('entity_name'),
            ''
        );
        $xtpl->form_add_input(
            _('Entity ID') . ':',
            'text',
            '30',
            'entity_id',
            get_val('entity_id'),
            ''
        );
    }

    api_param_to_form('order', $input->order, $_GET['order']);

    $xtpl->form_out(_('Show'));

    $xtpl->table_add_category(_('Date'));
    $xtpl->table_add_category(_('Duration'));
    $xtpl->table_add_category(_('Type'));
    $xtpl->table_add_category(_('State'));
    $xtpl->table_add_category(_('Systems'));
    $xtpl->table_add_category(_('Impact'));
    $xtpl->table_add_category(_('Reason'));

    if (isAdmin()) {
        $xtpl->table_add_category(_('Users'));
        $xtpl->table_add_category(_('VPS'));

    } elseif (isLoggedIn()) {
        $xtpl->table_add_category(_('Affects me?'));
    }

    $xtpl->table_add_category('');

    $params = [
        'limit' => get_val('limit', 25),
    ];

    foreach (['affected'] as $v) {
        if ($_GET[$v] === 'yes') {
            $params[$v] = true;
        } elseif ($_GET[$v] === 'no') {
            $params[$v] = false;
        }
    }

    $filters = [
        'state', 'type', 'impact', 'user', 'handled_by', 'vps', 'export', 'order',
        'environment', 'location', 'node', 'vpsadmin', 'entity_name', 'entity_id',
    ];

    foreach ($filters as $v) {
        if ($_GET[$v]) {
            $params[$v] = $_GET[$v];
        }
    }

    $outages = $api->outage->list($params);

    foreach ($outages as $outage) {
        $xtpl->table_td(tolocaltz($outage->begins_at, 'Y-m-d H:i'));
        $xtpl->table_td($outage->duration, false, true);
        $xtpl->table_td($outage->type);
        $xtpl->table_td($outage->state);
        $xtpl->table_td(implode(', ', array_map(
            function ($v) { return h($v->label); },
            $outage->entity->list()->asArray()
        )));
        $xtpl->table_td($outage->impact);
        $xtpl->table_td(h($outage->en_summary));

        if (isAdmin()) {
            if ($outage->state == 'staged') {
                $xtpl->table_td('-', false, true);
                $xtpl->table_td('-', false, true);

            } else {
                $xtpl->table_td(
                    '<a href="?page=outage&action=users&id=' . $outage->id . '">' .
                    $outage->affected_user_count .
                    '</a>',
                    false,
                    true
                );
                $xtpl->table_td(
                    '<a href="?page=outage&action=vps&id=' . $outage->id . '">' .
                    $outage->affected_direct_vps_count .
                    '</a>',
                    false,
                    true
                );
            }

        } elseif (isLoggedIn()) {
            $xtpl->table_td(boolean_icon($outage->affected));
        }

        $xtpl->table_td('<a href="?page=outage&action=show&id=' . $outage->id . '"><img src="template/icons/m_edit.png"  title="' . _("Details") . '" /></a>');

        $xtpl->table_tr();
    }

    $xtpl->table_out();
}

function outage_affected_users($id)
{
    global $xtpl, $api;

    $outage = $api->outage->show($id);

    $xtpl->sbar_add(_('Back'), '?page=outage&action=show&id=' . $outage->id);

    $xtpl->title(_('Outage') . ' #' . $outage->id);
    $xtpl->table_title(_('Affected users'));

    $users = $api->user_outage->list([
        'outage' => $outage->id,
        'meta' => ['includes' => 'user'],
    ]);

    $xtpl->table_add_category(_('Login'));
    $xtpl->table_add_category(_('Name'));
    $xtpl->table_add_category(_('VPS count'));
    $xtpl->table_add_category(_('Export count'));

    foreach ($users as $out) {
        $xtpl->table_td(user_link($out->user));
        $xtpl->table_td(h($out->user->full_name));
        $xtpl->table_td(
            '<a href="?page=outage&action=vps&id=' . $outage->id . '&user=' . $out->user_id . '">' .
            $out->vps_count .
            '</a>',
            false,
            true
        );
        $xtpl->table_td(
            '<a href="?page=outage&action=exports&id=' . $outage->id . '&user=' . $out->user_id . '">' .
            $out->export_count .
            '</a>',
            false,
            true
        );
        $xtpl->table_tr();
    }

    $xtpl->table_out();
}

function outage_affected_vps($id)
{
    global $xtpl, $api;

    $outage = $api->outage->show($id);

    $xtpl->sbar_add(_('Back'), '?page=outage&action=show&id=' . $outage->id);

    $xtpl->title(_('Outage') . ' #' . $outage->id);

    if (isAdmin()) {
        $xtpl->table_title(_('Filters'));
        $xtpl->form_create('', 'get', 'outage-list', false);

        $xtpl->table_td(
            _("User ID") . ':' .
            '<input type="hidden" name="page" value="outage">' .
            '<input type="hidden" name="action" value="vps">' .
            '<input type="hidden" name="id" value="' . $outage->id . '">'
        );
        $xtpl->form_add_input_pure('text', '30', 'user', get_val('user'), '');
        $xtpl->table_tr();

        $xtpl->form_add_select(
            _('Environment') . ':',
            'environment',
            resource_list_to_options($api->environment->list()),
            get_val('environment')
        );
        $xtpl->form_add_select(
            _('Location') . ':',
            'location',
            resource_list_to_options($api->location->list()),
            get_val('location')
        );
        $xtpl->form_add_select(
            _('Node') . ':',
            'node',
            resource_list_to_options($api->node->list(), 'id', 'domain_name'),
            get_val('node')
        );
        $xtpl->form_add_select(
            _('Direct') . ':',
            'direct',
            ['' => '---', 'yes' => _('Yes'), 'no' => _('No')],
            get_val('direct')
        );

        $xtpl->form_out(_('Show'));
    }

    $xtpl->table_title(_('Affected VPS'));

    $params = [
        'outage' => $outage->id,
        'meta' => ['includes' => 'vps,user,environment,location,node'],
    ];

    foreach (['user', 'environment', 'location', 'node'] as $v) {
        if ($_GET[$v]) {
            $params[$v] = $_GET[$v];
        }
    }

    if ($_GET['direct']) {
        $params['direct'] = $_GET['direct'] === 'yes';
    }

    $vpses = $api->vps_outage->list($params);

    $xtpl->table_add_category(_('VPS ID'));
    $xtpl->table_add_category(_('Hostname'));
    $xtpl->table_add_category(_('User'));
    $xtpl->table_add_category(_('Node'));
    $xtpl->table_add_category(_('Environment'));
    $xtpl->table_add_category(_('Location'));

    foreach ($vpses as $out) {
        $xtpl->table_td(vps_link($out->vps));
        $xtpl->table_td(h($out->vps->hostname));
        $xtpl->table_td(user_link($out->vps->user));
        $xtpl->table_td($out->node->domain_name);
        $xtpl->table_td($out->environment->label);
        $xtpl->table_td($out->location->label);
        $xtpl->table_tr();
    }

    $xtpl->table_out();
}

function outage_affected_exports($id)
{
    global $xtpl, $api;

    $outage = $api->outage->show($id);

    $xtpl->sbar_add(_('Back'), '?page=outage&action=show&id=' . $outage->id);

    $xtpl->title(_('Outage') . ' #' . $outage->id);

    if (isAdmin()) {
        $xtpl->table_title(_('Filters'));
        $xtpl->form_create('', 'get', 'outage-list', false);

        $xtpl->table_td(
            _("User ID") . ':' .
            '<input type="hidden" name="page" value="outage">' .
            '<input type="hidden" name="action" value="vps">' .
            '<input type="hidden" name="id" value="' . $outage->id . '">'
        );
        $xtpl->form_add_input_pure('text', '30', 'user', get_val('user'), '');
        $xtpl->table_tr();

        $xtpl->form_add_select(
            _('Environment') . ':',
            'environment',
            resource_list_to_options($api->environment->list()),
            get_val('environment')
        );
        $xtpl->form_add_select(
            _('Location') . ':',
            'location',
            resource_list_to_options($api->location->list()),
            get_val('location')
        );
        $xtpl->form_add_select(
            _('Node') . ':',
            'node',
            resource_list_to_options($api->node->list(), 'id', 'domain_name'),
            get_val('node')
        );

        $xtpl->form_out(_('Show'));
    }

    $xtpl->table_title(_('Affected exports'));

    $params = [
        'outage' => $outage->id,
        'meta' => ['includes' => 'export,user,environment,location,node'],
    ];

    foreach (['user', 'environment', 'location', 'node'] as $v) {
        if ($_GET[$v]) {
            $params[$v] = $_GET[$v];
        }
    }

    $exports = $api->export_outage->list($params);

    $xtpl->table_add_category(_('Export ID'));
    $xtpl->table_add_category(_('Address'));
    $xtpl->table_add_category(_('Path'));
    $xtpl->table_add_category(_('User'));
    $xtpl->table_add_category(_('Node'));
    $xtpl->table_add_category(_('Environment'));
    $xtpl->table_add_category(_('Location'));

    foreach ($exports as $out) {
        $xtpl->table_td(export_link($out->export));
        $xtpl->table_td($out->export->host_ip_address->addr);
        $xtpl->table_td($out->export->path);
        $xtpl->table_td(user_link($out->export->user));
        $xtpl->table_td($out->node->domain_name);
        $xtpl->table_td($out->environment->label);
        $xtpl->table_td($out->location->label);
        $xtpl->table_tr();
    }

    $xtpl->table_out();
}

function outage_list_recent()
{
    global $xtpl, $api;

    $outages = $api->outage->list([
        'recent_since' => date('c', strtotime('-2 days')),
        'order' => 'oldest',
    ]);

    $planned = [];
    $active = [];
    $past = [];
    $now = time();

    foreach ($outages as $outage) {
        if ($outage->state == 'announced') {
            $beginsAt = strtotime($outage->begins_at);

            if ($beginsAt > $now) {
                $planned[] = $outage;
            } else {
                $active[] = $outage;
            }
        } else {
            $past[] = $outage;
        }
    }

    if (count($planned) > 0) {
        $xtpl->table_title(outage_list_title(_('Planned'), $planned));
        outage_list_overview($planned);
    }

    if (count($active) > 0) {
        $xtpl->table_title(outage_list_title(_('Current'), $active));
        outage_list_overview($active);
    }

    if (count($past) > 0) {
        $xtpl->table_title(outage_list_title(_('Recently resolved'), $past));
        outage_list_overview($past);
    }
}

function outage_list_title($prefix, $outages)
{
    $hasMaintenance = false;
    $hasOutage = false;

    foreach ($outages as $outage) {
        if ($outage->type == 'maintenance') {
            $hasMaintenance = true;
        } else {
            $hasOutage = true;
        }

        if ($hasMaintenance && $hasOutage) {
            break;
        }
    }

    if ($hasMaintenance && $hasOutage) {
        return $prefix . ' ' . _('maintenances and outages');
    } elseif ($hasMaintenance) {
        return $prefix . ' ' . _('maintenances');
    } elseif ($hasOutage) {
        return $prefix . ' ' . _('outages');
    } else {
        return $prefix . ' ' . _('maintenances and outages');
    }
}

function outage_list_overview($outages)
{
    global $xtpl;

    $xtpl->table_add_category(_('Date'));
    $xtpl->table_add_category(_('Duration'));
    $xtpl->table_add_category(_('Type'));
    $xtpl->table_add_category(_('Systems'));
    $xtpl->table_add_category(_('Impact'));
    $xtpl->table_add_category(_('Reason'));

    if (isAdmin()) {
        $xtpl->table_add_category(_('Users'));
        $xtpl->table_add_category(_('VPS'));

    } elseif (isLoggedIn()) {
        $xtpl->table_add_category(_('Affects me?'));
    }

    $xtpl->table_add_category('');

    foreach ($outages as $outage) {
        $xtpl->table_td(tolocaltz($outage->begins_at, 'Y-m-d H:i'));
        $xtpl->table_td($outage->duration . ' min', false, true);
        $xtpl->table_td($outage->type);
        $xtpl->table_td(implode(', ', array_map(
            function ($v) { return h($v->label); },
            $outage->entity->list()->asArray()
        )));
        $xtpl->table_td($outage->impact);
        $xtpl->table_td(h($outage->en_summary));

        if (isAdmin()) {
            $xtpl->table_td(
                '<a href="?page=outage&action=users&id=' . $outage->id . '">' .
                $outage->affected_user_count .
                '</a>',
                false,
                true
            );
            $xtpl->table_td(
                '<a href="?page=outage&action=vps&id=' . $outage->id . '">' .
                $outage->affected_direct_vps_count .
                '</a>',
                false,
                true
            );

        } elseif (isLoggedIn()) {
            $xtpl->table_td(boolean_icon($outage->affected));
        }

        $xtpl->table_td('<a href="?page=outage&action=show&id=' . $outage->id . '"><img src="template/icons/m_edit.png"  title="' . _("Details") . '" /></a>');

        $xtpl->table_tr();
    }

    $xtpl->table_out();
}
