<?php

function list_object_history()
{
    global $xtpl, $api;

    $pagination = new \Pagination\System(null, $api->object_history->list);

    $xtpl->title(_('Object history'));

    if ($_GET['return_url']) {
        $xtpl->sbar_add(_('Back'), $_GET['return_url']);
        $xtpl->sbar_out(_("Object history"));
    }

    $xtpl->table_title(_('Filters'));
    $xtpl->form_create('', 'get', 'user-session-filter', false);

    $xtpl->form_set_hidden_fields(array_merge([
        'page' => 'history',
        'return_url' => $_GET['return_url'],
        'list' => '1',
    ], $pagination->hiddenFormFields()));

    $xtpl->form_add_input(_("Limit") . ':', 'text', '40', 'limit', get_val('limit', '25'), '');
    $xtpl->form_add_input(_("From ID") . ':', 'text', '40', 'from_id', get_val('from_id', '0'), '');

    if (isAdmin()) {
        $xtpl->form_add_input(_("User") . ':', 'text', '40', 'user', get_val('user', ''), '');
    }

    $xtpl->form_add_input(_("User session") . ':', 'text', '40', 'user_session', get_val('user_session', ''), '');
    $xtpl->form_add_input(_("Object") . ':', 'text', '40', 'object', get_val('object', ''), '');
    $xtpl->form_add_input(_("Object ID") . ':', 'text', '40', 'object_id', get_val('object_id', ''), '');
    $xtpl->form_add_input(_("Event") . ':', 'text', '40', 'event_type', get_val('event_type', ''), '');

    $xtpl->form_add_checkbox(_('Detailed output') . ':', 'details', '1', isset($_GET['details']));

    $xtpl->form_out(_('Show'));

    if (!$_GET['list']) {
        return;
    }

    $params = [
        'limit' => get_val('limit', 25),
        'from_id' => get_val('from_id', 0),
    ];

    $conds = ['user', 'user_session', 'object', 'object_id', 'event_type'];

    foreach ($conds as $c) {
        if ($_GET[$c]) {
            $params[$c] = $_GET[$c];
        }
    }

    $params['meta'] = ['includes' => 'user,user_session'];

    $events = $api->object_history->list($params);
    $pagination->setResourceList($events);

    $xtpl->table_add_category(_("Created at"));
    $xtpl->table_add_category(_("User"));
    $xtpl->table_add_category(_("Session"));
    $xtpl->table_add_category(_("Object"));
    $xtpl->table_add_category(_("Event"));
    $xtpl->table_add_category(_("Data"));

    foreach ($events as $e) {
        $xtpl->table_td(tolocaltz($e->created_at), false, false, 1, 1, 'top');

        if ($e->user_id) {
            $xtpl->table_td('<a href="?page=adminm&action=edit&id=' . $e->user_id . '">' . $e->user->login . '</a>', false, false, 1, 1, 'top');
            $xtpl->table_td('<a href="?page=adminm&action=user_sessions&id=' . $e->user_id . '&list=1&session_id=' . $e->user_session_id . '&details=1">' . $e->user_session_id . '</a>', false, false, 1, 1, 'top');

        } else {
            $xtpl->table_td('---', false, false, 1, 1, 'top');
            $xtpl->table_td('---', false, false, 1, 1, 'top');
        }

        $xtpl->table_td($e->object . ' ' . $e->object_id, false, false, 1, 1, 'top');
        $xtpl->table_td($e->event_type, false, false, 1, 1, 'top');
        $xtpl->table_td('<pre>' . h(print_r($e->event_data, true)) . '</pre>', false, false, 1, 1, 'top');
        $xtpl->table_tr();
    }

    $xtpl->table_pagination($pagination);
    $xtpl->table_out();
}
