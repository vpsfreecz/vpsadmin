<?php
/*
    ./pages/page_networking.php

    vpsAdmin
    Web-admin interface for vpsAdminOS (see https://vpsadminos.org)
    Copyright (C) 2008-2011 Pavel Snajdr, snajpa@snajpa.net
*/

function year_list()
{
    $now = date("Y");
    $ret = ['' => '---'];

    for ($i = $now - 5; $i <= $now; $i++) {
        $ret[$i] = $i;
    }

    return $ret;
}

function month_list()
{
    $ret = ['' => '---'];

    for ($i = 1; $i <= 12; $i++) {
        $ret[$i] = $i;
    }

    return $ret;
}

$show_top = false;
$show_live = false;
$show_traffic = false;

if (isLoggedIn()) {

    switch($_GET['action'] ?? null) {
        case 'ip_addresses':
            ip_address_list('networking');
            break;

        case 'host_ip_addresses':
            host_ip_address_list('networking');
            break;

        case "route_assign":
            route_assign_form($_GET['id']);
            break;

        case "route_assign2":
            csrf_check();

            try {
                if (isset($_POST['route-only'])) {
                    $api->ip_address($_GET['id'])->assign([
                        'network_interface' => $_POST['network_interface'],
                        'route_via' => $_POST['route_via'] ? $_POST['route_via'] : null,
                    ]);

                    notify_user(_('IP assigned'), '');
                    redirect($_GET['return'] ? $_GET['return'] : '?page=networking&action=ip_addresses');

                } elseif (isset($_POST['route-and-host'])) {
                    if ($_POST['route_via']) {
                        $xtpl->perex(
                            _('Invalid route'),
                            _('When adding the address to the interface, it cannot be routed ' .
                              'through another address: do not set the "Address" field')
                        );
                        route_assign_form($_GET['id']);

                    } else {
                        $api->ip_address($_GET['id'])->assign_with_host_address([
                            'network_interface' => $_POST['network_interface'],
                            'route_via' => $_POST['route_via'] ? $_POST['route_via'] : null,
                        ]);

                        notify_user(_('IP assigned'), '');
                        redirect($_GET['return'] ? $_GET['return'] : '?page=networking&action=ip_addresses');
                    }
                } else {
                    $xtpl->perex(_('Something went wrong'), _('Try again or contact support'));
                    route_assign_form($_GET['id']);
                }

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Action failed'), $e->getResponse());
                route_assign_form($_GET['id']);
            }

            break;

        case "route_unassign":
            route_unassign_form($_GET['id']);
            break;

        case "route_unassign2":
            csrf_check();

            if (!$_POST['confirm']) {
                route_unassign_form($_GET['id']);
                break;
            }

            try {
                $ip = $api->ip_address->show($_GET['id']);

                if (isAdmin() && $_POST['disown']) {
                    $ip->update(['user' => null]);
                }

                $ip->free();

                notify_user(_('IP removed'), '');
                redirect($_GET['return'] ? $_GET['return'] : '?page=networking&action=ip_addresses');

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Action failed'), $e->getResponse());
                route_unassign_form($_GET['id']);
            }

            break;

        case "hostaddr_assign":
            hostaddr_assign_form($_GET['id']);
            break;

        case "hostaddr_assign2":
            csrf_check();

            try {
                $api->host_ip_address($_GET['id'])->assign([
                    'network_interface' => $_POST['network_interface'],
                ]);

                notify_user(_('IP assigned'), '');
                redirect($_GET['return'] ? $_GET['return'] : '?page=networking&action=ip_addresses');

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Action failed'), $e->getResponse());
                ip_assign_form($_GET['id']);
            }

            break;

        case "hostaddr_unassign":
            hostaddr_unassign_form($_GET['id']);
            break;

        case "hostaddr_unassign2":
            csrf_check();

            if (!$_POST['confirm']) {
                hostaddr_unassign_form($_GET['id']);
                break;
            }

            try {
                $api->host_ip_address->free($_GET['id']);

                notify_user(_('IP removed'), '');
                redirect($_GET['return'] ? $_GET['return'] : '?page=networking&action=ip_addresses');

            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Action failed'), $e->getResponse());
                ip_unassign_form($_GET['id']);
            }

            break;

        case 'assignments':
            ip_address_assignment_list_form();
            break;

        case 'traffic':
            $show_traffic = true;
            break;

        case 'user_top':
            $show_top = true;
            break;

        case 'live':
            $show_live = true;
            break;

        default:
            $show_traffic = true;
            break;
    }

    $xtpl->sbar_add(_("Routable addresses"), '?page=networking&action=ip_addresses');
    $xtpl->sbar_add(_("Host addresses"), '?page=networking&action=host_ip_addresses');
    $xtpl->sbar_add(_("List monthly traffic"), '?page=networking&action=traffic');
    $xtpl->sbar_add(_("Live monitor"), '?page=networking&action=live');

    if (isAdmin()) {
        $xtpl->sbar_add(_("User top"), '?page=networking&action=user_top');
    }

    $xtpl->sbar_out(_('Networking'));

    if ($show_traffic) {
        $xtpl->title(_("Monthly traffic"));

        $xtpl->table_title(_('Filters'));
        $xtpl->form_create('', 'get', 'networking-filter', false);

        $xtpl->table_td(
            _("Limit") . ':' .
            '<input type="hidden" name="page" value="networking">' .
            '<input type="hidden" name="action" value="list">'
        );
        $xtpl->form_add_input_pure('text', '40', 'limit', get_val('limit', '25'), '');
        $xtpl->table_tr();

        $xtpl->form_add_select(_("Year") . ':', 'year', year_list(), get_val('year', date("Y")));
        $xtpl->form_add_select(_("Month") . ':', 'month', month_list(), get_val('month', date("n")));

        $xtpl->form_add_select(
            _("Environment") . ':',
            'environment',
            resource_list_to_options(
                $api->environment->list(['has_hypervisor' => true])
            ),
            get_val('environment')
        );
        $xtpl->form_add_select(
            _("Location") . ':',
            'location',
            resource_list_to_options(
                $api->location->list(['has_hypervisor' => true])
            ),
            get_val('location')
        );
        $xtpl->form_add_select(
            _("Node") . ':',
            'node',
            resource_list_to_options($api->node->list(), 'id', 'domain_name'),
            get_val('node')
        );
        $xtpl->form_add_input(_("VPS") . ':', 'text', '30', 'vps', get_val('vps'));

        if (isAdmin()) {
            $xtpl->form_add_input(_("User") . ':', 'text', '30', 'user', get_val('user'));
        }

        $xtpl->form_out(_('Show'));

        if (($_GET['action'] ?? '') != 'list') {
            return;
        }

        $xtpl->table_title(_("Statistics"));

        $params = [
            'offset' => get_val('offset', 0),
            'limit' => get_val('limit', 25),
            'order' => 'descending',
            'meta' => ['includes' => 'network_interface__vps__user'],
        ];

        $conds = [
            'year', 'month', 'vps', 'node', 'location', 'environment',
        ];

        if (isAdmin()) {
            if ($_GET['user']) {
                $params['user'] =  $_GET['user'];
            }
        }

        foreach ($conds as $c) {
            if ($_GET[$c]) {
                $params[$c] = $_GET[$c];
            }
        }

        $stats = $api->network_interface_accounting->list($params);

        if (isAdmin()) {
            $xtpl->table_add_category(_('User'));
        }

        $xtpl->table_add_category(_('VPS'));
        $xtpl->table_add_category(_('Interface'));
        $xtpl->table_add_category(_('Date'));
        $xtpl->table_add_category(_('Received'));
        $xtpl->table_add_category(_('Sent'));
        $xtpl->table_add_category(_('Total'));

        foreach ($stats as $stat) {
            if (isAdmin()) {
                $xtpl->table_td(user_link($stat->network_interface->vps->user));
            }

            $xtpl->table_td(vps_link($stat->network_interface->vps));
            $xtpl->table_td(h($stat->network_interface->name));
            $xtpl->table_td($stat->year . '/' . $stat->month);

            $xtpl->table_td(data_size_to_humanreadable($stat->bytes_in / 1024 / 1024), false, true);
            $xtpl->table_td(data_size_to_humanreadable($stat->bytes_out / 1024 / 1024), false, true);
            $xtpl->table_td(data_size_to_humanreadable(($stat->bytes_in + $stat->bytes_out) / 1024 / 1024), false, true);

            $xtpl->table_tr();
        }

        $xtpl->table_out();
    }

    if (isAdmin() && $show_top) {
        $xtpl->title(_("Top users"));

        $xtpl->table_title(_('Filters'));
        $xtpl->form_create('', 'get', 'networking-filter', false);

        $xtpl->table_td(
            _("Limit") . ':' .
            '<input type="hidden" name="page" value="networking">' .
            '<input type="hidden" name="action" value="user_top">' .
            '<input type="hidden" name="list" value="1">'
        );
        $xtpl->form_add_input_pure('text', '40', 'limit', get_val('limit', '25'), '');
        $xtpl->table_tr();

        $xtpl->form_add_select(_("Year") . ':', 'year', year_list(), get_val('year', date("Y")));
        $xtpl->form_add_select(_("Month") . ':', 'month', month_list(), get_val('month', date("n")));

        $xtpl->form_add_select(
            _("Environment") . ':',
            'environment',
            resource_list_to_options($api->environment->list()),
            get_val('environment')
        );
        $xtpl->form_add_select(
            _("Location") . ':',
            'location',
            resource_list_to_options($api->location->list()),
            get_val('location')
        );
        $xtpl->form_add_select(
            _("Node") . ':',
            'node',
            resource_list_to_options($api->node->list(), 'id', 'domain_name'),
            get_val('node')
        );

        $xtpl->form_out(_('Show'));

        if (!$_GET['list']) {
            return;
        }

        $xtpl->table_title(_("Statistics"));

        $params = [
            'offset' => get_val('offset', 0),
            'limit' => get_val('limit', 25),
            'meta' => ['includes' => 'user'],
        ];

        $conds = [
            'year', 'month', 'node', 'location', 'environment',
        ];

        foreach ($conds as $c) {
            if ($_GET[$c]) {
                $params[$c] = $_GET[$c];
            }
        }

        $stats = $api->network_interface_accounting->user_top($params);

        $xtpl->table_add_category(_('User'));
        $xtpl->table_add_category(_('Date'));
        $xtpl->table_add_category(_('In'));
        $xtpl->table_add_category(_('Out'));
        $xtpl->table_add_category(_('Total'));

        foreach ($stats as $stat) {
            $xtpl->table_td(
                '<a href="?page=networking&action=list&user=' . $stat->user_id . '&year=' . $_GET['year'] . '&month=' . $_GET['month'] . '">' .
                $stat->user->login .
                '</a>'
            );

            $xtpl->table_td($stat->year . '/' . $stat->month);

            $xtpl->table_td(data_size_to_humanreadable($stat->bytes_in / 1024 / 1024), false, true);
            $xtpl->table_td(data_size_to_humanreadable($stat->bytes_out / 1024 / 1024), false, true);
            $xtpl->table_td(data_size_to_humanreadable(($stat->bytes_in + $stat->bytes_out) / 1024 / 1024), false, true);

            $xtpl->table_tr();
        }

        $xtpl->table_out();
    }


    if ($show_live) {
        $xtpl->title(_('Live monitor'));

        $xtpl->form_create('?page=adminm&section=members&action=approval_requests', 'get');

        $xtpl->table_td(
            _("Limit") . ':' .
            '<input type="hidden" name="page" value="networking">' .
            '<input type="hidden" name="action" value="live">'
        );
        $xtpl->form_add_input_pure('text', '30', 'limit', get_val('limit', 25));
        $xtpl->table_tr();

        $xtpl->form_add_select(
            _("Environment") . ':',
            'environment',
            resource_list_to_options($api->environment->list()),
            get_val('environment')
        );
        $xtpl->form_add_select(
            _("Location") . ':',
            'location',
            resource_list_to_options($api->location->list()),
            get_val('location')
        );
        $xtpl->form_add_select(
            _("Node") . ':',
            'node',
            resource_list_to_options($api->node->list(), 'id', 'domain_name'),
            get_val('node')
        );

        $xtpl->form_add_input(_("VPS ID") . ':', 'text', '30', 'vps', get_val('vps'));

        if(isAdmin()) {
            $xtpl->form_add_input(_("User ID") . ':', 'text', '30', 'user', get_val('user'));
        }

        $xtpl->form_add_checkbox(
            _('Refresh automatically') . ':',
            'refresh',
            '1',
            true,
            _('10 second interval')
        );

        $xtpl->table_td(_('Last update') . ':');
        $xtpl->table_td(
            '
		<span id="monitor-last-update">
			' . date('Y-m-d H:i:s') . '
			<noscript>
				JavaScript needs to be enabled for automated refreshing to work.
			</noscript>
		</span>'
        );
        $xtpl->table_tr();

        $xtpl->form_out(_("Show"), 'monitor-filters');

        $params = [
            'limit' => get_val('limit', 25),
            'meta' => ['includes' => 'network_interface__vps__node'],
        ];

        $conds = [
            'vps', 'node', 'location', 'environment', 'user',
        ];

        foreach ($conds as $c) {
            if ($_GET[$c]) {
                $params[$c] = $_GET[$c];
            }
        }

        $monitors = $api->network_interface_monitor->list($params);

        $xtpl->table_td(_('VPS'), '#5EAFFF; color:#FFF; font-weight:bold;', false, '1', '2');
        $xtpl->table_td(_('Node'), '#5EAFFF; color:#FFF; font-weight:bold;', false, '1', '2');
        $xtpl->table_td(_('Interface'), '#5EAFFF; color:#FFF; font-weight:bold;', false, '1', '2');

        $xtpl->table_td(_('Receiving'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;', false, '2');
        $xtpl->table_td(_('Transmitting'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;', false, '2');
        $xtpl->table_td(_('Total'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;', false, '2');
        $xtpl->table_tr();

        $xtpl->table_td(_('bps'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;');
        $xtpl->table_td(_('Packets/s'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;');

        $xtpl->table_td(_('bps'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;');
        $xtpl->table_td(_('Packets/s'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;');

        $xtpl->table_td(_('bps'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;');
        $xtpl->table_td(_('Packets/s'), '#5EAFFF; color:#FFF; font-weight:bold; text-align:center;');

        $xtpl->table_tr();

        $xtpl->assign(
            'AJAX_SCRIPT',
            $xtpl->vars['AJAX_SCRIPT'] . '
		<script type="text/javascript" src="js/network-monitor.js"></script>'
        );

        foreach ($monitors as $data) {
            $xtpl->table_td(vps_link($data->network_interface->vps));
            $xtpl->table_td(node_link($data->network_interface->vps->node));
            $xtpl->table_td(h($data->network_interface->name));

            foreach (['in', 'out'] as $dir) {
                $xtpl->table_td(format_data_rate(($data->{"bytes_${dir}"} / $data->delta) * 8, ''), false, true);

                $xtpl->table_td(format_number_with_unit($data->{"packets_${dir}"} / $data->delta), false, true);
            }

            $xtpl->table_td(format_data_rate((($data->bytes_in + $data->bytes_out) / $data->delta) * 8, ''), false, true);

            $xtpl->table_td(format_number_with_unit(($data->packets_in + $data->packets_out) / $data->delta), false, true);

            $xtpl->table_tr();
        }

        $xtpl->table_out('live_monitor');
    }

} else {
    $xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
}
