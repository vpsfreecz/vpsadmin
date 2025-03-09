<?php

function vps_user_data_list()
{
    global $api, $xtpl;

    $xtpl->title(_('User data'));

    $params = [
        'limit' => get_val('limit', 25),
    ];

    $conds = ['user'];

    foreach ($conds as $c) {
        if ($_GET[$c] ?? false) {
            $params[$c] = $_GET[$c];
        }
    }

    $params['meta'] = [
        'includes' => 'user',
    ];

    $dataList = $api->vps_user_data->list($params);

    $pagination = new \Pagination\System($dataList);

    $xtpl->table_title(_('Filters'));
    $xtpl->form_create('', 'get', 'user-session-filter', false);

    $xtpl->form_set_hidden_fields([
        'page' => 'userdata',
        'action' => 'list',
    ]);

    $xtpl->form_add_input(_('Limit') . ':', 'text', '40', 'limit', get_val('limit', '25'), '');

    if (isAdmin()) {
        $xtpl->form_add_input(_("User") . ':', 'text', '40', 'user', get_val('user', ''), '');
    }

    $xtpl->form_out(_('Show'));

    if (isAdmin()) {
        $xtpl->table_add_category(_("User"));
    }

    $xtpl->table_add_category(_('Label'));
    $xtpl->table_add_category(_('Format'));
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');

    foreach ($dataList as $data) {
        if (isAdmin()) {
            $xtpl->table_td($data->user_id ? user_link($data->user) : '-');
        }

        $xtpl->table_td(h($data->label));
        $xtpl->table_td($data->format);

        $xtpl->table_td(
            '<a href="?page=userdata&action=edit&id=' . $data->id . '"><img src="template/icons/vps_edit.png" alt="' . _('Edit') . '" title="' . _('Edit') . '"></a>'
        );

        $xtpl->table_td(
            '<a href="?page=userdata&action=delete&id=' . $data->id . '&user=' . $data->user_id . '&t=' . csrf_token() . '"><img src="template/icons/vps_delete.png" alt="' . _('Delete') . '" title="' . _('Delete') . '"></a>'
        );
        $xtpl->table_tr();
    }

    $cols = isAdmin() ? 5 : 4;

    $xtpl->table_td(
        '<a href="?page=userdata&action=new">' . _('Add user data') . '</a>',
        false,
        true,
        $cols
    );
    $xtpl->table_tr();

    $xtpl->table_pagination($pagination);
    $xtpl->table_out();

    $xtpl->sbar_add(_('Add user data'), '?page=userdata&action=new');

    if (!isAdmin()) {
        $xtpl->sbar_add(_('Back to user details'), '?page=adminm&action=edit&id=' . $_SESSION['user']['id']);
    } elseif ($_GET['user'] ?? false) {
        $xtpl->sbar_add(_('Back to user details'), '?page=adminm&action=edit&id=' . $_GET['user']);
    }
}

function vps_user_data_new()
{
    global $api, $xtpl;

    $xtpl->title(_('Add user data'));

    $xtpl->form_create('?page=userdata&action=new', 'post');

    $input = $api->vps_user_data->create->getParameters('input');

    if (isAdmin()) {
        $xtpl->form_add_input(_('User ID') . ':', 'text', '30', 'user', post_val('user'));
    }

    api_param_to_form('label', $input->label);
    api_param_to_form('format', $input->format);
    api_param_to_form('content', $input->content);

    $xtpl->form_out(_('Add'));

    $xtpl->sbar_add(_('Back to list'), '?page=userdata&action=list&user=' . ($_GET['user'] ?? ''));
}

function vps_user_data_edit($id)
{
    global $api, $xtpl;

    $data = $api->vps_user_data->show($id);

    $xtpl->table_title(_('Edit user data'));
    $xtpl->form_create('?page=userdata&action=edit&id=' . $data->id, 'post');

    $input = $api->vps_user_data->create->getParameters('input');

    if (isAdmin()) {
        $xtpl->table_td(_('User') . ':');
        $xtpl->table_td(user_link($data->user));
        $xtpl->table_tr();
    }

    api_param_to_form('label', $input->label, $data->label);
    api_param_to_form('format', $input->format, $data->format);
    api_param_to_form('content', $input->content, $data->content);

    $xtpl->form_out(_('Save'));

    $xtpl->table_title(_('Deploy to VPS'));
    $xtpl->form_create('?page=userdata&action=deploy&id=' . $data->id, 'post');

    $xtpl->form_add_select(
        _('VPS') . ':',
        'vps',
        resource_list_to_options(
            $api->vps->list(['user' => $data->user_id]),
            'id',
            'hostname',
            false,
            function ($vps) { return $vps->id . ' - ' . h($vps->hostname); }
        ),
        post_val('vps')
    );

    $xtpl->form_out(_('Deploy'));

    $xtpl->sbar_add(_('Delete'), '?page=userdata&action=delete&id=' . $data->id . '&user=' . $data->user_id . '&t=' . csrf_token());
    $xtpl->sbar_add(_('Back to list'), '?page=userdata&action=list&user=' . $data->user_id);
}
