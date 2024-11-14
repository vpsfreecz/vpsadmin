<?php

function monitoring_list()
{
    global $xtpl, $api;

    $params = [
        'limit' => get_val('limit', 25),
    ];

    $ordering = $_GET['order'] ?? $api->monitored_event->index->getParameters('input')->order->default;

    if ($ordering == 'oldest' || $ordering == 'latest') {
        $paginationOptions = ['inputParameter' => 'from_id', 'outputParameter' => 'id'];
    } else {
        $paginationOptions = ['inputParameter' => 'from_duration', 'outputParameter' => 'duration'];
    }

    $paginateBy = $paginationOptions['inputParameter'];

    if (($_GET[$paginateBy] ?? 0) > 0) {
        $params[$paginateBy] = $_GET[$paginateBy];
    }

    $filters = [
        'monitor', 'user', 'object_name', 'object_id', 'state', 'order',
    ];

    foreach ($filters as $v) {
        if ($_GET[$v]) {
            $params[$v] = $_GET[$v];
        }
    }

    $events = $api->monitored_event->list($params);
    $pagination = new \Pagination\System($events, null, $paginationOptions);

    $xtpl->title(_('Monitored event list'));
    $xtpl->table_title(_('Filters'));
    $xtpl->form_create('', 'get', 'monitoring-list', false);

    $xtpl->form_set_hidden_fields([
        'page' => 'monitoring',
        'action' => 'list',
    ]);

    $xtpl->form_add_input(_("Limit") . ':', 'text', '40', 'limit', get_val('limit', '25'), '');

    $input = $api->monitored_event->list->getParameters('input');

    api_param_to_form('monitor', $input->monitor, $_GET['monitor']);

    if (isAdmin()) {
        $xtpl->form_add_input(_('User ID') . ':', 'text', '30', 'user', get_val('user'), '');
    }

    api_param_to_form('object_name', $input->object_name, $_GET['object_name']);
    api_param_to_form('object_id', $input->object_id, $_GET['object_id']);
    api_param_to_form('state', $input->state, $_GET['state'], null, true);
    api_param_to_form('order', $input->order, $_GET['order']);

    $xtpl->form_out(_('Show'));

    $xtpl->table_add_category(_('Detected at'));
    $xtpl->table_add_category(_('State'));

    if (isAdmin()) {
        $xtpl->table_add_category(_('User'));
    }

    $xtpl->table_add_category(_('Object'));
    $xtpl->table_add_category(_('Label'));
    $xtpl->table_add_category(_('Duration'));
    $xtpl->table_add_category('');

    foreach ($events as $e) {
        $xtpl->table_td(tolocaltz($e->created_at));
        $xtpl->table_td($e->state);

        if (isAdmin()) {
            $xtpl->table_td($e->user_id ? user_link($e->user) : '-');
        }

        $xtpl->table_td(
            transaction_concern_class($e->object_name) . ' ' .
            transaction_concern_link($e->object_name, $e->object_id)
        );
        $xtpl->table_td($e->label);
        $xtpl->table_td(format_duration($e->duration));
        $xtpl->table_td(
            '<a href="?page=monitoring&action=show&id=' . $e->id . '"><img src="template/icons/vps_edit.png" alt="' . _('Details') . '" title="' . _('Details') . '"></a>'
        );
        $xtpl->table_tr();
    }

    $xtpl->table_pagination($pagination);
    $xtpl->table_out();
}

function monitoring_event()
{
    global $xtpl, $api;

    $e = $api->monitored_event->show($_GET['id']);

    $xtpl->title(_('Event') . ' #' . $e->id . ': ' . $e->label);

    $xtpl->table_td(_('Object') . ':');
    $xtpl->table_td(
        transaction_concern_class($e->object_name) . ' ' .
        transaction_concern_link($e->object_name, $e->object_id)
    );
    $xtpl->table_tr();

    $xtpl->table_td(_('Issue') . ':');
    $xtpl->table_td($e->issue);
    $xtpl->table_tr();

    if (isAdmin()) {
        $xtpl->table_td(_('User') . ':');
        $xtpl->table_td($e->user_id ? user_link($e->user) : '-');
        $xtpl->table_tr();
    }

    $xtpl->table_td(_('Monitored since') . ':');
    $xtpl->table_td(tolocaltz($e->created_at));
    $xtpl->table_tr();

    $xtpl->table_td(_('Duration') . ':');
    $xtpl->table_td(format_duration($e->duration));
    $xtpl->table_tr();

    $xtpl->table_td(_('State') . ':');
    $xtpl->table_td($e->state);
    $xtpl->table_tr();

    $xtpl->table_out();

    monitoring_ack_form($e);
    monitoring_ignore_form($e);

    $xtpl->table_title(_('Log'));
    $xtpl->form_create('', 'get', 'monitoring-list', false);

    $params = [
        'limit' => get_val('limit', 25),
    ];

    if (($_GET['from_id'] ?? 0) > 0) {
        $params['from_id'] = $_GET['from_id'];
    }

    $logs = $e->log->list($params);
    $pagination = new \Pagination\System($logs);

    $xtpl->form_set_hidden_fields([
        'page' => 'monitoring',
        'action' => 'show',
        'id' => $e->id,
    ]);

    $xtpl->form_add_input(_("Limit") . ':', 'text', '40', 'limit', get_val('limit', '25'), '');
    $xtpl->form_out(_('Show'));

    $xtpl->table_add_category(_('Date'));
    $xtpl->table_add_category(_('Value'));

    foreach ($logs as $log) {
        $xtpl->table_td(tolocaltz($log->created_at));
        $xtpl->table_td('<pre>' . h(print_r($log->value, true)) . '</pre>');
        $xtpl->table_tr();
    }

    $xtpl->table_pagination($pagination);
    $xtpl->table_out();
}

function monitoring_ack_form($id)
{
    global $xtpl, $api;

    if (is_numeric($id)) {
        $e = $api->monitored_event->show($id);
    } else {
        $e = $id;
    }

    $xtpl->table_title(_('Acknowledge event ') . $e->id . ': ' . $e->label);
    $xtpl->form_create('?page=monitoring&action=ack&id=' . $e->id);

    if ($id != $e) {
        $xtpl->table_td(_('Object') . ':');
        $xtpl->table_td(
            transaction_concern_class($e->object_name) . ' ' .
            transaction_concern_link($e->object_name, $e->object_id)
        );
        $xtpl->table_tr();

        $xtpl->table_td(_('Issue') . ':');
        $xtpl->table_td($e->issue);
        $xtpl->table_tr();
    }

    $xtpl->table_td(
        _('When the event is acknowledged, you will not be notified about ' .
            'the issue until it is resolved.'),
        false,
        false,
        3
    );
    $xtpl->table_tr();

    $xtpl->form_add_input(_('Until') . ':', 'text', '30', 'until', post_val('until'), 'Y-m-d, optional');
    $xtpl->form_add_checkbox(_('Confirm') . ':', 'confirm', '1', false);
    $xtpl->form_out(_('Acknowledge'));
}

function monitoring_ignore_form($id)
{
    global $xtpl, $api;

    if (is_numeric($id)) {
        $e = $api->monitored_event->show($id);
    } else {
        $e = $id;
    }

    $xtpl->table_title(_('Ignore event ') . $e->id . ': ' . $e->label);
    $xtpl->form_create('?page=monitoring&action=ignore&id=' . $e->id);

    if ($id != $e) {
        $xtpl->table_td(_('Object') . ':');
        $xtpl->table_td(
            transaction_concern_class($e->object_name) . ' ' .
            transaction_concern_link($e->object_name, $e->object_id)
        );
        $xtpl->table_tr();

        $xtpl->table_td(_('Issue') . ':');
        $xtpl->table_td($e->issue);
        $xtpl->table_tr();
    }

    $xtpl->table_td(
        _('When the event is ignored, you will not be notified about ' .
            'this issue any more, even should it arise in the future again.'),
        false,
        false,
        3
    );
    $xtpl->table_tr();

    $xtpl->form_add_input(_('Until') . ':', 'text', '30', 'until', post_val('until'), 'Y-m-d, optional');
    $xtpl->form_add_checkbox(_('Confirm') . ':', 'confirm', '1', false);
    $xtpl->form_out(_('Ignore'));
}
