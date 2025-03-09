<?php

use PgSql\Lob;

if (isLoggedIn()) {
    switch ($_GET['action'] ?? '') {
        case 'list':
            vps_user_data_list();
            break;

        case 'new':
            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();

                $params = [
                    'label' => $_POST['label'],
                    'format' => $_POST['format'],
                    'content' => $_POST['content'],
                ];

                if (isAdmin()) {
                    $params['user'] = $_POST['user'];
                }

                try {
                    $data = $api->vps_user_data->create($params);

                    notify_user(_('User data saved'), '');
                    redirect('?page=userdata&action=list&user=' . $data->user_id);
                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Failed to add user data'), $e->getResponse());
                    vps_user_data_new();
                }
            } else {
                vps_user_data_new();
            }
            break;

        case 'edit':
            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();

                try {
                    $data = $api->vps_user_data->show($_GET['id']);

                    $data->update([
                        'label' => $_POST['label'],
                        'format' => $_POST['format'],
                        'content' => $_POST['content'],
                    ]);

                    notify_user(_('User data saved'), '');
                    redirect('?page=userdata&action=list&user=' . $data->user_id);
                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Failed to update user data'), $e->getResponse());
                    vps_user_data_edit($_GET['id']);
                }
            } else {
                vps_user_data_edit($_GET['id']);
            }
            break;

        case 'deploy':
            try {
                csrf_check();

                $data = $api->vps_user_data->show($_GET['id']);
                $data->deploy(['vps' => $_POST['vps']]);

                notify_user(_('User data deployed'), '');
                redirect('?page=userdata&action=edit&id=' . $data->id . '&user=' . $data->user_id);
            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to deploy user data'), $e->getResponse());
                vps_user_data_edit($_GET['id']);
            }
            break;

        case 'delete':
            csrf_check();

            try {
                $data = $api->vps_user_data->show($_GET['id']);
                $data->delete();

                notify_user(_('User data deleted'), '');
                redirect('?page=userdata&action=list&user=' . $data->user_id);
            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to delete user data'), $e->getResponse());
                vps_user_data_list();
            }
            break;

        default:
            vps_user_data_list();
    }

    $xtpl->sbar_out(_('User data'));

} else {
    $xtpl->perex(
        _("Access forbidden"),
        _("You have to log in to be able to access vpsAdmin's functions")
    );
}
