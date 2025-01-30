<?php

/*
    ./pages/page_adminvps.php

    vpsAdmin
    Web-admin interface for vpsAdminOS (see https://vpsadminos.org)
    Copyright (C) 2008-2009 Pavel Snajdr, snajpa@snajpa.net

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

function print_editvps($vps) {}

function vps_run_redirect_path($veid)
{
    $current_url = "http" . (isset($_SERVER["HTTPS"]) ? "s" : "") . "://$_SERVER[HTTP_HOST]$_SERVER[REQUEST_URI]";

    if ($_SERVER["HTTP_REFERER"] && $_SERVER["HTTP_REFERER"] != $current_url) {
        return $_SERVER["HTTP_REFERER"];
    } elseif ($_GET["action"] == "info") {
        return '?page=adminvps&action=info&veid=' . $veid;
    } else {
        return '?page=adminvps';
    }
}

if (isLoggedIn()) {

    $_GET["run"] ??= false;

    if ($_GET["run"] == 'stop') {
        csrf_check();

        try {
            $api->vps->stop($_GET["veid"]);

            notify_user(_("Stop VPS") . " {$_GET["veid"]} " . _("planned"));
            redirect(vps_run_redirect_path($_GET["veid"]));

        } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
            $xtpl->perex_format_errors(_('Unable to stop'), $e->getResponse());

            if ($_GET['action'] == 'info') {
                $show_info = true;
            }
        }
    }

    if ($_GET["run"] == 'start') {
        csrf_check();

        try {
            $api->vps->start($_GET["veid"]);

            notify_user(_("Start of") . " {$_GET["veid"]} " . _("planned"));
            redirect(vps_run_redirect_path($_GET["veid"]));

        } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
            $xtpl->perex_format_errors(_('Unable to start'), $e->getResponse());

            if ($_GET['action'] == 'info') {
                $show_info = true;
            }
        }
    }

    if ($_GET["run"] == 'restart') {
        csrf_check();

        try {
            $api->vps->restart($_GET["veid"]);

            notify_user(_("Restart of") . " {$_GET["veid"]} " . _("planned"), '');
            redirect(vps_run_redirect_path($_GET["veid"]));

        } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
            $xtpl->perex_format_errors(_('Unable to restart'), $e->getResponse());

            if ($_GET['action'] == 'info') {
                $show_info = true;
            }
        }
    }

    switch ($_GET["action"] ?? null) {
        case 'list':
            vps_list_form();
            break;

        case 'new-step-0':
            print_newvps_page0();
            break;

        case 'new-step-1':
            print_newvps_page1($_GET['user']);
            break;

        case 'new-step-2':
            print_newvps_page2(
                $_GET['user'],
                $_GET['location']
            );
            break;

        case 'new-step-3':
            print_newvps_page3(
                $_GET['user'],
                $_GET['location'],
                $_GET['os_template']
            );
            break;

        case 'new-step-4':
            print_newvps_page4(
                $_GET['user'],
                $_GET['location'],
                $_GET['os_template']
            );
            break;

        case 'new-submit':
            if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
                print_newvps_page4(
                    $_GET['user'],
                    $_GET['location'],
                    $_GET['os_template']
                );
                break;
            }

            csrf_check();

            $params = [
                'hostname' => $_POST['hostname'],
                'os_template' => $_GET['os_template'],
                'info' => isAdmin() ? '' : $_POST['info'],
                'memory' => (int) $_GET['memory'],
                'swap' => (int) $_GET['swap'],
                'cpu' => (int) $_GET['cpu'],
                'diskspace' => (int) $_GET['diskspace'],
                'ipv4' => (int) $_GET['ipv4'],
                'ipv4_private' => (int) $_GET['ipv4_private'],
                'ipv6' => (int) $_GET['ipv6'],
            ];

            if (isAdmin()) {
                $params['user'] = $_GET['user'];
                $params['node'] = $_POST['node'];
                $params['start'] = isset($_POST['boot_after_create']);

            } else {
                if ($_GET['location']) {
                    $params['location'] = (int) $_GET['location'];
                }
                if ($_POST['user_namespace_map']) {
                    $params['user_namespace_map'] = $_POST['user_namespace_map'];
                }
            }

            try {
                $vps = $api->vps->create($params);

                if ($params['start'] || !isAdmin()) {
                    notify_user(
                        _("VPS create ") . ' ' . $vps->id,
                        _("VPS will be created and booted afterwards.")
                    );

                } else {
                    notify_user(
                        _("VPS create ") . ' ' . $vps->id,
                        _("VPS will be created. You can start it manually.")
                    );
                }

                redirect('?page=adminvps&action=info&veid=' . $vps->id);

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('VPS creation failed'), $e->getResponse());
                print_newvps_page4(
                    $_GET['user'],
                    $_GET['location'],
                    $_GET['os_template']
                );
            }
            break;

        case 'delete':
            vps_delete_form($_GET['veid']);
            break;

        case 'delete2':
            try {
                csrf_check();
                $api->vps->destroy($_GET['veid'], [
                    'lazy' => $_POST['lazy_delete'] ? true : false,
                ]);

                notify_user(
                    _('Delete VPS') . ' #' . $_GET['veid'],
                    _('Deletion of VPS') . " {$_GET['veid']} " . strtolower(_('planned'))
                );
                redirect('?page=adminvps');
            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('VPS deletion failed'), $e->getResponse());
                vps_delete_form($_GET['veid']);
            }
            break;

        case 'info':
            $show_info = true;
            break;
        case 'passwd':
            try {
                csrf_check();
                $ret = $api->vps->passwd($_GET["veid"], [
                    'type' => $_POST['password_type'] == 'simple' ? 'simple' : 'secure',
                ]);

                if (!$_SESSION['vps_password']) {
                    $_SESSION['vps_password'] = [];
                }

                $_SESSION["vps_password"][(int) $_GET['veid']] = $ret['password'];

                notify_user(
                    _("Change of root password planned"),
                    _("New password is: ") . "<b>" . $ret['password'] . "</b>"
                );
                redirect('?page=adminvps&action=info&veid=' . $_GET["veid"]);

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Change of the password failed'), $e->getResponse());
                $show_info = true;
            }
            break;

        case 'pubkey':
            try {
                csrf_check();

                $ret = $api->vps->deploy_public_key($_GET["veid"], [
                    'public_key' => $_POST['public_key'],
                ]);

                notify_user(_("Public key deployment planned"), '');
                redirect('?page=adminvps&action=info&veid=' . $_GET["veid"]);

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Public key deployment failed'), $e->getResponse());
                $show_info = true;
            }

            break;

        case 'hostname':
            try {
                csrf_check();

                $params = [];

                if ($_POST['manage_hostname'] == 'manual') {
                    $params['manage_hostname'] = false;
                } else {
                    $params['hostname'] = $_POST['hostname'];
                }

                $api->vps->update($_GET['veid'], $params);

                notify_user(_("Hostname change planned"), '');
                redirect('?page=adminvps&action=info&veid=' . $_GET['veid']);

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $show_info = true;
            }
            break;

        case 'userns_map':
            csrf_check();

            try {
                $api->vps->update($_GET['veid'], [
                    'user_namespace_map' => $_POST['user_namespace_map'],
                ]);

                notify_user(_('VPS user namespace mapping updated') . '');
                redirect('?page=adminvps&action=info&veid=' . $_GET['veid']);

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('VPS user namespace map change failed'), $e->getResponse());
                $shot_info = true;
            }
            break;

        case 'resources':
            if (isset($_POST['memory'])) {
                csrf_check();

                try {
                    $vps_resources = ['memory', 'cpu', 'cpu_limit', 'swap'];
                    $params = [];

                    foreach ($vps_resources as $r) {
                        if (isset($_POST[$r])) {
                            $params[ $r ] = $_POST[$r];
                        }
                    }

                    if (isAdmin()) {
                        if ($_POST['change_reason']) {
                            $params['change_reason'] = $_POST['change_reason'];
                        }

                        if ($_POST['admin_override']) {
                            $params['admin_override'] = $_POST['admin_override'];
                        }

                        $params['admin_lock_type'] = $_POST['admin_lock_type'];
                    }

                    $api->vps($_GET['veid'])->update($params);

                    notify_user(_("Resources changed"), '');
                    redirect('?page=adminvps&action=info&veid=' . $_GET['veid']);

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Resource change failed'), $e->getResponse());
                    $show_info = true;
                }
            } else {
                $xtpl->perex(_("Error"), 'Error, contact your administrator');
                $show_info = true;
            }

            break;

        case 'chown':
            $vps = $api->vps->find($_GET['veid']);
            vps_owner_form_select($vps);
            break;

        case 'chown_confirm':
            $vps = $api->vps->find($_GET['veid']);
            $user = $api->user->find($_POST['user']);

            if (isset($_POST['cancel'])) {
                redirect('?page=adminvps&action=chown&veid=' . $_GET['veid']);

            } elseif (isset($_POST['chown']) && isset($_POST['confirm'])) {
                try {
                    csrf_check();
                    $api->vps->update($_GET['veid'], ['user' => $_POST['user']]);

                    notify_user(_("Owner changed"), '');
                    redirect('?page=adminvps&action=info&veid=' . $_GET['veid']);

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Change of the owner failed'), $e->getResponse());
                    vps_owner_form_confirm($vps, $user);
                }

            } else {
                vps_owner_form_confirm($vps, $user);
            };

            break;

        case 'netif':
            try {
                csrf_check();

                if ($_POST['name']) {
                    $params = [
                        'name' => trim($_POST['name']),
                    ];

                    if (isAdmin()) {
                        $params['max_tx'] = $_POST['max_tx'] * 1024 * 1024;
                        $params['max_rx'] = $_POST['max_rx'] * 1024 * 1024;
                    }

                    $api->network_interface($_GET['id'])->update($params);
                }

                notify_user(_('Interface updated'), '');
                redirect('?page=adminvps&action=info&veid=' . $_GET['veid']);

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to update interface'), $e->getResponse());
                $show_info = true;
            }
            break;

        case 'iproute_select':
            vps_netif_iproute_add_form();
            break;

        case 'iproute_add':
            try {
                csrf_check();

                $api->ip_address->assign($_POST['addr'], [
                    'network_interface' => $_GET['netif'],
                    'route_via' => $_POST['route_via'] ? $_POST['route_via'] : null,
                ]);
                notify_user(_("Addition of IP address planned"), '');

                redirect('?page=adminvps&action=info&veid=' . $_GET['veid']);

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to add IP address'), $e->getResponse());
                vps_netif_iproute_add_form();
            }
            break;

        case 'iproute_del':
            try {
                csrf_check();
                $api->ip_address($_GET['id'])->free();

                notify_user(_("Deletion of IP address planned"), '');
                redirect('?page=adminvps&action=info&veid=' . $_GET['veid']);

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to remove IP address'), $e->getResponse());
                $show_info = true;
            }
            break;

        case 'hostaddr_add':
            try {
                csrf_check();

                if ($_POST['hostaddr_public_v4']) {
                    $api->host_ip_address->assign($_POST['hostaddr_public_v4']);
                    notify_user(_("Addition of IP address planned"), '');

                } elseif ($_POST['hostaddr_private_v4']) {
                    $api->host_ip_address->assign($_POST['hostaddr_private_v4']);
                    notify_user(_("Addition of private IP address planned"), '');

                } elseif ($_POST['hostaddr_public_v6']) {
                    $api->host_ip_address->assign($_POST['hostaddr_public_v6']);
                    notify_user(_("Addition of IP address planned"), '');

                } else {
                    notify_user(_("Error"), 'Contact your administrator');
                }

                redirect('?page=adminvps&action=info&veid=' . $_GET['veid']);

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to add IP address'), $e->getResponse());
                $show_info = true;
            }
            break;

        case 'hostaddr_del':
            try {
                csrf_check();
                $api->host_ip_address($_GET['id'])->free();

                notify_user(_("Deletion of IP address planned"), '');
                redirect('?page=adminvps&action=info&veid=' . $_GET['veid']);

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to remove IP address'), $e->getResponse());
                $show_info = true;
            }
            break;

        case 'ipjoined_add':
            try {
                csrf_check();

                if ($_POST['iproute_public_v4']) {
                    $api->ip_address->assign_with_host_address($_POST['iproute_public_v4'], [
                        'network_interface' => $_GET['netif'],
                    ]);
                    notify_user(_("Addition of IP address planned"), '');

                } elseif ($_POST['iproute_private_v4']) {
                    $api->ip_address->assign_with_host_address($_POST['iproute_private_v4'], [
                        'network_interface' => $_GET['netif'],
                    ]);
                    notify_user(_("Addition of private IP address planned"), '');

                } elseif ($_POST['iproute_public_v6']) {
                    $api->ip_address->assign_with_host_address($_POST['iproute_public_v6'], [
                        'network_interface' => $_GET['netif'],
                    ]);
                    notify_user(_("Addition of IP address planned"), '');

                } else {
                    notify_user(_("Error"), 'Contact your administrator');
                }

                redirect('?page=adminvps&action=info&veid=' . $_GET['veid']);

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to add IP address'), $e->getResponse());
                $show_info = true;
            }
            break;

        case 'nameserver':
            try {
                csrf_check();

                $api->vps->update($_GET['veid'], [
                    'dns_resolver' => $_POST['manage_dns_resolver'] == 'managed' ? $_POST['nameserver'] : null,
                ]);

                notify_user(_("DNS change planned"), '');
                redirect('?page=adminvps&action=info&veid=' . $_GET['veid']);

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('DNS resolver change failed'), $e->getResponse());
                $show_info = true;
            }
            break;

        case 'migrate-step-1':
            vps_migrate_form_step1($_GET['veid']);
            break;

        case 'migrate-step-2':
            vps_migrate_form_step2($_GET['veid'], $_GET['node']);
            break;

        case 'migrate-step-3':
            vps_migrate_form_step3($_GET['veid'], $_GET['node'], $_GET);
            break;

        case 'migrate-submit':
            if ($_SERVER['REQUEST_METHOD'] !== 'POST' || !post_val_issetto('confirm', '1')) {
                vps_migrate_form_step3($_POST['veid'], $_POST['node'], $_POST);
                break;
            }

            csrf_check();

            $params = [
                'node' => $_POST['node'],
                'replace_ip_addresses' => $_POST['replace_ip_addresses'] == '1',
                'transfer_ip_addresses' => $_POST['transfer_ip_addresses'] == '1',
                'maintenance_window' => $_POST['maintenance_window'] == '1',
                'rsync' => $_POST['rsync'] == '1',
                'mounts_to_exports' => $_POST['mounts_to_exports'] == '1',
                'cleanup_data' => $_POST['cleanup_data'] == '1',
                'no_start' => $_POST['no_start'] == '1',
                'skip_start' => $_POST['skip_start'] == '1',
                'send_mail' => $_POST['send_mail'] == '1',
                'reason' => $_POST['reason'] ? $_POST['reason'] : null,
            ];

            if ($_POST['finish_weekday']) {
                $params['finish_weekday'] = $_POST['finish_weekday'] - 1;
                $params['finish_minutes'] = ($_POST['finish_minutes'] - 1) * 60;
            }

            try {
                $api->vps->migrate($_POST['veid'], $params);

                notify_user(_("Migration planned"), '');
                redirect('?page=adminvps&action=info&veid=' . $_POST['veid']);

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Migration failed'), $e->getResponse());
                vps_migrate_form_step3($_POST['veid'], $_POST['node'], $_POST);
            }

            break;

        case 'boot':
            if (isset($_POST['os_template'])) {
                csrf_check();

                try {
                    $api->vps($_GET['veid'])->boot([
                        'os_template' => $_POST['os_template'],
                        'mount_root_dataset' => $_POST['mount_root_dataset'] == 'mount' ? trim($_POST['mountpoint']) : null,
                    ]);

                    notify_user(
                        _("VPS") . " {$_GET["veid"]} " . _("will be rebooted momentarily"),
                        ''
                    );
                    redirect('?page=adminvps&action=info&veid=' . $_GET["veid"]);

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Boot failed'), $e->getResponse());
                    $show_info = true;
                }

            } else {
                $show_info = true;
            }
            break;

        case 'reinstall':
            if (isset($_POST['reinstall']) && $_POST['confirm']) {
                csrf_check();

                try {
                    $api->vps($_GET['veid'])->reinstall([
                        'os_template' => $_POST['os_template'],
                    ]);

                    notify_user(
                        _("Reinstallation of VPS") . " {$_GET["veid"]} " . _("planned"),
                        _("You will have to reset your <b>root</b> password.")
                    );
                    redirect('?page=adminvps&action=info&veid=' . $_GET["veid"]);

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Reinstall failed'), $e->getResponse());
                    $show_info = true;
                }

            } elseif ($_POST['reinstall_action'] === '1') {
                csrf_check();

                try {
                    $api->vps($_GET['veid'])->update([
                        'os_template' => $_POST['os_template'],
                    ]);

                    notify_user(_("Distribution information updated"), '');
                    redirect('?page=adminvps&action=info&veid=' . $_GET["veid"]);

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Failed to update distribution'), $e->getResponse());
                    $show_info = true;
                }
            } elseif (isset($_POST['cancel'])) {
                redirect('?page=adminvps&action=info&veid=' . $_GET["veid"]);

            } else {
                $vps = $api->vps->show($_GET['veid']);
                $new_tpl = $api->os_template->show(get_val('os_template', $_POST['os_template']));

                $xtpl->table_title(
                    _('Confirm reinstallation of VPS') . ' #' . $vps->id .
                    ' ' . $vps->hostname
                );
                $xtpl->form_create('?page=adminvps&action=reinstall&veid=' . $vps->id);

                $xtpl->table_td(
                    '<strong>' .
                    _('All data from this VPS will be deleted, including all subdatasets.') .
                    '</strong>' .
                    '<input type="hidden" name="os_template" value="' . $_POST['os_template'] . '">',
                    false,
                    false,
                    2
                );
                $xtpl->table_tr();

                $xtpl->table_td(_('ID') . ':');
                $xtpl->table_td($vps->id);
                $xtpl->table_tr();

                $xtpl->table_td(_('Hostname') . ':');
                $xtpl->table_td($vps->hostname);
                $xtpl->table_tr();

                $xtpl->table_td(_('Current OS template') . ':');
                $xtpl->table_td($vps->os_template->label);
                $xtpl->table_tr();

                $xtpl->table_td(_('New OS template') . ':');
                $xtpl->table_td($new_tpl->label);
                $xtpl->table_tr();

                $xtpl->form_add_checkbox(_('Confirm') . ':', 'confirm', '1', false);

                $xtpl->table_td('');
                $xtpl->table_td(
                    $xtpl->html_submit(_('Cancel'), 'cancel') .
                    $xtpl->html_submit(_('Reinstall'), 'reinstall')
                );
                $xtpl->table_tr();

                $xtpl->form_out_raw();
            }
            break;

        case 'toggle_os_template_auto_update':
            if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
                redirect('?page=adminvps&action=info&veid=' . $_GET["veid"]);
                break;
            }

            csrf_check();

            try {
                $enable = ($_POST['enable_os_template_auto_update'] ?? '') === '1';

                $api->vps($_GET['veid'])->update([
                    'enable_os_template_auto_update' => $enable,
                ]);

                if ($enable) {
                    $message = _('Reading of /etc/release was enabled');
                } else {
                    $message = _('Reading of /etc/release was disabled');
                }

                notify_user($message, '');
                redirect('?page=adminvps&action=info&veid=' . $_GET["veid"]);

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Update failed'), $e->getResponse());
                $show_info = true;
            }
            break;

        case 'features':
            if (isset($_GET["veid"]) && $_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();
                try {
                    $resource = $api->vps($_GET['veid'])->feature;
                    $features = $resource->list();
                    $params = [];

                    foreach ($features as $f) {
                        $params[$f->name] = isset($_POST[$f->name]);
                    }

                    $resource->update_all($params);

                    notify_user(_("Features set"), _('Features will be set momentarily.'));
                    redirect('?page=adminvps&action=info&veid=' . $_GET['veid']);

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Feature set failed'), $e->getResponse());
                    $show_info = true;
                }
            }
            break;

        case 'autostart':
            if (isset($_GET["veid"]) && $_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();
                try {
                    $api->vps($_GET['veid'])->update(['autostart_priority' => $_POST['autostart_priority']]);

                    notify_user(_("Auto-Start priority set"), _('The auto-start priority will be reconfigured momentarily.'));
                    redirect('?page=adminvps&action=info&veid=' . $_GET['veid']);

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Auto-Start change failed'), $e->getResponse());
                    $show_info = true;
                }
            }
            break;

        case 'startmenu':
            if (isset($_GET["veid"]) && $_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();
                try {
                    $api->vps($_GET['veid'])->update(['start_menu_timeout' => $_POST['timeout']]);

                    notify_user(_("Start menu set"), _('The start menu will be reconfigured momentarily.'));
                    redirect('?page=adminvps&action=info&veid=' . $_GET['veid']);

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Start menu change failed'), $e->getResponse());
                    $show_info = true;
                }
            }
            break;

        case 'setcgroup':
            if (isset($_GET["veid"]) && $_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();
                try {
                    $api->vps($_GET['veid'])->update(['cgroup_version' => $_POST['cgroup_version']]);

                    notify_user(_("Cgroup version set"), _('The cgroup version preference has been set.'));
                    redirect('?page=adminvps&action=info&veid=' . $_GET['veid']);

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Cgroup version change failed'), $e->getResponse());
                    $show_info = true;
                }
            }
            break;

        case 'setmodifications':
            if (isset($_GET["veid"]) && $_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();
                $allow_mods = $_POST['allow_admin_modifications'] === '1';

                try {
                    $api->vps($_GET['veid'])->update([
                        'allow_admin_modifications' => $allow_mods,
                    ]);

                    notify_user(
                        _("VPS modifications preference set"),
                        $allow_mods ? _('VPS modifications by the admin team have been enabled.')
                                    : _('VPS modifications by the admin team have been disabled.')
                    );
                    redirect('?page=adminvps&action=info&veid=' . $_GET['veid']);

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('VPS modifications preference change failed'), $e->getResponse());
                    $show_info = true;
                }
            }
            break;

        case 'maintenance_windows':
            csrf_check();

            try {
                $maint = $api->vps($_GET['veid'])->maintenance_window;

                if ($_POST['unified']) {
                    $maint->update_all([
                        'is_open' => true,
                        'opens_at' => $_POST['unified_opens_at'] * 60,
                        'closes_at' => $_POST['unified_closes_at'] * 60,
                    ]);

                } else {
                    for ($i = 0 ; $i < 7; $i++) {
                        $maint->update($i, [
                            'is_open' => array_search("$i", $_POST['is_open']) !== false,
                            'opens_at' => $_POST['opens_at'][$i] * 60,
                            'closes_at' => $_POST['closes_at'][$i] * 60,
                        ]);
                    }
                }

                notify_user(_("Maintenance windows set"), '');
                redirect('?page=adminvps&action=info&veid=' . $_GET['veid']);

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(
                    _('Maintenance window configuration failed'),
                    $e->getResponse()
                );
                $show_info = true;
            }
            break;

        case 'clone-step-0':
            vps_clone_form_step0($_GET['veid']);
            break;

        case 'clone-step-1':
            vps_clone_form_step1($_GET['veid'], $_GET['user']);
            break;

        case 'clone-step-2':
            vps_clone_form_step2($_GET['veid'], $_GET['user'], $_GET['location']);
            break;

        case 'clone-submit':
            if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
                vps_clone_form_step2(
                    $_GET['veid'],
                    $_GET['user'],
                    $_GET['location']
                );
                break;
            }

            csrf_check();

            $vps = $api->vps->find($_GET['veid']);
            $params = [
                'hostname' => $_POST['hostname'],
                'subdatasets' => isset($_POST['subdatasets']),
                'dataset_plans' => isset($_POST['dataset_plans']),
                'resources' => isset($_POST['resources']),
                'features' => isset($_POST['features']),
                'stop' => isset($_POST['stop']),
            ];

            if (isAdmin()) {
                $params['user'] = $_GET['user'];
                $params['node'] = $_POST['node'];

            } else {
                if ($_GET['location']) {
                    $params['location'] = (int) $_GET['location'];
                }
            }

            try {
                $cloned = $vps->clone($params);

                notify_user(_("Clone in progress"), '');
                redirect('?page=adminvps&action=info&veid=' . $cloned->id);

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('VPS cloning failed'), $e->getResponse());
                vps_clone_form_step2(
                    $_GET['veid'],
                    $_GET['user'],
                    $_GET['location']
                );
            }
            break;

        case 'swap_preview':
            $vps = $api->vps->find($_GET['veid']);

            try {
                $params = ['meta' => ['includes' => 'node']];

                vps_swap_preview_form(
                    $api->vps->find($_GET['veid'], $params),
                    $api->vps->find($_GET['vps'], $params),
                    $_GET
                );

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Swap preview failed'), $e->getResponse());
                vps_swap_form($vps);
            }
            break;

        case 'swap':
            $vps = $api->vps->find($_GET['veid']);

            if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
                vps_swap_form($vps);
                break;
            }

            if (isset($_POST['back'])) {
                redirect('?page=adminvps&action=swap&veid=' . $_GET['veid'] . '&vps=' . $_POST['vps'] . '&hostname=' . $_POST['hostname'] . '&resources=' . $_POST['resources'] . '&expirations=' . $_POST['expirations']);
            }

            csrf_check();

            try {
                $vps->swap_with(
                    client_params_to_api($api->vps->swap_with)
                );

                notify_user(_('Swap in progress'), '');
                redirect('?page=adminvps&action=info&veid=' . $_GET['veid']);

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Swap failed'), $e->getResponse());
                vps_swap_form($vps);
            }

            break;

        case 'replace':
            $vps = $api->vps->find($_GET['veid']);

            if ($_SERVER['REQUEST_METHOD'] !== 'POST' || !isset($_POST['confirm'])) {
                vps_replace_form($vps);
                break;
            }

            csrf_check();

            try {
                $params = [
                    'expiration_date' => date('c', strtotime($_POST['expiration_date'])),
                    'start' => isset($_POST['start']),
                    'reason' => $_POST['reason'],
                ];

                if ($_POST['node']) {
                    $params['node'] = $_POST['node'];
                }

                $newVps = $vps->replace($params);

                notify_user(_('VPS replace in progress'), '');
                redirect('?page=adminvps&action=info&veid=' . $newVps->id);

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Replace failed'), $e->getResponse());
                vps_replace_form($vps);
            }

            break;

        default:
            vps_list_form();
            break;
    }

    $xtpl->assign(
        'AJAX_SCRIPT',
        ($xtpl->vars['AJAX_SCRIPT'] ?? '') . '
	<script type="text/javascript" src="js/vps.js"></script>'
    );

    if (isset($show_info) && $show_info) {
        if (!isset($veid)) {
            $veid = $_GET["veid"];
        }

        $vps = $api->vps->find($veid, [
            'meta' => [
                'includes' => 'node__location__environment,user,os_template,user_namespace_map',
            ],
        ]);

        vps_details_suite($vps);

        if (isAdmin()) {
            $xtpl->sbar_add(_('State log'), '?page=lifetimes&action=changelog&resource=vps&id=' . $vps->id . '&return=' . urlencode($_SERVER['REQUEST_URI']));
        }


        $xtpl->table_td('ID:');
        $xtpl->table_td($vps->id);
        $xtpl->table_tr();

        $xtpl->table_td(_("Node") . ':');
        $xtpl->table_td(node_link($vps->node));
        $xtpl->table_tr();

        $xtpl->table_td(_("Storage pool") . ':');
        $xtpl->table_td(node_link($vps->node, $vps->pool->name));
        $xtpl->table_tr();

        $xtpl->table_td(_("Location") . ':');
        $xtpl->table_td($vps->node->location->label);
        $xtpl->table_tr();

        $xtpl->table_td(_("Environment") . ':');
        $xtpl->table_td($vps->node->location->environment->label);
        $xtpl->table_tr();

        $xtpl->table_td(_("Owner") . ':');
        $xtpl->table_td('<a href="?page=adminm&section=members&action=edit&id=' . $vps->user_id . '">' . $vps->user->login . '</a>');
        $xtpl->table_tr();

        $xtpl->table_td(_('Created at') . ':');
        $xtpl->table_td(tolocaltz($vps->created_at));
        $xtpl->table_tr();

        $xtpl->table_td(_("State") . ':');
        $xtpl->table_td($vps->object_state);
        $xtpl->table_tr();

        if ($vps->expiration_date) {
            $xtpl->table_td(_("Expiration") . ':');
            $xtpl->table_td(tolocaltz($vps->expiration_date));
            $xtpl->table_tr();
        }

        $xtpl->table_td(_("Distribution") . ':');
        $xtpl->table_td($vps->os_template->label);
        $xtpl->table_tr();

        $xtpl->table_td(_("Status") . ':');

        if ($vps->maintenance_lock == 'no') {
            $xtpl->table_td(
                (($vps->is_running) ?
                    _("running") . ' (<a href="?page=adminvps&action=info&run=restart&veid=' . $vps->id . '&t=' . csrf_token() . '" ' . vps_confirm_action_onclick($vps, 'restart') . '>' . _("restart") . '</a>, <a href="?page=adminvps&action=info&run=stop&veid=' . $vps->id . '&t=' . csrf_token() . '" ' . vps_confirm_action_onclick($vps, 'stop') . '>' . _("stop") . '</a>'
                    :
                    _("stopped") . ' (<a href="?page=adminvps&action=info&run=start&veid=' . $vps->id . '&t=' . csrf_token() . '">' . _("start") . '</a>') .
                    ', <a href="?page=console&veid=' . $vps->id . '&t=' . csrf_token() . '">' . _("open remote console") . '</a>)'
            );
        } else {
            $xtpl->table_td($vps->is_running ? _("running") : _("stopped"));
        }

        $xtpl->table_tr();

        $xtpl->table_td(_("Hostname") . ':');
        $xtpl->table_td(h($vps->hostname));
        $xtpl->table_tr();

        $xtpl->table_td(_("Uptime") . ':');
        $xtpl->table_td($vps->is_running ? format_duration($vps->uptime) : '-');
        $xtpl->table_tr();

        $xtpl->table_td(_("Load average") . ':');
        $xtpl->table_td($vps->is_running ? implode(', ', [$vps->loadavg1, $vps->loadavg5, $vps->loadavg15]) : '-');
        $xtpl->table_tr();

        $xtpl->table_td(_("Processes") . ':');
        $xtpl->table_td($vps->is_running ? $vps->process_count : '-');
        $xtpl->table_tr();

        $xtpl->table_td(_("CPU") . ':');
        $xtpl->table_td($vps->is_running ? sprintf('%.2f %%', 100.0 - $vps->cpu_idle) : '-');
        $xtpl->table_tr();

        $xtpl->table_td(_("RAM") . ':');
        $xtpl->table_td($vps->is_running ? sprintf('%4d MB', $vps->used_memory) : '-');
        $xtpl->table_tr();

        if ($vps->used_swap) {
            $xtpl->table_td(_("Swap") . ':');
            $xtpl->table_td(sprintf('%4d MB', $vps->used_swap));
            $xtpl->table_tr();
        }

        $xtpl->table_td(_("Disk") . ':');
        $xtpl->table_td(
            ($vps->diskspace && showVpsDiskSpaceWarning($vps) ? ('<img src="template/icons/warning.png" title="' . _('Disk at') . ' ' . sprintf('%.2f %%', round(vpsDiskUsagePercent($vps), 2)) . '"> ') : '') .
            ($vps->diskspace && showVpsDiskExpansionWarning($vps) ? ('<img src="template/icons/warning.png" title="' . _('Disk temporarily expanded') . '"> ') : '') .
            sprintf('%.2f GB', round($vps->used_diskspace / 1024, 2))
        );
        $xtpl->table_tr();

        if ($vps->maintenance_lock != 'no') {
            $xtpl->table_td(_('Maintenance lock') . ':');
            $xtpl->table_td($vps->maintenance_lock == 'lock' ? _('direct') : _('global lock'));
            $xtpl->table_tr();

            $xtpl->table_td(_('Maintenance reason') . ':');
            $xtpl->table_td($vps->maintenance_lock_reason);
            $xtpl->table_tr();
        }

        $xtpl->table_out();

        if (!isAdmin() && $vps->maintenance_lock != 'no') {
            $xtpl->perex(
                _("VPS is under maintenance"),
                _("All actions for this VPS are forbidden for the time being. This is usually used during outage to prevent data corruption.") .
                "<br><br>"
                . ($vps->maintenance_lock_reason ? _('Reason') . ': ' . $vps->maintenance_lock_reason . '<br><br>' : '')
                . _("Please be patient.")
            );

        } elseif ($vps->object_state == 'soft_delete') {
            if (isAdmin()) {
                lifetimes_set_state_form('vps', $vps->id, $vps);

            } else {
                $xtpl->perex(
                    _('VPS is scheduled for deletion.'),
                    _('This VPS is inaccessible and will be deleted when expiration date passes or some other event occurs. ' .
                    'Contact support if you want to revive it.')
                );
            }

        } elseif ($vps->object_state == 'hard_delete') {
            $xtpl->perex(_('VPS is deleted.'), _('This VPS is deleted and cannot be revived.'));

        } else {
            if ($vps->in_rescue_mode) {
                $xtpl->table_title(
                    '<img src="template/icons/warning.png" alt="' . _('Warning') . '">&nbsp;' .
                    _('VPS in rescue mode') .
                    '&nbsp;<img src="template/icons/warning.png" alt="' . _('Warning') . '">'
                );
                $xtpl->table_td(_('
				<p>
				The VPS has been booted from a clean template. All changes to the
				rescue system will be lost once the VPS is restarted.
				</p>
				<p>
				Restart the VPS to leave the rescue mode.
				</p>
			'));
                $xtpl->table_tr();
                $xtpl->table_out();
            }

            // SSH
            $xtpl->table_title(_('SSH connection'));
            $xtpl->table_td(
                _('The following credentials can be used on a newly created VPS ' .
                'with the default configuration.'),
                false,
                false,
                '2'
            );
            $xtpl->table_tr();

            $xtpl->table_td(_('User') . ':');
            $xtpl->table_td('root');
            $xtpl->table_tr();

            $xtpl->table_td(_('Password or SSH key') . ':');

            if ($_SESSION['vps_password'][$vps->id] ?? false) {
                $xtpl->table_td("<b>" . $_SESSION['vps_password'][$vps->id] . "</b>");

            } else {
                $xtpl->table_td(
                    _('Set root password or deploy public key in the forms below.')
                );
            }

            $xtpl->table_tr();

            $ssh_ips = $api->host_ip_address->list([
                'vps' => $vps->id,
                'assigned' => true,
                'meta' => ['includes' => 'ip_address__network'],
            ]);
            $ssh_cnt = $ssh_ips->count();

            $xtpl->table_td(_('Address') . ':');

            if ($ssh_cnt > 1) {
                $ssh_str = _('One of:') . '<br><ul>';

                foreach ($ssh_ips as $ip) {
                    $ssh_str .= '<li>' . $ip->addr . '</li>';
                }

                $ssh_str .= '</ul>';
                $xtpl->table_td($ssh_str);

            } elseif ($ssh_cnt == 1) {
                $xtpl->table_td($ssh_ips[0]->addr);
            } else {
                $xtpl->table_td(_('The VPS has no interface IP addresses set'));
            }
            $xtpl->table_tr();

            if ($ssh_cnt > 0) {
                $example_ssh_ip = findBestPublicHostAddress($ssh_ips);

                if (!$example_ssh_ip) {
                    $example_ssh_ip = $ssh_ips[0];
                }

                $xtpl->table_td(_('Example command') . ':');
                $xtpl->table_td('<pre><code>ssh root@' . $example_ssh_ip->addr . '</code></pre>');
                $xtpl->table_tr();
            }

            $xtpl->table_out();

            // SSH host keys
            $ssh_host_keys = $vps->ssh_host_key->list();

            if ($ssh_host_keys->count() > 0) {
                $xtpl->table_title(_('SSH host keys'));

                $xtpl->table_add_category(_('Algorithm'));
                $xtpl->table_add_category(_('Fingerprint'));
                $xtpl->table_add_category(_('Last read at'));

                $xtpl->table_td(
                    _('The following SSH host keys have been found inside the VPS. ' .
                      'You can verify that the fingerprints match on your first login.'),
                    false,
                    false,
                    '3'
                );
                $xtpl->table_tr();

                foreach ($ssh_host_keys as $key) {
                    $xtpl->table_td('<code>' . h($key->algorithm) . '</code>');
                    $xtpl->table_td('<code>' . h($key->fingerprint) . '</code>');
                    $xtpl->table_td(h(tolocaltz($key->updated_at)));
                    $xtpl->table_tr();
                }

                $xtpl->table_out();
            }

            // Password changer
            $xtpl->table_title(_("Set root's password (in the VPS, not in the vpsAdmin)"));
            $xtpl->form_create('?page=adminvps&action=passwd&veid=' . $vps->id, 'post');

            $xtpl->table_td(_("Username") . ':');
            $xtpl->table_td('root');
            $xtpl->table_tr();

            $xtpl->table_td(_("Password") . ':');

            if ($_SESSION['vps_password'][$vps->id] ?? false) {
                $xtpl->table_td("<b>" . $_SESSION['vps_password'][$vps->id] . "</b>");

            } else {
                $xtpl->table_td(_("will be generated"));
            }

            $xtpl->table_tr();

            if (!isAdmin()) {
                $xtpl->table_td('');
                $xtpl->table_td('<b>Warning</b>: The password is randomly generated.<br>
							This password changer is here only to enable the first access to SSH.<br>
							You can change it with <em>passwd</em> command once you\'ve logged onto SSH.');
                $xtpl->table_tr();
            }

            $xtpl->form_add_radio(_("Secure password") . ':', 'password_type', 'secure', true, _('20 characters long, consists of: a-z, A-Z, 0-9'));
            $xtpl->table_tr();

            $xtpl->form_add_radio(_("Simple password") . ':', 'password_type', 'simple', false, _('8 characters long, consists of: a-z, 2-9'));
            $xtpl->table_tr();

            $xtpl->form_out(_("Go >>"));

            // Public keys
            $xtpl->table_title(_("Deploy public key to /root/.ssh/authorized_keys"));
            $xtpl->form_create('?page=adminvps&action=pubkey&veid=' . $vps->id, 'post');

            $xtpl->table_td(
                _('Public keys can be registered in') .
                ' <a href="?page=adminm&action=pubkeys&id=' . $vps->user_id . '">' .
                _('profile settings') . '</a>.',
                false,
                false,
                '2'
            );
            $xtpl->table_tr();

            $xtpl->form_add_select(
                _('Public key') . ':',
                'public_key',
                resource_list_to_options($api->user($vps->user_id)->public_key->list())
            );

            $xtpl->form_out(_('Go >>'));

            // Network interfaces
            $netifs = $api->network_interface->list(['vps' => $vps->id]);
            $netif_accounting = $api->network_interface_accounting->list([
                'vps' => $vps->id,
                'year' => date('Y'),
                'month' => date('n'),
            ]);

            foreach ($netifs as $netif) {
                vps_netif_form($vps, $netif, $netif_accounting);
            }

            // DNS Server
            $return_url = urlencode($_SERVER['REQUEST_URI']);

            $xtpl->table_title(_('DNS resolver (/etc/resolv.conf)'));
            $xtpl->form_create('?page=adminvps&action=nameserver&veid=' . $vps->id, 'post');

            $xtpl->form_add_radio_pure('manage_dns_resolver', 'managed', $vps->dns_resolver_id != null);
            $xtpl->table_td(_('Manage DNS resolver by vpsAdmin') . ':');
            $xtpl->form_add_select_pure(
                'nameserver',
                resource_list_to_options(
                    $api->dns_resolver->list(['vps' => $vps->id]),
                    'id',
                    'label',
                    false
                ),
                $vps->dns_resolver_id,
                ''
            );
            $xtpl->table_tr();

            $xtpl->form_add_radio_pure('manage_dns_resolver', 'manual', $vps->dns_resolver_id == null);
            $xtpl->table_td(_('Manage DNS resolver manually'));
            $xtpl->table_tr();

            $xtpl->table_td('');
            $xtpl->table_td('<a href="?page=dns&action=resolver_list&return_url=' . $return_url . '">' . _('See available DNS resolvers and their IP addresses') . '</a>');
            $xtpl->table_tr();

            $xtpl->form_out(_("Go >>"));

            // Hostname change
            $xtpl->table_title(_('Hostname'));
            $xtpl->form_create('?page=adminvps&action=hostname&veid=' . $vps->id, 'post');

            $xtpl->form_add_radio_pure('manage_hostname', 'managed', $vps->manage_hostname);
            $xtpl->table_td(_('Manage hostname by vpsAdmin') . ':');
            $xtpl->form_add_input_pure('text', '30', 'hostname', $vps->hostname, _("A-z, a-z"), 255);
            $xtpl->table_tr();

            $xtpl->form_add_radio_pure('manage_hostname', 'manual', !$vps->manage_hostname);
            $xtpl->table_td(_('Manage hostname manually'));
            $xtpl->table_tr();


            $xtpl->form_out(_("Go >>"));

            // Datasets
            dataset_list('hypervisor', $vps->dataset_id);

            // Mounts
            mount_list($vps);

            $os_templates = list_templates($vps);

            // Boot
            $xtpl->table_title(_('Boot VPS from template (rescue mode)'));
            $xtpl->form_create('?page=adminvps&action=boot&veid=' . $vps->id, 'post');
            $xtpl->table_td(
                '<p>' .
                _('Boot the VPS from a clean template, e.g. to fix a broken system. ' .
                  'The VPS configuration (IP addresses, resources, etc.) is the same, ' .
                  'the VPS only starts from a clean system. The original root ' .
                  'filesystem from the VPS can be accessed through the mountpoint ' .
                  'configured below.') .
                '</p><p>' .
                _('On next VPS start/restart, the VPS will start from it\'s own ' .
                  'dataset again. The clean system created by this action is ' .
                  'temporary and any changes to it will be lost.') .
                '</p>',
                false,
                false,
                '3'
            );
            $xtpl->table_tr();

            $xtpl->form_add_select(_("Distribution") . ':', 'os_template', $os_templates, $vps->os_template_id, '');

            $xtpl->table_td(_('Mount root dataset') . ':');
            $xtpl->form_add_radio_pure('mount_root_dataset', 'mount', true);
            $xtpl->form_add_input_pure('text', '30', 'mountpoint', post_val('mountpoint', '/mnt/vps'));
            $xtpl->table_tr();

            $xtpl->table_td(_('Do not mount the root dataset'));
            $xtpl->form_add_radio_pure('mount_root_dataset', 'no', false);
            $xtpl->table_tr();
            $xtpl->form_out(_("Go >>"));

            // Distribution
            $xtpl->table_title(_('Distribution'));
            $xtpl->form_create('?page=adminvps&action=reinstall&veid=' . $vps->id, 'post');
            $xtpl->form_add_select(_("Distribution") . ':', 'os_template', $os_templates, $vps->os_template_id, '');
            $xtpl->table_td(_('Info') . ':');
            $xtpl->table_td($vps->os_template->info);
            $xtpl->table_tr();
            $xtpl->form_add_radio(
                _("Update information") . ':',
                'reinstall_action',
                '1',
                true,
                _("Use if you have upgraded your system.")
            );
            $xtpl->table_tr();
            $xtpl->form_add_radio(
                _("Reinstall") . ':',
                'reinstall_action',
                '2',
                false,
                _("Install base system again.") . ' ' . _('All data in the root filesystem will be removed.')
            );
            $xtpl->table_tr();
            $xtpl->form_out(_("Go >>"));

            // OS template auto-update
            $xtpl->table_title(_('Read /etc/os-release'));
            $xtpl->form_create('?page=adminvps&action=toggle_os_template_auto_update&veid=' . $vps->id, 'post');
            $xtpl->form_add_checkbox_pure('enable_os_template_auto_update', '1', post_val_issetto('enable_os_template_auto_update', '1', $vps->enable_os_template_auto_update));
            $xtpl->table_td(_('Automatically update distribution version information in vpsAdmin by reading <code>/etc/os-release</code> on VPS start.'));
            $xtpl->table_tr();
            $xtpl->form_out(_("Go >>"));

            // Resources
            $xtpl->table_title(_('Resources'));
            $xtpl->form_create('?page=adminvps&action=resources&veid=' . $vps->id, 'post');

            $params = $api->vps->update->getParameters('input');
            $vps_resources = ['memory', 'cpu', 'swap'];
            $user_resources = $vps->user->cluster_resource->list(
                [
                    'environment' => $vps->node->location->environment_id,
                    'meta' => ['includes' => 'environment,cluster_resource']]
            );
            $resource_map = [];

            foreach ($user_resources as $r) {
                $resource_map[ $r->cluster_resource->name ] = $r;
            }

            foreach ($vps_resources as $name) {
                $p = $params->{$name};
                $r = $resource_map[$name];

                if (!isAdmin() && $r->value === 0) {
                    continue;
                }

                $xtpl->table_td($p->label);
                $xtpl->form_add_number_pure(
                    $name,
                    $vps->{$name},
                    isAdmin() ? 0 : $r->cluster_resource->min,
                    isAdmin() ?
                        99999999999 :
                        min($vps->{$name} + $r->free, $r->cluster_resource->max),
                    $r->cluster_resource->stepsize,
                    unit_for_cluster_resource($name)
                );
                $xtpl->table_tr();
            }

            if (isAdmin()) {
                $xtpl->form_add_number(
                    _('CPU limit') . ':',
                    'cpu_limit',
                    post_val('cpu_limit', $vps->cpu_limit),
                    0,
                    10000,
                    25,
                    '%'
                );
            }

            if (isAdmin()) {
                api_param_to_form('change_reason', $params->change_reason);
                api_param_to_form('admin_override', $params->admin_override);
                api_param_to_form('admin_lock_type', $params->admin_lock_type);
            }

            $xtpl->form_out(_("Go >>"));

            // Enable devices/capabilities
            $xtpl->table_title(_('Features'));
            $xtpl->form_create('?page=adminvps&action=features&veid=' . $vps->id, 'post');

            $features = $vps->feature->list();

            foreach ($features as $f) {
                if ($f->name == 'impermanence' && $vps->os_template->distribution != 'nixos') {
                    continue;
                }

                $xtpl->table_td($f->label);
                $xtpl->form_add_checkbox_pure($f->name, '1', $f->enabled ? '1' : '0');
                $xtpl->table_tr();
            }

            $xtpl->table_td(_('VPS is restarted when features are changed.'), false, false, '2');
            $xtpl->table_tr();

            $xtpl->form_out(_("Go >>"));

            // Auto-start
            if (isAdmin()) {
                $xtpl->table_title(_('Auto-Start'));
                $xtpl->form_create('?page=adminvps&action=autostart&veid=' . $vps->id, 'post');

                $xtpl->table_td(_('Active') . ':');
                $xtpl->table_td(boolean_icon($vps->autostart_enable));
                $xtpl->table_tr();

                $xtpl->form_add_number(_('Priority') . ':', 'autostart_priority', post_val('autostart_priority', $vps->autostart_priority), 0, 100000, 1, '', $params->autostart_priority->description);

                $xtpl->form_out(_("Go >>"));
            }

            // Start menu
            $xtpl->table_title(_('Start Menu'));
            $xtpl->form_create('?page=adminvps&action=startmenu&veid=' . $vps->id, 'post');

            $xtpl->table_td(
                _('Configure the number of seconds the start menu waits for the user ' .
                'before the system is started. Set to zero to disable the start menu.'),
                false,
                false,
                2
            );
            $xtpl->table_tr();

            $xtpl->form_add_number(
                _('Timeout') . ':',
                'timeout',
                $vps->start_menu_timeout,
                0,
                3600,
                1,
                _('seconds')
            );

            $xtpl->form_out(_("Go >>"));

            // Cgroup version
            $xtpl->table_title(_('Cgroup version'));
            $xtpl->form_create('?page=adminvps&action=setcgroup&veid=' . $vps->id, 'post');

            $xtpl->table_td(_('In use:'));
            $xtpl->table_td(cgroupEnumToLabel($vps->node->cgroup_version));
            $xtpl->table_tr();

            $other_cgroup = 'cgroup_v2';
            if ($other_cgroup == $vps->node->cgroup_version) {
                $other_cgroup = 'cgroup_v1';
            }

            $xtpl->form_add_radio_pure(
                'cgroup_version',
                'cgroup_any',
                post_val('cgroup_version', $vps->cgroup_version) == 'cgroup_any',
            );
            $xtpl->table_td(
                _('Use cgroups supported by the distribution, i.e. ') .
                cgroupEnumToLabel($vps->os_template->cgroup_version) . ' ' . _('for') . ' ' .
                $vps->os_template->label . ' ' . _('(recommended)')
            );
            $xtpl->table_tr();

            $xtpl->form_add_radio_pure(
                'cgroup_version',
                $vps->node->cgroup_version,
                post_val('cgroup_version', $vps->cgroup_version) == $vps->node->cgroup_version,
            );
            $xtpl->table_td(_('Always require') . ' ' . cgroupEnumToLabel($vps->node->cgroup_version));
            $xtpl->table_tr();

            $xtpl->form_add_radio_pure(
                'cgroup_version',
                $other_cgroup,
                false,
                '',
                false
            );
            $xtpl->table_td(
                _("Contact support if you'd like to use") . ' ' . cgroupEnumTolabel($other_cgroup),
            );
            $xtpl->table_tr();

            $xtpl->form_out(_("Go >>"));

            // Admin modifications
            $xtpl->table_title(_('VPS modifications by the admin team'));
            $xtpl->form_create('?page=adminvps&action=setmodifications&veid=' . $vps->id, 'post');

            $xtpl->table_td(
                _('New software features or bugs may require or benefit from configuration ' .
                'changes inside the VPS. If allowed, we can make these necessary changes ' .
                'for you. We usually only modify the base system configuration files ' .
                'which we would otherwise deliver in OS templates for new VPS. We do not ' .
                'access or modify your applications or data. We will email you about any ' .
                'changes we will make.'),
                false,
                false,
                2
            );
            $xtpl->table_tr();

            $xtpl->form_add_radio_pure(
                'allow_admin_modifications',
                '1',
                post_val('allow_admin_modification', $vps->allow_admin_modifications ? '1' : '0') == '1',
            );
            $xtpl->table_td(_('Allow modifications by vpsFree.cz admin team (recommended)'));
            $xtpl->table_tr();

            $xtpl->form_add_radio_pure(
                'allow_admin_modifications',
                '0',
                post_val('allow_admin_modification', $vps->allow_admin_modifications ? '1' : '0') == '0',
            );
            $xtpl->table_td(_('Do not allow modifications by vpsFree.cz admin team'));
            $xtpl->table_tr();

            $xtpl->form_out(_("Go >>"));

            // Maintenance windows
            $xtpl->table_title(_('Maintenance windows'));
            $xtpl->table_add_category('');
            $xtpl->table_add_category(_('Day'));
            $xtpl->table_add_category(_('From'));
            $xtpl->table_add_category(_('To'));
            $xtpl->form_create('?page=adminvps&action=maintenance_windows&veid=' . $vps->id, 'post');

            $windows = $vps->maintenance_window->list();
            $days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
            $hours = [];

            for ($i = 0; $i < 25; $i++) {
                $hours[] = sprintf("%02d:00", $i);
            }

            $hours[ count($hours) - 1 ] = '23:59';

            $unified = true;
            $last = $windows->first();

            foreach ($windows as $w) {
                if ($last->is_open != $w->is_open || $last->opens_at != $w->opens_at ||
                    $last->closes_at != $w->closes_at) {
                    $unified = false;
                    break;
                }
            }

            $xtpl->form_add_radio_pure('unified', '1', $unified);
            $xtpl->table_td(_('Same maintenance window every day'));
            $xtpl->form_add_select_pure('unified_opens_at', $hours, $windows->first()->opens_at / 60);
            $xtpl->form_add_select_pure('unified_closes_at', $hours, $windows->first()->closes_at / 60);
            $xtpl->table_tr();

            $xtpl->form_add_radio_pure('unified', '0', !$unified);
            $xtpl->table_td(_('Configure maintenance windows per day'), false, false, '3');
            $xtpl->table_tr();

            foreach ($windows as $w) {
                $xtpl->table_td('');
                $xtpl->form_add_checkbox_pure('is_open[]', $w->weekday, $w->is_open, $days[ $w->weekday ]);
                $xtpl->form_add_select_pure('opens_at[]', $hours, $w->opens_at / 60);
                $xtpl->form_add_select_pure('closes_at[]', $hours, $w->closes_at / 60);
                $xtpl->table_tr();
            }

            $xtpl->form_out(_("Go >>"));

            // User namespace map
            if (isAdmin() || USERNS_PUBLIC) {
                $xtpl->table_title(_('UID/GID mapping'));
                $xtpl->form_create('?page=adminvps&action=userns_map&veid=' . $vps->id, 'post');

                $xtpl->table_td(_('Map') . ':');
                $xtpl->form_add_select_pure(
                    'user_namespace_map',
                    resource_list_to_options(
                        $api->user_namespace_map->list(['user' => $vps->user_id]),
                        'id',
                        'label',
                        false
                    ),
                    $vps->user_namespace_map_id
                );
                $xtpl->table_td(
                    '<a href="?page=userns&action=maps&user_namespace=' . $vps->user_namespace_map->user_namespace_id . '">' . _('Manage user namespace maps') . '</a>'
                );
                $xtpl->table_tr();

                $xtpl->table_td(
                    'VPS is restarted when user namespace map is changed.',
                    false,
                    false,
                    2
                );
                $xtpl->table_tr();

                $xtpl->form_out(_('Go >>'));

                $xtpl->table_add_category(_('Type'));
                $xtpl->table_add_category(_('ID within VPS'));
                $xtpl->table_add_category(_('ID within namespace'));
                $xtpl->table_add_category(_('ID count'));

                foreach ($vps->user_namespace_map->entry->list() as $e) {
                    $xtpl->table_td(strtoupper($e->kind));
                    $xtpl->table_td($e->vps_id);
                    $xtpl->table_td($e->ns_id);
                    $xtpl->table_td($e->count);
                    $xtpl->table_tr();
                }

                $xtpl->table_out();
            }

            // State change
            if (isAdmin()) {
                lifetimes_set_state_form('vps', $vps->id, $vps);
            }
        }
    }

    $xtpl->sbar_out(_("Manage VPS"));

} else {
    $xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
}
