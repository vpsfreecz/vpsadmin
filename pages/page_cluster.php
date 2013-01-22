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

$server_types = array("node" => "Node", "backuper" => "Backuper", "storage" => "Storage", "mailer" => "Mailer");
$location_types = array("production" => "Production", "playground" => "Playground");

switch($_REQUEST["action"]) {
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
		$xtpl->form_add_checkbox(_("Does it use OSPF?").':', 'has_ospf', '1', '0', _("Or another kind of dynamic routing"));
		$xtpl->form_add_checkbox(_("Run VPSes here on boot?").':', 'onboot', '1', '1', '');
		$xtpl->form_add_checkbox(_("Does use Rdiff-backup?").':', 'has_rdiff_backup', '1', '', _("<b>Note:</b> check only if available across all nodes in this location"));
		$xtpl->form_add_select(_("Backuper").':', 'backup_server_id', $cluster->list_servers_with_type("backuper"), '', _("Needs to be SSH paired"));
		$xtpl->form_add_input(_("How many backups to store").':', 'text', '3', 	'rdiff_history',		'', _("Number"));
		$xtpl->form_add_input(_("Local node SSHFS mountpath").':', 'text', '30', 	'rdiff_mount_sshfs',	'', _("Path, use {vps_id}"));
		$xtpl->form_add_input(_("Local node ArchFS mountpath").':', 'text', '30',	'rdiff_mount_archfs',	'', _("Path, use {vps_id}"));
		$xtpl->form_add_input(_("Template sync path").':', 'text', '30',	'tpl_sync_path',	'', _("Used with rsync"));
		$xtpl->form_add_input(_("Remote console server").':', 'text', '30',	'remote_console_server',	'', _("URL"));
		$xtpl->form_out(_("Save changes"));
		break;
	case "location_new_save":
		$cluster->set_location(NULL, $_REQUEST["location_label"], $_REQUEST["type"], $_REQUEST["has_ipv6"],
							$_REQUEST["onboot"], $_REQUEST["has_ospf"], $_REQUEST["has_rdiff_backup"],
							$_REQUEST["backup_server_id"], $_REQUEST["rdiff_history"], $_REQUEST["rdiff_mount_sshfs"],
							$_REQUEST["rdiff_mount_archfs"], $_REQUEST["tpl_sync_path"], $_REQUEST["remote_console_server"]);
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
			$xtpl->form_add_checkbox(_("Does it use OSPF?").':', 'has_ospf', '1', $item["location_has_ospf"], _("Or another kind of dynamic routing"));
			$xtpl->form_add_checkbox(_("Run VPSes here on boot?").':', 'onboot', '1', $item["location_vps_onboot"], '');
			$xtpl->form_add_checkbox(_("Does use Rdiff-backup?").':', 'has_rdiff_backup', '1', $item["location_has_rdiff_backup"], _("<b>Note:</b> check only if available across all nodes in this location"));
			$xtpl->form_add_select(_("Backuper").':', 'backup_server_id', $cluster->list_servers_with_type("backuper"), $item["location_backup_server_id"], _("Needs to be SSH paired"));
			$xtpl->form_add_input(_("How many backups to store").':', 'text', '30', 	'rdiff_history',		$item["location_rdiff_history"], _("Number"));
			$xtpl->form_add_input(_("Local node SSHFS mountpath").':', 'text', '30', 	'rdiff_mount_sshfs',	$item["location_rdiff_mount_sshfs"], _("Path, use {vps_id}"));
			$xtpl->form_add_input(_("Local node ArchFS mountpath").':', 'text', '30',	'rdiff_mount_archfs',	$item["location_rdiff_mount_archfs"], _("Path, use {vps_id}"));
			$xtpl->form_add_input(_("Template sync path").':', 'text', '30',	'tpl_sync_path',	$item["location_tpl_sync_path"], _("Used with rsync"));
			$xtpl->form_add_input(_("Remote console server").':', 'text', '30',	'remote_console_server',	$item["location_remote_console_server"], _("URL"));
			$xtpl->form_out(_("Save changes"));
		} else {
			$list_ramlimits = true;
		}
		break;
	case "location_edit_save":
		if ($item = $cluster->get_location_by_id($_REQUEST["id"])) {
			$cluster->set_location($_REQUEST["id"], $_REQUEST["location_label"], $_REQUEST["type"], $_REQUEST["has_ipv6"],
							$_REQUEST["onboot"], $_REQUEST["has_ospf"], $_REQUEST["has_rdiff_backup"],
							$_REQUEST["backup_server_id"], $_REQUEST["rdiff_history"], $_REQUEST["rdiff_mount_sshfs"],
							$_REQUEST["rdiff_mount_archfs"], $_REQUEST["tpl_sync_path"], $_REQUEST["remote_console_server"]);
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
			$xtpl->form_add_input(_("Special").':', 'text', '40', 'special', $template["special"], _("Special template features"));
			$xtpl->form_add_checkbox(_("Enabled").':', 'templ_enabled', 1, $template["templ_enabled"]);
			$xtpl->form_out(_("Save changes"));
		} else {
			$list_templates = true;
		}
		break;
	case "templates_edit_save":
		if ($template = $cluster->get_template_by_id($_REQUEST["id"])) {
			if (ereg('^[a-zA-Z0-9_\.\-]{1,63}$',$_REQUEST["templ_name"])) {
			$cluster->set_template($_REQUEST["id"], $_REQUEST["templ_name"], $_REQUEST["templ_label"], $_REQUEST["templ_info"], $_REQUEST["special"], $_REQUEST["templ_enabled"]);
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
	$xtpl->form_add_input(_("Special").':', 'text', '40', 'special', '', _("Special template features"));
	$xtpl->form_add_checkbox(_("Enabled").':', 'templ_enabled', 1, 1);
	$xtpl->form_out(_("Save changes"));
	$xtpl->helpbox(_("Help"), _("This procedure only <b>registers template</b> into the system database.
					 You need copy the template to proper path onto one of servers
					 and then proceed \"Copy template over nodes\" function.
					"));
	break;
	case "template_register_save":
		if (ereg('^[a-zA-Z0-9_\.\-]{1,63}$',$_REQUEST["templ_name"])) {
			$cluster->set_template(NULL, $_REQUEST["templ_name"], $_REQUEST["templ_label"], $_REQUEST["templ_info"], $_REQUEST["special"], $_REQUEST["templ_enabled"]);
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
			$cluster->delete_template($template["templ_id"]);
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
			$xtpl->form_add_checkbox(_("Reconfigure all affected VPSes").':', 'reapply', '1', '1');
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
		$xtpl->form_add_input(_("Max VPS count").':', 'text', '8', 'server_maxvps', '', '');
		$xtpl->form_add_input(_("OpenVZ Path").':', 'text', '10', 'server_path_vz', '/var/lib/vz', '');
		$xtpl->form_out(_("Save changes"));
		break;
	case "newnode_save":
		if (isset($_REQUEST["server_id"]) &&
			isset($_REQUEST["server_name"]) &&
			isset($_REQUEST["server_ip4"]) &&
			isset($_REQUEST["server_location"]) &&
			isset($_REQUEST["server_maxvps"]) &&
			isset($_REQUEST["server_path_vz"]) &&
			isset($_REQUEST["server_type"]) && in_array($_REQUEST["server_type"], array_keys($server_types))
		) {
			$sql = 'INSERT INTO servers
					SET server_id = "'.$db->check($_REQUEST["server_id"]).'",
					server_name = "'.$db->check($_REQUEST["server_name"]).'",
					server_type = "'.$db->check($_REQUEST["server_type"]).'",
					server_location = "'.$db->check($_REQUEST["server_location"]).'",
					server_availstat = "'.$db->check($_REQUEST["server_availstat"]).'",
					server_maxvps = "'.$db->check($_REQUEST["server_maxvps"]).'",
					server_ip4 = "'.$db->check($_REQUEST["server_ip4"]).'",
					server_path_vz = "'.$db->check($_REQUEST["server_path_vz"]).'"';
			$db->query($sql);
			$list_nodes = true;
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
	case "mailer_settings":
		$xtpl->title2("Manage Mailer Settings");
		$xtpl->table_add_category('');
		$xtpl->table_add_category('');
		$xtpl->form_create('?page=cluster&action=mailer_settings_save', 'post');
		$xtpl->form_add_checkbox(_("Mailer enabled").':', 'mailer_enabled', '1', $cluster_cfg->get("mailer_enabled"), $hint = '');
		$xtpl->form_add_checkbox(_("Admins in CC").':', 'admins_in_cc', '1', $cluster_cfg->get("mailer_admins_in_cc"), $hint = '');
		$xtpl->form_add_input(_("Admins in CC (mails)").':', 'text', '40', 'admin_mails', $cluster_cfg->get("mailer_admins_cc_mails"), '');
		$xtpl->form_add_input(_("Mails sent from").':', 'text', '40', 'mail_from', $cluster_cfg->get("mailer_from"), '');
		$xtpl->form_add_input(_("Payment warning subject").':', 'text', '40', 'tpl_payment_warning_subj', $cluster_cfg->get("mailer_tpl_payment_warning_subj"), '%member% - nick');
		$xtpl->form_add_textarea(_("Payment warning<br /> template").':', 50, 8, 'tpl_payment_warning', $cluster_cfg->get("mailer_tpl_payment_warning"), '
								%member% - nick<br />
								%memberid% - member id<br />
								%expiredate% - payment expiration date<br />
								%monthly% - monthly payment<br />
								');
		$xtpl->form_add_input(_("Member added subject").':', 'text', '40', 'tpl_member_added_subj', $cluster_cfg->get("mailer_tpl_member_added_subj"), '%member% - nick');
		$xtpl->form_add_textarea(_("Member added<br /> template").':', 50, 8, 'tpl_member_added', $cluster_cfg->get("mailer_tpl_member_added"), '
								%member% - nick<br />
								%memberid% - member id<br />
								%pass% - password<br />
								');
		$xtpl->form_add_input(_("Limits change subject").':', 'text', '40', 'tpl_limits_change_subj', $cluster_cfg->get("mailer_tpl_limits_change_subj"), '%member% - nick<br />%vpsid% = VPS ID');
		$xtpl->form_add_textarea(_("Limits changed<br /> template").':', 50, 8, 'tpl_limits_changed', $cluster_cfg->get("mailer_tpl_limits_changed"), '
								%member% - nick<br />
								%vpsid% - VPS ID<br />
								%configs% - List of configs
								');
		$xtpl->form_add_input(_("Send nonpayers info to").':', 'text', '40', 'nonpayers_mail', $cluster_cfg->get("mailer_nonpayers_mail"), '');
		$xtpl->form_add_input(_("Nonpayer subject").':', 'text', '40', 'tpl_nonpayers_subj', $cluster_cfg->get("mailer_tpl_nonpayers_subj"), '');
		$xtpl->form_add_textarea(_("Nonpayer text<br /> template").':', 50, 8, 'tpl_nonpayers', $cluster_cfg->get("mailer_tpl_nonpayers"), '
								%never_paid% - list of members who have never paid before<br />
								%nonpayers% - list of nonpayers
								');
		$xtpl->form_add_input(_("Download backup subject").':', 'text', '40', 'tpl_dl_backup_subj', $cluster_cfg->get("mailer_tpl_dl_backup_subj"), '%member% - nick<br />%vpsid% = VPS ID');
		$xtpl->form_add_textarea(_("Download backup<br /> template").':', 50, 8, 'tpl_dl_backup', $cluster_cfg->get("mailer_tpl_dl_backup"), '
								%member% - nick<br />
								%vpsid% - VPS ID<br />
								%url% - download link<br />
								%datetime% - date and time of backup
								');
		$xtpl->form_out(_("Save changes"));
		$xtpl->sbar_add(_("Back"), '?page=cluster&action=mailer');
		break;
	case "mailer_settings_save":
		$cluster_cfg->set("mailer_enabled", $_REQUEST["mailer_enabled"]);
		$cluster_cfg->set("mailer_admins_in_cc", $_REQUEST["admins_in_cc"]);
		$cluster_cfg->set("mailer_admins_cc_mails", $_REQUEST["admin_mails"]);
		$cluster_cfg->set("mailer_from", $_REQUEST["mail_from"]);
		$cluster_cfg->set("mailer_tpl_payment_warning_subj", $_REQUEST["tpl_payment_warning_subj"]);
		$cluster_cfg->set("mailer_tpl_payment_warning", $_REQUEST["tpl_payment_warning"]);
		$cluster_cfg->set("mailer_tpl_member_added_subj", $_REQUEST["tpl_member_added_subj"]);
		$cluster_cfg->set("mailer_tpl_member_added", $_REQUEST["tpl_member_added"]);
		$cluster_cfg->set("mailer_tpl_limits_change_subj", $_REQUEST["tpl_limits_change_subj"]);
		$cluster_cfg->set("mailer_tpl_limits_changed", $_REQUEST["tpl_limits_changed"]);
		$cluster_cfg->set("mailer_nonpayers_mail", $_REQUEST["nonpayers_mail"]);
		$cluster_cfg->set("mailer_tpl_nonpayers_subj", $_REQUEST["tpl_nonpayers_subj"]);
		$cluster_cfg->set("mailer_tpl_nonpayers", $_REQUEST["tpl_nonpayers"]);
		$cluster_cfg->set("mailer_tpl_dl_backup_subj", $_REQUEST["tpl_dl_backup_subj"]);
		$cluster_cfg->set("mailer_tpl_dl_backup", $_REQUEST["tpl_dl_backup"]);
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
	case "api_settings":
		$xtpl->title2("Manage API Settings");
		$xtpl->table_add_category('');
		$xtpl->table_add_category('');
		$xtpl->form_create('?page=cluster&action=api_settings_save', 'post');
		$xtpl->form_add_checkbox(_("API enabled").':', 'api_enabled', '1', $cluster_cfg->get("api_enabled"), $hint = '');
		$xtpl->form_add_input(_("API key").':', 'text', '40', 'api_key', $cluster_cfg->get("api_key"), '');
		$xtpl->form_out(_("Save changes"));
		$xtpl->sbar_add(_("Back"), '?page=cluster');
		break;
	case "api_settings_save":
		$cluster_cfg->set("api_enabled", $_REQUEST["api_enabled"]);
		$cluster_cfg->set("api_key", $_REQUEST["api_key"]);
		$xtpl->perex(_("API settings saved"), '');
		$list_nodes = true;
		break;
	case "playground_settings":
		$xtpl->sbar_add(_("Back"), '?page=cluster');
		$playground_settings=true;
		break;
	case "playground_settings_save":
		$xtpl->perex(_("Playground settings saved"), '');
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
		$xtpl->table_title(_("Notice board"));
		$xtpl->table_add_category('');
		$xtpl->table_add_category('');
		$xtpl->form_create('?page=cluster&action=noticeboard_save', 'post');
		$xtpl->form_add_textarea(_("Text").':', 80, 25, 'noticeboard', $cluster_cfg->get("noticeboard"));
		$xtpl->form_out(_("Save changes"));
		
		$xtpl->sbar_add(_("Back"), '?page=cluster');
		break;
	case "noticeboard_save":
		$cluster_cfg->set("noticeboard", $_POST["noticeboard"]);
		$xtpl->perex(_("Notice board saved"), '');
		$list_nodes = true;
		break;
	default:
		$list_nodes = true;
}
if ($list_mails) {
	$xtpl->title2("Sent mails log");
	$whereCond = array();
	$whereCond[] = 1;

	if ($_REQUEST["from"] != "") {
	$whereCond[] = "id < {$_REQUEST["from"]}";
	} elseif ($_REQUEST["id"] != "") {
	$whereCond[] = "id = {$_REQUEST["id"]}";
	}
	if ($_REQUEST["member"] != "") {
	$whereCond[] = "m_id = {$_REQUEST["member"]}";
	}
	if ($_REQUEST["limit"] != "") {
	$limit = $_REQUEST["limit"];
	} else {
	$limit = 50;
	}
	$xtpl->form_create('?page=cluster&action=mailer', 'post');
	$xtpl->form_add_input(_("Limit").':', 'text', '40', 'limit', $limit, '');
	$xtpl->form_add_input(_("Start from ID").':', 'text', '40', 'from', $_REQUEST["from"], '');
	$xtpl->form_add_input(_("Exact ID").':', 'text', '40', 'id', $_REQUEST["id"], '');
	$xtpl->form_add_input(_("Member ID").':', 'text', '40', 'member', $_REQUEST["member"], '');
	$xtpl->form_add_checkbox(_("Detailed mode").':', 'details', '1', $_REQUEST["details"], $hint = '');
	$xtpl->form_out(_("Show"));

	$xtpl->table_add_category('ID');
	$xtpl->table_add_category('MEMBER');
	$xtpl->table_add_category('TYPE');
	$xtpl->table_add_category('SENT');
	while ($mail = $db->find("mailer", $whereCond, "id DESC", $limit)) {
	$xtpl->table_td($mail["id"]);
	$member = $db->findByColumnOnce("members", "m_id", $mail["member_id"]);
	$xtpl->table_td($member["m_nick"]);
	$xtpl->table_td($mail["type"]);
	$xtpl->table_td(strftime("%Y-%m-%d %H:%M", $mail["sentTime"]));
	$xtpl->table_tr();
	if ($_REQUEST["details"]) {
		$xtpl->table_td(nl2br($mail["details"]), false, false, 4);
		$xtpl->table_tr();
	}
	}
	$xtpl->table_out();
	$xtpl->sbar_add(_("Mailer settings"), '?page=cluster&action=mailer_settings');
}
if ($list_nodes) {
	$xtpl->sbar_add(_("Register new node"), '?page=cluster&action=newnode');
	$xtpl->sbar_add(_("Manage VPS templates"), '?page=cluster&action=templates');
	$xtpl->sbar_add(_("Manage configs"), '?page=cluster&action=configs');
	$xtpl->sbar_add(_("Manage IPv4 address list"), '?page=cluster&action=ipv4addr');
	$xtpl->sbar_add(_("Manage IPv6 address list"), '?page=cluster&action=ipv6addr');
	$xtpl->sbar_add(_("Manage DNS servers"), '?page=cluster&action=dns');
	$xtpl->sbar_add(_("Manage locations"), '?page=cluster&action=locations');
	$xtpl->sbar_add(_("Manage Mailer"), '?page=cluster&action=mailer');
	$xtpl->sbar_add(_("Manage Payments"), '?page=cluster&action=payments_settings');
	$xtpl->sbar_add(_("Manage API"), '?page=cluster&action=api_settings');
	$xtpl->sbar_add(_("Manage playground"), '?page=cluster&action=playground_settings');
	$xtpl->sbar_add(_("Notice board"), '?page=cluster&action=noticeboard');
	$xtpl->sbar_add(_("Edit vpsAdmin textfields"), '?page=cluster&action=fields');
	
	$sql = 'SELECT * FROM servers ORDER BY server_location,server_id';
	$list_result = $db->query($sql);
	
	$i = 1;
	$on_row = 2;
	
	for ($j = 0; $j < $on_row; $j++) {
		$xtpl->table_add_category(_("A"));
		$xtpl->table_add_category(_("NAME"));
		$xtpl->table_add_category(_("L"));
		$xtpl->table_add_category(_("R"));
		$xtpl->table_add_category(_("S"));
		$xtpl->table_add_category(_("T"));
		$xtpl->table_add_category(_("M"));
		$xtpl->table_add_category(_("V"));
		$xtpl->table_add_category(' ');
		
		if ($j+1 < $on_row)
			$xtpl->table_add_category(' ');
	}
	
	while ($srv = $db->fetch_array($list_result)) {
		
		$node = new cluster_node($srv["server_id"]);
		$sql = 'SELECT * FROM servers_status WHERE server_id ="'.$srv["server_id"].'" ORDER BY id DESC LIMIT 1';
		
		if ($result = $db->query($sql))
			$status = $db->fetch_array($result);
		
		$icons = "";
		
		if ($cluster_cfg->get("lock_cron_".$srv["server_id"]))	{
			$icons .= '<img title="'._("The server is currently processing").'" src="template/icons/warning.png"/>';
		} elseif ((time()-$status["timestamp"]) > 360) {
			$icons .= '<img title="'._("The server is not responding").'" src="template/icons/error.png"/>';
		} else {
			$icons .= '<img title="'._("The server is online").'" src="template/icons/server_online.png"/>';
		}
		
		$xtpl->table_td($icons, false, true);
		
		$xtpl->table_td($srv["server_name"]);
		$xtpl->table_td($status["cpu_load"], false, true);
		
		$sql = 'SELECT COUNT(*) AS count FROM vps v INNER JOIN vps_status s ON v.vps_id = s.vps_id WHERE vps_up = 1 AND vps_server = '.$db->check($srv["server_id"]);
		
		if ($result = $db->query($sql))
			$running_count = $db->fetch_array($result);
		
		$xtpl->table_td($running_count["count"]);
		
		$sql = 'SELECT COUNT(*) AS count FROM vps v LEFT JOIN vps_status s ON v.vps_id = s.vps_id WHERE vps_up = 0 AND vps_server = '.$db->check($srv["server_id"]);
		
		if ($result = $db->query($sql))
			$stopped_count = $db->fetch_array($result);
			
		$xtpl->table_td($stopped_count["count"]);
		
		$sql = 'SELECT COUNT(*) AS count FROM vps WHERE vps_server='.$db->check($srv["server_id"]);
		
		if ($result = $db->query($sql))
			$vps_count = $db->fetch_array($result);
		
		$xtpl->table_td($vps_count["count"], false, true);
		
		$xtpl->table_td($srv["server_maxvps"]);
		
		/*
		$vps_free = ((int)$srv["server_maxvps"]-(int)$vps_count["count"]);
		$xtpl->table_td($vps_free, false, true);
		*/
		
		$xtpl->table_td($status["vpsadmin_version"]);
		
		$xtpl->table_td('<a href="?page=cluster&action=node_start_vpses&id='.$srv["server_id"].'"><img src="template/icons/vps_start.png" title="'._("Start all VPSes here").'"/></a>');
		
		if (!($i++ % $on_row))
			$xtpl->table_tr();
		else
			$xtpl->table_td('');
	}
	$xtpl->table_out();
	
	$xtpl->table_add_category('');
	$xtpl->table_add_category('Legend');
	
	$xtpl->table_td("A");
	$xtpl->table_td(_("Availability"));
	$xtpl->table_tr();
	
	$xtpl->table_td("L");
	$xtpl->table_td(_("Load"));
	$xtpl->table_tr();
	
	$xtpl->table_td("R");
	$xtpl->table_td(_("Running"));
	$xtpl->table_tr();
	
	$xtpl->table_td("S");
	$xtpl->table_td(_("Stopped"));
	$xtpl->table_tr();
	
	$xtpl->table_td("T");
	$xtpl->table_td(_("Total"));
	$xtpl->table_tr();
	
	$xtpl->table_td("M");
	$xtpl->table_td(_("Max"));
	$xtpl->table_tr();
	
	$xtpl->table_td("V");
	$xtpl->table_td(_("vpsAdmin"));
	$xtpl->table_tr();
	
	$xtpl->table_out();
}
if ($list_templates) {
	$xtpl->title2(_("Templates list"));
	$xtpl->table_add_category(_("ID"));
	$xtpl->table_add_category(_("Filename"));
	$xtpl->table_add_category(_("Label"));
	$xtpl->table_add_category(_("Uses"));
	$xtpl->table_add_category(_("Enabled"));
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
	$xtpl->table_add_category(_("OSPF"));
	$xtpl->table_add_category(_("RDIFF"));
	$xtpl->table_add_category(_("On Boot"));
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
	if ($item["location_has_ospf"]) {
		$xtpl->table_td('<img src="template/icons/transact_ok.png" />');
	} else {
		$xtpl->table_td('<img src="template/icons/transact_fail.png" />');
	}
	if ($item["location_has_rdiff_backup"]) {
		$xtpl->table_td('<img src="template/icons/transact_ok.png" />');
	} else {
		$xtpl->table_td('<img src="template/icons/transact_fail.png" />');
	}
	if ($item["location_vps_onboot"]) {
		$xtpl->table_td('<img src="template/icons/transact_ok.png" />');
	} else {
		$xtpl->table_td('<img src="template/icons/transact_fail.png" />');
	}
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

$xtpl->sbar_out(_("Manage Cluster"));

} else $xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
?>
