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
                    'dnssec_enabled' => isset($_POST['dnssec_enabled']),
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

        case 'server_zone_new':
            dns_zone_server_new($_GET['id']);
            break;

        case 'server_zone_new2':
            csrf_check();

            try {
                $api->dns_server_zone->create([
                    'dns_server' => $_POST['dns_server'],
                    'dns_zone' => $_GET['id'],
                    'type' => $_POST['type'],
                ]);

                notify_user(_('DNS zone added to server'), '');
                redirect('?page=dns&action=zone_show&id=' . $_GET['id']);

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to add zone to server'), $e->getResponse());
                dns_zone_server_new($_GET['id']);
            }
            break;

        case 'server_zone_delete':
            csrf_check();

            try {
                $api->dns_server_zone->delete($_GET['server_zone']);

                notify_user(_('DNS zone removed from server'), '');
                redirect('?page=dns&action=zone_show&id=' . $_GET['id']);

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to remove DNS zone from server'), $e->getResponse());
                dns_zone_show($_GET['id']);
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
                $zone = $api->dns_zone->show($_GET['id']);
                $api->dns_zone_transfer->delete($_GET['transfer']);

                notify_user(
                    $zone->source == 'internal_source' ? _('Secondary server deleted') : _('Primary server deleted'),
                    ''
                );
                redirect('?page=dns&action=zone_show&id=' . $zone->id);

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to delete server'), $e->getResponse());
                dns_zone_show($_GET['id']);
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
                    'source' => 'external_source',
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

        case 'primary_zone_list':
            primary_dns_zone_list();
            break;

        case 'primary_zone_new':
            primary_dns_zone_new();
            break;

        case 'primary_zone_new2':
            csrf_check();

            try {
                $name = $_POST['name'];

                if (!str_ends_with($name, '.')) {
                    $name .= '.';
                }

                $params = [
                    'name' => $name,
                    'email' => $_POST['email'],
                    'dnssec_enabled' => isset($_POST['dnssec_enabled']),
                    'source' => 'internal_source',
                ];

                if (!isAdmin() || $_POST['user']) {
                    $params['user'] = $_POST['user'];
                }

                $zone = $api->dns_zone->create($params);

                notify_user(_('Primary DNS zone created'), '');
                redirect('?page=dns&action=zone_show&id=' . $zone->id);

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to create primary DNS zone'), $e->getResponse());
                primary_dns_zone_new();
            }
            break;

        case 'dnssec_records':
            dnssec_records_list($_GET['id']);
            break;

        case 'record_new':
            dns_record_new($_GET['zone']);
            break;

        case 'record_new2':
            csrf_check();

            try {
                $params = [
                    'dns_zone' => $_GET['zone'],
                    'name' => $_POST['name'],
                    'type' => $_POST['type'],
                    'content' => $_POST['content'],
                    'comment' => $_POST['comment'],
                    'enabled' => isset($_POST['enabled']),
                ];

                if (trim($_POST['ttl'] ?? '') !== '') {
                    $params['ttl'] = $_POST['ttl'];
                }

                if (trim($_POST['priority'] ?? '') !== '') {
                    $params['priority'] = $_POST['priority'];
                }

                if (isset($_POST['dynamic_update_enabled'])) {
                    $params['dynamic_update_enabled'] = true;
                }

                $record = $api->dns_record->create($params);

                notify_user(_('Record added'), '');
                redirect('?page=dns&action=zone_show&id=' . $_GET['zone']);

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to add record'), $e->getResponse());
                dns_record_new($_GET['zone']);
            }
            break;

        case 'record_edit':
            dns_record_edit($_GET['id']);
            break;

        case 'record_edit2':
            csrf_check();

            try {
                $record = $api->dns_record->update($_GET['id'], [
                    'ttl' => trim($_POST['ttl'] ?? '') === '' ? null : $_POST['ttl'],
                    'priority' => trim($_POST['priority'] ?? '') === '' ? null : $_POST['priority'],
                    'content' => $_POST['content'],
                    'comment' => $_POST['comment'],
                    'dynamic_update_enabled' => isset($_POST['dynamic_update_enabled']),
                    'enabled' => isset($_POST['enabled']),
                ]);

                notify_user(_('Record updated'), '');
                redirect('?page=dns&action=zone_show&id=' . $record->dns_zone_id);

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to update record'), $e->getResponse());
                dns_record_edit($_GET['id']);
            }
            break;

        case 'record_delete':
            csrf_check();

            try {
                $api->dns_record->delete($_GET['id']);

                notify_user(_('Record deleted'), '');
                redirect('?page=dns&action=zone_show&id=' . $_GET['zone']);

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to update record'), $e->getResponse());
                dns_zone_show($_GET['zone']);
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
