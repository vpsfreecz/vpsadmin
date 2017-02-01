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

$xtpl->title(_("Manage Cluster"));
$list_nodes = false;
$list_templates = false;

$server_types = array("node" => "Node", "storage" => "Storage", "mailer" => "Mailer");

switch($_GET["action"]) {
	case "vps":
		cluster_header();
		node_vps_overview();
		break;

	case "sysconfig":
		system_config_form();

		$xtpl->sbar_add(_("Back"), '?page=cluster');
		break;

	case "sysconfig_save":
		$current_cfg = new SystemConfig($api, true);
		$changes = array();

		foreach ($current_cfg as $k => $v) {
			list($cat, $name) = explode(':', $k);
			$type = $current_cfg->getType($cat, $name);

			if ($type === 'Boolean') {
				if ($v && !$_POST[$k]) {
					$changes[] = array($cat, $name, '0');
					
				} elseif (!$v && $_POST[$k]) {
					$changes[] = array($cat, $name, '1');
				}
			
			} elseif ($_POST[$k] != $v) {
				$changes[] = array($cat, $name, $_POST[$k]);
			}
		}

		$failed = array();

		foreach ($changes as $change) {
			try {
				$api->system_config->update($change[0], $change[1], array(
					'value' => $change[2],
				));

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$failed[] = $change[0].':'.$change[1];
			}
		}

		$config->reload();

		if (count($failed)) {
			$xtpl->perex(
				_("Some changes were saved"),
				_("The following options failed:").'<br>'.
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
		$xtpl->form_add_input(_("IP Address").':', 'text', '30', 'dns_ip', '', '');
		$xtpl->form_add_input(_("Label").':', 'text', '30', 'dns_label', '', _("DNS Label"));
		$xtpl->form_add_checkbox(_("Is this DNS location independent?").':', 'dns_is_universal', '1', false, '');
		$xtpl->form_add_select(_("Location").':', 'dns_location',
			resource_list_to_options($api->location->list()), '',  '');
		$xtpl->form_out(_("Save changes"));
		break;
		
	case "dns_new_save":
		try {
			$api->dns_resolver->create(array(
				'label' => $_POST['dns_label'],
				'ip_addr' => $_POST['dns_ip'],
				'is_universal' => isset($_POST['dns_is_universal']),
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
			resource_list_to_options($api->location->list()), $ns->location_id, '');
		$xtpl->form_out(_("Save changes"));
		
		break;
		
	case "dns_edit_save":
		csrf_check();
		
		try {
			$api->dns_resolver->update($_GET['id'], array(
				'label' => $_POST['dns_label'],
				'ip_addr' => $_POST['dns_ip'],
				'is_universal' => isset($_POST['dns_is_universal']),
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
			$xtpl->form_add_input(_("Remote console server").':', 'text', '30',	'remote_console_server', $loc->remote_console_server, _("URL"));
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

	case "networks":
		networks_list();
		$xtpl->sbar_add(_("Back"), '?page=cluster');
		break;

	case "ip_addresses":
		ip_address_list('cluster');
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
			'network' => $_POST['network'],
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
	
	case "ipaddr_edit":
		ip_edit_form($_GET['id']);
		break;

	case "ipaddr_edit2":
		csrf_check();

		try {
			$params = array(
				'max_tx' => $_POST['max_tx'] * 1024 * 1024 / 8,
				'max_rx' => $_POST['max_rx'] * 1024 * 1024 / 8,
				'user' => $_POST['user'] ? $_POST['user'] : null,
			);

			$ret = $api->ip_address($_GET['id'])->update($params);

			notify_user(_('Changes saved'), '');
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

		try {
			$api->vps_config->new(array(
				'name' => $_POST['name'],
				'label' => $_POST['label'],
				'config' => $_POST['config']
			));

			notify_user(_('Config saved'), '');
			redirect('?page=cluster&action=configs');

		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			$xtpl->perex_format_errors(_('Save failed'), $e->getResponse());
		}
		
		$list_configs = true;
		break;

	case "config_edit":
		try {
			$cfg = $api->vps_config->find($_GET['config']);

			$xtpl->title2(_("Edit config"));
			$xtpl->table_add_category('');
			$xtpl->table_add_category('');
			$xtpl->form_create('?page=cluster&action=config_edit_save&config='.$cfg->id, 'post');
			$xtpl->form_add_input(_('Name').':', 'text', '30', 'name', $cfg->name);
			$xtpl->form_add_input(_('Label').':', 'text', '30', 'label', $cfg->label);
			$xtpl->form_add_textarea(_('Config').':', '60', '30', 'config', $cfg->config);
			$xtpl->form_out(_('Save'));

		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			$xtpl->perex_format_errors(_('Fetch failed'), $e->getResponse());
		}
		
		$xtpl->sbar_add(_("Back"), '?page=cluster&action=configs');
		
		break;

	case "config_edit_save":
		try {
			$api->vps_config($_GET['config'])->update(array(
				'name' => $_POST['name'],
				'label' => $_POST['label'],
				'config' => $_POST['config']
			));

			notify_user(_('Config updated'), '');
			redirect('?page=cluster&action=configs');

		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			$xtpl->perex_format_errors(_('Update failed'), $e->getResponse());
		}

		$list_configs = true;
		break;
	
	case "newnode":
		node_create_form();
		break;

	case "newnode_save":
		try {
			$data = $_POST;

			$params = $api->node->create->getParameters('input');
			$data['type'] = $params->type->validators->include->values[ $_POST['type'] ];

			$api->node->create($data);
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
		try {
			$api->node->update($_GET['node_id'], $_POST);
			notify_user(_("Settings updated"), _("Settings succesfully updated."));
			redirect('?page=cluster');

		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			$xtpl->perex_format_errors('Update failed', $e->getResponse());
			node_update_form($_GET['node_id']);
		}
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
		
	case "eventlog":
		news_list_and_create_form();
		$xtpl->sbar_add(_("Back"), '?page=cluster');
		break;

	case "log_add":
		try {
			$api->news_log->create(array(
				'published_at' => date('c', strtotime($_POST['published_at'])),
				'message' => $_POST['message'],
			));
			
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
		try {
			$api->news_log->update($_GET['id'], array(
				'published_at' => date('c', strtotime($_POST['published_at'])),
				'message' => $_POST['message'],
			));
			
			notify_user(_("Log message updated"), _("Message successfully updated."));
			redirect('?page=cluster&action=eventlog');

		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			$xtpl->perex_format_errors(_('Create failed'), $e->getResponse());
			news_edit_form($_GET['id']);
		}
		break;

	case "log_del":
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
	
	$xtpl->title2(_("Configs"));
		
	$xtpl->table_add_category(_('Label'));
	$xtpl->table_add_category(_('Name'));
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	
	foreach ($api->vps_config->list() as $cfg) {
		$xtpl->table_td($cfg->label);
		$xtpl->table_td($cfg->name);
		$xtpl->table_td('<a href="?page=cluster&action=config_edit&config='.$cfg->id.'"><img src="template/icons/edit.png" title="'._("Edit").'"></a>');
		$xtpl->table_td('<a href="?page=cluster&action=config_delete&id='.$cfg->id.'"><img src="template/icons/delete.png" title="'._("Delete").'"></a>');
		$xtpl->table_tr();
	}
	
	$xtpl->table_out();
}

if ($list_locations) {
	$xtpl->title2(_("Cluster locations list"));
	
	$xtpl->table_add_category(_("ID"));
	$xtpl->table_add_category(_("Location label"));
	$xtpl->table_add_category(_("Environment"));
	$xtpl->table_add_category(_("Servers"));
	$xtpl->table_add_category(_("IPv6"));
	$xtpl->table_add_category(_("On Boot"));
	$xtpl->table_add_category(_("Domain"));
	$xtpl->table_add_category('<img title="'._("Toggle maintenance on node.").'" alt="'._("Toggle maintenance on node.").'" src="template/icons/maintenance_mode.png">');
	$xtpl->table_add_category('');
// 	$xtpl->table_add_category('');
	
	$locations = $api->location->list(array('meta' => array('includes' => 'environment')));
	
	foreach($locations as $loc) {
		$nodes = $api->node->list(array(
			'location' => $loc->id,
			'limit' => 0,
			'meta' => array('count' => true))
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

$xtpl->sbar_out(_("Manage Cluster"));

} else $xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
?>
