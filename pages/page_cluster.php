<?php
/*
	./pages/page_cluster.php

	vpsAdmin
	Web-admin interface for OpenVZ (see http://openvz.org)
	Copyright (C) 2008-2011 Pavel Snajdr, snajpa@snajpa.net
*/
if ($_SESSION["is_admin"]) {

$xtpl->title(_("Manage Cluster"));
$list_nodes = false;
$list_templates = false;

$server_types = array("node" => "Node", "storage" => "Storage", "mailer" => "Mailer");
$location_types = array("production" => "Production", "playground" => "Playground");

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
		$xtpl->form_add_select(_("Location").':', 'dns_location', $cluster->list_locations(), '',  '');
		$xtpl->form_out(_("Save changes"));
		break;
	case "dns_new_save":
		$cluster->set_dns_server(NULL, $_REQUEST["dns_ip"], $_REQUEST["dns_label"], $_REQUEST["dns_is_universal"], $_REQUEST["dns_location"]);
		$xtpl->perex(_("Changes saved"), _("DNS server added."));
		$list_dns = true;
		break;
	case "dns_edit":
		if ($item = $cluster->get_dns_server_by_id($_REQUEST["id"])) {
			$xtpl->title2(_("Edit DNS Server"));
			$xtpl->table_add_category('');
			$xtpl->table_add_category('');
			$xtpl->form_create('?page=cluster&action=dns_edit_save&id='.$_REQUEST["id"], 'post');
			$xtpl->form_add_input(_("IP Address").':', 'text', '30', 'dns_ip', $item["dns_ip"], '');
			$xtpl->form_add_input(_("Label").':', 'text', '30', 'dns_label', $item["dns_label"], _("DNS Label"));
			$xtpl->form_add_checkbox(_("Is this DNS location independent?").':', 'dns_is_universal', '1', $item["dns_is_universal"], '');
			$xtpl->form_add_select(_("Location").':', 'dns_location', $cluster->list_locations(), $item["dns_location"],  '');
			$xtpl->form_out(_("Save changes"));
		} else {
			$list_dns = true;
		}
		break;
	case "dns_edit_save":
		if ($item = $cluster->get_dns_server_by_id($_REQUEST["id"])) {
			$cluster->set_dns_server($_REQUEST["id"], $_REQUEST["dns_ip"], $_REQUEST["dns_label"], $_REQUEST["dns_is_universal"], $_REQUEST["dns_location"]);
			$xtpl->perex(_("Changes saved"), _("DNS server saved."));
			$list_dns = true;
		} else {
			$list_dns = true;
		}
		break;
	case "dns_delete":
		if ($item = $cluster->get_dns_server_by_id($_REQUEST["id"])) {
			$cluster->delete_dns_server($_REQUEST["id"]);
			$xtpl->perex(_("Item deleted"), _("DNS Server deleted."));
		}
		$list_locations = true;
		break;
	case "locations":
		$list_locations = true;
		break;
	case "location_delete":
		if ($item = $cluster->get_location_by_id($_REQUEST["id"])) {
			if ($cluster->get_server_count_in_location($item["location_id"]) <= 0) {
			$cluster->delete_location($_REQUEST["id"]);
			$xtpl->perex(_("Item deleted"), _("Location deleted."));
			}
		}
		$list_locations = true;
		break;
	case "location_new":
		$xtpl->title2(_("New cluster location"));
		$xtpl->table_add_category('');
		$xtpl->table_add_category('');
		$xtpl->form_create('?page=cluster&action=location_new_save', 'post');
		$xtpl->form_add_input(_("Label").':', 'text', '30', 'location_label', '', _("Location name"));
		$xtpl->form_add_select(_("Type").':', 'type', $location_types, '', '');
		$xtpl->form_add_checkbox(_("Has this location IPv6 support?").':', 'has_ipv6', '1', false, '');
		$xtpl->form_add_checkbox(_("Run VPSes here on boot?").':', 'onboot', '1', '1', '');
		$xtpl->form_add_input(_("Remote console server").':', 'text', '30',	'remote_console_server',	'', _("URL"));
		$xtpl->form_add_input(_("Domain").':', 'text', '30',	'domain',	$item["domain"], '');
		$xtpl->form_out(_("Save changes"));
		break;
	case "location_new_save":
		$cluster->set_location(NULL, $_REQUEST["location_label"], $_REQUEST["type"], $_REQUEST["has_ipv6"],
							$_REQUEST["onboot"], $_REQUEST["remote_console_server"], $_REQUEST["domain"]);
		$xtpl->perex(_("Changes saved"), _("Location added."));
		$list_locations = true;
		break;
	case "location_edit":
		if ($item = $cluster->get_location_by_id($_REQUEST["id"])) {
			$xtpl->title2(_("Edit location"));
			$xtpl->table_add_category('');
			$xtpl->table_add_category('');
			$xtpl->form_create('?page=cluster&action=location_edit_save&id='.$_REQUEST["id"], 'post');
			$xtpl->form_add_input(_("Label").':', 'text', '30', 'location_label', $item["location_label"], _("Location name"));
			$xtpl->form_add_select(_("Type").':', 'type', $location_types, $item["location_type"], '');
			$xtpl->form_add_checkbox(_("Has this location IPv6 support?").':', 'has_ipv6', '1', $item["location_has_ipv6"], '');
			$xtpl->form_add_checkbox(_("Run VPSes here on boot?").':', 'onboot', '1', $item["location_vps_onboot"], '');
			$xtpl->form_add_input(_("Remote console server").':', 'text', '30',	'remote_console_server',	$item["location_remote_console_server"], _("URL"));
			$xtpl->form_add_input(_("Domain").':', 'text', '30',	'domain',	$item["domain"], '');
			$xtpl->form_out(_("Save changes"));
		} else {
			$list_ramlimits = true;
		}
		break;
	case "location_edit_save":
		if ($item = $cluster->get_location_by_id($_REQUEST["id"])) {
			$cluster->set_location($_REQUEST["id"], $_REQUEST["location_label"], $_REQUEST["type"], $_REQUEST["has_ipv6"],
							$_REQUEST["onboot"], $_REQUEST["remote_console_server"], $_REQUEST["domain"]);
			$xtpl->perex(_("Changes saved"), _("Location label saved."));
			$list_locations = true;
		} else {
			$list_locations = true;
		}
		break;
	case "ipv4addr":
		$Cluster_ipv4->table_used_out(_("Used IP addresses"), true);
		$Cluster_ipv4->table_unused_out(_("Unused IP addresses"), true);
		$xtpl->sbar_add(_("Back"), '?page=cluster');
		$xtpl->sbar_add(_("Add IPv4"), '?page=cluster&action=ipaddr_add&v=4');
		break;
	case "ipv6addr":
		$Cluster_ipv6->table_used_out(_("Used IP addresses"), true);
		$Cluster_ipv6->table_unused_out(_("Unused IP addresses"), true);
		$xtpl->sbar_add(_("Back"), '?page=cluster');
		$xtpl->sbar_add(_("Add IPv6"), '?page=cluster&action=ipaddr_add&v=6');
		break;
	case "ipaddr_delete":
		if (!isset($_REQUEST['vps_id']))
			$_REQUEST['vps_id'] = -1;
		if ($_REQUEST['v']==4)
			$res = $Cluster_ipv4->delete($_REQUEST['ip_id']*1, $_REQUEST['vps_id']*1);
		elseif ($_REQUEST['v']==6)
			$res = $Cluster_ipv6->delete($_REQUEST['ip_id']*1, $_REQUEST['vps_id']*1);
		if ($res==null)
			$xtpl->perex(_("Operation not succesful"), _("An error has occured, while you were trying to delete IP"));
		else
			$xtpl->perex(_("Operation succesful"), _("IP address has been successfully deleted."));
		break;
	case "ipaddr_remove":
		if (isset($_REQUEST['vps_id']) && isset($_REQUEST['ip_id'])) {
			if ($_REQUEST['v']==4)
			$Cluster_ipv4->remove_from_vps($_REQUEST['ip_id']*1, $_REQUEST['vps_id']*1);
			elseif ($_REQUEST['v']==6)
			$Cluster_ipv6->remove_from_vps($_REQUEST['ip_id']*1, $_REQUEST['vps_id']*1);
		}
		break;
	case "ipaddr_add":
		if ($_REQUEST['v']==4)
			$Cluster_ipv4->table_add_1();
		elseif ($_REQUEST['v']==6)
			$Cluster_ipv6->table_add_1();
		break;
	case "ipaddr_add2":
		if (isset($_REQUEST['m_ip']) && isset($_REQUEST["m_location"])) {
			if ($_REQUEST['v']==4)
			$Cluster_ipv4->table_add_2($_REQUEST['m_ip'], $_REQUEST['m_location']);
			elseif ($_REQUEST['v']==6)
			$Cluster_ipv6->table_add_2($_REQUEST['m_ip'], $_REQUEST['m_location']);
		if ($_REQUEST['v']==4)
			$Cluster_ipv4->table_add_1($_REQUEST['m_ip'], $_REQUEST['m_location']);
		elseif ($_REQUEST['v']==6)
			$Cluster_ipv6->table_add_1($_REQUEST['m_ip'], $_REQUEST['m_location']);
		}
		break;
	case "templates":
		$list_templates = true;
		break;
	case "templates_edit":
		if ($template = $cluster->get_template_by_id($_REQUEST["id"])) {
			$xtpl->title2(_("Edit template"));
			$xtpl->table_add_category('');
			$xtpl->table_add_category('');
			$xtpl->form_create('?page=cluster&action=templates_edit_save&id='.$_REQUEST["id"], 'post');
			$xtpl->form_add_input(_("Filename").':', 'text', '40', 'templ_name', $template["templ_name"], _("filename without .tar.gz"));
			$xtpl->form_add_input(_("Label").':', 'text', '30', 'templ_label', $template["templ_label"], _("User friendly label"));
			$xtpl->form_add_textarea(_("Info").':', 28, 4, 'templ_info', $template["templ_info"], _("Note for administrators"));
			$xtpl->form_add_checkbox(_("Enabled").':', 'templ_enabled', 1, $template["templ_enabled"]);
			$xtpl->form_add_checkbox(_("Supported").':', 'templ_supported', 1, $template["templ_supported"]);
			$xtpl->form_add_input(_("Order").':', 'text', '30', 'templ_order', $template["templ_order"]);
			$xtpl->form_out(_("Save changes"));
		} else {
			$list_templates = true;
		}
		break;
	case "templates_edit_save":
		if ($template = $cluster->get_template_by_id($_REQUEST["id"])) {
			if (ereg('^[a-zA-Z0-9_\.\-]{1,63}$',$_REQUEST["templ_name"])) {
			$cluster->set_template($_REQUEST["id"], $_REQUEST["templ_name"], $_REQUEST["templ_label"], $_REQUEST["templ_info"], $_REQUEST["templ_enabled"], $_REQUEST["templ_supported"], $_REQUEST["templ_order"]);
			$xtpl->perex(_("Changes saved"), _("Changes you've made to template were saved."));
			$list_templates = true;
			} else $list_templates = true;
		} else {
			$list_templates = true;
		}
		break;
	case "template_register":
	$xtpl->title2(_("Register new template"));
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	$xtpl->form_create('?page=cluster&action=template_register_save', 'post');
	$xtpl->form_add_input(_("Filename").':', 'text', '40', 'templ_name', '', _("filename without .tar.gz"));
	$xtpl->form_add_input(_("Label").':', 'text', '30', 'templ_label', '', _("User friendly label"));
	$xtpl->form_add_textarea(_("Info").':', 28, 4, 'templ_info', '', _("Note for administrators"));
	$xtpl->form_add_checkbox(_("Enabled").':', 'templ_enabled', 1, 1);
	$xtpl->form_add_checkbox(_("Supported").':', 'templ_supported', 1, 1);
	$xtpl->form_add_input(_("Order").':', 'text', '30', 'templ_order', "1");
	$xtpl->form_out(_("Save changes"));
	$xtpl->helpbox(_("Help"), _("This procedure only <b>registers template</b> into the system database.
					 You need copy the template to proper path onto one of servers
					 and then proceed \"Copy template over nodes\" function.
					"));
	break;
	case "template_register_save":
		if (ereg('^[a-zA-Z0-9_\.\-]{1,63}$',$_REQUEST["templ_name"])) {
			$cluster->set_template(NULL, $_REQUEST["templ_name"], $_REQUEST["templ_label"], $_REQUEST["templ_info"], $_REQUEST["templ_enabled"], $_REQUEST["templ_supported"], $_REQUEST["templ_order"]);
			$xtpl->perex(_("Changes saved"), _("Template successfully registered."));
			$list_templates = true;
		} else {
			$list_templates = true;
		}
		break;
	case "templates_copy_over_nodes":
		if ($template = $cluster->get_template_by_id($_REQUEST["id"])) {
			$xtpl->title2(_("Copy template over cluster nodes"));
			$xtpl->table_add_category('');
			$xtpl->table_add_category('');
			$xtpl->form_create('?page=cluster&action=templates_copy_over_nodes2&id='.$_REQUEST["id"], 'post');
			$xtpl->form_add_select(_("Source node").':', 'source_node', $cluster->list_servers(), '', '');
			$xtpl->form_out(_("Copy template"));
			$xtpl->helpbox(_("Help"), _("This procedure takes template file from source server and copies it using 'scp'
						over all nodes of cluster. This may take large amount of I/O resources,
						therefore it is recommended to use it only when cluster is not under full load.
						"));
		} else {
			$list_templates = true;
		}
		break;
	case "templates_copy_over_nodes2":
		if ($template = $cluster->get_template_by_id($_REQUEST["id"])) {
			if ($source_node = new cluster_node($_GET["source_node"])) {
			$cluster->copy_template_to_all_nodes($_REQUEST["id"], $_REQUEST["source_node"]);
			$xtpl->perex(_("Template copy added to transactions log"), $template["templ_name"]);
			$list_templates = true;
			}
		} else {
			$list_templates = true;
		}
		break;
	case "templates_delete":
		if ($template = $cluster->get_template_by_id($_REQUEST["id"])) {
			$xtpl->perex(_("Are you sure to delete template").' '.$template["templ_name"].'?',
				'<a href="?page=cluster&action=templates">'._("No").'</a> | '.
				'<a href="?page=cluster&action=templates_delete2&id='.$template["templ_id"].'">'._("Yes").'</a>');
		}
		break;
	case "templates_delete2":
		if ($template = $cluster->get_template_by_id($_REQUEST["id"])) {
			$usage = $cluster->get_template_usage($template["templ_id"]);
			if ($usage <= 0) {
			$nodes_instances = $cluster->list_servers_class();
			foreach ($nodes_instances as $node) {
				$params = array();
				$params["templ_id"] = $_REQUEST["id"];
				add_transaction($_SESSION["member"]["m_id"], $node->s["server_id"], 0, T_CLUSTER_TEMPLATE_DELETE, $params);
			}
			} else {
			$list_templates = true;
			}
		} else {
			$list_templates = true;
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
	case "configs_default_save":
		$xtpl->sbar_add(_("Back"), '?page=cluster');
		
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
			$cluster->save_default_configs($_POST["configs"] ? $_POST["configs"] : array(), $cfgs, $_POST["add_config"], "default_config_chain");
			
			$list_configs=true;
		} else {
			$xtpl->perex(_("Error"), 'Error, contact your administrator');
			$list_configs=true;
		}
		
		break;
	case "configs_regen":
		$cluster->regenerate_all_configs();
		
		$xtpl->perex(_("Regeneration scheduled"), _("Regeneration of all configs on all nodes scheduled."));
		break;
	case "node_toggle_maintenance":
		$node = new cluster_node($_GET["node_id"]);
		$node->toggle_maintenance();
		
		notify_user($node->s["server_name"].': '._('maintenance').' '.($node->is_under_maintenance() ? _('ON') : _('OFF')));
		redirect('?page=cluster');
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
	case "mailer":
		$list_mails = true;
		break;
	case "mailer_save":
		$cluster_cfg->set("mailer_from_name", $_POST["from_name"]);
		$cluster_cfg->set("mailer_from_mail", $_POST["from_mail"]);
		break;
	case "mail_templates":
		$xtpl->title2("Manage Mail Templates");
		$xtpl->table_add_category('');
		$xtpl->table_add_category('');
		$xtpl->form_create('?page=cluster&action=mail_templates_save', 'post');
		
		// Mailer settings
		$xtpl->form_add_checkbox(_("Mailer enabled").':', 'mailer_enabled', '1', $cluster_cfg->get("mailer_enabled"), $hint = '');
		$xtpl->form_add_checkbox(_("Admins in CC").':', 'admins_in_cc', '1', $cluster_cfg->get("mailer_admins_in_cc"), $hint = '');
		$xtpl->form_add_input(_("Admins in CC (mails)").':', 'text', '40', 'admin_mails', $cluster_cfg->get("mailer_admins_cc_mails"), '');
		$xtpl->form_add_input(_("Mails sent from").':', 'text', '40', 'mail_from', $cluster_cfg->get("mailer_from"), '');
		
		// Payment warning
		$xtpl->form_add_input(_("Payment warning subject").':', 'text', '40', 'tpl_payment_warning_subj', $cluster_cfg->get("mailer_tpl_payment_warning_subj"), '%member% - nick');
		$xtpl->form_add_textarea(_("Payment warning<br /> template").':', 50, 8, 'tpl_payment_warning', $cluster_cfg->get("mailer_tpl_payment_warning"), '
								%member% - nick<br />
								%memberid% - member id<br />
								%expiredate% - payment expiration date<br />
								%monthly% - monthly payment<br />
								');
		
		// Member add
		$xtpl->form_add_input(_("Member added subject").':', 'text', '40', 'tpl_member_added_subj', $cluster_cfg->get("mailer_tpl_member_added_subj"), '%member% - nick');
		$xtpl->form_add_textarea(_("Member added<br /> template").':', 50, 8, 'tpl_member_added', $cluster_cfg->get("mailer_tpl_member_added"), '
								%member% - nick<br />
								%memberid% - member id<br />
								%pass% - password<br />
								');
		
		// Suspend account
		$xtpl->form_add_input(_("Suspend subject").':', 'text', '40', 'tpl_suspend_account_subj', $cluster_cfg->get("mailer_tpl_suspend_account_subj"), '%member% - nick');
		$xtpl->form_add_textarea(_("Suspend<br />account").':', 50, 8, 'tpl_suspend_account', $cluster_cfg->get("mailer_tpl_suspend_account"), '
								%member% - nick<br />
								%reason% - suspend reason');
		
		// Restore account
		$xtpl->form_add_input(_("Restore subject").':', 'text', '40', 'tpl_restore_account_subj', $cluster_cfg->get("mailer_tpl_restore_account_subj"), '%member% - nick');
		$xtpl->form_add_textarea(_("Restore<br />account").':', 50, 8, 'tpl_restore_account', $cluster_cfg->get("mailer_tpl_restore_account"), '
								%member% - nick');
		
		// Delete member
		$xtpl->form_add_input(_("Delete member subject").':', 'text', '40', 'tpl_delete_member_subj', $cluster_cfg->get("mailer_tpl_delete_member_subj"), '%member% - nick');
		$xtpl->form_add_textarea(_("Delete<br />member").':', 50, 8, 'tpl_delete_member', $cluster_cfg->get("mailer_tpl_delete_member"), '
								%member% - nick');
		
		// Configs changed
		$xtpl->form_add_input(_("Limits change subject").':', 'text', '40', 'tpl_limits_change_subj', $cluster_cfg->get("mailer_tpl_limits_change_subj"), '%member% - nick<br />%vpsid% = VPS ID');
		$xtpl->form_add_textarea(_("Limits changed<br /> template").':', 50, 8, 'tpl_limits_changed', $cluster_cfg->get("mailer_tpl_limits_changed"), '
								%member% - nick<br />
								%vpsid% - VPS ID<br />
								%reason% - reason<br />
								%configs% - List of configs
								');
		
		// Backuper changed
		$xtpl->form_add_input(_("Backuper change subject").':', 'text', '40', 'tpl_backuper_change_subj', $cluster_cfg->get("mailer_tpl_backuper_change_subj"), '%member% - nick<br />%vpsid% = VPS ID');
		$xtpl->form_add_textarea(_("Backuper changed<br /> template").':', 50, 8, 'tpl_backuper_changed', $cluster_cfg->get("mailer_tpl_backuper_changed"), '
								%member% - nick<br />
								%vpsid% - VPS ID<br />
								%backuper% - State
								');
		
		// Nonpayers
		$xtpl->form_add_input(_("Send nonpayers info to").':', 'text', '40', 'nonpayers_mail', $cluster_cfg->get("mailer_nonpayers_mail"), '');
		$xtpl->form_add_input(_("Nonpayer subject").':', 'text', '40', 'tpl_nonpayers_subj', $cluster_cfg->get("mailer_tpl_nonpayers_subj"), '');
		$xtpl->form_add_textarea(_("Nonpayer text<br /> template").':', 50, 8, 'tpl_nonpayers', $cluster_cfg->get("mailer_tpl_nonpayers"), '
								%never_paid% - list of members who have never paid before<br />
								%nonpayers% - list of nonpayers
								');
		
		// Backup download notification
		$xtpl->form_add_input(_("Download backup subject").':', 'text', '40', 'tpl_dl_backup_subj', $cluster_cfg->get("mailer_tpl_dl_backup_subj"), '%member% - nick<br />%vpsid% - VPS ID');
		$xtpl->form_add_textarea(_("Download backup<br /> template").':', 50, 8, 'tpl_dl_backup', $cluster_cfg->get("mailer_tpl_dl_backup"), '
								%member% - nick<br />
								%vpsid% - VPS ID<br />
								%url% - download link<br />
								%datetime% - date and time of backup
								');
		
		// VPS expiration
		$xtpl->form_add_input(_("VPS expiration subject").':', 'text', '40', 'tpl_vps_expiration_subj', $cluster_cfg->get("mailer_tpl_vps_expiration_subj"), '%member% - nick<br />%vpsid% - VPS ID');
		$xtpl->form_add_textarea(_("VPS expiration<br /> template").':', 50, 8, 'tpl_vps_expiration', $cluster_cfg->get("mailer_tpl_vps_expiration"), '
								%member% - nick<br />
								%vpsid% - VPS ID<br />
								%datetime% - date and time of expiration
								');
		
		$xtpl->form_out(_("Save changes"));
		$xtpl->sbar_add(_("Back"), '?page=cluster&action=mailer');
		break;
	case "mail_templates_save":
		$cluster_cfg->set("mailer_enabled", $_REQUEST["mailer_enabled"]);
		$cluster_cfg->set("mailer_admins_in_cc", $_REQUEST["admins_in_cc"]);
		$cluster_cfg->set("mailer_admins_cc_mails", $_REQUEST["admin_mails"]);
		$cluster_cfg->set("mailer_from", $_REQUEST["mail_from"]);
		
		$cluster_cfg->set("mailer_tpl_payment_warning_subj", $_REQUEST["tpl_payment_warning_subj"]);
		$cluster_cfg->set("mailer_tpl_payment_warning", $_REQUEST["tpl_payment_warning"]);
		
		$cluster_cfg->set("mailer_tpl_member_added_subj", $_REQUEST["tpl_member_added_subj"]);
		$cluster_cfg->set("mailer_tpl_member_added", $_REQUEST["tpl_member_added"]);
		
		$cluster_cfg->set("mailer_tpl_suspend_account_subj", $_REQUEST["tpl_suspend_account_subj"]);
		$cluster_cfg->set("mailer_tpl_suspend_account", $_REQUEST["tpl_suspend_account"]);
		
		$cluster_cfg->set("mailer_tpl_restore_account_subj", $_REQUEST["tpl_restore_account_subj"]);
		$cluster_cfg->set("mailer_tpl_restore_account", $_REQUEST["tpl_restore_account"]);
		
		$cluster_cfg->set("mailer_tpl_delete_member_subj", $_REQUEST["tpl_delete_member_subj"]);
		$cluster_cfg->set("mailer_tpl_delete_member", $_REQUEST["tpl_delete_member"]);
		
		$cluster_cfg->set("mailer_tpl_limits_change_subj", $_REQUEST["tpl_limits_change_subj"]);
		$cluster_cfg->set("mailer_tpl_limits_changed", $_REQUEST["tpl_limits_changed"]);
		
		$cluster_cfg->set("mailer_tpl_backuper_change_subj", $_REQUEST["tpl_backuper_change_subj"]);
		$cluster_cfg->set("mailer_tpl_backuper_changed", $_REQUEST["tpl_backuper_changed"]);
		
		$cluster_cfg->set("mailer_nonpayers_mail", $_REQUEST["nonpayers_mail"]);
		$cluster_cfg->set("mailer_tpl_nonpayers_subj", $_REQUEST["tpl_nonpayers_subj"]);
		$cluster_cfg->set("mailer_tpl_nonpayers", $_REQUEST["tpl_nonpayers"]);
		
		$cluster_cfg->set("mailer_tpl_dl_backup_subj", $_REQUEST["tpl_dl_backup_subj"]);
		$cluster_cfg->set("mailer_tpl_dl_backup", $_REQUEST["tpl_dl_backup"]);
		
		$cluster_cfg->set("mailer_tpl_vps_expiration_subj", $_REQUEST["tpl_vps_expiration_subj"]);
		$cluster_cfg->set("mailer_tpl_vps_expiration", $_REQUEST["tpl_vps_expiration"]);
		
		$list_mails = true;
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
	case "freelock":
		$xtpl->perex(_("Are you sure to delete this lock?"), '<a href="?page=">'.strtoupper(_("No")).'</a> | <a href="?page=cluster&action=freelock2&lock=backuper&id='.$_GET["id"].'">'.strtoupper(_("Yes")).'</a>');
		$list_nodes = true;
		break;
	case "freelock2":
		if (($_GET["lock"] == "backuper") && isset($_GET["id"])) {
			if ($cluster_cfg->get("lock_cron_backup_".$_GET["id"])) {
				$cluster_cfg->set("lock_cron_backup_".$_GET["id"], false);
				$xtpl->perex(_("Lock has been deleted"), '');
				$xtpl->delayed_redirect('?page=', 350);
			}
		}
		break;
	case "maintenance_toggle":
		if ($cluster_cfg->get("maintenance_mode")) {
			$cluster_cfg->set("maintenance_mode", false);
			$xtpl->perex(_("Maintenance mode status: OFF"), '');
		} else {
			$cluster_cfg->set("maintenance_mode", true);
			$xtpl->perex(_("Maintenance mode status: ON"), '');
		}
		$list_nodes = true;
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
	case "playground_settings":
		$xtpl->sbar_add(_("Back"), '?page=cluster');
		$playground_settings=true;
		break;
	case "playground_settings_save":
		$xtpl->perex(_("Playground settings saved"), '');
		
		$cluster_cfg->set("playground_enabled", (bool)$_POST["enabled"]);
		$cluster_cfg->set("playground_backup", (bool)$_POST["backup"]);
		$cluster_cfg->set("playground_vps_lifetime", (int)$_POST["lifetime"]);
		
		$playground_settings = true;
		break;
	case "playground_configs_default_save":
		$xtpl->sbar_add(_("Back"), '?page=cluster');
		
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
			$cluster->save_default_configs($_POST["configs"] ? $_POST["configs"] : array(), $cfgs, $_POST["add_config"], "playground_default_config_chain");
			
			$playground_settings=true;
		} else {
			$xtpl->perex(_("Error"), 'Error, contact your administrator');
			$playground_settings=true;
		}
		
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
	$xtpl->sbar_add(_("Manage VPS templates"), '?page=cluster&action=templates');
	$xtpl->sbar_add(_("Manage configs"), '?page=cluster&action=configs');
	$xtpl->sbar_add(_("Manage IPv4 address list"), '?page=cluster&action=ipv4addr');
	$xtpl->sbar_add(_("Manage IPv6 address list"), '?page=cluster&action=ipv6addr');
	$xtpl->sbar_add(_("Manage DNS servers"), '?page=cluster&action=dns');
	$xtpl->sbar_add(_("Manage locations"), '?page=cluster&action=locations');
	$xtpl->sbar_add(_("Manage Mailer"), '?page=cluster&action=mailer');
	$xtpl->sbar_add(_("Manage Payments"), '?page=cluster&action=payments_settings');
	$xtpl->sbar_add(_("Manage playground"), '?page=cluster&action=playground_settings');
	$xtpl->sbar_add(_("Notice board & log"), '?page=cluster&action=noticeboard');
	$xtpl->sbar_add(_("Help boxes"), '?page=cluster&action=helpboxes');
	$xtpl->sbar_add(_("Edit vpsAdmin textfields"), '?page=cluster&action=fields');
	
	$xtpl->table_title(_("Summary"));
	
	$nodes_on = $db->fetch_array($db->query("SELECT COUNT(*) AS cnt FROM (
                                               SELECT s.server_id
                                               FROM servers s INNER JOIN servers_status t ON s.server_id = t.server_id
                                               WHERE (UNIX_TIMESTAMP() - t.timestamp) <= 150
                                               GROUP BY s.server_id
                                             ) tmp"));
	
	$nodes_all = $db->fetch_array($db->query("SELECT COUNT(server_id) AS cnt FROM servers"));
	
	$xtpl->table_td(_("Nodes").':');
	$xtpl->table_td($nodes_on["cnt"] .' '._("online").' / '. $nodes_all["cnt"] .' '._("total"), $nodes_on["cnt"] < $nodes_all["cnt"] ? '#FFA500' : '#66FF66');
	$xtpl->table_tr();
	
	$vps_on = $db->fetch_array($db->query("SELECT COUNT(*) AS cnt FROM vps v INNER JOIN vps_status s ON v.vps_id = s.vps_id WHERE vps_up = 1"));
	$vps_stopped = $db->fetch_array($db->query("SELECT COUNT(*) AS cnt FROM vps v INNER JOIN vps_status s ON v.vps_id = s.vps_id INNER JOIN members m ON m.m_id = v.m_id WHERE vps_up = 0 AND vps_deleted IS NULL AND m_state = 'active'"));
	$vps_suspended = $db->fetch_array($db->query("SELECT COUNT(*) AS cnt FROM vps v INNER JOIN members m ON v.m_id = m.m_id WHERE m_state = 'suspended'"));
	$vps_deleted = $db->fetch_array($db->query("SELECT COUNT(*) AS cnt FROM vps WHERE vps_deleted IS NOT NULL AND vps_deleted > 0"));
	$vps_all = $db->fetch_array($db->query("SELECT COUNT(*) AS cnt FROM vps"));
	
	$xtpl->table_td(_("VPS").':');
	$xtpl->table_td($vps_on["cnt"] .' '._("running").' / '. $vps_stopped["cnt"] .' '._("stopped").' / '. $vps_suspended["cnt"] .' '._("suspended").' / '.
					$vps_deleted["cnt"] .' '._("deleted").' / '. $vps_all["cnt"] .' '._("total"));
	$xtpl->table_tr();
	
	$m_active = $db->fetch_array($db->query("SELECT COUNT(*) AS cnt FROM members WHERE m_state = 'active'"));
	$m_suspended = $db->fetch_array($db->query("SELECT COUNT(*) AS cnt FROM members WHERE m_state = 'suspended'"));
	$m_total = $db->fetch_array($db->query("SELECT COUNT(*) AS cnt FROM members"));;
	$m_deleted = $db->fetch_array($db->query("SELECT COUNT(*) AS cnt FROM members WHERE m_state = 'deleted'"));;
	
	$xtpl->table_td(_("Members").':');
	$xtpl->table_td($m_active["cnt"] .' '._("active").' / '. $m_suspended["cnt"] .' '._("suspended")
	                .' / '. $m_deleted["cnt"] .' '._("deleted").' / '. $m_total["cnt"] .' '._("total"));
	$xtpl->table_tr();
	
	$free = count((array)get_free_ip_list(4));
	$all = count((array)get_all_ip_list(4));
	
	$xtpl->table_td(_("IPv4 addresses").':');
	$xtpl->table_td($all - $free .' '._("used").' / '. $all .' '._("total"));
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
	
	$rs = $db->query("SELECT server_id FROM locations l INNER JOIN servers s ON l.location_id = s.server_location ORDER BY l.location_id, s.server_id");
	
	while($row = $db->fetch_array($rs)) {
		$node = new cluster_node($row["server_id"]);
		
		// Availability
		$sql = 'SELECT * FROM servers_status WHERE server_id ="'.$node->s["server_id"].'"';
			
		if ($result = $db->query($sql))
			$status = $db->fetch_array($result);
		
		$icons = "";
		
		if ($cluster_cfg->get("lock_cron_".$node->s["server_id"]))	{
			$icons .= '<img title="'._("The server is currently processing").'" src="template/icons/warning.png"/>';
		} elseif ((time()-$status["timestamp"]) > 150) {
			$icons .= '<img title="'._("The server is not responding").'" src="template/icons/error.png"/>';
		} else {
			$icons .= '<img title="'._("The server is online").'" src="template/icons/server_online.png"/>';
		}
		
		$icons = '<a href="?page=cluster&action=node_toggle_maintenance&node_id='.$node->s["server_id"].'">'.$icons.'</a>';
		
		$xtpl->table_td($icons, false, true);
		$xtpl->table_td($node->s["server_id"]);
		
		// Name, IP, load
		$xtpl->table_td($node->s["server_name"]);
		$xtpl->table_td($node->s["server_ip4"]);
		$xtpl->table_td($status["cpu_load"], false, true);
		
		// Running
		$sql = 'SELECT COUNT(*) AS count FROM vps v INNER JOIN vps_status s ON v.vps_id = s.vps_id WHERE vps_up = 1 AND vps_server = '.$db->check($node->s["server_id"]);
			
		if ($result = $db->query($sql))
			$running_count = $db->fetch_array($result);
		
		$xtpl->table_td($running_count["count"], false, true);
		
		// Stopped
		$sql = "SELECT COUNT(*) AS count FROM vps v
				LEFT JOIN vps_status s ON v.vps_id = s.vps_id
				INNER JOIN members m ON m.m_id = v.m_id
				WHERE m_state = 'active' AND vps_up = 0 AND vps_deleted IS NULL AND vps_server = ".$db->check($node->s["server_id"]);
		
		if ($result = $db->query($sql))
			$stopped_count = $db->fetch_array($result);
			
		$xtpl->table_td($stopped_count["count"], false, true);
		
		// Deleted
		$sql = 'SELECT COUNT(*) AS count FROM vps WHERE vps_deleted IS NOT NULL AND vps_deleted > 0 AND vps_server = '.$db->check($node->s["server_id"]);
		
		if ($result = $db->query($sql))
			$deleted_count = $db->fetch_array($result);
			
		$xtpl->table_td($deleted_count["count"], false, true);
		
		// Total
		$sql = 'SELECT COUNT(*) AS count FROM vps WHERE vps_server='.$db->check($node->s["server_id"]);
		
		if ($result = $db->query($sql))
			$vps_count = $db->fetch_array($result);
		
		$xtpl->table_td($vps_count["count"], false, true);
		
		// Free
		$xtpl->table_td($node->role["max_vps"] - $running_count["count"], false, true);
		
		// Max
		$xtpl->table_td($node->role["max_vps"], false, true);
		
		// vpsAdmind
		$xtpl->table_td($status["vpsadmin_version"]);
		
		if(preg_match("/\d+stab.+/", $status['kernel'], $matches))
			$xtpl->table_td($matches[0]);
		else
			$xtpl->table_td($status["kernel"]);
		
		$m_icon_on = '<img alt="'._('Turn maintenance OFF.').'" src="template/icons/maintenance_mode.png">';
		$m_icon_off = '<img alt="'._('Turn maintenance ON.').'" src="template/icons/transact_ok.png">';
		$xtpl->table_td('<a href="?page=cluster&action=node_toggle_maintenance&node_id='.$node->s["server_id"].'">'.($node->s["server_maintenance"] ? $m_icon_on : $m_icon_off).'</a>');
		$xtpl->table_td('<a href="?page=cluster&action=node_edit&node_id='.$node->s["server_id"].'"><img src="template/icons/edit.png" title="'._("Edit").'"></a>');
		
		$xtpl->table_tr();
	}
	
	$xtpl->table_out('cluster_node_list');
}
if ($list_templates) {
	$xtpl->title2(_("Templates list"));
	$xtpl->table_add_category(_("ID"));
	$xtpl->table_add_category(_("Filename"));
	$xtpl->table_add_category(_("Label"));
	$xtpl->table_add_category(_("Uses"));
	$xtpl->table_add_category(_("Enabled"));
	$xtpl->table_add_category(_("Supported"));
	$xtpl->table_add_category(_("#"));
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	$templates = $cluster->get_templates();
	foreach($templates as $template) {
	$usage = 0;
	$usage = $cluster->get_template_usage($template["templ_id"]);
	$xtpl->table_td($template["templ_id"], false, true);
	$xtpl->table_td($template["templ_name"].'.tar.gz');
	$xtpl->table_td($template["templ_label"]);
	$xtpl->table_td($usage);
	$xtpl->table_td('<img src="template/icons/transact_'.($template["templ_enabled"] ? "ok" : "fail").'.png" alt="'.($template["templ_enabled"] ? _('Enabled') : _('Disabled')).'">');
	$xtpl->table_td('<img src="template/icons/transact_'.($template["templ_supported"] ? "ok" : "fail").'.png" alt="'.($template["templ_supported"] ? _('Yes') : _('No')).'">');
	$xtpl->table_td($template["templ_order"]);
	$xtpl->table_td('<a href="?page=cluster&action=templates_edit&id='.$template["templ_id"].'"><img src="template/icons/edit.png" title="'._("Edit").'"></a>');
	$xtpl->table_td('<a href="?page=cluster&action=templates_copy_over_nodes&id='.$template["templ_id"].'"><img src="template/icons/copy_template.png" title="'._("Copy over nodes").'"></a>');
	if ($usage > 0)
		$xtpl->table_td('<img src="template/icons/delete_grey.png" title="'._("Delete - N/A, template is in use").'">');
	else
		$xtpl->table_td('<a href="?page=cluster&action=templates_delete&id='.$template["templ_id"].'"><img src="template/icons/delete.png" title="'._("Delete").'"></a>');
	if ($template["templ_info"]) $xtpl->table_td('<img src="template/icons/info.png" title="'._("Info").'"');
	$xtpl->table_tr();
	}
	$xtpl->table_out();
	$xtpl->sbar_add(_("Register new template"), '?page=cluster&action=template_register');
	$xtpl->helpbox(_("Help"), _("This is simple cluster template management.
				To add new template, save it to one node, then click 'Register new template' and finally copy it over all nodes.
				"));
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
				$(\'<tr id="add_config_\' + add_config_id++ + \'"><td>'._('Add').':</td><td><select name="add_config[]">'.$options.'</select></td></tr>\').fadeIn("slow").insertBefore("#configs tr:nth-last-child(1)");
				dnd();
			});
			
			$(".delete-config").click(function (){
				$(this).closest("tr").remove();
			});
		});
    </script>');
	
	$chain = $cluster_cfg->get("default_config_chain");
	$configs = list_configs();
	
	$xtpl->form_create('?page=cluster&action=configs_default_save', 'post');
	$xtpl->table_title(_("Default config chain"));
	$xtpl->table_add_category(_('Config'));
	$xtpl->table_add_category('');
	
	foreach($chain as $cfg) {
		$xtpl->form_add_select_pure('configs[]', $configs, $cfg);
		$xtpl->table_td('<a href="javascript:" class="delete-config">'._('delete').'</a>');
		$xtpl->table_tr(false, false, false, "order_$cfg");
	}
	
	$xtpl->table_td('<input type="hidden" name="configs_order" id="configs_order" value="">' .  _('Add').':');
	$xtpl->form_add_select_pure('add_config[]', $configs_select);
	$xtpl->table_tr(false, false, false, 'add_config');
	$xtpl->form_out(_("Save changes"), 'configs', '<a href="javascript:" id="add_row">+</a>');
}

if ($list_locations) {
	$xtpl->title2(_("Cluster locations list"));
	$xtpl->table_add_category(_("ID"));
	$xtpl->table_add_category(_("Location label"));
	$xtpl->table_add_category(_("Servers"));
	$xtpl->table_add_category(_("IPv6"));
	$xtpl->table_add_category(_("On Boot"));
	$xtpl->table_add_category(_("Domain"));
	$xtpl->table_add_category('');
	$xtpl->table_add_category('');
	$list = $cluster->get_locations();
	if ($list)
	foreach($list as $item) {
		$servers = 0;
		$servers = $cluster->get_server_count_in_location($item["location_id"]);
		$xtpl->table_td($item["location_id"]);
		$xtpl->table_td($item["location_label"]);
		$xtpl->table_td($servers, false, true);
		if ($item["location_has_ipv6"]) {
			$xtpl->table_td('<img src="template/icons/transact_ok.png" />');
		} else {
			$xtpl->table_td('<img src="template/icons/transact_fail.png" />');
		}
		if ($item["location_vps_onboot"]) {
			$xtpl->table_td('<img src="template/icons/transact_ok.png" />');
		} else {
			$xtpl->table_td('<img src="template/icons/transact_fail.png" />');
		}
		$xtpl->table_td($item['domain']);
		$xtpl->table_td('<a href="?page=cluster&action=location_edit&id='.$item["location_id"].'"><img src="template/icons/edit.png" title="'._("Edit").'"></a>');
		if ($servers > 0) {
			$xtpl->table_td('<img src="template/icons/delete_grey.png" title="'._("Delete - N/A, item is in use").'">');
		} else {
			$xtpl->table_td('<a href="?page=cluster&action=location_delete&id='.$item["location_id"].'"><img src="template/icons/delete.png" title="'._("Delete").'"></a>');
		}
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
	$list = $cluster->get_dns_servers();
	if ($list)
	foreach($list as $item) {
	$xtpl->table_td($item["dns_id"]);
	$xtpl->table_td($item["dns_ip"]);
	$xtpl->table_td($item["dns_label"]);
	$location = $cluster->get_location_by_id($item["dns_location"]);
	if ($item["dns_is_universal"]) {
		$xtpl->table_td('<img src="template/icons/transact_ok.png" />');
		$xtpl->table_td('---');
	}
	else {
		$xtpl->table_td('<img src="template/icons/transact_fail.png" />');
		$xtpl->table_td($location["location_label"]);
	}
	$xtpl->table_td('<a href="?page=cluster&action=dns_edit&id='.$item["dns_id"].'"><img src="template/icons/edit.png" title="'._("Edit").'"></a>');
	$xtpl->table_td('<a href="?page=cluster&action=dns_delete&id='.$item["dns_id"].'"><img src="template/icons/delete.png" title="'._("Delete").'"></a>');
	$xtpl->table_tr();
	}
	$xtpl->table_out();
	$xtpl->sbar_add(_("New DNS Server"), '?page=cluster&action=dns_new');
}

if ($playground_settings) {
	$xtpl->title2("Manage Playground Settings");
	
	$xtpl->table_add_category(_('Playground'));
	$xtpl->table_add_category('');
	$xtpl->form_create('?page=cluster&action=playground_settings_save', 'post');
	$xtpl->form_add_checkbox(_('Enabled').':', 'enabled', '1', $cluster_cfg->get("playground_enabled"), _('Allow members to create playground VPS'));
	$xtpl->form_add_checkbox(_('Backup').':', 'backup', '1', $cluster_cfg->get("playground_backup"), _('Should be newly created VPS backed up?'));
	$xtpl->form_add_input(_("Default VPS lifetime").':', 'text', '5', 'lifetime', $cluster_cfg->get("playground_vps_lifetime"), _("days"));
	$xtpl->form_out(_('Save'));
	
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
				$(\'<tr id="add_config_\' + add_config_id++ + \'"><td>'._('Add').':</td><td><select name="add_config[]">'.$options.'</select></td></tr>\').fadeIn("slow").insertBefore("#configs tr:nth-last-child(1)");
				dnd();
			});
			
			$(".delete-config").click(function (){
				$(this).closest("tr").remove();
			});
		});
    </script>');
	
	$chain = $cluster_cfg->get("playground_default_config_chain");
	$configs = list_configs();
	
	$xtpl->form_create('?page=cluster&action=playground_configs_default_save', 'post');
	$xtpl->table_title(_("Playground config chain"));
	$xtpl->table_add_category(_('Config'));
	$xtpl->table_add_category('');
	
	foreach($chain as $cfg) {
		$xtpl->form_add_select_pure('configs[]', $configs, $cfg);
		$xtpl->table_td('<a href="javascript:" class="delete-config">'._('delete').'</a>');
		$xtpl->table_tr(false, false, false, "order_$cfg");
	}
	
	$xtpl->table_td('<input type="hidden" name="configs_order" id="configs_order" value="">' .  _('Add').':');
	$xtpl->form_add_select_pure('add_config[]', $configs_select);
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
