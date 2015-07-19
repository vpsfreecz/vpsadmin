<?php
/*
	./pages/page_cluster.php

	vpsAdmin
	Web-admin interface for OpenVZ (see http://openvz.org)
	Copyright (C) 2008-2011 Pavel Snajdr, snajpa@snajpa.net
*/
if ($_SESSION["is_admin"]) {

function maintenance_lock_by_type() {
	global $api;
	
	$r = null;
	$label = '';
	
	switch ($_GET['type']) {
		case 'cluster':
			$r = $api->cluster;
			$label = _('Cluster');
			break;
			
		case 'environment':
			$label = _('Environment').' '.$api->environment->find($_GET['obj_id'])->label;
			break;
		
		case 'location':
			$label = _('Location').' '.$api->location->find($_GET['obj_id'])->label;
			break;
			
		case 'node':
			$label = _('Node').' '.$api->node->find($_GET['obj_id'])->name;
			break;
		
		case 'vps':
			$label = 'VPS #'.$_GET['obj_id'];
			break;
		
		default:
			break;
	}
	
	return array('resource' => $r, 'label' => $label);
}

function list_mail_templates() {
	global $xtpl, $api;
	
	$tpls = $api->mail_template->list();
	
	$xtpl->table_title(_('Mail templates'));
	$xtpl->table_add_category(_('Name'));
	$xtpl->table_add_category(_('Label'));
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	
	foreach ($tpls as $tpl) {
		$xtpl->table_td($tpl->name);
		$xtpl->table_td($tpl->label);
		$xtpl->table_td('<a href="?page=cluster&action=mail_template_edit&id='.$tpl->id.'"><img src="template/icons/vps_edit.png"  title="'._("Edit").'"></a>');
		$xtpl->table_td('<a href="?page=cluster&action=mail_template_destroy&id='.$tpl->id.'"><img src="template/icons/vps_delete.png"  title="'._("Delete").'"></a>');
		$xtpl->table_tr();
	}
	
	$xtpl->table_out();
	
	$xtpl->sbar_add(_('New mail template'), '?page=cluster&action=mail_template_new');
	$xtpl->sbar_add(_('Back'), '?page=cluster');
}

function mail_template_new() {
	global $xtpl, $api;
	
	$xtpl->table_title(_('Create a new mail template'));
	$xtpl->form_create('?page=cluster&action=mail_template_new', 'post');
	
	api_params_to_form($api->mail_template->create, 'input');
	
	$xtpl->form_out(_('Save changes'));
	
	$xtpl->sbar_add(_('Back'), '?page=cluster&action=mail_templates');
}

function mail_template_edit() {
	global $xtpl, $api;
	
	$t = $api->mail_template->show($_GET['id']);
	$params = $api->mail_template->update->getParameters('input');
	
	$xtpl->table_title(_('Edit mail template').' '.'#'.$t->id);
	$xtpl->form_create('?page=cluster&action=mail_template_edit&id='.$t->id, 'post');
	
	foreach ($params as $name => $desc) {
		api_param_to_form($name, $desc, htmlspecialchars($t->{$name}));
	}
	
	$xtpl->form_out(_('Save changes'));
	
	$xtpl->sbar_add(_('Back'), '?page=cluster&action=mail_templates');
}

$xtpl->title(_("Manage Cluster"));
$list_nodes = false;
$list_templates = false;

$server_types = array("node" => "Node", "storage" => "Storage", "mailer" => "Mailer");

switch($_REQUEST["action"]) {
	case "general_settings":
		$xtpl->title2(_("General settings"));
		$xtpl->table_add_category('');
		$xtpl->table_add_category('');
		$xtpl->form_create('?page=cluster&action=general_settings_save', 'post');
		$xtpl->form_add_input(_("Base URL").':', 'text', '30', 'base_url', $cluster_cfg->get("general_base_url"));
		$xtpl->form_add_input(_("Member delete timeout").':', 'text', '30', 'member_del_timeout', $cluster_cfg->get("general_member_delete_timeout"), _("days"));
		$xtpl->form_add_input(_("VPS delete timeout").':', 'text', '30', 'vps_del_timeout', $cluster_cfg->get("general_vps_delete_timeout"), _("days"));
		$xtpl->form_out(_("Save changes"));
		
		$xtpl->sbar_add(_("Back"), '?page=cluster');
		break;
	case "general_settings_save":
		$cluster_cfg->set("general_base_url", $_POST["base_url"]);
		$cluster_cfg->set("general_member_delete_timeout", $_POST["member_del_timeout"]);
		$cluster_cfg->set("general_vps_delete_timeout", $_POST["vps_del_timeout"]);
		notify_user(_("Changes saved"), _("Changes sucessfully saved."));
		redirect('?page=cluster&action=general_settings');
		break;
	case "restart_node":
		$node = new cluster_node($_REQUEST["id"]);
		$xtpl->perex(_("Are you sure to reboot node").' '.$node->s["server_name"].'?',
			'<a href="?page=cluster">NO</a> | <a href="?page=cluster&action=restart_node2&id='.$_REQUEST["id"].'">YES</a>');
		break;
	case "restart_node2":
		$node = new cluster_node($_REQUEST["id"]);
		$xtpl->perex(_("WARNING: This will stop ALL VPSes on the node. Really continue?"),
			'<a href="?page=cluster&action=restart_node3&id='.$_REQUEST["id"].'">YES</a> | <a href="?page=cluster">NO</a>');
		break;
	case "restart_node3":
		if (isset($_REQUEST["id"])) {
			add_transaction($_SESSION["member"]["m_id"], $_REQUEST["id"], 0, T_RESTART_NODE);
		}
		$list_nodes = true;
		break;
		
	case "dns":
		$list_dns = true;
		break;
		
	case "dns_new":
		$xtpl->title2(_("New DNS Server"));
		$xtpl->table_add_category('');
		$xtpl->table_add_category('');
		$xtpl->form_create('?page=cluster&action=dns_new_save', 'post');
		$xtpl->form_add_input(_("IP Address").':', 'text', '30', 'dns_ip', '', '');
		$xtpl->form_add_input(_("Label").':', 'text', '30', 'dns_label', '', _("DNS Label"));
		$xtpl->form_add_checkbox(_("Is this DNS location independent?").':', 'dns_is_universal', '1', false, '');
		$xtpl->form_add_select(_("Location").':', 'dns_location',
			resource_list_to_options($api->dns_resolver->list()), '',  '');
		$xtpl->form_out(_("Save changes"));
		break;
		
	case "dns_new_save":
		try {
			$api->dns_resolver->create(array(
				'ip_addr' => $_POST['dns_ip'],
				'is_universal' => $_POST['dns_is_universal'],
				'location' => $_POST['dns_location']
			));
			
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
		$xtpl->form_create('?page=cluster&action=dns_edit_save&id='.$ns->id, 'post');
		$xtpl->form_add_input(_("IP Address").':', 'text', '30', 'dns_ip', $ns->ip_addr, '');
		$xtpl->form_add_input(_("Label").':', 'text', '30', 'dns_label', $ns->label, _("DNS Label"));
		$xtpl->form_add_checkbox(_("Is this DNS location independent?").':', 'dns_is_universal', '1', $ns->is_universal, '');
		$xtpl->form_add_select(_("Location").':', 'dns_location',
			resource_list_to_options($api->dns_resolver->list()), $ns->location_id, '');
		$xtpl->form_out(_("Save changes"));
		
		break;
		
	case "dns_edit_save":
		csrf_check();
		
		try {
			$api->dns_resolver->update($_GET['id'], array(
				'ip_addr' => $_POST['dns_ip'],
				'is_universal' => $_POST['dns_is_universal'],
				'location' => $_POST['dns_location']
			));
			
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
				$api->dns_resolver->delete($_GET['id'], array('force' => isset($_POST['force'])));
				
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
		$xtpl->table_add_category('<img title="'._("Toggle maintenance on environment.").'" alt="'._("Toggle maintenance on environment.").'" src="template/icons/maintenance_mode.png">');
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
			$xtpl->table_td('<a href="?page=cluster&action=env_edit&id='.$env->id.'"><img src="template/icons/edit.png" title="'._("Edit").'"></a>');
			
			$xtpl->table_tr();
		}
		
		$xtpl->table_out();
		
		break;
	
	case 'env_edit':
		$xtpl->sbar_add(_("Back"), '?page=cluster&action=environments');
		$env_settings = true;
		break;
	
	case 'env_chain_save':
		$xtpl->sbar_add(_("Back"), '?page=cluster&action=environments');
		
		if (isset($_POST["configs"]) || isset($_POST["add_config"])) {
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
			
			try {
				$api->environment($_GET['id'])->config_chain->replace($params);
				
				notify_user(_('Environment config chain set'), '');
				redirect('?page=cluster&action=env_edit&id='.$_GET['id']);
				
			} catch (\HaveAPI\Client\Exception\ActionFailde $e) {
				$xtpl->perex_format_errors(_('Change of environment config chain failed'), $e->getResponse());
			}
			
			
		} else {
			$xtpl->perex(_("Error"), 'Error, contact your administrator');
			$list_configs=true;
		}
		
		break;
	
	case 'env_save':
		if (isset($_POST['label'])) {
			try {
				$api->environment->update($_GET['id'], array(
					'label' => $_POST['label'],
					'domain' => $_POST['domain'],
					'can_create_vps' => isset($_POST['can_create_vps']),
					'can_destroy_vps' => isset($_POST['can_destroy_vps']),
					'vps_lifetime' => $_POST['vps_lifetime'],
					'max_vps_count' => $_POST['max_vps_count'],
					'user_ip_ownership' => isset($_POST['user_ip_ownership'])
				));
				
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
		$xtpl->form_add_input(_("Label").':', 'text', '30', 'location_label', '', _("Location name"));
		$xtpl->form_add_checkbox(_("Has this location IPv6 support?").':', 'has_ipv6', '1', false, '');
		$xtpl->form_add_checkbox(_("Run VPSes here on boot?").':', 'onboot', '1', '1', '');
		$xtpl->form_add_input(_("Remote console server").':', 'text', '30',	'remote_console_server',	'', _("URL"));
		$xtpl->form_add_input(_("Domain").':', 'text', '30',	'domain',	$item["domain"], '');
		$xtpl->form_out(_("Save changes"));
		
		break;
		
	case "location_new_save":
		try {
			$api->location->create(array(
				'label' => $_POST['location_label'],
				'type' => $_POST['type'],
				'has_ipv6' => (bool)$_POST['has_ipv6'],
				'vps_onboot' => (bool)$_POST['onboot'],
				'remote_console_server' => $_POST['remote_console_server'],
				'domain' => $_POST['domain']
			));
			
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
			$xtpl->form_create('?page=cluster&action=location_edit_save&id='.$loc->id, 'post');
			$xtpl->form_add_input(_("Label").':', 'text', '30', 'location_label', $loc->label, _("Location name"));
			$xtpl->form_add_checkbox(_("Has this location IPv6 support?").':', 'has_ipv6', '1', $loc->has_ipv6, '');
			$xtpl->form_add_checkbox(_("Run VPSes here on boot?").':', 'onboot', '1', $loc->vps_onboot, '');
			$xtpl->form_add_input(_("Remote console server").':', 'text', '30',	'remote_console_server', $loc->_remote_console_server, _("URL"));
			$xtpl->form_add_input(_("Domain").':', 'text', '30',	'domain',	$loc->domain, '');
			
			$xtpl->form_out(_("Save changes"));
			
		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			$xtpl->perex_format_errors(_('Location find failed'), $e->getResponse());
		}
		
		break;
		
	case "location_edit_save":
		try {
			$api->location->update($_GET['id'], array(
				'label' => $_POST['location_label'],
				'type' => $_POST['type'],
				'has_ipv6' => (bool)$_POST['has_ipv6'],
				'vps_onboot' => (bool)$_POST['onboot'],
				'remote_console_server' => $_POST['remote_console_server'],
				'domain' => $_POST['domain']
			));
			
			notify_user(_("Changes saved"), _("Location label saved."));
			redirect('?page=cluster&action=locations');
			
		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			$xtpl->perex_format_errors(_('Location update failed'), $e->getResponse());
		}
		
		break;
		
	case "ip_addresses":
		ip_adress_list();
		$xtpl->sbar_add(_("Back"), '?page=cluster');
		$xtpl->sbar_add(_("Add IP addresses"), '?page=cluster&action=ipaddr_add');
		break;
	
	case "ipaddr_add":
		ip_add_form();
		break;
	
	case "ipaddr_add2":
		if (!$_POST['ip_addresses'])
			return;
		
		$addrs = preg_split("/(\r\n|\n|\r)/", trim($_POST['ip_addresses']));
		$res = array();
		$params = array(
			'addr' => $t,
			'location' => $_POST['location'],
		);
		
		if ($_POST['user'])
			$params['user'] = $_POST['user'];
		
		$failed = false;
		
		foreach ($addrs as $a) {
			$t = trim($a);
			
			if (!$t)
				continue;
			
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
				if (!$status)
					$str .= "$addr\n";
			}
			
			ip_add_form($str);
			
		} else {
			foreach ($res as $addr => $status) {
				if ($status)
					$str .= "Added $addr<br>\n";
			}
			
			notify_user(_('IP addresses added'), $str);
			redirect('?page=cluster&action=ip_addresses');
		}
		
		break;
		
	case "templates":
		$list_templates = true;
		break;
	
	case "templates_edit":
		if ($_SERVER['REQUEST_METHOD'] === 'POST') {
			csrf_check();
			
			try {
				$api->os_template->update($_GET['id'], array(
					'name' => $_POST['name'],
					'label' => $_POST['label'],
					'info' => $_POST['info'],
					'enabled' => isset($_POST['enabled']),
					'supported' => isset($_POST['supported']),
					'order' => $_POST['order']
				));
				
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
				$api->os_template->create(array(
					'name' => $_POST['name'],
					'label' => $_POST['label'],
					'info' => $_POST['info'],
					'enabled' => isset($_POST['enabled']),
					'supported' => isset($_POST['supported']),
					'order' => $_POST['order']
				));
				
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
			
			$xtpl->table_title(_('Confirm deletion of OS template').' '.$t->label);
			$xtpl->form_create('?page=cluster&action=templates_delete&id='.$t->id, 'post');
			$xtpl->form_add_checkbox(_('Confirm').':', 'confirm', '1', false);
			$xtpl->form_out(_("Delete"));
			
			$xtpl->sbar_add(_("Back"), '?page=cluster&action=templates');
		}
		break;
	
	case "configs":
		$xtpl->sbar_add(_("Back"), '?page=cluster');
		$list_configs = true;
		break;
	case "config_new":
		$xtpl->sbar_add(_("Back"), '?page=cluster&action=configs');
		$xtpl->title2(_("Create config"));
		$xtpl->table_add_category('');
		$xtpl->table_add_category('');
		$xtpl->form_create('?page=cluster&action=config_new_save', 'post');
		$xtpl->form_add_input(_('Name'), 'text', '30', 'name');
		$xtpl->form_add_input(_('Label'), 'text', '30', 'label');
		$xtpl->form_add_textarea(_('Config'), '60', '30', 'config');
		$xtpl->form_out(_('Save'));
		break;
	case "config_new_save":
		$xtpl->sbar_add(_("Back"), '?page=cluster');
		if (isset($_POST["config"])) {
			$cluster->save_config(NULL, $_POST["name"], $_POST["label"], $_POST["config"]);
			$xtpl->perex(_("Changes saved"), _("Config successfully saved."));
		}
		$list_configs = true;
		break;
	case "config_edit":
		if ($cfg = $db->findByColumnOnce("config", "id", $_GET["config"])) {
			$xtpl->title2(_("Edit config"));
			$xtpl->table_add_category('');
			$xtpl->table_add_category('');
			$xtpl->form_create('?page=cluster&action=config_edit_save&config='.$cfg["id"], 'post');
			$xtpl->form_add_input(_('Name').':', 'text', '30', 'name', $cfg["name"]);
			$xtpl->form_add_input(_('Label').':', 'text', '30', 'label', $cfg["label"]);
			$xtpl->form_add_textarea(_('Config').':', '60', '30', 'config', $cfg["config"]);
			$xtpl->form_add_checkbox(_("Reconfigure all affected VPSes").':', 'reapply', '1', '0');
			$xtpl->form_out(_('Save'));
		}
		
		$xtpl->sbar_add(_("Back"), '?page=cluster&action=configs');
		
		break;
	case "config_edit_save":
		if (isset($_POST["config"])) {
			$cluster->save_config($_GET["config"], $_POST["name"], $_POST["label"], $_POST["config"], $_POST["reapply"]);
			$xtpl->perex(_("Changes saved"), _("Config successfully saved."));
		}
		$list_configs = true;
		break;
	case "configs_regen":
		$cluster->regenerate_all_configs();
		
		$xtpl->perex(_("Regeneration scheduled"), _("Regeneration of all configs on all nodes scheduled."));
		break;
	
	case "newnode":
		$xtpl->title2(_("Register new server into cluster"));
		$xtpl->table_add_category('');
		$xtpl->table_add_category('');
		$xtpl->form_create('?page=cluster&action=newnode_save', 'post');
		$xtpl->form_add_input(_("ID").':', 'text', '8', 'server_id', '', '');
		$xtpl->form_add_input(_("Name").':', 'text', '30', 'server_name', '', '');
		$xtpl->form_add_select(_("Type").':', 'server_type', $server_types);
		$xtpl->form_add_select(_("Location").':', 'server_location', $cluster->list_locations(), '',  '');
		$xtpl->form_add_input(_("Server IPv4 address").':', 'text', '30', 'server_ip4', '', '');
		$xtpl->form_add_textarea(_("Availability icon (if you wish)").':', 28, 4, 'server_availstat', '', _("Paste HTML link here"));
		$xtpl->form_out(_("Save changes"));
		break;
	case "newnode_save":
		if (isset($_REQUEST["server_id"]) &&
			isset($_REQUEST["server_name"]) &&
			isset($_REQUEST["server_ip4"]) &&
			isset($_REQUEST["server_location"]) &&
			isset($_REQUEST["server_type"]) && in_array($_REQUEST["server_type"], array_keys($server_types))
		) {
			$sql = 'INSERT INTO servers
					SET server_id = "'.$db->check($_REQUEST["server_id"]).'",
					server_name = "'.$db->check($_REQUEST["server_name"]).'",
					server_type = "'.$db->check($_REQUEST["server_type"]).'",
					server_location = "'.$db->check($_REQUEST["server_location"]).'",
					server_availstat = "'.$db->check($_REQUEST["server_availstat"]).'",
					server_ip4 = "'.$db->check($_REQUEST["server_ip4"]).'"';
			$db->query($sql);
			$list_nodes = true;
		}
		break;
	case "node_edit":
		$node = new cluster_node($_GET["node_id"]);
		
		$xtpl->sbar_add(_("Back"), '?page=cluster');
		
		if ($node->exists) {
			$xtpl->title2(_("Edit node"));
			$xtpl->table_add_category('');
			$xtpl->table_add_category('');
			$xtpl->form_create('?page=cluster&action=node_edit_save&node_id='.$node->s["server_id"], 'post');
			$xtpl->form_add_input(_("Name").':', 'text', '30', 'server_name', $node->s["server_name"]);
			$xtpl->form_add_select(_("Type").':', 'server_type', $server_types, $node->s["server_type"]);
			$xtpl->form_add_select(_("Location").':', 'server_location', $cluster->list_locations(), $node->s["server_location"]);
			$xtpl->form_add_input(_("Server IPv4 address").':', 'text', '30', 'server_ip4', $node->s["server_ip4"]);
			$xtpl->form_add_textarea(_("Availability icon (if you wish)").':', 28, 4, 'server_availstat', $node->s["server_availstat"], _("Paste HTML link here"));
			
			switch ($node->s["server_type"]) {
				case "node":
					$xtpl->form_add_input(_("Max VPS count").':', 'text', '8', 'max_vps', $node->role["max_vps"]);
					$xtpl->form_add_input(_("Path to VE private").':', 'text', '30', 've_private', $node->role["ve_private"], _("%{veid} - VPS ID"));
					$xtpl->form_add_select(_("FS type").':', 'fstype', $NODE_FSTYPES, $node->role["fstype"]);
					break;
				default:break;
			}
			
			$xtpl->form_out(_("Save"));
			
			switch ($node->s["server_type"]) {
				case "storage":
					$xtpl->table_title(_("Export roots"));
					
					foreach($node->storage_roots as $root) {
						$q = nas_quota_to_val_unit($root["quota"]);
						
						$xtpl->table_add_category('');
						$xtpl->table_add_category('');
						$xtpl->form_create('?page=cluster&action=node_storage_root_save&node_id='.$node->s["server_id"].'&root_id='.$root["id"], 'post');
						$xtpl->form_add_input(_("Label").':', 'text', '30', 'storage_label', $root["label"]);
						$xtpl->form_add_input(_("Root dataset").':', 'text', '30', 'storage_root_dataset', $root["root_dataset"]);
						$xtpl->form_add_input(_("Root path").':', 'text', '30', 'storage_root_path', $root["root_path"]);
						$xtpl->form_add_select(_("Storage type").':', 'storage_type', $STORAGE_TYPES, $root["storage_layout"]);
						$xtpl->form_add_checkbox(_("User export").':', 'storage_user_export', '1', $root["user_export"], _("Can user manage exports?"));
						$xtpl->form_add_select(_("User mount").':', 'storage_user_mount', $STORAGE_MOUNT_MODES, $root["user_mount"]);
						$xtpl->table_td(_("Quota").':');
						$xtpl->form_add_input_pure('text', '30', 'quota_val', $q[0]);
						$xtpl->form_add_select_pure('quota_unit', $NAS_QUOTA_UNITS, $q[1]);
						$xtpl->table_tr();
						$xtpl->form_add_input(_("Share options").':', 'text', '30', 'share_options', $root["share_options"], _("Passed directly to zfs sharenfs"));
						$xtpl->form_out(_("Save"));
					}
					
					$xtpl->sbar_add(_("Add export root"), '?page=cluster&action=node_storage_root_add&node_id='.$node->s["server_id"]);
					break;
				default:break;
			}
		}
		break;
	case "node_edit_save":
		$node = new cluster_node($_GET["node_id"]);
		
		if ($node->exists) {
			$node->update_settings($_POST);
			$xtpl->perex(_("Settings updated"), _("Settings succesfully updated."));
		}
		
		$list_nodes = true;
		break;
	case "node_storage_root_add":
		$node = new cluster_node($_GET["node_id"]);
		
		if ($node->exists) {
			$xtpl->title2(_("Add export root"));
			$xtpl->table_add_category('');
			$xtpl->table_add_category('');
			$xtpl->form_create('?page=cluster&action=node_storage_root_save&node_id='.$node->s["server_id"], 'post');
			$xtpl->form_add_input(_("Label").':', 'text', '30', 'storage_label');
			$xtpl->form_add_input(_("Root dataset").':', 'text', '30', 'storage_root_dataset');
			$xtpl->form_add_input(_("Root path").':', 'text', '30', 'storage_root_path');
			$xtpl->form_add_select(_("Storage type").':', 'storage_type', $STORAGE_TYPES);
			$xtpl->form_add_checkbox(_("User export").':', 'storage_user_export', '1', '', _("Can user manage exports?"));
			$xtpl->form_add_select(_("User mount").':', 'storage_user_mount', $STORAGE_MOUNT_MODES);
			$xtpl->table_td(_("Quota").':');
			$xtpl->form_add_input_pure('text', '30', 'quota_val', $_POST["quota_val"] ? $_POST["quota_val"] : '0');
			$xtpl->form_add_select_pure('quota_unit', $NAS_QUOTA_UNITS, $_POST["quota_unit"]);
			$xtpl->table_tr();
			$xtpl->form_add_input(_("Share options").':', 'text', '30', 'share_options', $root["share_options"], _("Passed directly to zfs sharenfs"));
			$xtpl->form_out(_("Save"));
		}
		
		break;
	case "node_storage_root_save":
		$node = new cluster_node($_GET["node_id"]);
		
		if($node->exists && $_POST["storage_root_dataset"] && $_POST["storage_root_path"]) {
			if($_GET["root_id"]) {
				nas_root_update(
					$_GET["root_id"],
					$_POST["storage_label"],
					$_POST["storage_root_dataset"],
					$_POST["storage_root_path"],
					$_POST["storage_type"],
					$_POST["storage_user_export"],
					$_POST["storage_user_mount"],
					$_POST["quota_val"] * (2 << $NAS_UNITS_TR[$_POST["quota_unit"]]),
					$_POST["share_options"]
				);
			} else {
				nas_root_add(
					$_GET["node_id"],
					$_POST["storage_label"],
					$_POST["storage_root_dataset"],
					$_POST["storage_root_path"],
					$_POST["storage_type"],
					$_POST["storage_user_export"],
					$_POST["storage_user_mount"],
					$_POST["quota_val"] * (2 << $NAS_UNITS_TR[$_POST["quota_unit"]]),
					$_POST["share_options"]
				);
			}
			
			header('Location: ?page=cluster&action=node_edit&node_id='.$node->s["server_id"]);
		}
		break;
	case "fields":
		$xtpl->title2(_("Edit textfields"));
		$xtpl->table_add_category('');
		$xtpl->table_add_category('');
		$xtpl->form_create('?page=cluster&action=fields_save', 'post');
		$xtpl->form_add_input(_("Page title").':', 'text', '40', 'page_title', $cluster_cfg->get("page_title"), '');
		$xtpl->form_add_textarea(_("Text on sidebar").':', 50, 8, 'adminbox_content', $cluster_cfg->get("adminbox_content"), _("HTML"));
		$xtpl->form_add_textarea(_("Page Status infobox title").':', 50, 8, 'page_index_info_box_title', $cluster_cfg->get("page_index_info_box_title"), _("HTML"));
		$xtpl->form_add_textarea(_("Page Status infobox content").':', 50, 8, 'page_index_info_box_content', $cluster_cfg->get("page_index_info_box_content"), _("HTML"));
		$xtpl->form_out(_("Save changes"));
		break;
	case "fields_save":
		$cluster_cfg->set('page_title', $_REQUEST["page_title"]);
		$cluster_cfg->set('adminbox_content', $_REQUEST["adminbox_content"]);
		$cluster_cfg->set('page_index_info_box_title', $_REQUEST["page_index_info_box_title"]);
		$cluster_cfg->set('page_index_info_box_content', $_REQUEST["page_index_info_box_content"]);
		$list_nodes = true;
		break;
		
	case "mail_templates":
		list_mail_templates();
		break;
		
	case "mail_template_new":
		if (isset($_POST['name'])) {
			csrf_check();
			
			try {
				$input_params = $api->mail_template->create->getParameters('input');
				$params = array();
				
				foreach ($input_params as $name => $desc) {
					if ($_POST[$name])
						$params[$name] = $_POST[$name];
				}
				
				$api->mail_template->create($params);
				
				redirect('?page=cluster&action=mail_templates');
				notify_user(_('Template created'), '');
				
			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Mail template creation failed'), $e->getResponse());
				mail_template_new();
			}
			
		} else {
			mail_template_new();
		}
		break;
	
	case "mail_template_edit":
		if (isset($_POST['name'])) {
			csrf_check();
			
			try {
				$input_params = $api->mail_template->update->getParameters('input');
				$params = array();
				
				foreach ($input_params as $name => $desc) {
					if (isset($_POST[$name]))
						$params[$name] = $_POST[$name];
				}
				
				$api->mail_template($_GET['id'])->update($params);
				
				redirect('?page=cluster&action=mail_templates');
				notify_user(_('Template updated'), '');
				
			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Mail template update failed'), $e->getResponse());
				mail_template_edit();
			}
			
		} else {
			mail_template_edit();
		}
		break;
	
	case 'mail_template_destroy':
		if (isset($_POST['confirm']) && $_POST['confirm']) {
			csrf_check();
			
			try {
				$api->mail_template->delete($_GET['id']);
				
				notify_user(_('Mail template deleted'), '');
				redirect('?page=cluster&action=mail_templates');
				
			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Mail template deletion failed'), $e->getResponse());
			}
			
		} else {
			try {
				$t = $api->mail_template->find($_GET['id']);
				
				$xtpl->table_title(_('Confirm the deletion of mail template').' '.$t->name);
				$xtpl->form_create('?page=cluster&action=mail_template_destroy&id='.$t->id, 'post');
				
				$xtpl->table_td('<strong>'._('Please confirm the deletion of mail template').' '.$t->name, false, false, '2');
				$xtpl->table_tr();
				
				$xtpl->form_add_checkbox(_('Confirm').':', 'confirm', '1', false);
				
				$xtpl->form_out(_('Delete mail template'));
				
			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Mail template not found'), $e->getResponse());
			}
		}
		break;
		
	case "daily_reports":
		$xtpl->form_create('?page=cluster&action=daily_reports_save', 'post');
		$xtpl->form_add_input(_("Send to").':', 'text', '40', 'sendto', $cluster_cfg->get("mailer_daily_report_sendto"));
		$xtpl->form_out(_('Save changes'));
		
		$xtpl->sbar_add(_("Back"), '?page=cluster&action=mailer');
		break;
	case "daily_reports_save":
		$cluster_cfg->set("mailer_daily_report_sendto", $_POST["sendto"]);
		
		$list_mails = true;
		break;
	case "approval_requests":
		$xtpl->form_create('?page=cluster&action=approval_requests_save', 'post');
		$xtpl->form_add_input(_("Send to").':', 'text', '40', 'sendto', $cluster_cfg->get("mailer_requests_sendto"));
		
		$xtpl->form_add_input(_("Admin subject").':', 'text', '40', 'admin_sub', $cluster_cfg->get("mailer_requests_admin_sub"), '
								%request_id% - ID<br />
								%type% <br />
								%state% - approved/denied/ignored<br />
								%member_id% - id<br />
								%member% - nick
								');
		$xtpl->form_add_textarea(_("Admin mail").':', 50, 8, 'admin_text', $cluster_cfg->get("mailer_requests_admin_text"), '
								%created% - datetime<br />
								%changed_at% - datetime<br />
								%request_id%<br />
								%type% <br />
								%state% - approved/denied/ignored<br />
								%member_id% - id<br />
								%member% - nick<br />
								%admin_id% - admin id<br />
								%admin% - admin nick<br />
								%changed_info% - changed data<br />
								%reason%<br />
								%admin_response%<br />
								%ip%<br />
								%ptr%
								');
		
		$xtpl->form_add_input(_("Member subject").':', 'text', '40', 'member_sub', $cluster_cfg->get("mailer_requests_member_sub"), '
								%request_id% - ID<br />
								%state% - approved/denied<br />
								%member_id% - id<br />
								%member% - nick
								');
		$xtpl->form_add_textarea(_("Member mail").':', 50, 8, 'member_text', $cluster_cfg->get("mailer_requests_member_text"), '
								%request_id% - ID
								%state% - approved/denied<br />
								%member_id% - id<br />
								%member% - nick<br />
								%admin_id% - admin id<br />
								%admin% - admin nick<br />
								%admin_response%<br />
								');
		
		$xtpl->form_out(_('Save changes'));
		
		$xtpl->sbar_add(_("Back"), '?page=cluster&action=mailer');
		break;
	case "approval_requests_save":
		$cluster_cfg->set("mailer_requests_sendto", $_POST["sendto"]);
		
		$cluster_cfg->set("mailer_requests_admin_sub", $_POST["admin_sub"]);
		$cluster_cfg->set("mailer_requests_admin_text", $_POST["admin_text"]);
		
		$cluster_cfg->set("mailer_requests_member_sub", $_POST["member_sub"]);
		$cluster_cfg->set("mailer_requests_member_text", $_POST["member_text"]);
		
		$list_mails = true;
		break;

	case "integrity_check":
		integrity_check_list();
		break;

	case "integrity_objects":
		integrity_object_list();
		break;
	
	case "integrity_facts":
		integrity_fact_list();
		break;

	case "maintenance_lock":
		$xtpl->title("Maintenance lock");
		
		$xtpl->table_add_category('');
		$xtpl->table_add_category('');
		
		$xtpl->form_create('?page=cluster&action=set_maintenance_lock&lock=1&type='.$_GET['type'].'&obj_id='.$_GET['obj_id'], 'post');
		
		$ret = maintenance_lock_by_type();
		
		$xtpl->table_td(_('Set on').':');
		$xtpl->table_td($ret['label']);
		$xtpl->table_tr();
		
		$xtpl->form_add_input(_("Reason").':', 'text', '30', 'reason', '', _('optional'));
		
		$xtpl->form_out(_("Lock"));
		break;
		
	case "set_maintenance_lock":
		if (isset($_GET['type'])) {
			$ret = maintenance_lock_by_type();
			
			$r = $ret['resource'];
			$label = $ret['label'];
			
			if (!$r)
				$r = $api->{$_GET['type']}($_GET['obj_id']);
			
			try {
				$params = array('lock' => $_GET['lock'] ? true : false);
				
				if ($_GET['lock'])
					$params['reason'] = $_POST['reason'];
				
				$r->set_maintenance($params);
				
				notify_user($label.': '._('maintenance').' '.($_GET['lock'] ? _('ON') : _('OFF')));
				redirect('?page=cluster');
			
			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors($label.': '._('maintenance').' FAILED to set', $e->getResponse());
			}
			
		}
		break;
		
	case "payments_settings":
		$xtpl->title2("Manage Payment Settings");
		$xtpl->table_add_category('');
		$xtpl->table_add_category('');
		$xtpl->form_create('?page=cluster&action=payments_settings_save', 'post');
		$xtpl->form_add_checkbox(_("Payments management enabled").':', 'payments_enabled', '1', $cluster_cfg->get("payments_enabled"), $hint = '');
		$xtpl->form_out(_("Save changes"));
		$xtpl->sbar_add(_("Back"), '?page=cluster');
		break;
	case "payments_settings_save":
		$cluster_cfg->set("payments_enabled", $_REQUEST["payments_enabled"]);
		$xtpl->perex(_("Payments settings saved"), '');
		$list_nodes = true;
		break;
	case "noticeboard":
		$noticeboard = true;
		break;
	case "noticeboard_save":
		$cluster_cfg->set("noticeboard", $_POST["noticeboard"]);
		$xtpl->perex(_("Notice board saved"), '');
		$list_nodes = true;
		break;
	case "log_add":
		$noticeboard = true;
		if ($_POST["datetime"] && $_POST["msg"]) {
			log_add($_POST["datetime"], $_POST["msg"]);
			
			$xtpl->perex(_("Log message added"), _("Message successfully saved."));
		}
		break;
	case "log_edit":
		$log = $db->findByColumnOnce("log", "id", $_GET["id"]);
		
		$xtpl->form_create('?page=cluster&action=log_edit_save&id='.$log["id"], 'post');
		$xtpl->form_add_input(_("Date and time").':', 'text', '30', 'datetime', strftime("%Y-%m-%d %H:%M", $log["timestamp"]));
		$xtpl->form_add_textarea(_("Message").':', 80, 5, 'msg', $log["msg"]);
		$xtpl->form_out(_("Update"));
		
		break;
	case "log_edit_save":
		$noticeboard = true;
		
		if ($_GET["id"]) {
			log_save($_GET["id"], $_POST["datetime"], $_POST["msg"]);
			$xtpl->perex(_("Log message updated"), _("Message successfully updated."));
		}
		
		break;
	case "log_del":
		$noticeboard = true;
		
		log_del($_GET["id"]);
		
		$xtpl->perex(_("Log message deleted"), _("Message successfully deleted."));
		break;
	
	case "helpboxes":
		$helpbox = true;
		
		break;
	case "helpboxes_add":
		$helpbox = true;
		
		if (isset($_POST["help_page"])) {
			helpbox_add($_POST["help_page"], $_POST["help_action"], $_POST["help_content"]);
			
			$xtpl->perex(_("Help box added"), _("Help box successfully saved."));
		}
		
		break;
	case "helpboxes_edit":
		$help = $db->findByColumnOnce("helpbox", "id", $_GET["id"]);
		
		$xtpl->form_create('?page=cluster&action=helpboxes_edit_save&id='.$help["id"], 'post');
		$xtpl->form_add_input(_("Page").':', 'text', '30', 'help_page', $help["page"]);
		$xtpl->form_add_input(_("Action").':', 'text', '30', 'help_action', $help["action"]);
		$xtpl->form_add_textarea(_("Content").':', 80, 15, 'help_content', $help["content"]);
		$xtpl->form_out(_("Update"));
		
		break;
	case "helpboxes_edit_save":
		$helpbox = true;
		
		if ($_GET["id"]) {
			helpbox_save($_GET["id"], $_POST["help_page"], $_POST["help_action"], $_POST["help_content"]);
			
			$xtpl->perex(_("Help box updated"), _("Help box successfully updated."));
		}
		
		break;
	case "helpboxes_del":
		$helpbox = true;
		
		helpbox_del($_GET["id"]);
		
		$xtpl->perex(_("Help box deleted"), _("Help box successfully deleted."));
		
		break;
	
	default:
		$list_nodes = true;
}
if ($list_mails) {
	$xtpl->title2("Mailer");
	
	$xtpl->form_create('?page=cluster&action=mailer_save', 'post');
	$xtpl->form_add_input(_("Send mails from name").':', 'text', '40', 'from_name', $cluster_cfg->get("mailer_from_name"));
	$xtpl->form_add_input(_("Send mails from mail").':', 'text', '40', 'from_mail', $cluster_cfg->get("mailer_from_mail"));
	$xtpl->form_out(_("Save"));
	
	$xtpl->sbar_add(_("Mail templates"), '?page=cluster&action=mail_templates');
	$xtpl->sbar_add(_("Daily reports"), '?page=cluster&action=daily_reports');
	$xtpl->sbar_add(_("Approval requests"), '?page=cluster&action=approval_requests');
}
if ($list_nodes) {
	$xtpl->sbar_add(_("General settings"), '?page=cluster&action=general_settings');
	$xtpl->sbar_add(_("Register new node"), '?page=cluster&action=newnode');
	$xtpl->sbar_add(_("Manage OS templates"), '?page=cluster&action=templates');
	$xtpl->sbar_add(_("Manage configs"), '?page=cluster&action=configs');
	$xtpl->sbar_add(_("Manage IP addresses"), '?page=cluster&action=ip_addresses');
	$xtpl->sbar_add(_("Manage DNS servers"), '?page=cluster&action=dns');
	$xtpl->sbar_add(_("Manage environments"), '?page=cluster&action=environments');
	$xtpl->sbar_add(_("Manage locations"), '?page=cluster&action=locations');
	$xtpl->sbar_add(_("Mail templates"), '?page=cluster&action=mail_templates');
	$xtpl->sbar_add(_("Integrity check"), '?page=cluster&action=integrity_check');
	$xtpl->sbar_add(_("Manage Payments"), '?page=cluster&action=payments_settings');
	$xtpl->sbar_add(_("Notice board & log"), '?page=cluster&action=noticeboard');
	$xtpl->sbar_add(_("Help boxes"), '?page=cluster&action=helpboxes');
	$xtpl->sbar_add(_("Edit vpsAdmin textfields"), '?page=cluster&action=fields');
	
	$xtpl->table_title(_("Summary"));
	
	$stats = $api->cluster->full_stats();
	
	$xtpl->table_td(_("Nodes").':');
	$xtpl->table_td($stats["nodes_online"] .' '._("online").' / '. $stats["node_count"] .' '._("total"), $stats["nodes_online"] < $stats["node_count"] ? '#FFA500' : '#66FF66');
	$xtpl->table_tr();
	
	$xtpl->table_td(_("VPS").':');
	$xtpl->table_td($stats["vps_running"] .' '._("running").' / '. $stats["vps_stopped"] .' '._("stopped").' / '. $stats["vps_suspended"] .' '._("suspended").' / '.
					$stats["vps_deleted"] .' '._("deleted").' / '. $stats["vps_count"] .' '._("total"));
	$xtpl->table_tr();
	
	$xtpl->table_td(_("Members").':');
	$xtpl->table_td($stats["user_active"] .' '._("active").' / '. $stats["user_suspended"] .' '._("suspended")
	                .' / '. $stats["user_deleted"] .' '._("deleted").' / '. $stats["user_count"] .' '._("total"));
	$xtpl->table_tr();
	
	$xtpl->table_td(_("IPv4 addresses").':');
	$xtpl->table_td($stats["ipv4_used"] .' '._("used").' / '. $stats["ipv4_count"] .' '._("total"));
	$xtpl->table_tr();
	
	$xtpl->table_out();
	
	
	$xtpl->table_title(_("Node list"));
	$xtpl->table_add_category('');
	$xtpl->table_add_category('#');
	$xtpl->table_add_category(_("Name"));
	$xtpl->table_add_category(_("IP"));
	$xtpl->table_add_category(_("Load"));
	$xtpl->table_add_category(_("Up"));
	$xtpl->table_add_category(_("Down"));
	$xtpl->table_add_category(_("Del"));
	$xtpl->table_add_category(_("Sum"));
	$xtpl->table_add_category(_("Free"));
	$xtpl->table_add_category(_("Max"));
	$xtpl->table_add_category(_("Version"));
	$xtpl->table_add_category(_("Kernel"));
	$xtpl->table_add_category('<img title="'._("Toggle maintenance on node.").'" alt="'._("Toggle maintenance on node.").'" src="template/icons/maintenance_mode.png">');
	$xtpl->table_add_category(' ');
	
	foreach ($api->node->overview_list() as $node) {
		// Availability icon
		$icons = "";
		$maintenance_toggle = $node->maintenance_lock == 'lock' ? 0 : 1;
		
		if ((time() - strtotime($node->last_report)) > 150) {
			$icons .= '<img title="'._("The server is not responding").'" src="template/icons/error.png"/>';
		
		} else {
			$icons .= '<img title="'._("The server is online").'" src="template/icons/server_online.png"/>';
		}
		
		$icons = '<a href="?page=cluster&action='.($maintenance_toggle ? 'maintenance_lock' : 'set_maintenance_lock').'&type=node&obj_id='.$node->id.'&lock='.$maintenance_toggle.'">'.$icons.'</a>';
		
		$xtpl->table_td($icons, false, true);
		
		// Node ID, Name, IP, load
		$xtpl->table_td($node->id);
		$xtpl->table_td($node->name);
		$xtpl->table_td($node->ip_addr);
		$xtpl->table_td($node->loadavg, false, true);
		
		// Up, down, del, sum
		$xtpl->table_td($node->vps_running, false, true);
		$xtpl->table_td($node->vps_stopped, false, true);
		$xtpl->table_td($node->vps_deleted, false, true);
		$xtpl->table_td($node->vps_total, false, true);
		
		// Free, max
		$xtpl->table_td($node->vps_free, false, true);
		$xtpl->table_td($node->vps_max, false, true);
		
		// Daemon version
		$xtpl->table_td($node->version);
		
		// Kernel
		if(preg_match("/\d+stab.+/",$node->kernel, $matches))
			$xtpl->table_td($matches[0]);
		else
			$xtpl->table_td($node->kernel);
		
		$xtpl->table_td(maintenance_lock_icon('node', $node));
		$xtpl->table_td('<a href="?page=cluster&action=node_edit&node_id='.$node->id.'"><img src="template/icons/edit.png" title="'._("Edit").'"></a>');
		
		
		$xtpl->table_tr();
	}
	
	$xtpl->table_out('cluster_node_list');
	
}

if ($list_templates) {
	$xtpl->title2(_("Templates list"));
	$xtpl->table_add_category(_("Filename"));
	$xtpl->table_add_category(_("Label"));
	$xtpl->table_add_category(_("Uses"));
	$xtpl->table_add_category(_("Enabled"));
	$xtpl->table_add_category(_("Supported"));
	$xtpl->table_add_category(_("#"));
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	
	$templates = $api->os_template->list();
	
	foreach($templates as $t) {
		$usage = $api->vps->list(array(
			'os_template' => $t->id,
			'limit' => 0,
			'meta' => array('count' => true)
		))->getTotalCount();
		
		$xtpl->table_td($t->name);
		$xtpl->table_td($t->label);
		$xtpl->table_td($usage);
		$xtpl->table_td(boolean_icon($t->enabled));
		$xtpl->table_td(boolean_icon($t->supported));
		$xtpl->table_td($t->order);
		$xtpl->table_td('<a href="?page=cluster&action=templates_edit&id='.$t->id.'"><img src="template/icons/edit.png" title="'._("Edit").'"></a>');
		
		if ($usage > 0)
			$xtpl->table_td('<img src="template/icons/delete_grey.png" title="'._("Delete - N/A, template is in use").'">');
		else
			$xtpl->table_td('<a href="?page=cluster&action=templates_delete&id='.$t->id.'"><img src="template/icons/delete.png" title="'._("Delete").'"></a>');
		
		$xtpl->table_tr();
	}
	$xtpl->table_out();
	
	$xtpl->sbar_add(_("Back"), '?page=cluster');
	$xtpl->sbar_add(_("Register new template"), '?page=cluster&action=template_register');
}

if ($list_configs) {
	$xtpl->sbar_add(_("New config"), '?page=cluster&action=config_new');
	$xtpl->sbar_add(_("Regenerate all configs on all nodes"), '?page=cluster&action=configs_regen');
	
	$xtpl->title2(_("Configs"));
		
	$xtpl->table_add_category(_('Label'));
	$xtpl->table_add_category(_('Name'));
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	
	while($row = $db->find("config", NULL, "name")) {
		$xtpl->table_td($row["label"]);
		$xtpl->table_td($row["name"]);
		$xtpl->table_td('<a href="?page=cluster&action=config_edit&config='.$row["id"].'"><img src="template/icons/edit.png" title="'._("Edit").'"></a>');
		$xtpl->table_td('<a href="?page=cluster&action=config_delete&id='.$row["id"].'"><img src="template/icons/delete.png" title="'._("Delete").'"></a>');
		$xtpl->table_tr();
	}
	
	$xtpl->table_out();
}

if ($list_locations) {
	$xtpl->title2(_("Cluster locations list"));
	
	$xtpl->table_add_category(_("ID"));
	$xtpl->table_add_category(_("Location label"));
	$xtpl->table_add_category(_("Servers"));
	$xtpl->table_add_category(_("IPv6"));
	$xtpl->table_add_category(_("On Boot"));
	$xtpl->table_add_category(_("Domain"));
	$xtpl->table_add_category('<img title="'._("Toggle maintenance on node.").'" alt="'._("Toggle maintenance on node.").'" src="template/icons/maintenance_mode.png">');
	$xtpl->table_add_category('');
// 	$xtpl->table_add_category('');
	
	$locations = $api->location->list();
	
	foreach($locations as $loc) {
		$nodes = $api->node->list(array(
			'location' => $loc->id,
			'limit' => 0,
			'meta' => array('count' => true))
		);
		
		$xtpl->table_td($loc->id);
		$xtpl->table_td($loc->label);
		$xtpl->table_td($nodes->getTotalCount(), false, true);
		
		if ($loc->has_ipv6) {
			$xtpl->table_td('<img src="template/icons/transact_ok.png" />');
		} else {
			$xtpl->table_td('<img src="template/icons/transact_fail.png" />');
		}
		
		if ($loc->vps_onboot) {
			$xtpl->table_td('<img src="template/icons/transact_ok.png" />');
		} else {
			$xtpl->table_td('<img src="template/icons/transact_fail.png" />');
		}
		$xtpl->table_td($loc->domain);
		$xtpl->table_td(maintenance_lock_icon('location', $loc));
		$xtpl->table_td('<a href="?page=cluster&action=location_edit&id='.$loc->id.'"><img src="template/icons/edit.png" title="'._("Edit").'"></a>');
		
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
	
	$nameservers = $api->dns_resolver->list(array(
		'meta' => array('includes' => 'location')
	));
	
	foreach($nameservers as $ns) {
		$xtpl->table_td($ns->id);
		$xtpl->table_td($ns->ip_addr);
		$xtpl->table_td($ns->label);
		$xtpl->table_td(boolean_icon($ns->is_universal));
		$xtpl->table_td($ns->is_universal ? '---' : $ns->location->label);
		$xtpl->table_td('<a href="?page=cluster&action=dns_edit&id='.$ns->id.'"><img src="template/icons/edit.png" title="'._("Edit").'"></a>');
		$xtpl->table_td('<a href="?page=cluster&action=dns_delete&id='.$ns->id.'"><img src="template/icons/delete.png" title="'._("Delete").'"></a>');
		$xtpl->table_tr();
	}
	$xtpl->table_out();
	$xtpl->sbar_add(_("New DNS Server"), '?page=cluster&action=dns_new');
}

if ($env_settings) {
	$env = $api->environment->find($_GET['id']);
	
	$xtpl->title2(_("Manage environment").' '.$env->label);
	
	$xtpl->table_add_category($env->label);
	$xtpl->table_add_category('');
	
	$xtpl->form_create('?page=cluster&action=env_save&id='.$env->id, 'post');
	api_update_form($env);
	$xtpl->form_out(_('Save'));
	
	$all_configs = resource_list_to_options($api->vps_config->list());
	$options = "";
	$with_empty = array(0 => '---') + $all_configs;
	
	foreach($with_empty as $id => $label)
		$options .= '<option value="'.$id.'">'.$label.'</option>';
	
	$xtpl->assign('AJAX_SCRIPT', $xtpl->vars['AJAX_SCRIPT'] . '
	<script type="text/javascript">
		function dnd() {
			$("#configs").tableDnD({
				onDrop: function(table, row) {
					$("#configs_order").val($.tableDnD.serialize());
				}
			});
		}i
		
		$(document).ready(function() {
			var add_config_id = 1;
			
			dnd();
			
			$("#add_row").click(function (){
				$(\'<tr id="add_config_\' + add_config_id++ + \'"><td>'._('Add').':</td><td><select name="add_config[]">'.$options.'</select></td></tr>\').fadeIn("slow").insertBefore("#configs tr:nth-last-child(1)");
				dnd();
			});
			
			$(".delete-config").click(function (){
				$(this).closest("tr").remove();
			});
		});
    </script>');
	
	$chain = $env->config_chain->list();
	
	$xtpl->form_create('?page=cluster&action=env_chain_save&id='.$env->id, 'post');
	$xtpl->table_title($env->label.' '._("config chain"));
	$xtpl->table_add_category(_('Config'));
	$xtpl->table_add_category('');
	
	foreach($chain as $cfg) {
		$xtpl->form_add_select_pure('configs[]', $all_configs, $cfg->vps_config_id);
		$xtpl->table_td('<a href="javascript:" class="delete-config">'._('delete').'</a>');
		$xtpl->table_tr(false, false, false, "order_{$cfg->vps_config_id}");
	}
	
	$xtpl->table_td('<input type="hidden" name="configs_order" id="configs_order" value="">' .  _('Add').':');
	$xtpl->form_add_select_pure('add_config[]', $with_empty);
	$xtpl->table_tr(false, false, false, 'add_config');
	$xtpl->form_out(_("Save changes"), 'configs', '<a href="javascript:" id="add_row">+</a>');
}

if ($noticeboard) {
	$xtpl->table_title(_("Notice board"));
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	$xtpl->form_create('?page=cluster&action=noticeboard_save', 'post');
	$xtpl->form_add_textarea(_("Text").':', 80, 15, 'noticeboard', $cluster_cfg->get("noticeboard"));
	$xtpl->form_out(_("Save changes"));
	
	$xtpl->table_title(_("Log"));
	$xtpl->table_add_category('Add entry');
	$xtpl->table_add_category('');
	$xtpl->form_create('?page=cluster&action=log_add', 'post');
	$xtpl->form_add_input(_("Date and time").':', 'text', '30', 'datetime', strftime("%Y-%m-%d %H:%M"));
	$xtpl->form_add_textarea(_("Message").':', 80, 5, 'msg');
	$xtpl->form_out(_("Add"));
	
	$xtpl->table_add_category(_('Date and time'));
	$xtpl->table_add_category(_('Message'));
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	
	while($log = $db->find("log", NULL, "timestamp DESC")) {
		$xtpl->table_td(strftime("%Y-%m-%d %H:%M", $log["timestamp"]));
		$xtpl->table_td($log["msg"]);
		$xtpl->table_td('<a href="?page=cluster&action=log_edit&id='.$log["id"].'" title="'._("Edit").'"><img src="template/icons/edit.png" title="'._("Edit").'"></a>');
		$xtpl->table_td('<a href="?page=cluster&action=log_del&id='.$log["id"].'" title="'._("Delete").'"><img src="template/icons/delete.png" title="'._("Delete").'"></a>');
		$xtpl->table_tr();
	}
	
	$xtpl->table_out();
	
	$xtpl->sbar_add(_("Back"), '?page=cluster');
}

if ($helpbox) {
	$xtpl->table_title(_("Help boxes"));
	
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	$xtpl->form_create('?page=cluster&action=helpboxes_add', 'post');
	$xtpl->form_add_input(_("Page").':', 'text', '30', 'help_page', $_GET["help_page"]);
	$xtpl->form_add_input(_("Action").':', 'text', '30', 'help_action', $_GET["help_action"]);
	$xtpl->form_add_textarea(_("Content").':', 80, 15, 'help_content');
	$xtpl->form_out(_("Add"));
	
	$xtpl->table_add_category(_("Page"));
	$xtpl->table_add_category(_("Action"));
	$xtpl->table_add_category(_("Content"));
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	
	while ($help = $db->find("helpbox", NULL, "page ASC, action ASC")) {
		$xtpl->table_td($help["page"]);
		$xtpl->table_td($help["action"]);
		$xtpl->table_td($help["content"]);
		$xtpl->table_td('<a href="?page=cluster&action=helpboxes_edit&id='.$help["id"].'" title="'._("Edit").'"><img src="template/icons/edit.png" title="'._("Edit").'"></a>');
		$xtpl->table_td('<a href="?page=cluster&action=helpboxes_del&id='.$help["id"].'" title="'._("Delete").'"><img src="template/icons/delete.png" title="'._("Delete").'"></a>');
		$xtpl->table_tr();
	}
	
	$xtpl->table_out();
	
	$xtpl->sbar_add(_("Back"), '?page=cluster');
}

$xtpl->sbar_out(_("Manage Cluster"));

} else $xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
?>
