<?php
/*
    ./pages/page_cluster.php

    vpsAdmin
    Web-admin interface for vpsAdminOS (see https://vpsadminos.org)
    Copyright (C) 2008-2011 Pavel Snajdr, snajpa@snajpa.net
*/
if (isAdmin()) {

    function maintenance_lock_by_type()
    {
        global $api;

        $r = null;
        $label = '';

        switch ($_GET['type']) {
            case 'cluster':
                $r = $api->cluster;
                $label = _('Cluster');
                break;

            case 'environment':
                $label = _('Environment') . ' ' . $api->environment->find($_GET['obj_id'])->label;
                break;

            case 'location':
                $label = _('Location') . ' ' . $api->location->find($_GET['obj_id'])->label;
                break;

            case 'node':
                $label = _('Node') . ' ' . $api->node->find($_GET['obj_id'])->name;
                break;

            case 'vps':
                $label = 'VPS #' . $_GET['obj_id'];
                break;

            default:
                break;
        }

        return ['resource' => $r, 'label' => $label];
    }

    $xtpl->title(_("Manage Cluster"));
    $list_locations = false;
    $list_nodes = false;
    $list_templates = false;
    $list_dns = false;
    $env_settings = false;

    $server_types = ["node" => "Node", "storage" => "Storage", "mailer" => "Mailer"];

    switch($_GET["action"] ?? null) {
        case "vps":
            cluster_header();
            node_vps_overview();
            break;

        case "sysconfig":
            system_config_form();

            $xtpl->sbar_add(_("Back"), '?page=cluster');
            break;

        case "sysconfig_save":
            csrf_check();

            $current_cfg = new SystemConfig($api, true);
            $changes = [];

            foreach ($current_cfg as $k => $v) {
                [$cat, $name] = explode(':', $k);
                $type = $current_cfg->getType($cat, $name);

                if ($type === 'Boolean') {
                    if ($v && !$_POST[$k]) {
                        $changes[] = [$cat, $name, '0'];

                    } elseif (!$v && $_POST[$k]) {
                        $changes[] = [$cat, $name, '1'];
                    }

                } elseif ($_POST[$k] != $v) {
                    $changes[] = [$cat, $name, $_POST[$k]];
                }
            }

            $failed = [];

            foreach ($changes as $change) {
                try {
                    $api->system_config->update($change[0], $change[1], [
                        'value' => $change[2],
                    ]);

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $failed[] = $change[0] . ':' . $change[1];
                }
            }

            $config->reload();

            if (count($failed)) {
                $xtpl->perex(
                    _("Some changes were saved"),
                    _("The following options failed:") . '<br>' .
                    implode("\n<br>\n", $failed)
                );
                system_config_form();

            } else {
                notify_user(_("Changes saved"), _("Changes sucessfully saved."));
                redirect('?page=cluster&action=sysconfig');
            }

            break;

        case "dns":
            $list_dns = true;
            break;

        case "dns_new":
            $xtpl->title2(_("New DNS Server"));
            $xtpl->table_add_category('');
            $xtpl->table_add_category('');
            $xtpl->form_create('?page=cluster&action=dns_new_save', 'post');
            $xtpl->form_add_input(_("IP Address") . ':', 'text', '30', 'dns_ip', '', '');
            $xtpl->form_add_input(_("Label") . ':', 'text', '30', 'dns_label', '', _("DNS Label"));
            $xtpl->form_add_checkbox(_("Is this DNS location independent?") . ':', 'dns_is_universal', '1', false, '');
            $xtpl->form_add_select(
                _("Location") . ':',
                'dns_location',
                resource_list_to_options($api->location->list()),
                '',
                ''
            );
            $xtpl->form_out(_("Save changes"));
            break;

        case "dns_new_save":
            csrf_check();

            try {
                $api->dns_resolver->create([
                    'label' => $_POST['dns_label'],
                    'ip_addr' => $_POST['dns_ip'],
                    'is_universal' => isset($_POST['dns_is_universal']),
                    'location' => $_POST['dns_location'],
                ]);

                notify_user(_("Changes saved"), _("DNS server added."));
                redirect('?page=cluster&action=dns');

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to create a DNS resolver'), $e->getResponse());
            }
            break;

        case "dns_edit":
            $ns = $api->dns_resolver->find($_GET['id']);

            $xtpl->title2(_("Edit DNS Server"));
            $xtpl->table_add_category('');
            $xtpl->table_add_category('');
            $xtpl->form_create('?page=cluster&action=dns_edit_save&id=' . $ns->id, 'post');
            $xtpl->form_add_input(_("IP Address") . ':', 'text', '30', 'dns_ip', $ns->ip_addr, '');
            $xtpl->form_add_input(_("Label") . ':', 'text', '30', 'dns_label', $ns->label, _("DNS Label"));
            $xtpl->form_add_checkbox(_("Is this DNS location independent?") . ':', 'dns_is_universal', '1', $ns->is_universal, '');
            $xtpl->form_add_select(
                _("Location") . ':',
                'dns_location',
                resource_list_to_options($api->location->list()),
                $ns->location_id,
                ''
            );
            $xtpl->form_out(_("Save changes"));

            break;

        case "dns_edit_save":
            csrf_check();

            try {
                $api->dns_resolver->update($_GET['id'], [
                    'label' => $_POST['dns_label'],
                    'ip_addr' => $_POST['dns_ip'],
                    'is_universal' => isset($_POST['dns_is_universal']),
                    'location' => $_POST['dns_location'] ? $_POST['dns_location'] : NULL,
                ]);

                notify_user(_("Changes saved"), _("DNS server updated."));
                redirect('?page=cluster&action=dns');

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to update a DNS resolver'), $e->getResponse());
            }
            break;

        case "dns_delete":
            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();

                try {
                    $api->dns_resolver->delete($_GET['id'], ['force' => isset($_POST['force'])]);

                    notify_user(_("Changes saved"), _("DNS server deleted."));
                    redirect('?page=cluster&action=dns');

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Failed to delete a DNS resolver'), $e->getResponse());
                    dns_delete_form();
                }

            } else {
                dns_delete_form();
            }
            break;

        case 'environments':
            $xtpl->sbar_add(_("Back"), '?page=cluster');

            $xtpl->title2(_("Environments"));

            $xtpl->table_add_category('#');
            $xtpl->table_add_category(_('Label'));
            $xtpl->table_add_category(_('Domain'));
            $xtpl->table_add_category(_('Create a VPS'));
            $xtpl->table_add_category(_('Destroy a VPS'));
            $xtpl->table_add_category(_('VPS count'));
            $xtpl->table_add_category(_('IP ownership'));
            $xtpl->table_add_category('<img title="' . _("Toggle maintenance on environment.") . '" alt="' . _("Toggle maintenance on environment.") . '" src="template/icons/maintenance_mode.png">');
            $xtpl->table_add_category('');

            $envs = $api->environment->list();

            foreach ($envs as $env) {
                $xtpl->table_td($env->id);
                $xtpl->table_td($env->label);
                $xtpl->table_td($env->domain);
                $xtpl->table_td(boolean_icon($env->can_create_vps));
                $xtpl->table_td(boolean_icon($env->can_destroy_vps));
                $xtpl->table_td($env->max_vps_count, false, true);
                $xtpl->table_td(boolean_icon($env->user_ip_ownership));
                $xtpl->table_td(maintenance_lock_icon('environment', $env));
                $xtpl->table_td('<a href="?page=cluster&action=env_edit&id=' . $env->id . '"><img src="template/icons/edit.png" title="' . _("Edit") . '"></a>');

                $xtpl->table_tr();
            }

            $xtpl->table_out();

            break;

        case 'env_edit':
            $xtpl->sbar_add(_("Back"), '?page=cluster&action=environments');
            $env_settings = true;
            break;


        case 'env_save':
            if (isset($_POST['label'])) {
                csrf_check();

                try {
                    $api->environment->update($_GET['id'], [
                        'label' => $_POST['label'],
                        'domain' => $_POST['domain'],
                        'can_create_vps' => isset($_POST['can_create_vps']),
                        'can_destroy_vps' => isset($_POST['can_destroy_vps']),
                        'vps_lifetime' => $_POST['vps_lifetime'],
                        'max_vps_count' => $_POST['max_vps_count'],
                        'user_ip_ownership' => isset($_POST['user_ip_ownership']),
                    ]);

                    notify_user(_("Environment updated"), '');
                    redirect('?page=cluster&action=environments');

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Environment update failed'), $e->getResponse());
                }
            }
            break;

        case "locations":
            $list_locations = true;
            break;

            // 	case "location_delete":
            // 		try {
            // 			$api->location->delete($_GET['id']);
            //
            // 			notify_user(_("Location deleted"), '');
            // 			redirect('?page=cluster&action=locations');
            //
            // 		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
            // 			$xtpl->perex_format_errors(_('Location deletion failed'), $e->getResponse());
            // 		}
            //
            // 		$list_locations = true;
            // 		break;

        case "location_new":
            $xtpl->title2(_("New cluster location"));

            $xtpl->table_add_category('');
            $xtpl->table_add_category('');

            $xtpl->form_create('?page=cluster&action=location_new_save', 'post');
            $xtpl->form_add_input(_("Label") . ':', 'text', '30', 'location_label', '', _("Location name"));
            $xtpl->form_add_checkbox(_("Has this location IPv6 support?") . ':', 'has_ipv6', '1', false, '');
            $xtpl->form_add_input(_("Remote console server") . ':', 'text', '30', 'remote_console_server', '', _("URL"));
            $xtpl->form_add_input(_("Domain") . ':', 'text', '30', 'domain', $item["domain"], '');
            $xtpl->form_out(_("Save changes"));

            break;

        case "location_new_save":
            csrf_check();

            try {
                $api->location->create([
                    'label' => $_POST['location_label'],
                    'type' => $_POST['type'],
                    'has_ipv6' => (bool) $_POST['has_ipv6'],
                    'remote_console_server' => $_POST['remote_console_server'],
                    'domain' => $_POST['domain'],
                ]);

                notify_user(_("Location created"), '');
                redirect('?page=cluster&action=locations');

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Location creation failed'), $e->getResponse());
            }

            break;

        case "location_edit":
            try {
                $loc = $api->location->find($_GET['id']);

                $xtpl->title2(_("Edit location"));
                $xtpl->table_add_category('');
                $xtpl->table_add_category('');
                $xtpl->form_create('?page=cluster&action=location_edit_save&id=' . $loc->id, 'post');
                $xtpl->form_add_input(_("Label") . ':', 'text', '30', 'location_label', $loc->label, _("Location name"));
                $xtpl->form_add_checkbox(_("Has this location IPv6 support?") . ':', 'has_ipv6', '1', $loc->has_ipv6, '');
                $xtpl->form_add_input(_("Remote console server") . ':', 'text', '30', 'remote_console_server', $loc->remote_console_server, _("URL"));
                $xtpl->form_add_input(_("Domain") . ':', 'text', '30', 'domain', $loc->domain, '');

                $xtpl->form_out(_("Save changes"));

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Location find failed'), $e->getResponse());
            }

            break;

        case "location_edit_save":
            csrf_check();

            try {
                $api->location->update($_GET['id'], [
                    'label' => $_POST['location_label'],
                    'type' => $_POST['type'],
                    'has_ipv6' => (bool) $_POST['has_ipv6'],
                    'remote_console_server' => $_POST['remote_console_server'],
                    'domain' => $_POST['domain'],
                ]);

                notify_user(_("Changes saved"), _("Location label saved."));
                redirect('?page=cluster&action=locations');

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Location update failed'), $e->getResponse());
            }

            break;

        case 'resource_packages':
            resource_packages_list();
            break;

        case 'resource_packages_new':
            if ($_POST['label']) {
                csrf_check();

                try {
                    $pkg = $api->cluster_resource_package->create([
                        'label' => $_POST['label'],
                    ]);

                    notify_user(_("Package created"), _("The cluster resource package was created."));
                    redirect('?page=cluster&action=resource_packages_edit&id=' . $pkg->id);

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Create failed'), $e->getResponse());
                    resource_packages_create_form();
                }
            } else {
                resource_packages_create_form();
            }
            break;

        case 'resource_packages_edit':
            if ($_POST['label']) {
                csrf_check();

                try {
                    $api->cluster_resource_package->update($_GET['id'], [
                        'label' => $_POST['label'],
                    ]);

                    notify_user(_("Package updated "), _("The cluster resource package was updated."));
                    redirect('?page=cluster&action=resource_packages_edit&id=' . $_GET['id']);

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Update failed'), $e->getResponse());
                    resource_packages_edit_form($_GET['id']);
                }
            } else {
                resource_packages_edit_form($_GET['id']);
            }
            break;

        case 'resource_packages_delete':
            if ($_POST['confirm'] == '1') {
                csrf_check();

                try {
                    $api->cluster_resource_package->delete($_GET['id']);

                    redirect('?page=cluster&action=resource_packages');

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Delete failed'), $e->getResponse());
                    resource_packages_delete_form($_GET['id']);
                }
            } else {
                resource_packages_delete_form($_GET['id']);
            }
            break;

        case 'resource_packages_item_add':
            if ($_POST['value']) {
                csrf_check();

                try {
                    $api->cluster_resource_package($_GET['id'])->item->create([
                        'cluster_resource' => $_POST['cluster_resource'],
                        'value' => $_POST['value'],
                    ]);

                    redirect('?page=cluster&action=resource_packages_edit&id=' . $_GET['id']);

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Update failed'), $e->getResponse());
                    resource_packages_edit_form($_GET['id']);
                }
            } else {
                resource_packages_edit_form($_GET['id']);
            }
            break;

        case 'resource_packages_item_edit':
            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();

                try {
                    $api->cluster_resource_package($_GET['id'])->item->update($_GET['item'], [
                        'value' => $_POST['value'],
                    ]);

                    redirect('?page=cluster&action=resource_packages_edit&id=' . $_GET['id']);

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Update failed'), $e->getResponse());
                    resource_packages_item_edit_form($_GET['id'], $_GET['item']);
                }
            } else {
                resource_packages_item_edit_form($_GET['id'], $_GET['item']);
            }
            break;

        case 'resource_packages_item_delete':
            if ($_POST['confirm'] == '1') {
                csrf_check();

                try {
                    $api->cluster_resource_package($_GET['id'])->item->delete($_GET['item']);

                    redirect('?page=cluster&action=resource_packages_edit&id=' . $_GET['id']);

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Delete failed'), $e->getResponse());
                    resource_packages_item_delete_form($_GET['id'], $_GET['item']);
                }
            } else {
                resource_packages_item_delete_form($_GET['id'], $_GET['item']);
            }
            break;

        case "networks":
            networks_list();
            $xtpl->sbar_add(_("Back"), '?page=cluster');
            break;

        case "network_locations":
            network_locations_list($_GET['network']);
            $xtpl->sbar_add(_("Back to networks"), '?page=cluster&action=networks');
            break;

        case "location_networks":
            location_networks_list($_GET['location']);
            $xtpl->sbar_add(_("Back to locations"), '?page=cluster&action=locations');
            break;

        case "location_network_add_nettoloc":
            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();

                try {
                    $api->location_network->create([
                        'location' => $_GET['location'],
                        'network' => $_POST['network'],
                        'primary' => isset($_POST['primary']),
                        'priority' => $_POST['priority'],
                        'autopick' => isset($_POST['autopick']),
                        'userpick' => isset($_POST['userpick']),
                    ]);

                    notify_user(_('Network added to location'), '');
                    redirect('?page=cluster&action=location_networks&location=' . $_GET['location']);

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Create failed'), $e->getResponse());
                    location_network_add_nettoloc_form($_GET['location']);
                }
            } else {
                location_network_add_nettoloc_form($_GET['location']);
            }
            break;

        case "location_network_add_loctonet":
            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();

                try {
                    $api->location_network->create([
                        'location' => $_POST['location'],
                        'network' => $_GET['network'],
                        'primary' => isset($_POST['primary']),
                        'priority' => $_POST['priority'],
                        'autopick' => isset($_POST['autopick']),
                        'userpick' => isset($_POST['userpick']),
                    ]);

                    notify_user(_('Location added to network'), '');
                    redirect('?page=cluster&action=network_locations&network=' . $_GET['network']);

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Create failed'), $e->getResponse());
                    location_network_add_loctonet_form($_GET['network']);
                }
            } else {
                location_network_add_loctonet_form($_GET['network']);
            }
            break;

        case "location_network_edit":
            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();

                try {
                    $api->location_network($_GET['id'])->update([
                        'primary' => isset($_POST['primary']),
                        'priority' => $_POST['priority'],
                        'autopick' => isset($_POST['autopick']),
                        'userpick' => isset($_POST['userpick']),
                    ]);

                    notify_user(_('Changes saved'), '');
                    redirect('?page=cluster&action=location_network_edit&id=' . $_GET['id']);

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Update failed'), $e->getResponse());
                    location_network_edit_form($_GET['id']);
                }
            } else {
                location_network_edit_form($_GET['id']);
            }
            break;

        case "location_network_del":
            csrf_check();

            try {
                $api->location_network($_GET['id'])->delete();

                notify_user(_('Network removed from location'), '');
                redirect($_GET['return']);

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Delete failed'), $e->getResponse());
                redirect($_GET['return']);
            }
            break;

        case "ip_addresses":
            ip_address_list('cluster');
            $xtpl->sbar_add(_("Back"), '?page=cluster');
            $xtpl->sbar_add(_("Add IP addresses"), '?page=cluster&action=ipaddr_add');
            break;

        case "host_ip_addresses":
            host_ip_address_list('cluster');
            $xtpl->sbar_add(_("Back"), '?page=cluster');
            break;

        case "ipaddr_add":
            ip_add_form();
            break;

        case "ipaddr_add2":
            csrf_check();

            if (!$_POST['ip_addresses']) {
                return;
            }

            $addrs = preg_split("/(\r\n|\n|\r)/", trim($_POST['ip_addresses']));
            $res = [];
            $params = [
                'addr' => $t,
                'network' => $_POST['network'],
            ];

            if ($_POST['user']) {
                $params['user'] = $_POST['user'];
            }

            $failed = false;

            foreach ($addrs as $a) {
                $t = trim($a);

                if (!$t) {
                    continue;
                }

                if ($failed) {
                    $res[$t] = false;
                    continue;
                }

                $params['addr'] = $t;

                try {
                    $api->ip_address->create($params);
                    $res[$t] = true;

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('IP addition failed'), $e->getResponse());
                    $res[$t] = false;
                    $failed = true;
                }
            }

            $str = '';

            if ($failed) {
                foreach ($res as $addr => $status) {
                    if (!$status) {
                        $str .= "$addr\n";
                    }
                }

                ip_add_form($str);

            } else {
                foreach ($res as $addr => $status) {
                    if ($status) {
                        $str .= "Added $addr<br>\n";
                    }
                }

                notify_user(_('IP addresses added'), $str);
                redirect('?page=cluster&action=ip_addresses');
            }

            break;

        case "ipaddr_edit":
            ip_edit_form($_GET['id']);
            break;

        case "ipaddr_edit_user":
            csrf_check();

            try {
                $params = [
                    'user' => $_POST['user'] ? $_POST['user'] : null,
                    'environment' => $_POST['environment'] ? $_POST['environment'] : null,
                ];

                $ret = $api->ip_address($_GET['id'])->update($params);

                notify_user(_('Owner set'), '');
                redirect($_GET['return'] ? $_GET['return'] : '?page=cluster&action=ip_addresses');

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Update failed'), $e->getResponse());
                ip_edit_form($_GET['id']);
            }

            break;

        case "templates":
            $list_templates = true;
            break;

        case "templates_edit":
            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();

                try {
                    $api->os_template->update($_GET['id'], [
                        'label' => $_POST['label'],
                        'info' => $_POST['info'],
                        'enabled' => isset($_POST['enabled']),
                        'supported' => isset($_POST['supported']),
                        'order' => $_POST['order'],
                        'hypervisor_type' => $_POST['hypervisor_type'],
                        'cgroup_version' => $_POST['cgroup_version'],
                        'vendor' => $_POST['vendor'],
                        'variant' => $_POST['variant'],
                        'arch' => $_POST['arch'],
                        'distribution' => $_POST['distribution'],
                        'version' => $_POST['version'],
                    ]);

                    notify_user(_("Changes saved"), _("Changes you've made to the template were saved."));
                    redirect('?page=cluster&action=templates');

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Update failed'), $e->getResponse());
                    os_template_edit_form();
                }

            } else {
                os_template_edit_form();
            }

            break;

        case "template_register":
            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();

                try {
                    $api->os_template->create([
                        'label' => $_POST['label'],
                        'info' => $_POST['info'],
                        'enabled' => isset($_POST['enabled']),
                        'supported' => isset($_POST['supported']),
                        'order' => $_POST['order'],
                        'hypervisor_type' => $_POST['hypervisor_type'],
                        'cgroup_version' => $_POST['cgroup_version'],
                        'vendor' => $_POST['vendor'],
                        'variant' => $_POST['variant'],
                        'arch' => $_POST['arch'],
                        'distribution' => $_POST['distribution'],
                        'version' => $_POST['version'],
                    ]);

                    notify_user(_("OS template registered"), _("The OS template was successfully registered."));
                    redirect('?page=cluster&action=templates');

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Create failed'), $e->getResponse());
                    os_template_add_form();
                }

            } else {
                os_template_add_form();
            }
            break;

        case "templates_delete":
            if ($_POST['confirm']) {
                csrf_check();

                try {
                    $api->os_template->delete($_GET['id']);

                    notify_user(_("OS template deleted"), _("The OS template was successfully deleted."));
                    redirect('?page=cluster&action=templates');

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Delete failed'), $e->getResponse());
                }

            } else {
                $t = $api->os_template->find($_GET['id']);

                $xtpl->table_title(_('Confirm deletion of OS template') . ' ' . $t->label);
                $xtpl->form_create('?page=cluster&action=templates_delete&id=' . $t->id, 'post');
                $xtpl->form_add_checkbox(_('Confirm') . ':', 'confirm', '1', false);
                $xtpl->form_out(_("Delete"));

                $xtpl->sbar_add(_("Back"), '?page=cluster&action=templates');
            }
            break;


        case "newnode":
            node_create_form();
            $xtpl->sbar_add(_("Back"), '?page=cluster');
            break;

        case "newnode_save":
            csrf_check();

            try {
                $api->node->create($_POST);
                notify_user(_("Node created"), _("The node was succesfully registered."));
                redirect('?page=cluster');

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors('Registration failed', $e->getResponse());
                node_create_form();
            }
            break;

        case "node_edit":
            $xtpl->sbar_add(_("Back"), '?page=cluster');
            node_update_form($_GET['node_id']);
            break;

        case "node_edit_save":
            csrf_check();

            try {
                $api->node->update($_GET['node_id'], $_POST);
                notify_user(_("Settings updated"), _("Settings succesfully updated."));
                redirect('?page=cluster');

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors('Update failed', $e->getResponse());
                node_update_form($_GET['node_id']);
            }
            break;

        case "maintenance_lock":
            $xtpl->title("Maintenance lock");

            $xtpl->table_add_category('');
            $xtpl->table_add_category('');

            $xtpl->form_create('?page=cluster&action=set_maintenance_lock&lock=1&type=' . $_GET['type'] . '&obj_id=' . $_GET['obj_id'], 'post');

            $ret = maintenance_lock_by_type();

            $xtpl->table_td(_('Set on') . ':');
            $xtpl->table_td($ret['label']);
            $xtpl->table_tr();

            $xtpl->form_add_input(_("Reason") . ':', 'text', '30', 'reason', '', _('optional'));

            $xtpl->form_out(_("Lock"));

            if ($api->outage) {
                outage_report_form($_GET['type'], $_GET['obj_id']);
            }
            break;

        case "set_maintenance_lock":
            csrf_check();

            if (isset($_GET['type'])) {
                $ret = maintenance_lock_by_type();

                $r = $ret['resource'];
                $label = $ret['label'];

                if (!$r) {
                    $r = $api->{$_GET['type']}($_GET['obj_id']);
                }

                try {
                    $params = ['lock' => $_GET['lock'] ? true : false];

                    if ($_GET['lock']) {
                        $params['reason'] = $_POST['reason'];
                    }

                    $r->set_maintenance($params);

                    notify_user($label . ': ' . _('maintenance') . ' ' . ($_GET['lock'] ? _('ON') : _('OFF')), '');
                    redirect('?page=cluster');

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors($label . ': ' . _('maintenance') . ' FAILED to set', $e->getResponse());
                }

            }
            break;

        case "eventlog":
            news_list_and_create_form();
            $xtpl->sbar_add(_("Back"), '?page=cluster');
            break;

        case "log_add":
            csrf_check();

            try {
                $api->news_log->create([
                    'published_at' => date('c', strtotime($_POST['published_at'])),
                    'message' => $_POST['message'],
                ]);

                notify_user(_("News message added"), _("Message successfully saved."));
                redirect('?page=cluster&action=eventlog');

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Create failed'), $e->getResponse());
                news_list_and_create_form();
            }
            break;

        case "log_edit":
            news_edit_form($_GET['id']);
            break;

        case "log_edit_save":
            csrf_check();

            try {
                $api->news_log->update($_GET['id'], [
                    'published_at' => date('c', strtotime($_POST['published_at'])),
                    'message' => $_POST['message'],
                ]);

                notify_user(_("Log message updated"), _("Message successfully updated."));
                redirect('?page=cluster&action=eventlog');

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Create failed'), $e->getResponse());
                news_edit_form($_GET['id']);
            }
            break;

        case "log_del":
            csrf_check();

            try {
                $api->news_log->delete($_GET['id']);

                notify_user(_("Log message deleted"), _("Message successfully deleted."));
                redirect('?page=cluster&action=eventlog');

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Create failed'), $e->getResponse());
                news_list_and_create_form();
            }
            break;

        case "helpboxes":
            helpbox_list_and_create_form();
            $xtpl->sbar_add(_("Back"), '?page=cluster');
            break;

        case "helpboxes_add":
            csrf_check();

            try {
                $api->help_box->create(client_params_to_api($api->help_box->create));

                notify_user(_("Help box added"), _("Help box successfully saved."));
                redirect('?page=cluster&action=helpboxes');

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Create failed'), $e->getResponse());
                helpbox_list_and_create_form();
            }
            break;

        case "helpboxes_edit":
            helpbox_edit_form($_GET['id']);
            break;

        case "helpboxes_edit_save":
            csrf_check();

            try {
                $api->help_box->update($_GET['id'], client_params_to_api($api->help_box->update));

                notify_user(_("Help box updated"), _("Help box successfully saved."));
                redirect('?page=cluster&action=helpboxes');

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Create failed'), $e->getResponse());
                helpbox_edit_form($_GET['id']);
            }

            break;

        case "helpboxes_del":
            csrf_check();

            try {
                $api->help_box->delete($_GET['id']);

                notify_user(_("Help box deleted"), _("Help box successfully deleted."));
                redirect('?page=cluster&action=helpboxes');

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Create failed'), $e->getResponse());
                helpbox_list_and_create_form();
            }
            break;

        default:
            $list_nodes = true;
    }

    if ($list_nodes) {
        cluster_header();
        node_overview();
    }

    if ($list_templates) {
        $xtpl->title2(_("Templates list"));
        $xtpl->table_add_category(_("Label"));
        $xtpl->table_add_category(_("Name"));
        $xtpl->table_add_category(_("Uses"));
        $xtpl->table_add_category(_("Enabled"));
        $xtpl->table_add_category(_("Supported"));
        $xtpl->table_add_category(_("#"));
        $xtpl->table_add_category('');
        $xtpl->table_add_category('');

        $templates = $api->os_template->list();

        foreach($templates as $t) {
            $usage = $api->vps->list([
                'os_template' => $t->id,
                'limit' => 0,
                'meta' => ['count' => true],
            ])->getTotalCount();

            $xtpl->table_td($t->label);
            $xtpl->table_td($t->name);
            $xtpl->table_td($usage);
            $xtpl->table_td(boolean_icon($t->enabled));
            $xtpl->table_td(boolean_icon($t->supported));
            $xtpl->table_td($t->order);
            $xtpl->table_td('<a href="?page=cluster&action=templates_edit&id=' . $t->id . '"><img src="template/icons/edit.png" title="' . _("Edit") . '"></a>');

            if ($usage > 0) {
                $xtpl->table_td('<img src="template/icons/delete_grey.png" title="' . _("Delete - N/A, template is in use") . '">');
            } else {
                $xtpl->table_td('<a href="?page=cluster&action=templates_delete&id=' . $t->id . '"><img src="template/icons/delete.png" title="' . _("Delete") . '"></a>');
            }

            $xtpl->table_tr();
        }
        $xtpl->table_out();

        $xtpl->sbar_add(_("Back"), '?page=cluster');
        $xtpl->sbar_add(_("Register new template"), '?page=cluster&action=template_register');
    }

    if ($list_locations) {
        $xtpl->title2(_("Cluster locations list"));

        $xtpl->table_add_category(_("ID"));
        $xtpl->table_add_category(_("Location label"));
        $xtpl->table_add_category(_("Environment"));
        $xtpl->table_add_category(_("Servers"));
        $xtpl->table_add_category(_("IPv6"));
        $xtpl->table_add_category(_("Domain"));
        $xtpl->table_add_category(_("Networks"));
        $xtpl->table_add_category('<img title="' . _("Toggle maintenance on node.") . '" alt="' . _("Toggle maintenance on node.") . '" src="template/icons/maintenance_mode.png">');
        $xtpl->table_add_category('');
        // 	$xtpl->table_add_category('');

        $locations = $api->location->list(['meta' => ['includes' => 'environment']]);

        foreach($locations as $loc) {
            $nodes = $api->node->list(
                [
                'location' => $loc->id,
                'limit' => 0,
                'meta' => ['count' => true]]
            );

            $xtpl->table_td($loc->id);
            $xtpl->table_td($loc->label);
            $xtpl->table_td($loc->environment->label);
            $xtpl->table_td($nodes->getTotalCount(), false, true);

            if ($loc->has_ipv6) {
                $xtpl->table_td('<img src="template/icons/transact_ok.png" />');
            } else {
                $xtpl->table_td('<img src="template/icons/transact_fail.png" />');
            }
            $xtpl->table_td($loc->domain);
            $xtpl->table_td(
                '<a href="?page=cluster&action=location_networks&location=' . $loc->id . '">' .
                '<img
				src="template/icons/vps_ip_list.png"
				title="' . _('List networks available in this location') . '">' .
                '</a>'
            );
            $xtpl->table_td(maintenance_lock_icon('location', $loc));
            $xtpl->table_td('<a href="?page=cluster&action=location_edit&id=' . $loc->id . '"><img src="template/icons/edit.png" title="' . _("Edit") . '"></a>');

            // 		if ($nodes->getTotalCount() > 0) {
            // 			$xtpl->table_td('<img src="template/icons/delete_grey.png" title="'._("Delete - N/A, item is in use").'">');
            // 		} else {
            // 			$xtpl->table_td('<a href="?page=cluster&action=location_delete&id='.$loc->id.'"><img src="template/icons/delete.png" title="'._("Delete").'"></a>');
            // 		}

            $xtpl->table_tr();
        }
        $xtpl->table_out();
        $xtpl->sbar_add(_("New location"), '?page=cluster&action=location_new');
    }
    if ($list_dns) {
        $xtpl->title2(_("DNS Servers list"));
        $xtpl->table_add_category(_("ID"));
        $xtpl->table_add_category(_("IP"));
        $xtpl->table_add_category(_("Label"));
        $xtpl->table_add_category(_("All locations"));
        $xtpl->table_add_category(_("Location"));
        $xtpl->table_add_category('');
        $xtpl->table_add_category('');

        $nameservers = $api->dns_resolver->list([
            'meta' => ['includes' => 'location'],
        ]);

        foreach($nameservers as $ns) {
            $xtpl->table_td($ns->id);
            $xtpl->table_td($ns->ip_addr);
            $xtpl->table_td($ns->label);
            $xtpl->table_td(boolean_icon($ns->is_universal));
            $xtpl->table_td($ns->is_universal ? '---' : $ns->location->label);
            $xtpl->table_td('<a href="?page=cluster&action=dns_edit&id=' . $ns->id . '"><img src="template/icons/edit.png" title="' . _("Edit") . '"></a>');
            $xtpl->table_td('<a href="?page=cluster&action=dns_delete&id=' . $ns->id . '"><img src="template/icons/delete.png" title="' . _("Delete") . '"></a>');
            $xtpl->table_tr();
        }
        $xtpl->table_out();
        $xtpl->sbar_add(_("New DNS Server"), '?page=cluster&action=dns_new');
    }

    if ($env_settings) {
        $env = $api->environment->find($_GET['id']);

        $xtpl->title2(_("Manage environment") . ' ' . $env->label);

        $xtpl->table_add_category($env->label);
        $xtpl->table_add_category('');

        $xtpl->form_create('?page=cluster&action=env_save&id=' . $env->id, 'post');
        api_update_form($env);
        $xtpl->form_out(_('Save'));
    }

    $xtpl->sbar_out(_("Manage Cluster"));

} else {
    $xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
}
