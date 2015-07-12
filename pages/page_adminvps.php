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
		$show_info = true;
	}
}

$_GET["action"] = isset($_GET["action"]) ? $_GET["action"] : false;

switch ($_GET["action"]) {
		case 'list':
			$list_vps = true;
			break;
			
		case 'new':
			print_newvps_page1();
			break;
			
		case 'new2':
			print_newvps_page2($_GET['environment']);
			break;
		
		case 'new3':
			print_newvps_page3($_GET['environment'], $_GET['location']);
			break;
			
		case 'new4':
			if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
				print_newvps_page3($_GET['environment'], $_GET['location']);
				break;
			}
			
			csrf_check();
			
			$params = array(
				'hostname' => $_POST['vps_hostname'],
				'os_template' => $_POST['vps_template'],
				'info' => $_SESSION['is_admin'] ? '' : $_POST['vps_info'],
				'memory' => $_POST['memory'],
				'cpu' => $_POST['cpu'],
				'diskspace' => $_POST['diskspace'],
				'ipv4' => $_POST['ipv4'],
				'ipv6' => $_POST['ipv6']
			);
			
			if($_SESSION["is_admin"]) {
				$params['user'] = $_POST['m_id'];
				$params['node'] = $_POST['vps_server'];
				$params['onboot'] = $_POST['boot_after_create'];
				
			} else {
				if ($_GET['location'])
					$params['location'] = (int)$_GET['location'];
				if ($_GET['environment'])
					$params['environment'] = (int)$_GET['environment'];
			}
			
			try {
				$vps = $api->vps->create($params);
				
				if ($params['onboot'] || !$_SESSION['is_admin']) {
					notify_user(_("VPS create ").' '.$vps->id, _("VPS will be created and booted afterwards."));
					
				} else {
					notify_user(_("VPS create ").' '.$vps->id, _("VPS will be created. You can start it manually."));
				}

				redirect('?page=adminvps&action=info&veid='.$vps->id);
				
			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('VPS creation failed'), $e->getResponse());
				
				print_newvps_page3($_GET['environment'], $_GET['location']);
			}
			break;
			
		case 'delete':
			$vps = $api->vps->find($_GET['veid']);

			$xtpl->perex(_("Are you sure you want to delete VPS number").' '.$vps->id.'?', '');
			
			$xtpl->table_title(_("Delete VPS"));
			$xtpl->table_td(_("Hostname").':');
			$xtpl->table_td($vps->hostname);
			$xtpl->table_tr();
			$xtpl->form_create('?page=adminvps&section=vps&action=delete2&veid='.$_GET["veid"], 'post');
			$xtpl->form_csrf();
			
			if($_SESSION["is_admin"]) {
				$xtpl->form_add_checkbox(_("Lazy delete").':', 'lazy_delete', '1', true,
					_("Do not delete VPS immediately, but after passing of predefined time."));
			}
			$xtpl->form_out(_("Delete"));
			break;
			
		case 'delete2':
			csrf_check();
			$api->vps->destroy($_GET["veid"], array('lazy' => $_POST["lazy_delete"] ? true : false));
			
			notify_user(_("Delete VPS").' #'.$_GET["veid"], _("Deletion of VPS")." {$_GET["veid"]} ".strtolower(_("planned")));
			redirect('?page=adminvps');
			break;
			
		case 'revive':
			try {
				csrf_check();
				$api->vps->revive($_GET['veid']);
				
				notify_user(_("Revival"), _("VPS was revived."));
				redirect('?page=adminvps&action=info&veid='.$_GET['veid']);
				
			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Unable to revive VPS'), $e->getResponse());
				$show_info=true;
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
		case 'hostname':
			try {
				csrf_check();
				$api->vps->update($_GET['veid'], array('hostname' => $_POST['hostname']));
				
				notify_user(_("Hostname change planned"), '');
				redirect('?page=adminvps&action=info&veid='.$_GET['veid']);
				
			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				 {}$show_info=true;
			}
			break;
		case 'configs':
			if ($_SESSION["is_admin"] && isset($_REQUEST["veid"]) && (isset($_POST["configs"]) || isset($_POST["add_config"]))) {
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
			if ($_SESSION['is_admin']) {
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
					$update_params = $api->vps->update->getParameters('input');
					$vps_resources = array('memory', 'cpu', 'swap');
					$params = array();
					
					foreach ($vps_resources as $r) {
						$params[ $r ] = $_POST[$r];
					}
					
					if ($_SESSION['is_admin']) {
						if ($_POST['change_reason'])
							$params['change_reason'] = $_POST['change_reason'];
						
						if ($_POST['admin_override'])
							$params['admin_override'] = $_POST['admin_override'];
						
						$params['admin_lock_type'] = $update_params->admin_lock_type->choices[ (int) $_POST['admin_lock_type'] ];
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
			if($_POST['m_id']) {
				try {
					csrf_check();
					$api->vps->update($_GET['veid'], array('user' => $_POST['m_id']));
					
					notify_user(_("Owner changed"), '');
					redirect('?page=adminvps&action=info&veid='.$_GET['veid']);
					
				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('Change of the owner failed'), $e->getResponse());
					$show_info=true;
				}
			}
			
			$show_info=true;
			break;
		case 'addip':
			try {
				csrf_check();
				
				if($_POST['ip_recycle']) {
					$api->vps($_GET['veid'])->ip_address->create(array('ip_address' => $_POST['ip_recycle']));
					notify_user(_("Addition of IP address planned"), '');
					
				} else if($_POST['ip6_recycle']) {
					$api->vps($_GET['veid'])->ip_address->create(array('ip_address' => $_POST['ip6_recycle']));
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
		case 'delip':
			try {
				csrf_check();
				$api->vps($_GET['veid'])->ip_address($_GET['ip'])->delete();
				
				notify_user(_("Deletion of IP address planned"), '');
				redirect('?page=adminvps&action=info&veid='.$_GET['veid']);
				
			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Failed to remove IP address'), $e->getResponse());
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
			if ($_SESSION["is_admin"] && isset($_GET["veid"])) {
				csrf_check();
				
				try {
					$api->vps($_GET['veid'])->migrate(array(
						'node' => $_POST['node'],
						'replace_ip_addresses' => isset($_POST['replace_ip_addresses'])
					));
					
					notify_user(_("Offline migration planned"), '');
					redirect('?page=adminvps&action=info&veid='.$_GET['veid']);
					
				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('Offline migration failed'), $e->getResponse());
					$show_info=true;
				}
				
			} else {
				$xtpl->perex(_("Error"), '');
			}
			
			$show_info=true;
			break;
		
		case 'reinstall':
			csrf_check();
			
			if ($_POST['reinstall_action'] === '1') {
				try {
					$api->vps($_GET['veid'])->update(array(
						'os_template' => $_POST['vps_template']
					));
					
					notify_user(_("Distribution information updated"), '');
					redirect('?page=adminvps&action=info&veid='.$_GET["veid"]);
					
				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('Failed to update distribution'), $e->getResponse());
					$show_info=true;
				}
				
			} elseif ($_POST['reinstall_action'] === '2') {
				$xtpl->perex(
					_("Are you sure you want to reinstall VPS").' '.$_GET["veid"].'?',
					'<a href="?page=adminvps">'.strtoupper(_("No")).'</a> | <a href="?page=adminvps&action=reinstall2&veid='.$_GET["veid"].'&vps_template='.$_POST["vps_template"].'&t='.csrf_token().'">'.strtoupper(_("Yes")).'</a>'
				);
			}
			break;
		case 'reinstall2':
			try {
				csrf_check();
				$api->vps->reinstall($_GET["veid"], array('os_template' => $_GET["vps_template"]));
				
				notify_user(_("Reinstallation of VPS")." {$_GET["veid"]} ".strtolower(_("planned")), _("You will have to reset your <b>root</b> password."));
				redirect('?page=adminvps&action=info&veid='.$_GET["veid"]);
				
			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Reinstall failed'), $e->getResponse());
				$show_info=true;
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
		case 'clone':
			if (isset($_POST['hostname'])) {
				csrf_check();
				
				try {
					$cloned = $api->vps($_GET['veid'])->clone(client_params_to_api($api->vps->clone));
					
					notify_user(_("Clone in progress"), '');
					redirect('?page=adminvps&action=info&veid='.$cloned->id);
					
				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('Clone failed'), $e->getResponse());
					$show_info=true;
				}
				
			} else
				 $xtpl->perex(_("Invalid data"), _("Please fill the form correctly."));
			
			$show_info=true;
			break;

		case 'swap_preview':
			try {
				$params = array('meta' => array('includes' => 'node'));

				vps_swap_preview_form(
					$api->vps->find($_GET['veid'], $params),
					$api->vps->find($_GET['vps'], $params),
					$_GET
				);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Swap preview failed'), $e->getResponse());
				$show_info = true;
			}
			break;

		case 'swap':
			if (isset($_POST['cancel']))
				redirect('?page=adminvps&action=info&veid='.$_GET['veid']);

			csrf_check();

			try {
				$api->vps($_GET['veid'])->swap_with(
					client_params_to_api($api->vps->swap_with)
				);

				notify_user(_('Swap in progress'), '');
				redirect('?page=adminvps&action=info&veid='.$_GET['veid']);
				
			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Swap failed'), $e->getResponse());
				$show_info = true;
			}

			break;
		
		default:
			$list_vps=true;
			break;
	}

if ($list_vps) {
	if ($_SESSION["is_admin"])
		$xtpl->title(_("VPS list").' '._("[Admin mode]"));
	else
		$xtpl->title(_("VPS list").' '._("[User mode]"));
	
	if ($_SESSION['is_admin']) {
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
			resource_list_to_options($api->node->list(), 'id', 'name'), get_val('node'));
		$xtpl->form_add_select(_("Location").':', 'location',
			resource_list_to_options($api->location->list()), get_val('location'));
		$xtpl->form_add_select(_("Environment").':', 'environment',
			resource_list_to_options($api->environment->list()), get_val('environment'));
		
		$p = $api->vps->index->getParameters('input')->object_state;
		
		api_param_to_form('object_state', $p,
			$p->choices[ $_GET['object_state'] ]);
		
		$xtpl->form_out(_('Show'));
	}
	
	if (!$_SESSION['is_admin'] || $_GET['action'] == 'list') {
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

		if (!$_SESSION['is_admin']) {
			$envs_destroy = array();

			foreach ($api->user($_SESSION['member']['m_id'])->environment_config->list() as $env) {
				$envs_destroy[$env->environment_id] = $env->can_destroy_vps;
			}
		}
		
		if ($_SESSION['is_admin']) {
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
				$params['object_state'] = $api->vps->index->getParameters('input')->object_state->choices[(int) $_GET['object_state']];
			
			$vpses = $api->vps->list($params);
			
		} else {
			$vpses = $api->vps->list(array('meta' => array('count' => true, 'includes' => 'user,node')));
		}
		
		foreach ($vpses as $vps) {
			
			$xtpl->table_td('<a href="?page=adminvps&action=info&veid='.$vps->id.'">'.$vps->id.'</a>');
			$xtpl->table_td('<a href="?page=adminvps&server_name='.$vps->node->name.'">'. $vps->node->name . '</a>');
			$xtpl->table_td('<a href="?page=adminm&section=members&action=edit&id='.$vps->user_id.'">'.$vps->user->login.'</a>');
			$xtpl->table_td($vps->process_count, false, true);
			$xtpl->table_td('<a href="?page=adminvps&action=info&veid='.$vps->id.'"><img src="template/icons/vps_edit.png"  title="'._("Edit").'"/> '.$vps->hostname.'</a>');
			$xtpl->table_td(sprintf('%4d MB',$vps->used_memory), false, true);
			
			if ($vps->used_disk > 0)
				$xtpl->table_td(sprintf('%.2f GB',round($vps->used_disk/1024, 2)), false, true);
			else $xtpl->table_td('---', false, true);
			
			if($_SESSION['is_admin'] || $vps->maintenance_lock == 'no') {
				$xtpl->table_td(($vps->running) ? '<a href="?page=adminvps&run=restart&veid='.$vps->id.'&t='.csrf_token().'"><img src="template/icons/vps_restart.png" title="'._("Restart").'"/></a>' : '<img src="template/icons/vps_restart_grey.png"  title="'._("Unable to restart").'" />');
				$xtpl->table_td(($vps->running) ? '<a href="?page=adminvps&run=stop&veid='.$vps->id.'&t='.csrf_token().'"><img src="template/icons/vps_stop.png"  title="'._("Stop").'"/></a>' : '<a href="?page=adminvps&run=start&veid='.$vps->id.'"><img src="template/icons/vps_start.png"  title="'._("Start").'"/></a>');
				
				if (!$_SESSION['is_admin'])
					$xtpl->table_td('<a href="?page=console&veid='.$vps->id.'&t='.csrf_token().'"><img src="template/icons/console.png"  title="'._("Remote Console").'"/></a>');
				
				if ($_SESSION['is_admin'])
					$xtpl->table_td(maintenance_lock_icon('vps', $vps));
				
				if ($_SESSION["is_admin"] || $envs_destroy[$vps->node->environment_id]){
					$xtpl->table_td((!$vps->running) ? '<a href="?page=adminvps&action=delete&veid='.$vps->id.'"><img src="template/icons/vps_delete.png"  title="'._("Delete").'"/></a>' : '<img src="template/icons/vps_delete_grey.png"  title="'._("Unable to delete").'"/>');
				} else {
					$xtpl->table_td('<img src="template/icons/vps_delete_grey.png"  title="'._("Cannot delete").'"/>');
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
			if($vps->running)
				$color = false;
			
			$xtpl->table_tr($color);
			
		}
		
		$xtpl->table_out();

		if ($_SESSION["is_admin"]) {
			$xtpl->table_add_category(_("Total number of VPS").':');
			$xtpl->table_add_category($vpses->getTotalCount());
			$xtpl->table_out();
			
		}
	}
	
	if (!$_SESSION['is_admin']) {
		$xtpl->sbar_add('<img src="template/icons/m_add.png"  title="'._("New VPS").'" /> '._("New VPS"), '?page=adminvps&section=vps&action=new');
	}
}

if($_SESSION["is_admin"] && $list_vps) {
	if ($_SESSION["is_admin"]) {
		$xtpl->sbar_add('<img src="template/icons/m_add.png"  title="'._("New VPS").'" /> '._("New VPS"), '?page=adminvps&section=vps&action=new3');
		$xtpl->sbar_add('<img src="template/icons/vps_ip_list.png"  title="'._("List VPSes").'" /> '._("List VPSes"), '?page=adminvps&action=list');
	}
}

if (isset($show_info) && $show_info) {
	if (!isset($veid))
		$veid = $_GET["veid"];
	
	$vps = $api->vps->find($veid, array('meta' => array('includes' => 'node__location,node__environment,user,os_template')));
	
	$title = 'VPS <a href="?page=adminvps&action=info&veid='.$veid.'">#'.$veid.'</a> '._("details");
	
	if ($_SESSION["is_admin"])
		$xtpl->title($title.' '._("[Admin mode]"));
	else
		$xtpl->title($title.' '._("[User mode]"));
	
	
	if ($_SESSION['is_admin'])
		$xtpl->sbar_add(_('State log'), '?page=lifetimes&action=changelog&resource=vps&id='.$vps->id.'&return='. urlencode($_SERVER['REQUEST_URI']));
	
	$xtpl->table_td('ID:');
	$xtpl->table_td($vps->id);
	$xtpl->table_tr();
	
	$xtpl->table_td(_("Server").':');
	$xtpl->table_td($vps->node->name);
	$xtpl->table_tr();
	
	$xtpl->table_td(_("Location").':');
	$xtpl->table_td($vps->node->location->label);
	$xtpl->table_tr();
	
	$xtpl->table_td(_("Environment").':');
	$xtpl->table_td($vps->node->environment->label);
	$xtpl->table_tr();
	
	$xtpl->table_td(_("Owner").':');
	$xtpl->table_td('<a href="?page=adminm&section=members&action=edit&id='.$vps->user_id.'">'.$vps->user->login.'</a>');
	$xtpl->table_tr();
	
	$xtpl->table_td(_("State").':');
	$xtpl->table_td($vps->object_state);
	$xtpl->table_tr();
	
	if ($vps->expiration_date) {
		$xtpl->table_td(_("Expiration").':');
		$xtpl->table_td($vps->expiration_date);
		$xtpl->table_tr();
	}
	
	$xtpl->table_td(_("Status").':');
	
	if($vps->maintenance_lock == 'no') {
		$xtpl->table_td(
			(($vps->running) ?
				_("running").' (<a href="?page=adminvps&action=info&run=restart&veid='.$vps->id.'&t='.csrf_token().'">'._("restart").'</a>, <a href="?page=adminvps&action=info&run=stop&veid='.$vps->id.'&t='.csrf_token().'">'._("stop").'</a>'
				: 
				_("stopped").' (<a href="?page=adminvps&action=info&run=start&veid='.$vps->id.'&t='.csrf_token().'">'._("start").'</a>') .
				', <a href="?page=console&veid='.$vps->id.'&t='.csrf_token().'">'._("open remote console").'</a>)'
		);
	} else {
		$xtpl->table_td($vps->running ? _("running") : _("stopped"));
	}
	
	$xtpl->table_tr();
	
	$xtpl->table_td(_("Processes").':');
	$xtpl->table_td($vps->process_count);
	$xtpl->table_tr();
	
	$xtpl->table_td(_("Hostname").':');
	$xtpl->table_td($vps->hostname);
	$xtpl->table_tr();
	
	$xtpl->table_td(_("RAM").':');
	$xtpl->table_td(sprintf('%4d MB', $vps->used_memory));
	$xtpl->table_tr();
	
	$xtpl->table_td(_("HDD").':');
	$xtpl->table_td(sprintf('%.2f GB',round($vps->used_disk / 1024, 2)));
	$xtpl->table_tr();
	
	$xtpl->table_td(_("Distribution").':');
	$xtpl->table_td($vps->os_template->label);
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
	
	if (!$_SESSION['is_admin'] && $vps->maintenance_lock != 'no') {
		$xtpl->perex(
			_("VPS is under maintenance"),
			_("All actions for this VPS are forbidden for the time being. This is usually used during outage to prevent data corruption.").
			"<br><br>"
			.($vps->maintenance_lock_reason ? _('Reason').': '.$vps->maintenance_lock_reason.'<br><br>' : '')
			._("Please be patient.")
		);
	
	} elseif ($vps->object_state == 'soft_delete') {
		if ($_SESSION["is_admin"]) {
			lifetimes_set_state_form('vps', $vps->id);
			
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
		
		if (!$_SESSION["is_admin"]) {
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

	// IP addresses
		$xtpl->table_title(_('IP addresses'));
		$xtpl->form_create('?page=adminvps&action=addip&veid='.$vps->id, 'post');
		
		foreach ($api->vps($vps->id)->ip_address->list() as $ip) {
			if ($ip->version == 4)
				$xtpl->table_td(_("IPv4"));
			else
				$xtpl->table_td(_("IPv6"));
			
			$xtpl->table_td($ip->addr);
			$xtpl->table_td('<a href="?page=adminvps&action=delip&ip='.$ip->id.'&veid='.$vps->id.'&t='.csrf_token().'">('._("Remove").')</a>');
			$xtpl->table_tr();
		}
		
		$tmp[] = '-------';
		$free_4 = $tmp + get_free_ip_list(4, $vps);
		
		if ($vps_location["location_has_ipv6"])
			$free_6 = $tmp + get_free_ip_list(6, $vps);
			
		$xtpl->form_add_select(_("Add IPv4 address").':', 'ip_recycle', $free_4, '', _('Add one IP address at a time'));
		
		if ($vps->location->has_ipv6)
			$xtpl->form_add_select(_("Add IPv6 address").':', 'ip6_recycle', $free_6, '', _('Add one IP address at a time'));
			
		$xtpl->table_tr();
		
		$xtpl->form_out(_("Go >>"));
		

	// DNS Server
		$xtpl->table_title(_('DNS resolver (/etc/resolv.conf)'));
		$xtpl->form_create('?page=adminvps&action=nameserver&veid='.$vps->id, 'post');
		$xtpl->form_add_select(_("DNS servers address").':', 'nameserver', $cluster->list_dns_servers($vps->node->location_id), $vps->dns_resolver_id,  '');
		$xtpl->form_out(_("Go >>"));

	// Hostname change
		$xtpl->table_title(_('Hostname'));
		$xtpl->form_create('?page=adminvps&action=hostname&veid='.$vps->id, 'post');
		$xtpl->form_add_input(_("Hostname").':', 'text', '30', 'hostname', $vps->hostname, _("A-z, a-z"), 255);
		$xtpl->form_out(_("Go >>"));
	
	// Datasets
	dataset_list('hypervisor', $vps->dataset_id);
	
	// Mounts
	mount_list($vps->id);
	
		
	// Distribution
		$xtpl->table_title(_('Distribution'));
		$xtpl->form_create('?page=adminvps&action=reinstall&veid='.$vps->id, 'post');
		$xtpl->form_add_select(_("Distribution").':', 'vps_template', list_templates(), $vps->os_template_id,  '');
		$xtpl->form_add_radio(_("Update information").':', 'reinstall_action', '1', true, $hint = _("Use if you have upgraded your system"));
		$xtpl->table_tr();
		$xtpl->form_add_radio(_("Reinstall").':', 'reinstall_action', '2', false, $hint = _("Install base system again"));
		$xtpl->table_tr();
		$xtpl->form_out(_("Go >>"));

	// Configs
		$xtpl->table_title(_('Configs'));
		
		$configs_select = list_configs(true);
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
		
		$vps_configs = $api->vps($vps->id)->config->list();
		
		if ($_SESSION["is_admin"]) {
			$all_configs = $api->vps_config->list();
			$config_choices = array();
			
			foreach ($all_configs as $cfg) {
				$config_choices[$cfg->id] = $cfg->label;
			}
			
			$config_choices_empty = array(0 => '---') + $config_choices;
			
			$xtpl->form_create('?page=adminvps&action=configs&veid='.$vps->id, 'post');
		}
		
		foreach($vps_configs as $cfg) {
			if ($_SESSION["is_admin"]) {
				$xtpl->form_add_select_pure('configs[]', $config_choices, $cfg->vps_config->id);
				$xtpl->table_td('<a href="javascript:" class="delete-config">'._('delete').'</a>');
			} else $xtpl->table_td($cfg->vps_config->label);
			
			$xtpl->table_tr(false, false, false, "order_".$cfg->vps_config->id);
		}
		
		if ($_SESSION["is_admin"]) {
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
		if ($_SESSION["is_admin"]) {
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
		'environment' => $vps->node->environment_id,
		'meta' => array('includes' => 'environment,cluster_resource'))
	);
	$resource_map = array();
	
	foreach ($user_resources as $r) {
		$resource_map[ $r->cluster_resource->name ] = $r;
	}
	
	foreach ($vps_resources as $name) {
		$p = $params->{$name};
		$r = $resource_map[$name];
		
		$xtpl->table_td($p->label);
		$xtpl->form_add_number_pure(
			$name,
			$vps->{$name},
			$r->cluster_resource->min,
			$_SESSION['is_admin'] ?
				$r->cluster_resource->max :
				min($vps->{$name} + $r->free, $r->cluster_resource->max),
			$r->cluster_resource->stepsize,
			'MiB'
		);
		$xtpl->table_tr();
	}
	
	if ($_SESSION['is_admin']) {
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

	// Owner change
		if ($_SESSION["is_admin"]) {
			$xtpl->table_title(_('VPS owner'));
			$xtpl->form_create('?page=adminvps&action=chown&veid='.$vps->id, 'post');
			$xtpl->form_add_select(_("Owner").':', 'm_id',
				resource_list_to_options($api->user->list(), 'id', 'login', false),
				$vps->user_id);
			$xtpl->form_out(_("Go >>"));
		}
		
	// State change
		if ($_SESSION['is_admin']) {
			lifetimes_set_state_form('vps', $vps->id);
		}

	// Offline migration
		if ($_SESSION["is_admin"]) {
			$xtpl->table_title(_('Offline migration'));
			$xtpl->form_create('?page=adminvps&action=offlinemigrate&veid='.$vps->id, 'post');
			api_params_to_form($vps->migrate, 'input');
			$xtpl->form_out(_("Go >>"));
		}
	
	// Clone
		$xtpl->table_title(_('Clone VPS'));
		$xtpl->form_create('?page=adminvps&action=clone&veid='.$vps->id, 'post');
		
		api_params_to_form($vps->clone, 'input', array('vps' => function($vps) {
			return '#'.$vps->id.' '.$vps->hostname;
		}));
		
		$xtpl->form_out(_("Go >>"));
	
	// Swap
		$xtpl->table_title(_('Swap VPS'));
		$xtpl->form_create('?page=adminvps&action=swap_preview&veid='.$vps->id, 'get', 'vps-swap', false);
		
		api_params_to_form($vps->swap_with, 'input', array('vps' => function($vps) {
			return '#'.$vps->id.' '.$vps->hostname;
		}));
		
		$xtpl->form_out(_("Continue"), null,
			'<input type="hidden" name="page" value="adminvps">'.
			'<input type="hidden" name="action" value="swap_preview">'.
			'<input type="hidden" name="veid" value="'.$vps->id.'">'
		);
	}
}

$xtpl->sbar_out(_("Manage VPS"));

} else $xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
?>
