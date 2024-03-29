<?php

if (isLoggedIn()) {
    $quotas = ['quota', 'refquota'];

    switch ($_GET['action']) {
        case 'new':
            if (isset($_POST['name'])) {
                csrf_check();

                $input_params = $api->dataset->create->getParameters('input');
                $params = [
                    'name' => $_POST['name'],
                    'dataset' => $_POST['dataset'] ? $_POST['dataset'] : $_GET['parent'],
                    'automount' => $_POST['automount'] ? true : false,
                ];

                foreach ($quotas as $quota) {
                    if (isset($_POST[$quota])) {
                        $params[$quota] = $_POST[$quota] * $DATASET_UNITS_TR[$_POST["quota_unit"]];
                    }
                }

                foreach ($DATASET_PROPERTIES as $p) {
                    if (!$_POST['inherit_' . $p]) {
                        $validators = $input_params->{$p}->validators;

                        if ($validators && $validators->include) {
                            $params[$p] = $_POST[$p];
                        } elseif (in_array($p, ['compression', 'atime', 'relatime'])) {
                            $params[$p] = isset($_POST[$p]);
                        } else {
                            $params[$p] = $_POST[$p];
                        }
                    }
                }

                try {
                    $api->dataset->create($params);

                    notify_user(_('Dataset created') . '');
                    redirect($_POST['return'] ? $_POST['return'] : '?page=');

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Dataset creation failed'), $e->getResponse());
                    dataset_create_form();
                }

            } else {
                dataset_create_form();
            }
            break;

        case 'edit':
            if (isset($_POST['return'])) {
                csrf_check();

                $ds = $api->dataset->find($_GET['id']);
                $input_params = $api->dataset->update->getParameters('input');
                $params = [];

                if (isAdmin()) {
                    $params['admin_override'] = isset($_POST['admin_override']);
                    $params['admin_lock_type'] = $_POST['admin_lock_type'];
                }

                foreach ($quotas as $quota) {
                    if (isset($_POST[$quota])) {
                        $params[$quota] = $_POST[$quota] * $DATASET_UNITS_TR[$_POST["quota_unit"]];
                    }
                }

                foreach ($DATASET_PROPERTIES as $p) {
                    if (!$_POST['inherit_' . $p]) {
                        $validators = $input_params->{$p}->validators;

                        if ($validators && $validators->include) {
                            $params[$p] = $_POST[$p];
                        } elseif (in_array($p, ['compression', 'atime', 'relatime'])) {
                            $params[$p] = isset($_POST[$p]);
                        } else {
                            $params[$p] = $_POST[$p];
                        }
                    }
                }

                try {
                    $ds->update($params);

                    notify_user(_('Dataset updated') . '');
                    redirect($_POST['return'] ? $_POST['return'] : '?page=');

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Dataset save failed'), $e->getResponse());
                    dataset_edit_form();
                }

            } else {
                dataset_edit_form();
            }
            break;

        case 'destroy':
            if (isset($_POST['confirm']) && $_POST['confirm']) {
                csrf_check();

                try {
                    $api->dataset($_GET['id'])->delete();

                    notify_user(_('Dataset destroyed'), _('Dataset was successfully destroyed.'));
                    redirect($_POST['return'] ? $_POST['return'] : '?page=');

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Failed to destroy dataset'), $e->getResponse());
                    $show_info = true;
                }

            } else {
                try {
                    $ds = $api->dataset->find($_GET['id']);

                    $xtpl->table_title(_('Confirm the destroyal of dataset') . ' ' . $ds->name);
                    $xtpl->form_create('?page=dataset&action=destroy&id=' . $ds->id, 'post');

                    $xtpl->table_td(
                        _("Confirm") . ' ' .
                        '<input type="hidden" name="return" value="' . ($_GET['return'] ? $_GET['return'] : $_POST['return']) . '">'
                    );
                    $xtpl->form_add_checkbox_pure('confirm', '1', false);
                    $xtpl->table_td(_('The dataset will be destroyed along with all its descendants.
									<strong>This action is irreversible!</strong>'));
                    $xtpl->table_tr();

                    $xtpl->form_out(_('Destroy dataset'));

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Dataset cannot be found'), $e->getResponse());
                    $show_info = true;
                }
            }

            break;

        case 'edit_expansion':
            if (isAdmin() && isset($_POST['return'])) {
                csrf_check();

                $ds = $api->dataset->find($_GET['id']);
                $exp = $api->dataset_expansion->find($_GET['expansion']);

                try {
                    $exp->update([
                        'max_over_refquota_seconds' => $_POST['max_over_refquota_days'] * 24 * 60 * 60,
                        'enable_notifications' => isset($_POST['enable_notifications']),
                        'enable_shrink' => isset($_POST['enable_shrink']),
                        'stop_vps' => isset($_POST['stop_vps']),
                    ]);

                    notify_user(_('Dataset expansion updated') . '');
                    redirect('?page=dataset&action=edit&role=' . $_GET['role'] . '&id=' . $ds->id . '&return=' . urlencode($_POST['return']));

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Dataset expansion save failed'), $e->getResponse());
                    dataset_edit_form();
                }

            } else {
                dataset_edit_form();
            }
            break;

        case 'add_expansion':
            if (isAdmin() && isset($_POST['return'])) {
                csrf_check();

                $ds = $api->dataset->find($_GET['id']);

                try {
                    $api->dataset_expansion->create([
                        'dataset' => $ds->id,
                        'added_space' => $_POST['added_space'] * $DATASET_UNITS_TR[$_POST["unit"]],
                        'max_over_refquota_seconds' => $_POST['max_over_refquota_days'] * 24 * 60 * 60,
                        'enable_notifications' => isset($_POST['enable_notifications']),
                        'enable_shrink' => isset($_POST['enable_shrink']),
                        'stop_vps' => isset($_POST['stop_vps']),
                    ]);

                    notify_user(_('Dataset expanded') . '');
                    redirect('?page=dataset&action=edit&role=' . $_GET['role'] . '&id=' . $ds->id . '&return=' . urlencode($_POST['return']));

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Dataset expansion failed'), $e->getResponse());
                    dataset_edit_form();
                }

            } else {
                dataset_edit_form();
            }
            break;

        case 'register_expansion':
            if (isAdmin() && isset($_POST['return'])) {
                csrf_check();

                $ds = $api->dataset->find($_GET['id']);

                try {
                    $api->dataset_expansion->register_expanded([
                        'dataset' => $ds->id,
                        'original_refquota' => $_POST['original_refquota'] * $DATASET_UNITS_TR[$_POST["unit"]],
                        'max_over_refquota_seconds' => $_POST['max_over_refquota_days'] * 24 * 60 * 60,
                        'enable_notifications' => isset($_POST['enable_notifications']),
                        'enable_shrink' => isset($_POST['enable_shrink']),
                        'stop_vps' => isset($_POST['stop_vps']),
                    ]);

                    notify_user(_('Dataset expansion registered') . '');
                    redirect('?page=dataset&action=edit&role=' . $_GET['role'] . '&id=' . $ds->id . '&return=' . urlencode($_POST['return']));

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Dataset expansion failed'), $e->getResponse());
                    dataset_edit_form();
                }

            } else {
                dataset_edit_form();
            }
            break;

        case 'expand_add_space':
            if (isAdmin() && isset($_POST['return'])) {
                csrf_check();

                $ds = $api->dataset->find($_GET['id']);
                $exp = $api->dataset_expansion->find($_GET['expansion']);

                try {
                    $exp->history->create([
                        'added_space' => $_POST['added_space'] * $DATASET_UNITS_TR[$_POST["unit"]],
                    ]);

                    notify_user(_('Dataset expanded') . '');
                    redirect('?page=dataset&action=edit&role=' . $_GET['role'] . '&id=' . $ds->id . '&return=' . urlencode($_POST['return']));

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Dataset expand failed'), $e->getResponse());
                    dataset_edit_form();
                }

            } else {
                dataset_edit_form();
            }
            break;

        case 'mount':
            if (isset($_POST['mountpoint'])) {
                csrf_check();

                try {
                    $input_params = $api->vps->mount->create->getParameters('input');
                    $params = [
                        'dataset' => $_POST['dataset'],
                        'mountpoint' => $_POST['mountpoint'],
                        'mode' => $_POST['mode'],
                        'on_start_fail' => $_POST['on_start_fail'],
                    ];

                    $api->vps($_POST['vps'])->mount->create($params);

                    notify_user(_('Mount created'), _('The mount was successfully created.'));
                    redirect($_POST['return'] ? $_POST['return'] : '?page=');

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Failed create a mount'), $e->getResponse());

                    mount_create_form();
                }

            } else {
                mount_create_form();
            }
            break;

        case 'mount_destroy':
            if (isset($_POST['confirm']) && $_POST['confirm']) {
                csrf_check();

                try {
                    $api->vps($_GET['vps'])->mount($_GET['id'])->delete();

                    notify_user(_('Mount removed'), _('The mount was successfully removed.'));
                    redirect($_POST['return'] ? $_POST['return'] : '?page=');

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Failed to remove mount'), $e->getResponse());
                }

            } else {
                try {
                    $vps = $api->vps->find($_GET['vps']);
                    $m = $vps->mount->find($_GET['id']);

                    $xtpl->table_title(_('Confirm the removal of mount from VPS') . ' #' . $vps->id . _(' at ') . $m->mountpoint);
                    $xtpl->form_create('?page=dataset&action=mount_destroy&vps=' . $vps->id . '&id=' . $m->id, 'post');

                    $xtpl->table_td(
                        _("Confirm") . ' ' .
                        '<input type="hidden" name="return" value="' . ($_GET['return'] ? $_GET['return'] : $_POST['return']) . '">'
                    );
                    $xtpl->form_add_checkbox_pure('confirm', '1', false);
                    $xtpl->table_td(_('The dataset will be unmounted. The data itself is not touched.'));
                    $xtpl->table_tr();

                    $xtpl->form_out(_('Remove mount'));

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Mount removal failed'), $e->getResponse());
                }
            }

            break;

        case 'mount_edit':
            if (isset($_POST['on_start_fail'])) {
                try {
                    $input_params = $api->vps->mount->create->getParameters('input');
                    $api->vps($_GET['vps'])->mount($_GET['id'])->update([
                        'on_start_fail' => $_POST['on_start_fail'],
                    ]);

                    notify_user(_('Changes saved'), '');
                    redirect($_POST['return'] ? $_POST['return'] : '?page=');

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Mount edit failed'), $e->getResponse());
                }

            } else {
                mount_edit_form($_GET['vps'], $_GET['id']);
            }

            break;

        case 'mount_toggle':
            csrf_check();

            try {
                $api->vps($_GET['vps'])->mount($_GET['id'])->update([
                    'enabled' => $_GET['do'],
                ]);

                notify_user(_('Mount') . ' ' . ($_GET['do'] ? _('enabled') : _('disabled')), '');
                redirect($_GET['return'] ? $_GET['return'] : '?page=');

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Mount toggle failed'), $e->getResponse());
            }
            break;

        case 'plan_add':
            csrf_check();

            try {
                $api->dataset($_GET['id'])->plan->create([
                    'environment_dataset_plan' => $_POST['environment_dataset_plan'],
                ]);

                notify_user(_('Backup plan added.'), _('The dataset was successfully added to the backup plan.'));
                redirect('?page=dataset&action=edit&role=' . $_GET['role'] . '&id=' . $_GET['id'] . '&return=' . urlencode($_POST['return']));

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Addition to backup plan failed'), $e->getResponse());
                dataset_edit_form();
            }

            break;

        case 'plan_delete':
            csrf_check();

            try {
                $api->dataset($_GET['id'])->plan->delete($_GET['plan']);

                notify_user(_('Backup plan removed.'), _('The dataset was successfully removed from the backup plan.'));
                redirect('?page=dataset&action=edit&role=' . $_GET['role'] . '&id=' . $_GET['id'] . '&return=' . urlencode($_GET['return']));

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Backup plan removal failed'), $e->getResponse());
                dataset_edit_form();
            }

            break;

        default:

    }

} else {
    $xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
}
