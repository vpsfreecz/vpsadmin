<?php

if (isLoggedIn()) {
    switch ($_GET['action'] ?? '') {
        case 'server_list':
            dns_server_list();
            break;

        case 'zone_list':
            $xtpl->title(_('DNS zones'));
            dns_zone_list('zone_list');
            break;

        case 'zone_show':
            dns_zone_show($_GET['id']);
            break;

        case 'zone_update':
            csrf_check();

            try {
                $zone = $api->dns_zone->show($_GET['id']);

                $params = [
                    'enabled' => isset($_POST['enabled']),
                ];

                if ($zone->source == 'internal_source') {
                    $params['default_ttl'] = $_POST['default_ttl'];
                    $params['email'] = $_POST['email'];
                }

                $zone->update($params);

                notify_user(_('DNS zone updated'), '');
                redirect('?page=dns&action=zone_show&id=' . $zone->id);

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to save DNS zone'), $e->getResponse());
                dns_zone_show($_GET['id']);
            }
            break;

        case 'zone_delete':
            dns_zone_delete($_GET['id']);
            break;

        case 'zone_delete2':
            csrf_check();

            if ($_POST['confirm'] === '1') {
                try {
                    $api->dns_zone->delete($_GET['id']);

                    notify_user(_('DNS zone deleted'), '');
                    redirect($_POST['return_url'] ?? '?page=dns');

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Failed to delete DNS zone'), $e->getResponse());
                    dns_zone_delete($_GET['id']);
                }
            } else {
                dns_zone_delete($_GET['id']);
            }
            break;

        case 'zone_transfer_new':
            dns_zone_transfer_new($_GET['id']);
            break;

        case 'zone_transfer_new2':
            csrf_check();

            try {
                $zone = $api->dns_zone->show($_GET['id']);
                $params = [
                    'dns_zone' => $zone->id,
                    'host_ip_address' => $_POST['host_ip_address'],
                    'peer_type' => $zone->source == 'internal_source' ? 'secondary_type' : 'primary_type',
                ];

                if ($_POST['dns_tsig_key']) {
                    $params['dns_tsig_key'] = $_POST['dns_tsig_key'];
                }

                $api->dns_zone_transfer->create($params);

                notify_user(
                    $zone->source == 'internal_source' ? _('Secondary server added') : _('Primary server added'),
                    ''
                );
                redirect('?page=dns&action=zone_show&id=' . $zone->id);

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to add server'), $e->getResponse());
                dns_zone_transfer_new($_GET['id']);
            }
            break;

        case 'zone_transfer_delete':
            csrf_check();

            try {
                $api->dns_zone_transfer->delete($_GET['transfer']);

                notify_user(_('Transfer deleted'), '');
                redirect('?page=dns&action=zone_show&id=' . $_GET['id']);

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to delete transfer'), $e->getResponse());
                dns_zone_transfer_new($_GET['id']);
            }

            break;

        case 'secondary_zone_list':
            secondary_dns_zone_list();
            break;

        case 'secondary_zone_new':
            secondary_dns_zone_new();
            break;

        case 'secondary_zone_new2':
            csrf_check();

            try {
                $name = $_POST['name'];

                if (!str_ends_with($name, '.')) {
                    $name .= '.';
                }

                $params = [
                    'name' => $name,
                ];

                if (!isAdmin() || $_POST['user']) {
                    $params['user'] = $_POST['user'];
                }

                $zone = $api->dns_zone->create($params);

                notify_user(_('Secondary DNS zone created'), '');
                redirect('?page=dns&action=zone_show&id=' . $zone->id);

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to create secondary DNS zone'), $e->getResponse());
                secondary_dns_zone_new();
            }
            break;

        case 'tsig_key_list':
            tsig_key_list();
            break;

        case 'tsig_key_new':
            tsig_key_new();
            break;

        case 'tsig_key_new2':
            csrf_check();

            try {
                $params = [
                    'name' => $_POST['name'],
                    'algorithm' => $_POST['algorithm'],
                ];

                if (!isAdmin() || $_POST['user']) {
                    $params['user'] = $_POST['user'];
                }

                $key = $api->dns_tsig_key->create($params);

                notify_user(_('TSIG key created'), '');
                redirect('?page=dns&action=tsig_key_list');

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to create TSIG key'), $e->getResponse());
                tsig_key_new();
            }
            break;

        case 'tsig_key_delete':
            tsig_key_delete($_GET['id']);
            break;

        case 'tsig_key_delete2':
            csrf_check();

            if ($_POST['confirm'] === '1') {
                try {
                    $api->dns_tsig_key->delete($_GET['id']);

                    notify_user(_('TSIG key deleted'), '');
                    redirect($_POST['return_url'] ?? '?page=dns&action=tsig_key_list');

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Failed to delete TSIG key'), $e->getResponse());
                    tsig_key_delete($_GET['id']);
                }
            } else {
                tsig_key_delete($_GET['id']);
            }
            break;

        case 'ptr_list':
            dns_ptr_list();
            break;

        default:
            dns_ptr_list();
    }

    dns_submenu();
    $xtpl->sbar_out(_('DNS'));

} else {
    $xtpl->perex(
        _("Access forbidden"),
        _("You have to log in to be able to access vpsAdmin's functions")
    );
}
