<?php
/*
    ./pages/page_adminvps.php

    vpsAdmin
    Web-admin interface for OpenVZ (see http://openvz.org)
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

function print_editvps($vps) {
}

function vps_run_redirect_path($veid) {
	$current_url = "http".(isset($_SERVER["HTTPS"]) ? "s" : "")."://$_SERVER[HTTP_HOST]$_SERVER[REQUEST_URI]";

	if($_SERVER["HTTP_REFERER"] && $_SERVER["HTTP_REFERER"] != $current_url)
		return $_SERVER["HTTP_REFERER"];

	elseif($_GET["action"] == "info")
		return '?page=adminvps&action=info&veid='.$veid;

	else
		return '?page=adminvps';
}

if (isset($_SESSION["logged_in"]) && $_SESSION["logged_in"]) {

$_GET["run"] = isset($_GET["run"]) ? $_GET["run"] : false;

if ($_GET["run"] == 'stop') {
	csrf_check();

	try {
		$api->vps->stop($_GET["veid"]);

		notify_user(_("Stop VPS")." {$_GET["veid"]} "._("planned"));
		redirect(vps_run_redirect_path($_GET["veid"]));

	} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
		$xtpl->perex_format_errors(_('Unable to stop'), $e->getResponse());

		if ($_GET['action'] == 'info')
			$show_info = true;
	}
}

if ($_GET["run"] == 'start') {
	csrf_check();

	try {
		$api->vps->start($_GET["veid"]);

		notify_user(_("Start of")." {$_GET["veid"]} "._("planned"));
		redirect(vps_run_redirect_path($_GET["veid"]));

	} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
		$xtpl->perex_format_errors(_('Unable to start'), $e->getResponse());

		if ($_GET['action'] == 'info')
			$show_info = true;
	}
}

if ($_GET["run"] == 'restart') {
	csrf_check();

	try {
		$api->vps->restart($_GET["veid"]);

		notify_user(_("Restart of")." {$_GET["veid"]} "._("planned"), '');
		redirect(vps_run_redirect_path($_GET["veid"]));

	} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
		$xtpl->perex_format_errors(_('Unable to restart'), $e->getResponse());

		if ($_GET['action'] == 'info')
			$show_info = true;
	}
}

$_GET["action"] = isset($_GET["action"]) ? $_GET["action"] : false;

switch ($_GET["action"]) {
		case 'list':
			$list_vps = true;
			break;

		case 'new-step-0':
			print_newvps_page0();
			break;

		case 'new-step-1':
			print_newvps_page1($_GET['user']);
			break;

		case 'new-step-2':
			print_newvps_page2($_GET['user'], $_GET['platform']);
			break;

		case 'new-step-3':
			print_newvps_page3(
				$_GET['user'],
				$_GET['platform'],
				$_GET['location']
			);
			break;

		case 'new-step-4':
			print_newvps_page4(
				$_GET['user'],
				$_GET['platform'],
				$_GET['location'],
				$_GET['os_template']
			);
			break;

		case 'new-step-5':
			print_newvps_page5(
				$_GET['user'],
				$_GET['platform'],
				$_GET['location'],
				$_GET['os_template']
			);
			break;

		case 'new-submit':
			if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
				print_newvps_page5(
					$_GET['user'],
					$_GET['platform'],
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
				'memory' => (int)$_GET['memory'],
				'swap' => (int)$_GET['swap'],
				'cpu' => (int)$_GET['cpu'],
				'diskspace' => (int)$_GET['diskspace'],
				'ipv4' => (int)$_GET['ipv4'],
				'ipv4_private' => (int)$_GET['ipv4_private'],
				'ipv6' => (int)$_GET['ipv6'],
			];

			if (isAdmin()) {
				$params['user'] = $_GET['user'];
				$params['node'] = $_POST['node'];
				$params['onboot'] = isset($_POST['boot_after_create']);

			} else {
				if ($_GET['location'])
					$params['location'] = (int)$_GET['location'];
				if ($_POST['user_namespace_map'])
					$params['user_namespace_map'] = $_POST['user_namespace_map'];
			}

			try {
				$vps = $api->vps->create($params);

				if ($params['onboot'] || !isAdmin()) {
					notify_user(
						_("VPS create ").' '.$vps->id,
						_("VPS will be created and booted afterwards.")
					);

				} else {
					notify_user(
						_("VPS create ").' '.$vps->id,
						_("VPS will be created. You can start it manually.")
					);
				}

				redirect('?page=adminvps&action=info&veid='.$vps->id);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('VPS creation failed'), $e->getResponse());
				print_newvps_page5(
					$_GET['user'],
					$_GET['platform'],
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
					'lazy' => $_POST['lazy_delete'] ? true : false
				]);

				notify_user(
					_('Delete VPS').' #'.$_GET['veid'],
					_('Deletion of VPS')." {$_GET['veid']} ".strtolower(_('planned'))
				);
				redirect('?page=adminvps');
			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('VPS deletion failed'), $e->getResponse());
				vps_delete_form($_GET['veid']);
			}
			break;

		case 'info':
			$show_info=true;
			break;
		case 'passwd':
			try {
				csrf_check();
				$ret = $api->vps->passwd($_GET["veid"], array(
					'type' => $_POST['password_type'] == 'simple' ? 'simple' : 'secure'
				));

				if (!$_SESSION['vps_password'])
					$_SESSION['vps_password'] = array();

				$_SESSION["vps_password"][(int) $_GET['veid']] = $ret['password'];

				notify_user(
					_("Change of root password planned"),
					_("New password is: ")."<b>".$ret['password']."</b>"
				);
				redirect('?page=adminvps&action=info&veid='.$_GET["veid"]);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Change of the password failed'), $e->getResponse());
				$show_info=true;
			}
			break;

		case 'pubkey':
			try {
				csrf_check();

				$ret = $api->vps->deploy_public_key($_GET["veid"], array(
					'public_key' => $_POST['public_key'],
				));

				notify_user(_("Public key deployment planned"), '');
				redirect('?page=adminvps&action=info&veid='.$_GET["veid"]);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Public key deployment failed'), $e->getResponse());
				$show_info=true;
			}

			break;

		case 'hostname':
			try {
				csrf_check();

				$params = array();

				if ($_POST['manage_hostname'] == 'manual')
					$params['manage_hostname'] = false;
				else
					$params['hostname'] = $_POST['hostname'];

				$api->vps->update($_GET['veid'], $params);

				notify_user(_("Hostname change planned"), '');
				redirect('?page=adminvps&action=info&veid='.$_GET['veid']);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				 {}$show_info=true;
			}
			break;
		case 'configs':
			if (isAdmin() && isset($_REQUEST["veid"]) && (isset($_POST["configs"]) || isset($_POST["add_config"]))) {
				csrf_check();
				$raw_order = explode('&', $_POST['configs_order']);
				$cfgs = array();
				$i = 0;

				foreach($raw_order as $item) {
					$item = explode('=', $item);

					if (!$item[1])
						continue;
					elseif (!strncmp($item[1], "add_config", strlen("add_config")))
						$cfgs[] = $_POST['add_config'][$i++];
					else {
						$order = explode('_', $item[1]);
						$cfgs[] = $order[1];
					}
				}

				$params = array();

				if ($cfgs) {
					// configs were changed with javascript dnd
					foreach ($cfgs as $cfg) {
						if (!$cfg)
							continue;

						$params[] = array('vps_config' => $cfg);
					}

				} else {
					foreach ($_POST['configs'] as $cfg) {
						if (!$cfg)
							continue;

						$params[] = array('vps_config' => $cfg);
					}

					foreach ($_POST['add_config'] as $cfg) {
						if (!$cfg)
							continue;

						$params[] = array('vps_config' => $cfg);
					}
				}

				$api->vps($_GET['veid'])->config->replace($params);

				if($_POST["reason"])
					$vps->configs_change_notify($_POST["reason"]);

				redirect('?page=adminvps&action=info&veid='.$_GET['veid']);

			} else {
				$xtpl->perex(_("Error"), 'Error, contact your administrator');
				$show_info=true;
			}
			break;

		case 'custom_config':
			if (isAdmin()) {
				csrf_check();

				try {
					$api->vps->update($_GET['veid'], array('config' => $_POST['custom_config']));

					notify_user(_("Config changed"), '');
					redirect('?page=adminvps&action=info&veid='.$_GET['veid']);

				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('Change of the config failed'), $e->getResponse());
					$show_info=true;
				}
			}
			break;

		case 'resources':
			if (isset($_POST['memory'])) {
				csrf_check();

				try {
					$vps_resources = array('memory', 'cpu', 'cpu_limit', 'swap');
					$params = array();

					foreach ($vps_resources as $r) {
						if (isset($_POST[$r]))
							$params[ $r ] = $_POST[$r];
					}

					if (isAdmin()) {
						if ($_POST['change_reason'])
							$params['change_reason'] = $_POST['change_reason'];

						if ($_POST['admin_override'])
							$params['admin_override'] = $_POST['admin_override'];

						$params['admin_lock_type'] = $_POST['admin_lock_type'];
					}

					$api->vps($_GET['veid'])->update($params);

					notify_user(_("Resources changed"), '');
					redirect('?page=adminvps&action=info&veid='.$_GET['veid']);

				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('Resource change failed'), $e->getResponse());
					$show_info=true;
				}
			} else {
				$xtpl->perex(_("Error"), 'Error, contact your administrator');
				$show_info=true;
			}

			break;

		case 'chown':
			$vps = $api->vps->find($_GET['veid']);

			if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
				vps_owner_form($vps);
				break;
			}

			try {
				csrf_check();
				$api->vps->update($_GET['veid'], array('user' => $_POST['m_id']));

				notify_user(_("Owner changed"), '');
				redirect('?page=adminvps&action=info&veid='.$_GET['veid']);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Change of the owner failed'), $e->getResponse());
				vps_owner_form($vps);
			}

			break;

		case 'netif':
			try {
				csrf_check();

				if ($_POST['name']) {
					$api->network_interface($_GET['id'])->update([
						'name' => trim($_POST['name']),
					]);
				}

				notify_user(_('Interface renamed'), '');
				redirect('?page=adminvps&action=info&veid='.$_GET['veid']);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Failed to set interface name'), $e->getResponse());
				$show_info=true;
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

				redirect('?page=adminvps&action=info&veid='.$_GET['veid']);

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
				redirect('?page=adminvps&action=info&veid='.$_GET['veid']);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Failed to remove IP address'), $e->getResponse());
				$show_info=true;
			}
			break;

		case 'hostaddr_add':
			try {
				csrf_check();

				if($_POST['hostaddr_public_v4']) {
					$api->host_ip_address->assign($_POST['hostaddr_public_v4']);
					notify_user(_("Addition of IP address planned"), '');

				} else if($_POST['hostaddr_private_v4']) {
					$api->host_ip_address->assign($_POST['hostaddr_private_v4']);
					notify_user(_("Addition of private IP address planned"), '');

				} else if($_POST['hostaddr_public_v6']) {
					$api->host_ip_address->assign($_POST['hostaddr_public_v6']);
					notify_user(_("Addition of IP address planned"), '');

				} else {
					notify_user(_("Error"), 'Contact your administrator');
				}

				redirect('?page=adminvps&action=info&veid='.$_GET['veid']);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Failed to add IP address'), $e->getResponse());
				$show_info=true;
			}
			break;

		case 'hostaddr_del':
			try {
				csrf_check();
				$api->host_ip_address($_GET['id'])->free();

				notify_user(_("Deletion of IP address planned"), '');
				redirect('?page=adminvps&action=info&veid='.$_GET['veid']);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Failed to remove IP address'), $e->getResponse());
				$show_info=true;
			}
			break;

		case 'ipjoined_add':
			try {
				csrf_check();

				if($_POST['iproute_public_v4']) {
					$api->ip_address->assign_with_host_address($_POST['iproute_public_v4'], [
						'network_interface' => $_GET['netif'],
					]);
					notify_user(_("Addition of IP address planned"), '');

				} else if($_POST['iproute_private_v4']) {
					$api->ip_address->assign_with_host_address($_POST['iproute_private_v4'], [
						'network_interface' => $_GET['netif'],
					]);
					notify_user(_("Addition of private IP address planned"), '');

				} else if($_POST['iproute_public_v6']) {
					$api->ip_address->assign_with_host_address($_POST['iproute_public_v6'], [
						'network_interface' => $_GET['netif'],
					]);
					notify_user(_("Addition of IP address planned"), '');

				} else {
					notify_user(_("Error"), 'Contact your administrator');
				}

				redirect('?page=adminvps&action=info&veid='.$_GET['veid']);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Failed to add IP address'), $e->getResponse());
				$show_info=true;
			}
			break;

		case 'nameserver':
			try {
				csrf_check();
				$api->vps->update($_GET['veid'], array('dns_resolver' => $_POST['nameserver']));

				notify_user(_("DNS change planned"), '');
				redirect('?page=adminvps&action=info&veid='.$_GET['veid']);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('DNS resolver change failed'), $e->getResponse());
				$show_info=true;
			}
			break;

		case 'offlinemigrate':
			$vps = $api->vps->find($_GET['veid']);

			if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
				vps_migrate_form($vps);
				break;
			}

			csrf_check();

			try {
				$vps->migrate(array(
					'node' => $_POST['node'],
					'replace_ip_addresses' => isset($_POST['replace_ip_addresses']),
					'transfer_ip_addresses' => isset($_POST['transfer_ip_addresses']),
					'maintenance_window' => isset($_POST['maintenance_window']),
					'cleanup_data' => isset($_POST['cleanup_data']),
					'send_mail' => isset($_POST['send_mail']),
					'reason' => $_POST['reason'] ? $_POST['reason'] : null,
				));

				notify_user(_("Offline migration planned"), '');
				redirect('?page=adminvps&action=info&veid='.$_GET['veid']);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Offline migration failed'), $e->getResponse());
				vps_migrate_form($vps);
			}

			break;

		case 'reinstall':
			if (isset($_POST['reinstall']) && $_POST['confirm']) {
				csrf_check();

				try {
					$api->vps($_GET['veid'])->reinstall(array(
						'os_template' => $_POST['os_template'],
					));

					notify_user(
						_("Reinstallation of VPS")." {$_GET["veid"]} "._("planned"),
						_("You will have to reset your <b>root</b> password."));
					redirect('?page=adminvps&action=info&veid='.$_GET["veid"]);

				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('Reinstall failed'), $e->getResponse());
					$show_info=true;
				}

			} elseif ($_POST['reinstall_action'] === '1') {
				csrf_check();

				try {
					$api->vps($_GET['veid'])->update(array(
						'os_template' => $_POST['os_template']
					));

					notify_user(_("Distribution information updated"), '');
					redirect('?page=adminvps&action=info&veid='.$_GET["veid"]);

				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('Failed to update distribution'), $e->getResponse());
					$show_info=true;
				}
			} elseif (isset($_POST['cancel'])) {
				redirect('?page=adminvps&action=info&veid='.$_GET["veid"]);

			} else {
				$vps = $api->vps->show($_GET['veid']);
				$new_tpl = $api->os_template->show(get_val('os_template', $_POST['os_template']));

				$xtpl->table_title(
					_('Confirm reinstallation of VPS').' #'.$vps->id.
					' '.$vps->hostname
				);
				$xtpl->form_create('?page=adminvps&action=reinstall&veid='.$vps->id);

				$xtpl->table_td(
					'<strong>'.
					_('All data from this VPS will be deleted, including all subdatasets.').
					'</strong>'.
					'<input type="hidden" name="os_template" value="'.$_POST['os_template'].'">',
					false, false, 2
				);
				$xtpl->table_tr();

				$xtpl->table_td(_('ID').':');
				$xtpl->table_td($vps->id);
				$xtpl->table_tr();

				$xtpl->table_td(_('Hostname').':');
				$xtpl->table_td($vps->hostname);
				$xtpl->table_tr();

				$xtpl->table_td(_('Current OS template').':');
				$xtpl->table_td($vps->os_template->label);
				$xtpl->table_tr();

				$xtpl->table_td(_('New OS template').':');
				$xtpl->table_td($new_tpl->label);
				$xtpl->table_tr();

				$xtpl->form_add_checkbox(_('Confirm').':', 'confirm', '1', false);

				$xtpl->table_td('');
				$xtpl->table_td(
					$xtpl->html_submit(_('Cancel'), 'cancel').
					$xtpl->html_submit(_('Reinstall'), 'reinstall')
				);
				$xtpl->table_tr();

				$xtpl->form_out_raw();
			}
			break;

		case 'features':
			if (isset($_GET["veid"]) && $_SERVER['REQUEST_METHOD'] === 'POST') {
				csrf_check();
				try {
					$resource = $api->vps($_GET['veid'])->feature;
					$features = $resource->list();
					$params = array();

					foreach ($features as $f)
						$params[$f->name] = isset($_POST[$f->name]);

					$resource->update_all($params);

					notify_user(_("Features set"), _('Features will be set momentarily.'));
					redirect('?page=adminvps&action=info&veid='.$_GET['veid']);

				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('Feature set failed'), $e->getResponse());
					$show_info=true;
				}
			}
			break;

		case 'maintenance_windows':
			csrf_check();

			try {
				$maint = $api->vps($_GET['veid'])->maintenance_window;

				if ($_POST['unified']) {
					$maint->update_all(array(
						'is_open' => true,
						'opens_at' => $_POST['unified_opens_at'] * 60,
						'closes_at' => $_POST['unified_closes_at'] * 60,
					));

				} else {
					for ($i = 0 ; $i < 7; $i++) {
						$maint->update($i, array(
							'is_open' => array_search("$i", $_POST['is_open']) !== false,
							'opens_at' => $_POST['opens_at'][$i] * 60,
							'closes_at' => $_POST['closes_at'][$i] * 60,
						));
					}
				}

				notify_user(_("Maintenance windows set"), '');
				redirect('?page=adminvps&action=info&veid='.$_GET['veid']);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(
					_('Maintenance window configuration failed'),
					$e->getResponse()
				);
				$show_info=true;
			}
			break;

		case 'clone-step-0':
			vps_clone_form_step0($_GET['veid']);
			break;

		case 'clone-step-1':
			vps_clone_form_step1($_GET['veid'], $_GET['user']);
			break;

		case 'clone-step-2':
			vps_clone_form_step2($_GET['veid'], $_GET['user'], $_GET['platform']);
			break;

		case 'clone-step-3':
			vps_clone_form_step3($_GET['veid'], $_GET['user'], $_GET['platform'], $_GET['location']);
			break;

		case 'clone-submit':
			if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
				vps_clone_form_step3(
					$_GET['veid'],
					$_GET['user'],
					$_GET['platform'],
					$_GET['location']
				);
				break;
			}

			csrf_check();

			$vps = $api->vps->find($_GET['veid']);
			$params = [
				'hostname' => $_POST['hostname'],
				'platform' => $_GET['platform'],
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
				if ($_GET['location'])
					$params['location'] = (int)$_GET['location'];
			}

			try {
				$cloned = $vps->clone($params);

				notify_user(_("Clone in progress"), '');
				redirect('?page=adminvps&action=info&veid='.$cloned->id);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('VPS cloning failed'), $e->getResponse());
				vps_clone_form_step3(
					$_GET['veid'],
					$_GET['user'],
					$_GET['platform'],
					$_GET['location']
				);
			}
			break;

		case 'swap_preview':
			$vps = $api->vps->find($_GET['veid']);

			try {
				$params = array('meta' => array('includes' => 'node'));

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

			if (isset($_POST['cancel']))
				redirect('?page=adminvps&action=info&veid='.$_GET['veid']);

			csrf_check();

			try {
				$vps->swap_with(
					client_params_to_api($api->vps->swap_with)
				);

				notify_user(_('Swap in progress'), '');
				redirect('?page=adminvps&action=info&veid='.$_GET['veid']);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Swap failed'), $e->getResponse());
				vps_swap_form($vps);
			}

			break;

		default:
			$list_vps = true;
			break;
	}

if ($list_vps) {
	if (isAdmin())
		$xtpl->title(_("VPS list").' '._("[Admin mode]"));
	else
		$xtpl->title(_("VPS list").' '._("[User mode]"));

	if (isAdmin()) {
		$xtpl->table_title(_('Filters'));
		$xtpl->form_create('', 'get', 'vps-filter', false);

		$xtpl->table_td(_("Limit").':'.
			'<input type="hidden" name="page" value="adminvps">'.
			'<input type="hidden" name="action" value="list">'
		);
		$xtpl->form_add_input_pure('text', '40', 'limit', get_val('limit', '25'), '');
		$xtpl->table_tr();

		$xtpl->form_add_input(_("Offset").':', 'text', '40', 'offset', get_val('offset', '0'), '');
		$xtpl->form_add_input(_("User ID").':', 'text', '40', 'user', get_val('user'));
		$xtpl->form_add_select(_("Node").':', 'node',
			resource_list_to_options($api->node->list(), 'id', 'domain_name'), get_val('node'));
		$xtpl->form_add_select(_("Location").':', 'location',
			resource_list_to_options($api->location->list()), get_val('location'));
		$xtpl->form_add_select(_("Environment").':', 'environment',
			resource_list_to_options($api->environment->list()), get_val('environment'));

		$p = $api->vps->index->getParameters('input')->object_state;
		api_param_to_form('object_state', $p, $_GET['object_state']);

		$xtpl->form_out(_('Show'));
	}

	if (!isAdmin() || $_GET['action'] == 'list') {
		$xtpl->table_add_category('ID');
		$xtpl->table_add_category('HW');
		$xtpl->table_add_category(_("OWNER"));
		$xtpl->table_add_category(_("#PROC"));
		$xtpl->table_add_category(_("HOSTNAME"));
		$xtpl->table_add_category(_("USED RAM"));
		$xtpl->table_add_category(_("USED HDD"));
		$xtpl->table_add_category('');
		$xtpl->table_add_category('');
		$xtpl->table_add_category('');
		$xtpl->table_add_category('');

		if (!isAdmin()) {
			$envs_destroy = array();

			foreach ($api->user($_SESSION['user']['id'])->environment_config->list() as $env) {
				$envs_destroy[$env->environment_id] = $env->can_destroy_vps;
			}
		}

		if (isAdmin()) {
			$params = array(
				'limit' => get_val('limit', 25),
				'offset' => get_val('offset', 0),
				'meta' => array('count' => true, 'includes' => 'user,node')
			);

			if ($_GET['user'])
				$params['user'] = $_GET['user'];

			if ($_GET['node'])
				$params['node'] = $_GET['node'];

			if ($_GET['location'])
				$params['location'] = $_GET['location'];

			if ($_GET['environment'])
				$params['environment'] = $_GET['environment'];

			if ($_GET['object_state'])
				$params['object_state'] = $_GET['object_state'];

			$vpses = $api->vps->list($params);

		} else {
			$vpses = $api->vps->list(array('meta' => array('count' => true, 'includes' => 'user,node')));
		}

		foreach ($vpses as $vps) {

			$xtpl->table_td('<a href="?page=adminvps&action=info&veid='.$vps->id.'">'.$vps->id.'</a>');
			$xtpl->table_td('<a href="?page=adminvps&action=list&node='.$vps->node_id.'">'. $vps->node->domain_name . '</a>');
			$xtpl->table_td('<a href="?page=adminm&section=members&action=edit&id='.$vps->user_id.'">'.$vps->user->login.'</a>');
			$xtpl->table_td($vps->process_count, false, true);
			$xtpl->table_td('<a href="?page=adminvps&action=info&veid='.$vps->id.'"><img src="template/icons/vps_edit.png"  title="'._("Edit").'"/> '.h($vps->hostname).'</a>');
			$xtpl->table_td(sprintf('%4d MB',$vps->used_memory), false, true);

			if ($vps->used_diskspace > 0)
				$xtpl->table_td(sprintf('%.2f GB',round($vps->used_diskspace/1024, 2)), false, true);
			else $xtpl->table_td('---', false, true);

			if(isAdmin() || $vps->maintenance_lock == 'no') {
				$xtpl->table_td(($vps->is_running) ? '<a href="?page=adminvps&run=restart&veid='.$vps->id.'&t='.csrf_token().'"><img src="template/icons/vps_restart.png" title="'._("Restart").'"/></a>' : '<img src="template/icons/vps_restart_grey.png"  title="'._("Unable to restart").'" />');
				$xtpl->table_td(($vps->is_running) ? '<a href="?page=adminvps&run=stop&veid='.$vps->id.'&t='.csrf_token().'"><img src="template/icons/vps_stop.png"  title="'._("Stop").'"/></a>' : '<a href="?page=adminvps&run=start&veid='.$vps->id.'&t='.csrf_token().'"><img src="template/icons/vps_start.png"  title="'._("Start").'"/></a>');

				if (!isAdmin())
					$xtpl->table_td('<a href="?page=console&veid='.$vps->id.'&t='.csrf_token().'"><img src="template/icons/console.png"  title="'._("Remote Console").'"/></a>');

				if (isAdmin())
					$xtpl->table_td(maintenance_lock_icon('vps', $vps));

				$deleteAction = function () use ($xtpl, $vps) {
					$xtpl->table_td('<a href="?page=adminvps&action=delete&veid='.$vps->id.'"><img src="template/icons/vps_delete.png" title="'._("Delete").'"/></a>');
				};

				$cantDelete = function ($reason) use ($xtpl) {
					$xtpl->table_td('<img src="template/icons/vps_delete_grey.png" title="'.$reason.'"/>');
				};

				if (isAdmin()) {
					$deleteAction();
				} elseif ($envs_destroy[$vps->node->location->environment_id]) {
					if ($vps->is_running)
						$cantDelete(_('Stop the VPS to be able to delete it'));
					else
						$deleteAction();
				} else {
					$cantDelete(_('Environment configuration does not allow VPS deletion'));
				}

			} else {
				$xtpl->table_td('');
				$xtpl->table_td('');
				$xtpl->table_td('');
				$xtpl->table_td('');
			}

			$color = '#FFCCCC';

	// 		if($vps->ve["vps_deleted"]) // FIXME
	// 			$color = '#A6A6A6';
			if($vps->is_running)
				$color = false;

			$xtpl->table_tr($color);

		}

		$xtpl->table_out();

		if (isAdmin()) {
			$xtpl->table_add_category(_("Total number of VPS").':');
			$xtpl->table_add_category($vpses->getTotalCount());
			$xtpl->table_out();

		}
	}

	if (!isAdmin()) {
		$xtpl->sbar_add('<img src="template/icons/m_add.png"  title="'._("New VPS").'" /> '._("New VPS"), '?page=adminvps&section=vps&action=new-step-1');
	}
}

if(isAdmin() && $list_vps) {
	$xtpl->sbar_add('<img src="template/icons/m_add.png"  title="'._("New VPS").'" /> '._("New VPS"), '?page=adminvps&section=vps&action=new-step-0');
	$xtpl->sbar_add('<img src="template/icons/vps_ip_list.png"  title="'._("List VPSes").'" /> '._("List VPSes"), '?page=adminvps&action=list');
}

if (isset($show_info) && $show_info) {
	if (!isset($veid))
		$veid = $_GET["veid"];

	$vps = $api->vps->find($veid, array('meta' => array('includes' => 'node__location__environment,user,os_template')));

	vps_details_suite($vps);

	if (isAdmin())
		$xtpl->sbar_add(_('State log'), '?page=lifetimes&action=changelog&resource=vps&id='.$vps->id.'&return='. urlencode($_SERVER['REQUEST_URI']));

	$xtpl->table_td('ID:');
	$xtpl->table_td($vps->id);
	$xtpl->table_tr();

	$xtpl->table_td(_("Node").':');
	$xtpl->table_td($vps->node->domain_name);
	$xtpl->table_tr();

	$xtpl->table_td(_("Location").':');
	$xtpl->table_td($vps->node->location->label);
	$xtpl->table_tr();

	$xtpl->table_td(_("Environment").':');
	$xtpl->table_td($vps->node->location->environment->label);
	$xtpl->table_tr();

	$xtpl->table_td(_("Platform").':');
	$xtpl->table_td(hypervisorTypeToLabel($vps->node->hypervisor_type));
	$xtpl->table_tr();

	$xtpl->table_td(_("Owner").':');
	$xtpl->table_td('<a href="?page=adminm&section=members&action=edit&id='.$vps->user_id.'">'.$vps->user->login.'</a>');
	$xtpl->table_tr();

	$xtpl->table_td(_('Created at').':');
	$xtpl->table_td(tolocaltz($vps->created_at));
	$xtpl->table_tr();

	$xtpl->table_td(_("State").':');
	$xtpl->table_td($vps->object_state);
	$xtpl->table_tr();

	if ($vps->expiration_date) {
		$xtpl->table_td(_("Expiration").':');
		$xtpl->table_td(tolocaltz($vps->expiration_date));
		$xtpl->table_tr();
	}

	$xtpl->table_td(_("Distribution").':');
	$xtpl->table_td($vps->os_template->label);
	$xtpl->table_tr();

	$xtpl->table_td(_("Status").':');

	if($vps->maintenance_lock == 'no') {
		$xtpl->table_td(
			(($vps->is_running) ?
				_("running").' (<a href="?page=adminvps&action=info&run=restart&veid='.$vps->id.'&t='.csrf_token().'">'._("restart").'</a>, <a href="?page=adminvps&action=info&run=stop&veid='.$vps->id.'&t='.csrf_token().'">'._("stop").'</a>'
				:
				_("stopped").' (<a href="?page=adminvps&action=info&run=start&veid='.$vps->id.'&t='.csrf_token().'">'._("start").'</a>') .
				', <a href="?page=console&veid='.$vps->id.'&t='.csrf_token().'">'._("open remote console").'</a>)'
		);
	} else {
		$xtpl->table_td($vps->is_running ? _("running") : _("stopped"));
	}

	$xtpl->table_tr();

	$xtpl->table_td(_("Hostname").':');
	$xtpl->table_td(h($vps->hostname));
	$xtpl->table_tr();

	$xtpl->table_td(_("Uptime").':');
	$xtpl->table_td($vps->is_running ? format_duration($vps->uptime) : '-');
	$xtpl->table_tr();

	$xtpl->table_td(_("Load average").':');
	$xtpl->table_td($vps->is_running ? $vps->loadavg : '-');
	$xtpl->table_tr();

	$xtpl->table_td(_("Processes").':');
	$xtpl->table_td($vps->is_running ? $vps->process_count : '-');
	$xtpl->table_tr();

	$xtpl->table_td(_("CPU").':');
	$xtpl->table_td($vps->is_running ? sprintf('%.2f %%', 100.0 - $vps->cpu_idle) : '-');
	$xtpl->table_tr();

	$xtpl->table_td(_("RAM").':');
	$xtpl->table_td($vps->is_running ? sprintf('%4d MB', $vps->used_memory) : '-');
	$xtpl->table_tr();

	if ($vps->used_swap) {
		$xtpl->table_td(_("Swap").':');
		$xtpl->table_td(sprintf('%4d MB', $vps->used_swap));
		$xtpl->table_tr();
	}

	$xtpl->table_td(_("HDD").':');
	$xtpl->table_td(sprintf('%.2f GB',round($vps->used_diskspace / 1024, 2)));
	$xtpl->table_tr();

	if ($vps->maintenance_lock != 'no') {
		$xtpl->table_td(_('Maintenance lock').':');
		$xtpl->table_td($vps->maintenance_lock == 'lock' ? _('direct') : _('global lock'));
		$xtpl->table_tr();

		$xtpl->table_td(_('Maintenance reason').':');
		$xtpl->table_td($vps->maintenance_lock_reason);
		$xtpl->table_tr();
	}

	$xtpl->table_out();

	if (!isAdmin() && $vps->maintenance_lock != 'no') {
		$xtpl->perex(
			_("VPS is under maintenance"),
			_("All actions for this VPS are forbidden for the time being. This is usually used during outage to prevent data corruption.").
			"<br><br>"
			.($vps->maintenance_lock_reason ? _('Reason').': '.$vps->maintenance_lock_reason.'<br><br>' : '')
			._("Please be patient.")
		);

	} elseif ($vps->object_state == 'soft_delete') {
		if (isAdmin()) {
			lifetimes_set_state_form('vps', $vps->id, $vps);

		} else {
			$xtpl->perex(_('VPS is scheduled for deletion.'),
				_('This VPS is inaccessible and will be deleted when expiration date passes or some other event occurs. '.
				'Contact support if you want to revive it.'));
		}

	} elseif ($vps->object_state == 'hard_delete') {
		$xtpl->perex(_('VPS is deleted.'), _('This VPS is deleted and cannot be revived.'));

	} else {

	// Password changer
		$xtpl->table_title(_("Set root's password (in the VPS, not in the vpsAdmin)"));
		$xtpl->form_create('?page=adminvps&action=passwd&veid='.$vps->id, 'post');

		$xtpl->table_td(_("Username").':');
		$xtpl->table_td('root');
		$xtpl->table_tr();

		$xtpl->table_td(_("Password").':');

		if($_SESSION['vps_password'][$vps->id]) {
			$xtpl->table_td("<b>".$_SESSION['vps_password'][$vps->id]."</b>");

		} else
			$xtpl->table_td(_("will be generated"));

		$xtpl->table_tr();

		if (!isAdmin()) {
			$xtpl->table_td('');
			$xtpl->table_td('<b>Warning</b>: The password is randomly generated.<br>
							This password changer is here only to enable the first access to SSH.<br>
							You can change it with <em>passwd</em> command once you\'ve logged onto SSH.');
			$xtpl->table_tr();
		}

		$xtpl->form_add_radio(_("Secure password").':', 'password_type', 'secure', true, _('20 characters long, consists of: a-z, A-Z, 0-9'));
		$xtpl->table_tr();

		$xtpl->form_add_radio(_("Simple password").':', 'password_type', 'simple', false, _('8 characters long, consists of: a-z, 2-9'));
		$xtpl->table_tr();

		$xtpl->form_out(_("Go >>"));

	// Public keys
		$xtpl->table_title(_("Deploy public key to /root/.ssh/authorized_keys"));
		$xtpl->form_create('?page=adminvps&action=pubkey&veid='.$vps->id, 'post');

		$xtpl->table_td(
			_('Public keys can be registered in').
			' <a href="?page=adminm&action=pubkeys&id='.$vps->user_id.'">'.
			_('profile settings').'</a>.',
			false, false, '2'
		);
		$xtpl->table_tr();

		$xtpl->form_add_select(
			_('Public key').':',
			'public_key',
			resource_list_to_options($api->user($vps->user_id)->public_key->list())
		);

		$xtpl->form_out(_('Go >>'));

		// Network interfaces
		$netifs = $api->network_interface->list(['vps' => $vps->id]);

		foreach ($netifs as $netif) {
			vps_netif_form($vps, $netif);
		}

	// DNS Server
		$xtpl->table_title(_('DNS resolver (/etc/resolv.conf)'));
		$xtpl->form_create('?page=adminvps&action=nameserver&veid='.$vps->id, 'post');
		$xtpl->form_add_select(
			_("DNS resolver").':',
			'nameserver',
			resource_list_to_options(
				$api->dns_resolver->list(array('vps' => $vps->id)),
				'id', 'label', false
			),
			$vps->dns_resolver_id,
			''
		);
		$xtpl->form_out(_("Go >>"));

	// Hostname change
		$xtpl->table_title(_('Hostname'));
		$xtpl->form_create('?page=adminvps&action=hostname&veid='.$vps->id, 'post');

		$xtpl->form_add_radio_pure('manage_hostname', 'managed', $vps->manage_hostname);
		$xtpl->table_td(_('Manage hostname by vpsAdmin').':');
		$xtpl->form_add_input_pure('text', '30', 'hostname', $vps->hostname, _("A-z, a-z"), 255);
		$xtpl->table_tr();

		$xtpl->form_add_radio_pure('manage_hostname', 'manual', !$vps->manage_hostname);
		$xtpl->table_td(_('Manage hostname manually'));
		$xtpl->table_tr();


		$xtpl->form_out(_("Go >>"));

	// Datasets
	dataset_list('hypervisor', $vps->dataset_id);

	// Mounts
	mount_list($vps->id);


	// Distribution
		$xtpl->table_title(_('Distribution'));
		$xtpl->form_create('?page=adminvps&action=reinstall&veid='.$vps->id, 'post');
		$xtpl->form_add_select(_("Distribution").':', 'os_template', list_templates($vps), $vps->os_template_id,  '');
		$xtpl->table_td(_('Info').':');
		$xtpl->table_td($vps->os_template->info);
		$xtpl->table_tr();
		$xtpl->form_add_radio(
			_("Update information").':',
			'reinstall_action',
			'1', true,
			_("Use if you have upgraded your system.")
			.($vps->node->hypervisor_type == 'vpsadminos' ? ' '._('The VPS will be restarted.') : '')
		);
		$xtpl->table_tr();
		$xtpl->form_add_radio(
			_("Reinstall").':',
			'reinstall_action',
			'2', false,
			_("Install base system again.").' '
			.($vps->node->hypervisor_type == 'vpsadminos' ? _('All data in the root filesystem will be removed.') : _('All data will be removed.'))
		);
		$xtpl->table_tr();
		$xtpl->form_out(_("Go >>"));

	// Configs
		$xtpl->table_title(_('Configs'));

		$vps_configs = $api->vps($vps->id)->config->list();

		if (isAdmin()) {
			$all_configs = $api->vps_config->list();
			$configs_select = resource_list_to_options($all_configs, 'id', 'label', false);
			$options = "";

			foreach($configs_select as $id => $label)
				$options .= '<option value="'.$id.'">'.$label.'</option>';

			$xtpl->assign('AJAX_SCRIPT', $xtpl->vars['AJAX_SCRIPT'] . '
			<script type="text/javascript">
				function dnd() {
					$("#configs").tableDnD({
						onDrop: function(table, row) {
							$("#configs_order").val($.tableDnD.serialize());
						}
					});
				}

				$(document).ready(function() {
					var add_config_id = 1;

					dnd();

					$("#add_row").click(function (){
						$(\'<tr id="add_config_\' + add_config_id++ + \'"><td>'._('Add').':</td><td><select name="add_config[]">'.$options.'</select></td></tr>\').fadeIn("slow").insertBefore("#configs tr:nth-last-child(2)");
						dnd();
					});

					$(".delete-config").click(function (){
						$(this).closest("tr").remove();
					});
				});
			</script>');

			$config_choices_empty = array(0 => '---') + $configs_select;

			$xtpl->form_create('?page=adminvps&action=configs&veid='.$vps->id, 'post');
		}

		foreach($vps_configs as $cfg) {
			if (isAdmin()) {
				$xtpl->form_add_select_pure('configs[]', $configs_select, $cfg->vps_config->id);
				$xtpl->table_td('<a href="javascript:" class="delete-config">'._('delete').'</a>');
			} else $xtpl->table_td($cfg->vps_config->label);

			$xtpl->table_tr(false, false, false, "order_".$cfg->vps_config->id);
		}

		if (isAdmin()) {
			$xtpl->table_td('<input type="hidden" name="configs_order" id="configs_order" value="">' .  _('Add').':');
			$xtpl->form_add_select_pure('add_config[]', $config_choices_empty);
			$xtpl->table_tr(false, false, false, 'add_config');
// 			$xtpl->form_add_checkbox(_("Notify owner").':', 'notify_owner', '1', true);
			$xtpl->table_td(_("Reason").':');
			$xtpl->form_add_input_pure('text', '30', 'reason', '', _("If filled, user will be notified by email"));
			$xtpl->table_tr(false, "nodrag nodrop", false);
			$xtpl->form_out(_("Go >>>"), 'configs', '<a href="javascript:" id="add_row">+</a>');
		} else {
			$xtpl->table_out();
		}

	// Custom config
		if (isAdmin()) {
			$xtpl->table_title(_('Custom config'));
			$xtpl->form_create('?page=adminvps&action=custom_config&veid='.$vps->id, 'post');
			$xtpl->form_add_textarea(_("Config").':', 60, 10, 'custom_config', $vps->config, _('Applied last'));
			$xtpl->form_out(_("Go >>"));
		}

	// Resources
	$xtpl->table_title(_('Resources'));
	$xtpl->form_create('?page=adminvps&action=resources&veid='.$vps->id, 'post');

	$params = $api->vps->update->getParameters('input');
	$vps_resources = array('memory', 'cpu', 'swap');
	$user_resources = $vps->user->cluster_resource->list(array(
		'environment' => $vps->node->location->environment_id,
		'meta' => array('includes' => 'environment,cluster_resource'))
	);
	$resource_map = array();

	foreach ($user_resources as $r) {
		$resource_map[ $r->cluster_resource->name ] = $r;
	}

	foreach ($vps_resources as $name) {
		$p = $params->{$name};
		$r = $resource_map[$name];

		if (!isAdmin() && $r->value === 0)
			continue;

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
			_('CPU limit').':',
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
		$xtpl->form_create('?page=adminvps&action=features&veid='.$vps->id, 'post');

		$features = $vps->feature->list();

		foreach ($features as $f) {
			$xtpl->table_td($f->label);
			$xtpl->form_add_checkbox_pure($f->name, '1', $f->enabled ? '1' : '0');
			$xtpl->table_tr();
		}

		$xtpl->table_td(_('VPS is restarted when features are changed.'), false, false, '2');
		$xtpl->table_tr();

		$xtpl->form_out(_("Go >>"));

	// Maintenance windows
		$xtpl->table_title(_('Maintenance windows'));
		$xtpl->table_add_category('');
		$xtpl->table_add_category(_('Day'));
		$xtpl->table_add_category(_('From'));
		$xtpl->table_add_category(_('To'));
		$xtpl->form_create('?page=adminvps&action=maintenance_windows&veid='.$vps->id, 'post');

		$windows = $vps->maintenance_window->list();
		$days = array('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat');
		$hours = array();

		for ($i = 0; $i < 25; $i++)
			$hours[] = sprintf("%02d:00", $i);

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


	// State change
		if (isAdmin()) {
			lifetimes_set_state_form('vps', $vps->id, $vps);
		}
	}
}

$xtpl->sbar_out(_("Manage VPS"));

} else $xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
?>
