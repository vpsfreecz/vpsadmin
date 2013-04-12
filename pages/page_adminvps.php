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
function print_newvps() {
	global $xtpl, $cluster;
	$xtpl->title(_("Create VPS"));
	$xtpl->form_create('?page=adminvps&section=vps&action=new2&create=1', 'post');
	$xtpl->form_add_input(_("Hostname").':', 'text', '30', 'vps_hostname', '', _("A-z, a-z"), 30);
	if ($_SESSION["is_admin"]) {
		$xtpl->form_add_select(_("HW server").':', 'vps_server', list_servers(false, array("node")), '2', '');
		$xtpl->form_add_select(_("Owner").':', 'm_id', members_list(), '', '');
	}
	$xtpl->form_add_select(_("Distribution").':', 'vps_template', list_templates(false), '',  '');
	
	if ($_SESSION["is_admin"]) {
		//$xtpl->form_add_select(_("IPv4").':', 'ipv4', get_all_ip_list(4), '1', '');
		$xtpl->form_add_checkbox(_("Boot on create").':', 'boot_after_create', '1', true, $hint = '');
		$xtpl->form_add_textarea(_("Extra information about VPS").':', 28, 4, 'vps_info', '', '');
	}
	$xtpl->table_add_category('&nbsp;');
	$xtpl->table_add_category('&nbsp;');
	$xtpl->table_add_category('&nbsp;');
	$xtpl->form_out(_("Create"));
}

function print_editvps($vps) {
}

if (isset($_SESSION["logged_in"]) && $_SESSION["logged_in"]) {

$member_of_session = member_load($_SESSION["member"]["m_id"]);

$_GET["run"] = isset($_GET["run"]) ? $_GET["run"] : false;

if ($_GET["run"] == 'stop') {
	$vps = vps_load($_GET["veid"]);
	$xtpl->perex_cmd_output(_("Stop VPS")." {$_GET["veid"]} ".strtolower(_("planned")), $vps->stop());
}

if ($_GET["run"] == 'start') {
	if ($member_of_session->m["m_state"] == "active" || (!$cluster_cfg->get("payments_enabled"))) {
			$vps = vps_load($_GET["veid"]);
			$xtpl->perex_cmd_output(_("Start of")." {$_GET["veid"]} ".strtolower(_("planned")), $vps->start());
	} else $xtpl->perex(_("Account suspended"), _("You are not allowed to make \"start\" operation.<br />Your account is suspended because of:") . ' ' . $member_of_session->m["m_suspend_reason"]);
}

if ($_GET["run"] == 'restart') {
	if ($member_of_session->m["m_state"] == "active" || (!$cluster_cfg->get("payments_enabled"))) {
		$vps = vps_load($_GET["veid"]);
		$xtpl->perex_cmd_output(_("Restart of")." {$_GET["veid"]} ".strtolower(_("planned")), $vps->restart());
	} else $xtpl->perex(_("Account suspended"), _("You are not allowed to make \"restart\" operation.<br />Your account is suspended because of:") . ' ' . $member_of_session->m["m_suspend_reason"]);
}

$playground_servers = $cluster->list_playground_servers();
$playground_enabled = $cluster_cfg->get("playground_enabled");
$playground_mode = !$_SESSION["is_admin"] && $playground_enabled && count($playground_servers) > 0 && $member_of_session->can_use_playground();

$_GET["action"] = isset($_GET["action"]) ? $_GET["action"] : false;

switch ($_GET["action"]) {
		case 'new':
			print_newvps();
			break;
		case 'new2':
			if ((ereg('^[a-zA-Z0-9\.\-]{1,30}$',$_REQUEST["vps_hostname"])
			    && $_GET["create"]
			    && ($_SESSION["is_admin"] || $playground_mode)))
					{
					$tpl = template_by_id($_REQUEST["vps_template"]);
					
					if (!$tpl["templ_enabled"]) {
						$xtpl->perex(_("Error"), _("Template not enabled, it cannot be used, you bloody hacker."));
						break;
					}
					
					if ($playground_mode)
						$server = pick_playground_server();
					else
						$server = server_by_id($_REQUEST["vps_server"]);
					
					if(!$server) {
						$xtpl->perex(_("Error"), _("Selected serve does not exist."));
						break;
					}
					
					if (!$vps->exists) $vps = vps_load($_REQUEST["veid"]);
					if (!$vps->exists) {
						$perex = $vps->create_new($server["server_id"],
													$_REQUEST["vps_template"],
													$_REQUEST["vps_hostname"],
													$playground_mode ? $_SESSION["member"]["m_id"] : $_REQUEST["m_id"],
													$playground_mode ? '' : $_REQUEST["vps_info"]);
						
						$mapping = nas_create_default_exports("vps", $vps->ve);
						nas_create_default_mounts($vps->ve, $mapping);
						
						if ($playground_mode) {
							$vps->add_default_configs("playground_default_config_chain");
							$vps->add_first_available_ip($server["server_location"], 4);
							$vps->add_first_available_ip($server["server_location"], 6);
							$vps->set_backuper($cluster_cfg->get("playground_backup"), NULL, "", true);
						} else {
							$vps->add_default_configs("default_config_chain");
						}

						$veid = $vps->veid;

						if ($_REQUEST["boot_after_create"] || $playground_mode) {
							$vps->start();
							$xtpl->perex(_("VPS create ").' '.$vps->veid, _("VPS will be created and booted afterwards."));
						} else {
							$xtpl->perex(_("VPS create ").' '.$vps->veid, _("VPS will be created. You can start it manually."));
						}

						$xtpl->delayed_redirect('?page=adminvps&action=info&veid='.$vps->veid, 350);
					}
					else {
						$xtpl->perex(_("Error"), _("VPS already exists"));
						$list_vps=true;
						}
					}
			else  {
				$xtpl->perex(_("Error"), _("Wrong hostname name"));
				print_newvps();
				}
			break;
		case 'delete':
			if (!$vps->exists) $vps = vps_load($_REQUEST["veid"]);
			
			$xtpl->perex(_("Are you sure you want to delete VPS number").' '.$_GET["veid"].'?', '');
			$xtpl->table_title(_("Delete VPS"));
			$xtpl->table_td(_("Hostname").':');
			$xtpl->table_td($vps->ve["vps_hostname"]);
			$xtpl->table_tr();
			$xtpl->form_create('?page=adminvps&section=vps&action=delete2&veid='.$_GET["veid"], 'post');
			
			if($_SESSION["is_admin"]) {
				$xtpl->form_add_checkbox(_("Lazy delete").':', 'lazy_delete', '1', true,
					_("Do not delete VPS immediately, but after passing of predefined time."));
			}
			$xtpl->form_out(_("Delete"));
			break;
		case 'delete2':
			if (!$vps->exists) $vps = vps_load($_REQUEST["veid"]);
			
			$lazy = $_POST["lazy_delete"] ? true : false;
			$can_delete = false;
				
			if ($playground_enabled && $_SESSION["member"]["m_id"] == $vps->ve["m_id"]) {
				foreach ($playground_servers as $pg)
					if ($pg["server_id"] == $vps->ve["server_id"]) {
						$can_delete = true;
						$lazy = true;
						break;
					}
			}
			
			if ($_SESSION["is_admin"] || $can_delete) {
				if(!$lazy && $vps->ve["vps_backup_export"]) {
					nas_export_delete($vps->ve["vps_backup_export"]);
					$vps->delete_all_backups();
				}
				
				$xtpl->perex_cmd_output(_("Deletion of VPS")." {$_GET["veid"]} ".strtolower(_("planned")), $vps->destroy($lazy, $can_delete));
				$list_vps=true;
			}
			break;
		case 'info':
			$show_info=true;
			break;
		case 'passwd':
			if (!$vps->exists) $vps = vps_load($_REQUEST["veid"]);

			if (($_REQUEST["pass"] == $_REQUEST["pass2"]) &&
					(strlen($_REQUEST["pass"]) >= 5) &&
					(strlen($_REQUEST["user"]) >= 2) &&
					!preg_match("/\\\/", $_REQUEST["pass"]) &&
					!preg_match("/\`/", $_REQUEST["pass"]) &&
					!preg_match("/\"/", $_REQUEST["pass"]) &&
					!preg_match("/\\\/", $_REQUEST["user"]) &&
					!preg_match("/\`/", $_REQUEST["user"]) &&
					!preg_match("/\"/", $_REQUEST["user"]))
			{
				$xtpl->perex_cmd_output(_("Change of user's password").' '.$_REQUEST["user"].' '.strtolower(_("planned")), $vps->passwd($_REQUEST["user"], $_REQUEST["pass"]));
			} else {
				$xtpl->perex(_("Error"), _("Wrong username or unsafe password"));
			}

			$show_info=true;
			break;
		case 'hostname':
			if (!$vps->exists) $vps = vps_load($_REQUEST["veid"]);
			if ($vps->exists) {
				if (ereg('^[a-zA-Z0-9\.\-]{1,30}$',$_REQUEST["hostname"]))
				$xtpl->perex_cmd_output(_("Hostname change planned"), $vps->set_hostname($_REQUEST["hostname"]));
				else $xtpl->perex(_("Error"), _("Wrong hostname name"));
				$show_info=true;
			}
			break;
		case 'configs':
			if ($_SESSION["is_admin"] && isset($_REQUEST["veid"]) && (isset($_POST["configs"]) || isset($_POST["add_config"]))) {
				if (!$vps->exists) $vps = vps_load($_REQUEST["veid"]);
				if ($vps->exists) {
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
					$vps->update_configs($_POST["configs"] ? $_POST["configs"] : array(), $cfgs, $_POST['add_config']);
					
					if($_REQUEST["notify_owner"])
						$vps->configs_change_notify();
					
					$show_info=true;
				}
			} else {
				$xtpl->perex(_("Error"), 'Error, contact your administrator');
				$show_info=true;
			}
			break;
		case 'custom_config':
			if ($_SESSION["is_admin"] && isset($_POST["custom_config"])) {
				if (!$vps->exists) $vps = vps_load($_REQUEST["veid"]);
				if ($vps->exists) {
					$vps->update_custom_config($_POST["custom_config"]);
					$show_info=true;
				}
			} else {
				$xtpl->perex(_("Error"), 'Error, contact your administrator');
				$show_info=true;
			}
			
			break;
		case 'chown':
			if (($_REQUEST["m_id"] > 0) && isset($_REQUEST["veid"]) && $_SESSION["is_admin"]) {
				if (!$vps->exists) $vps = vps_load($_REQUEST["veid"]);
				if ($vps->vchown($_REQUEST["m_id"]))
					$xtpl->perex(_("Owner change"), '' .strtolower(_("planned")));
				else $xtpl->perex(_("Error"), '');
				}
			else $xtpl->perex(_("Error"), '');
			$show_info=true;
			break;
		case 'addip':
			if (isset($_REQUEST["veid"]) && $_SESSION["is_admin"]) {
				if (!$vps->exists) $vps = vps_load($_REQUEST["veid"]);
					if (ip_is_free($_REQUEST["ip_recycle"]))
						$xtpl->perex_cmd_output(_("Addition of IP planned")." {$_REQUEST["ip"]}", $vps->ipadd($_POST["ip_recycle"]));
					elseif (ip_is_free($_REQUEST["ip6_recycle"]))
						$xtpl->perex_cmd_output(_("Addition of IP planned")." {$_REQUEST["ip"]}", $vps->ipadd($_POST["ip6_recycle"]));
					else
						$xtpl->perex(_("Error"), 'Contact your administrator');
			} else {
				$xtpl->perex(_("Error"), 'Contact your administrator');
			}
			$show_info=true;
			break;
		case 'delip':
			if ((validate_ip_address($_REQUEST["ip"])) && isset($_REQUEST["veid"]) && $_SESSION["is_admin"]) {
				if (!$vps->exists) $vps = vps_load($_REQUEST["veid"]);
				$xtpl->perex_cmd_output(_("Deletion of IP planned")." {$_REQUEST["ip"]}", $vps->ipdel($_REQUEST["ip"]));
				}
			else {
				$xtpl->perex(_("Error"), 'Contact your administrator');
				}
			$show_info=true;
			break;
		case 'nameserver':
			if ((isset($_REQUEST["nameserver"])) && isset($_REQUEST["veid"])) {
				if (!$vps->exists) $vps = vps_load($_REQUEST["veid"]);
				$xtpl->perex_cmd_output(_("DNS change planned"), $vps->nameserver($_REQUEST["nameserver"]));
				}
			else {
				$xtpl->perex(_("Error"), '');
				}
			$show_info=true;
			break;
		case 'offlinemigrate':
			if ($_SESSION["is_admin"] && isset($_REQUEST["veid"])) {
				if (!$vps->exists) $vps = vps_load($_REQUEST["veid"]);
				$xtpl->perex_cmd_output(_("Offline migration planned"), $vps->offline_migrate($_REQUEST["target_id"], $_POST["stop"]));
				}
			else {
				$xtpl->perex(_("Error"), '');
				}
			$show_info=true;
			break;
		case 'onlinemigrate':
			if ($_SESSION["is_admin"] && isset($_REQUEST["veid"])) {
				if (!$vps->exists) $vps = vps_load($_REQUEST["veid"]);
				$xtpl->perex_cmd_output(_("Online Migration added to transaction log"), $vps->online_migrate($_REQUEST["target_id"]));
				}
			else {
				$xtpl->perex(_("Error"), '');
				}
			$show_info=true;
			break;
		case 'alliplist':
			if ($_SESSION["is_admin"]) {
				$xtpl->title(_("List of IP addresses").' '._("[Admin mode]"));
				$Cluster_ipv4->table_used_out();
				$Cluster_ipv6->table_used_out();
				$xtpl->sbar_add(_("Back"), '?page=adminvps');
			} else $list_vps=true;
			break;
		case 'reinstall':
			if (!$vps->exists) $vps = vps_load($_REQUEST["veid"]);
			$tpl = template_by_id($_REQUEST["vps_template"]);
			
			if (!$tpl) {
				$xtpl->perex(_("Template does not exist!"));
				$show_info=true;
			} else if (!$tpl["templ_enabled"]) {
				$xtpl->perex(_("Template not enabled, it cannot be used!"), _("You will have to use different template."));
				$show_info=true;
			} else if ($_REQUEST["reinstallsure"] && $_REQUEST["vps_template"]) {
				$xtpl->perex(_("Are you sure you want to reinstall VPS").' '.$_GET["veid"].'?', '<a href="?page=adminvps">'.strtoupper(_("No")).'</a> | <a href="?page=adminvps&action=reinstall2&veid='.$_GET["veid"].'">'.strtoupper(_("Yes")).'</a>');
				$vps->change_distro_before_reinstall($_REQUEST["vps_template"]);
			}
			else $list_vps=true;
			break;
		case 'reinstall2':
			if (!$vps->exists) $vps = vps_load($_REQUEST["veid"]);
			$xtpl->perex_cmd_output(_("Reinstallation of VPS")." {$_GET["veid"]} ".strtolower(_("planned")).'<br />'._("You will have to reset your <b>root</b> password"), $vps->reinstall());
			$list_vps=true;
			break;
		case 'enablefeatures':
			if (isset($_REQUEST["veid"]) && isset($_REQUEST["enable"]) && $_REQUEST["enable"]) {
				if (!$vps->exists) $vps = vps_load($_REQUEST["veid"]);
				$xtpl->perex_cmd_output(_("Enable devices"), $vps->enable_features());
			} else {
				$xtpl->perex(_("Error"), '');
			}
			$show_info=true;
			break;
		case "special_setup_ispcp":
			if (isset($_REQUEST["veid"]) && isset($_REQUEST["setup_hostname"]) &&
			  isset($_REQUEST["setup_mail"]) &&
			  isset($_REQUEST["setup_username"]) && isset($_REQUEST["setup_vhost"]) &&
			  isset($_REQUEST["passwd"]) && ($_REQUEST["passwd"] == $_REQUEST["passwd2"]) &&
			  (strlen($_REQUEST["passwd"]) >= 5) && isset($_REQUEST["ip_addr"]) &&
			  preg_match("/[0-9]/", $_REQUEST["passwd"]) && preg_match("/[a-zA-Z]/", $_REQUEST["passwd"])) {
			    if (!$vps->exists) $vps = vps_load($_REQUEST["veid"]);
			    if ($_REQUEST["awstats"]) {
				$params = ' -s ';
			    }
			    $params .= ' '.$_REQUEST["ip_addr"];
			    $params .= ' '.$_REQUEST["setup_hostname"];
			    $params .= ' '.$_REQUEST["setup_vhost"];
    			    $params .= ' '.$_REQUEST["setup_mail"];
    			    $params .= ' '.$_REQUEST["passwd"];
    			    $params .= ' -a '.$_REQUEST["setup_username"];
    			    $vps->restart();
			    $vps->special_setup_ispcp($params);
			    $xtpl->perex(_("Transaction added"), _(" "));
			} else {
			    $xtpl->perex(_("Invalid data"), _("Please fill the form correctly."));
			}
			$show_info=true;
			break;
		case 'clone':
			if (isset($_REQUEST["veid"])  && ($_SESSION["is_admin"] || $playground_mode) && ($server = server_by_id($_REQUEST["target_server_id"]))) {
				if (!$vps->exists) $vps = vps_load($_REQUEST["veid"]);
				
				if ($playground_mode) {
					$is_pg = false;
					foreach ($playground_servers as $pg)
						if($pg["server_id"] == $server["server_id"]) {
							$is_pg = true;
							break;
						}
					
					if (!$is_pg) {
						$xtpl->perex(_("Error"), _("Selected node is not playground node, you bloody hacker."));
						break;
					}
				}
				
				$pg_backup = $cluster_cfg->get("playground_backup");
				
				$cloned = $vps->clone_vps($playground_mode ? $vps->ve["m_id"] : $_REQUEST["target_owner_id"],
								$_REQUEST["target_server_id"],
								$_REQUEST["hostname"],
								$playground_mode ? 2 : $_REQUEST["configs"],
								$playground_mode ? 1 : $_REQUEST["features"],
								$playground_mode ? $pg_backup : $_REQUEST["backuper"]
				);
				
				if ($playground_mode) {
					$cloned->add_first_available_ip($server["server_location"], 4);
					$cloned->add_first_available_ip($server["server_location"], 6);
					
					if (!$pg_backup)
						$cloned->set_backuper($pg_backup, NULL, "", true);
				}
				$xtpl->perex(_("Clone in progress"), '');
			} else
				 $xtpl->perex(_("Invalid data"), _("Please fill the form correctly."));
			
			$show_info=true;
			break;
		case 'setbackuper':
			if (isset($_REQUEST["veid"]) && isset($_POST["backup_exclude"])) {
				if (!$vps->exists) $vps = vps_load($_REQUEST["veid"]);
				$xtpl->perex_cmd_output(
					_("Backuper status changed"),
					$vps->set_backuper(
						$_SESSION["is_admin"] ? ($_POST["backup_enabled"] ? true : false) : NULL,
						$_SESSION["is_admin"] ? $_POST["backup_export"] : NULL,
						$_POST["backup_exclude"]
					)
				);
				
				if ($_SESSION["is_admin"] && $_REQUEST["notify_owner"])
					$vps->backuper_change_notify();
			} else {
				$xtpl->perex(_("Error"), '');
			}
			$show_info=true;
			break;
		default:
			// Vypsat všechny VPS registrované ve vpsAdminu
			$list_vps=true;
			break;
	}

if (isset($list_vps) && $list_vps) {
	if ($_SESSION["is_admin"])
		$xtpl->title(_("VPS list").' '._("[Admin mode]"));
	else
		$xtpl->title(_("VPS list").' '._("[User mode]"));

			$all_vps = get_vps_array();
//			print_r($all_vps);
			$listed_vps = 0;
			$old_server_name = '#';
			if (is_array($all_vps)) foreach ($all_vps as $vps) {
				$vps->info();

				if (isset($_GET['m_nick']) && ($vps->ve["m_nick"] != $_GET['m_nick']))
					continue;
				if (isset($_GET['server_name']) && ($vps->ve["server_name"] != $_GET['server_name']))
					continue;

				if (($cfg_adminvps['table_heading']=='server' && $old_server_name!=$vps->ve['server_name']) ||
				   ($cfg_adminvps['table_heading']=='' && $old_server_name=='#')) { // add table header if...
				    if ($old_server_name!='#')
						$xtpl->table_out(); // once we are not here for the first time, we need to output the old table

					$xtpl->table_add_category('ID');
					$xtpl->table_add_category('HW');
					$xtpl->table_add_category(_("OWNER"));
					$xtpl->table_add_category(_("#PROC"));
					$xtpl->table_add_category(_("HOSTNAME"));
					$xtpl->table_add_category(_("USED RAM"));
					$xtpl->table_add_category(_("USED HDD"));
//					$xtpl->table_add_category(strtoupper(_("template")));
					$xtpl->table_add_category('');
					$xtpl->table_add_category('');
					$xtpl->table_add_category('');
					$xtpl->table_add_category('');
				}

				$xtpl->table_td('<a href="?page=adminvps&action=info&veid='.$vps->veid.'">'.$vps->veid.'</a>');
				$xtpl->table_td('<a href="?page=adminvps&server_name='.$vps->ve['server_name'].'">'.(isset($vps->ve["server_name"]) ? $vps->ve["server_name"] : false) . '</a>');
				$xtpl->table_td('<a href="?page=adminm&section=members&action=edit&id='.$vps->ve['m_id'].'">'.(isset($vps->ve["m_nick"]) ? $vps->ve["m_nick"] : false ).'</a>');
				$xtpl->table_td($vps->ve["vps_nproc"], false, true);
				$xtpl->table_td('<a href="?page=adminvps&action=info&veid='.$vps->veid.'"><img src="template/icons/vps_edit.png"  title="'._("Edit").'"/> '.(isset($vps->ve["vps_hostname"]) ? $vps->ve["vps_hostname"] : false).'</a>');

				$xtpl->table_td(sprintf('%4d MB',$vps->ve["vps_vm_used_mb"]), false, true);
				if ($vps->ve["vps_disk_used_mb"] > 0)
					$xtpl->table_td(sprintf('%.2f GB',round($vps->ve["vps_disk_used_mb"]/1024,2)), false, true);
				else $xtpl->table_td('---', false, true);
//				$xtpl->table_td($vps->ve["templ_label"]);
				$xtpl->table_td(($vps->ve["vps_up"]) ? '<a href="?page=adminvps&run=restart&veid='.$vps->veid.'"><img src="template/icons/vps_restart.png" title="'._("Restart").'"/></a>' : '<img src="template/icons/vps_restart_grey.png"  title="'._("Unable to restart").'" />');
				$xtpl->table_td(($vps->ve["vps_up"]) ? '<a href="?page=adminvps&run=stop&veid='.$vps->veid.'"><img src="template/icons/vps_stop.png"  title="'._("Stop").'"/></a>' : '<a href="?page=adminvps&run=start&veid='.$vps->veid.'"><img src="template/icons/vps_start.png"  title="'._("Start").'"/></a>');
				$xtpl->table_td('<a href="?page=console&veid='.$vps->veid.'"><img src="template/icons/console.png"  title="'._("Remote Console").'"/></a>');
				
				$can_delete = false;
				
				if ($playground_enabled && $_SESSION["member"]["m_id"] == $vps->ve["m_id"]) {
					foreach ($playground_servers as $pg)
						if ($pg["server_id"] == $vps->ve["server_id"]) {
							$can_delete = true;
							break;
						}
				}
				
				if ($_SESSION["is_admin"] || $can_delete){
				    $xtpl->table_td((!$vps->ve["vps_up"]) ? '<a href="?page=adminvps&action=delete&veid='.$vps->veid.'"><img src="template/icons/vps_delete.png"  title="'._("Delete").'"/></a>' : '<img src="template/icons/vps_delete_grey.png"  title="'._("Unable to delete").'"/>');
				} else {
				    $xtpl->table_td('<img src="template/icons/vps_delete_grey.png"  title="'._("Cannot delete").'"/>');
				}
				
				$color = '#FFCCCC';
				
				if($vps->ve["vps_deleted"])
					$color = '#A6A6A6';
				elseif($vps->ve["vps_up"])
					$color = false;
				
				$xtpl->table_tr($color);
				$listed_vps++;
				$old_server_name = $vps->ve['server_name'];
			}
			$xtpl->table_out(); // output the last table
			$_SESSION["member"]["number_owned_vps"] = count($all_vps);

	if ($_SESSION["is_admin"]) {
			$xtpl->table_add_category(_("Total number of VPS").':');
			$xtpl->table_add_category($listed_vps);
			$xtpl->table_out();
			}
if ($_SESSION["is_admin"] || $playground_mode) {
	$new_title = $playground_mode ? _("New playground VPS") : _("New VPS");
	$xtpl->sbar_add('<img src="template/icons/m_add.png"  title="'.$new_title.'" /> '.$new_title, '?page=adminvps&section=vps&action=new');
}

if ($_SESSION["is_admin"]) {
	$xtpl->sbar_add('<img src="template/icons/vps_ip_list.png"  title="'._("List IP addresses").'" /> '._("List IP addresses"), '?page=adminvps&action=alliplist');
}
}
if (isset($show_info) && $show_info) {
	if (!isset($veid)) $veid = $_GET["veid"];
	if ($_SESSION["is_admin"])
		$xtpl->title(_("VPS details").' '._("[Admin mode]"));
	else
		$xtpl->title(_("VPS details").' '._("[User mode]"));
	if (!$vps->exists)
      $vps = vps_load($veid);

	$vps->info();
	$xtpl->table_add_category('&nbsp;');
	$xtpl->table_add_category('&nbsp;');
	$xtpl->table_td('ID:');
	$xtpl->table_td($vps->veid);
		$xtpl->table_tr();
	$xtpl->table_td(_("Server").':');
	$s = new cluster_node($vps->ve["vps_server"]);
	 $xtpl->table_td($s->s["server_name"]);
		$xtpl->table_tr();
	$xtpl->table_td(_("Location").':');
	$xtpl->table_td($s->get_location_label());
	$xtpl->table_tr();
	$xtpl->table_td(_("Owner").':');
	$xtpl->table_td('<a href="?page=adminm&section=members&action=edit&id='.$vps->ve['m_id'].'">'.(isset($vps->ve["m_nick"]) ? $vps->ve["m_nick"] : false ).'</a>');
		$xtpl->table_tr();
	
	$xtpl->table_td(_("Status").':');
	$xtpl->table_td(
		(($vps->ve["vps_up"]) ?
			_("running").' (<a href="?page=adminvps&action=info&run=restart&veid='.$vps->veid.'">'._("restart").'</a>, <a href="?page=adminvps&action=info&run=stop&veid='.$vps->veid.'">'._("stop").'</a>'
			: 
			_("stopped").' (<a href="?page=adminvps&action=info&run=start&veid='.$vps->veid.'">'._("start").'</a>') .
			', <a href="?page=console&veid='.$vps->veid.'">'._("open remote console").'</a>)'
	);
		$xtpl->table_tr();
	$xtpl->table_td(_("Processes").':');
	$xtpl->table_td($vps->ve["vps_nproc"]);
		$xtpl->table_tr();
	$xtpl->table_td(_("Hostname").':');
	$xtpl->table_td($vps->ve["vps_hostname"]);
		$xtpl->table_tr();
	$xtpl->table_td(_("Distribution").':');
	$templ = template_by_id($vps->ve["vps_template"]);
	$xtpl->table_td($templ["templ_label"]);
		$xtpl->table_tr();
	if ($vps->ve["vps_specials_installed"]) {
	    $xtpl->table_td(_("Special features installed").':');
	    $xtpl->table_td($vps->ve["vps_specials_installed"]);
		$xtpl->table_tr();
	}
	$xtpl->table_td(_("Backuper").':');
	$xtpl->table_td(($vps->ve["vps_backup_enabled"] ? _("enabled") : _("disabled")));
		$xtpl->table_tr();
	
	if ($_SESSION["is_admin"]) {
		$xtpl->table_td(_("Backup lock").':');
		$xtpl->table_td($vps->ve["vps_backup_lock"] ? _("locked") : _("unlocked"));
		$xtpl->table_tr();
	}
	
	
	$xtpl->table_out();

    // set up ispcp
    if (preg_match("/ispcp/", $templ["special"]) && !preg_match("/ispcp/", $vps->ve["vps_specials_installed"])) {
	$ips = array();
	if ($iplist = $vps->iplist(4)){
	    foreach ($iplist as $ip) {
		$ips[$ip["ip_addr"]] = $ip["ip_addr"];
	    }
	}
	$ve_owner = member_load($vps->ve["m_id"]);
	$xtpl->form_create('?page=adminvps&action=special_setup_ispcp&veid='.$vps->veid, 'post');
	$xtpl->form_add_select(_("Use IPv4 address").':', 'ip_addr', $ips, '');
	$xtpl->form_add_input(_("Hostname FQDN").':', 'text', '30', 'setup_hostname', $_REQUEST["setup_hostname"], 'Important for mail to work correctly<br>eg. mail.mydomain.com');
	$xtpl->form_add_input(_("Admin panel FQDN").':', 'text', '30', 'setup_vhost', $_REQUEST["setup_vhost"], 'From where will be accessed the admin panel<br>eg. admin.mydomain.com');
	$xtpl->form_add_input(_("Admin e-mail").':', 'text', '30', 'setup_mail', $ve_owner->m["m_mail"], 'Where will ispCP send notices');
	$xtpl->form_add_input(_("Admin username").':', 'text', '30', 'setup_username', 'admin', '');
	$xtpl->form_add_input(_("Admin safe password").':', 'password', '30', 'passwd', '', '<br>Must contain characters as well as at least one number.', -5);
	$xtpl->form_add_input(_("Admin password again").':', 'password', '30', 'passwd2', '', '');
	$xtpl->form_add_checkbox(_("Install AWStats").':', 'awstats', '1', $_REQUEST["awstats"], $hint = '');
	$xtpl->table_add_category(_("Set up ispCP Omega"));
	$xtpl->table_add_category(' ');
	$xtpl->form_out(_("Go >>"));
    }

// Password changer
	$xtpl->form_create('?page=adminvps&action=passwd&veid='.$vps->veid, 'post');
	$xtpl->form_add_input(_("Unix username").':', 'text', '30', 'user', 'root', '');
	$xtpl->form_add_input(_("Safe password").':', 'password', '30', 'pass', '', '', -5);
	$xtpl->form_add_input(_("Once again").':', 'password', '30', 'pass2', '', '');
	if (!$_SESSION["is_admin"]) {
    $xtpl->table_td('');
    $xtpl->table_td('<b> Warning </b>: In order to set the password, <br />
                    it has to be <b>sent in plaintext</b> to the target server. <br />
                    This password changer is here only to enable first access to SSH of VPS. <br />
                    Please use some simple password here and then change it <br />
                    with <b>passwd</b> command once you\'ve logged onto SSH.');
    $xtpl->table_tr();
  }
	$xtpl->table_add_category(_("Set password"));
	$xtpl->table_add_category(_("(in your VPS, not in vpsAdmin!)"));
	$xtpl->form_out(_("Go >>"));

// IP addresses
	if ($_SESSION["is_admin"]) {
		$xtpl->form_create('?page=adminvps&action=addip&veid='.$vps->veid, 'post');
		if ($iplist = $vps->iplist())
			foreach ($iplist as $ip) {
				if ($ip["ip_v"] == 4)
					$xtpl->table_td(_("IPv4"));
				else $xtpl->table_td(_("IPv6"));
				$xtpl->table_td($ip["ip_addr"]);
				$xtpl->table_td('<a href="?page=adminvps&action=delip&ip='.$ip["ip_addr"].'&veid='.$vps->veid.'">('._("Remove").')</a>');
				$xtpl->table_tr();
				}
		$tmp["0"] = '-------';
		$vps_location = $db->findByColumnOnce("locations", "location_id", $cluster->get_location_of_server($vps->ve["vps_server"]));
		$free_4 = array_merge($tmp, get_free_ip_list(4, $vps->get_location()));
		if ($vps_location["location_has_ipv6"])
		    $free_6 = array_merge($tmp, get_free_ip_list(6, $vps->get_location()));
		$xtpl->form_add_select(_("Add IPv4 address").':', 'ip_recycle', $free_4, $vps->ve["m_id"]);
		if ($vps_location["location_has_ipv6"])
		    $xtpl->form_add_select(_("Add IPv6 address").':', 'ip6_recycle', $free_6, $vps->ve["m_id"]);
			$xtpl->table_tr();
		$xtpl->table_add_category(_("Add IP address"));
		$xtpl->table_add_category('&nbsp;');
			$xtpl->form_out(_("Go >>"));
	} else {
		$xtpl->table_add_category(_("Add IP address"));
		$xtpl->table_add_category(_("(Please contact administrator for change)"));
		if ($iplist = $vps->iplist())
			foreach ($iplist as $ip) {
				if ($ip["ip_v"] == 4)
					$xtpl->table_td(_("IPv4"));
				else $xtpl->table_td(_("IPv6"));
				$xtpl->table_td($ip["ip_addr"]);
				$xtpl->table_tr();
				}
		$xtpl->table_out();
	}

// DNS Server
	$xtpl->form_create('?page=adminvps&action=nameserver&veid='.$vps->veid, 'post');
	$xtpl->form_add_select(_("DNS servers address").':', 'nameserver', $cluster->list_dns_servers($vps->get_location()), $vps->ve["vps_nameserver"],  '');
	$xtpl->table_add_category(_("DNS server"));
	$xtpl->table_add_category('&nbsp;');
	$xtpl->form_out(_("Go >>"));

// Hostname change
	$xtpl->form_create('?page=adminvps&action=hostname&veid='.$vps->veid, 'post');
	$xtpl->form_add_input(_("Hostname").':', 'text', '30', 'hostname', $vps->ve["vps_hostname"], _("A-z, a-z"), 30);
	$xtpl->table_add_category(_("Hostname list"));
	$xtpl->table_add_category('&nbsp;');
	$xtpl->form_out(_("Go >>"));

// Reinstall
	$xtpl->form_create('?page=adminvps&action=reinstall&veid='.$vps->veid, 'post');
	$xtpl->form_add_checkbox(_("Reinstall distribution").':', 'reinstallsure', '1', false, $hint = _("Install base system again"));
	$xtpl->form_add_select(_("Distribution").':', 'vps_template', list_templates(), $vps->ve["vps_template"],  '');
	$xtpl->table_add_category(_("Reinstall"));
	$xtpl->table_add_category('&nbsp;');
	$xtpl->form_out(_("Go >>"));

// Configs
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
				$(\'<tr id="add_config_\' + add_config_id++ + \'"><td>'._('Add').':</td><td><select name="add_config[]">'.$options.'</select></td></tr>\').fadeIn("slow").insertBefore("#configs tr:nth-last-child(3)");
				dnd();
			});
			
			$(".delete-config").click(function (){
				$(this).closest("tr").remove();
			});
		});
    </script>');
	
	$vps_configs = $vps->get_configs();
	$configs = list_configs();
	
	if ($_SESSION["is_admin"])
		$xtpl->form_create('?page=adminvps&action=configs&veid='.$vps->veid, 'post');
	$xtpl->table_add_category(_('Configs'));
	
	if ($_SESSION["is_admin"])
		$xtpl->table_add_category('');
	
	foreach($vps_configs as $id => $label) {
		if ($_SESSION["is_admin"]) {
			$xtpl->form_add_select_pure('configs[]', $configs, $id);
			$xtpl->table_td('<a href="javascript:" class="delete-config">'._('delete').'</a>');
		} else $xtpl->table_td($label);
		$xtpl->table_tr(false, false, false, "order_$id");
	}
	
	if ($_SESSION["is_admin"]) {
		$xtpl->table_td('<input type="hidden" name="configs_order" id="configs_order" value="">' .  _('Add').':');
		$xtpl->form_add_select_pure('add_config[]', $configs_select);
		$xtpl->table_tr(false, false, false, 'add_config');
		$xtpl->form_add_checkbox(_("Notify owner").':', 'notify_owner', '1', true);
		$xtpl->table_tr(false, "nodrag nodrop", false);
		$xtpl->form_out(_("Go >>>"), 'configs', '<a href="javascript:" id="add_row">+</a>');
	} else {
		$xtpl->table_out();
	}
	
// Custom config
	if ($_SESSION["is_admin"]) {
		$xtpl->form_create('?page=adminvps&action=custom_config&veid='.$vps->veid, 'post');
		$xtpl->table_add_category(_("Custom config"));
		$xtpl->table_add_category('');
		$xtpl->form_add_textarea(_("Config").':', 60, 10, 'custom_config', $vps->ve["vps_config"], _('Applied last'));
		$xtpl->form_out(_("Go >>"));
	}

// Enable devices/capabilities
	$xtpl->form_create('?page=adminvps&action=enablefeatures&veid='.$vps->veid, 'post');
	if (!$vps->ve["vps_features_enabled"]) {
		$xtpl->table_td(_("Enable TUN/TAP"));
		$xtpl->table_td(_("disabled"));
		$xtpl->table_tr();
		$xtpl->table_td(_("Enable iptables"));
		$xtpl->table_td(_("disabled"));
		$xtpl->table_tr();
    $xtpl->table_td(_("Enable FUSE"));
    $xtpl->table_td(_("disabled"));
    $xtpl->table_tr();
    $xtpl->table_td(_("NFS server + client"));
    $xtpl->table_td(_("disabled"));
    $xtpl->table_tr();
    $xtpl->table_td(_("PPP"));
    $xtpl->table_td(_("disabled"));
    $xtpl->table_tr();
    $xtpl->form_add_checkbox(_("Enable all").':', 'enable', '1', false);
	} else {
    $xtpl->table_td(_("Enable TUN/TAP"));
    $xtpl->table_td(_("enabled"));
    $xtpl->table_tr();
		$xtpl->table_td(_("Enable iptables"));
		$xtpl->table_td(_("enabled"));
		$xtpl->table_tr();
    $xtpl->table_td(_("Enable FUSE"));
    $xtpl->table_td(_("enabled"));
    $xtpl->table_tr();
    $xtpl->table_td(_("NFS server + client"));
    $xtpl->table_td(_("enabled"));
    $xtpl->table_tr();
    $xtpl->table_td(_("PPP"));
    $xtpl->table_td(_("enabled"));
    $xtpl->table_tr();
	}
	$xtpl->table_add_category(_("Enable features"));
	$xtpl->table_add_category('&nbsp;');
	$xtpl->form_out(_("Go >>"));

// Owner change
	if ($_SESSION["is_admin"]) {
		$xtpl->form_create('?page=adminvps&action=chown&veid='.$vps->veid, 'post');
		$xtpl->form_add_select(_("Owner").':', 'm_id', members_list(), $vps->ve["m_id"]);
		$xtpl->table_add_category(_("Change owner"));
		$xtpl->table_add_category('&nbsp;');
		$xtpl->form_out(_("Go >>"));
	}

//Offline migration
	if ($_SESSION["is_admin"]) {
		$xtpl->form_create('?page=adminvps&action=offlinemigrate&veid='.$vps->veid, 'post');
		$xtpl->form_add_select(_("Target server").':', 'target_id', $cluster->list_servers($vps->ve["vps_server"], $vps->get_location(), true), '');
		$xtpl->form_add_checkbox(_("Stop before migration").':', 'stop', '1', false);
		$xtpl->table_add_category(_("Offline VPS Migration"));
		$xtpl->table_add_category('&nbsp;');
		$xtpl->form_out(_("Go >>"));
	}
// Online migration
	if ($_SESSION["is_admin"]) {
		$xtpl->form_create('?page=adminvps&action=onlinemigrate&veid='.$vps->veid, 'post');
		$xtpl->form_add_select(_("Target server:").':', 'target_id', $cluster->list_servers($vps->ve["vps_server"], $vps->get_location()), '');
		$xtpl->table_add_category(_("Online VPS Migration"));
		$xtpl->table_add_category('&nbsp;');
		$xtpl->form_out(_("Go >>"));
	}
// Clone
	if ($_SESSION["is_admin"] || $playground_mode) {
		$xtpl->form_create('?page=adminvps&action=clone&veid='.$vps->veid, 'post');
		
		if ($_SESSION["is_admin"])
			$xtpl->form_add_select(_("Target owner").':', 'target_owner_id', members_list(), $vps->ve["m_id"]);
		$xtpl->form_add_select(_("Target server").':', 'target_server_id', $playground_mode ? list_playground_servers() : $cluster->list_servers(), $vps->ve["vps_server"]);
		$xtpl->form_add_input(_("Hostname").':', 'text', '30', 'hostname', $vps->ve["vps_hostname"] . "-{$vps->veid}-clone");
		
		if ($_SESSION["is_admin"]) {
			$xtpl->form_add_checkbox(_("Clone configs").':', 'configs', '1', true);
			$xtpl->form_add_checkbox(_("Clone features").':', 'features', '1', true);
			$xtpl->form_add_checkbox(_("Clone backuper").':', 'backuper', '1', true);
		}
		$xtpl->table_add_category($playground_mode ? _("Clone to playground") : _("Clone"));
		$xtpl->table_add_category('&nbsp;');
		$xtpl->form_out(_("Go >>"));
	}
	
// Backuper
	$xtpl->form_create('?page=adminvps&action=setbackuper&veid='.$vps->veid, 'post');
	if ($_SESSION["is_admin"]) {
		$xtpl->form_add_checkbox(_("Backup enabled").':', 'backup_enabled', '1', $vps->ve["vps_backup_enabled"]);
		$xtpl->form_add_select(_("Export").':', 'backup_export', get_nas_export_list(false), $vps->ve["vps_backup_export"]);
		$xtpl->form_add_checkbox(_("Notify owner").':', 'notify_owner', '1', true);
	}
	$xtpl->form_add_textarea(_("Exclude files").':', 60, 10, "backup_exclude", $vps->ve["vps_backup_exclude"], _("One path per line"));
	$xtpl->table_add_category(_("Backuper"));
	$xtpl->table_add_category('&nbsp;');
	$xtpl->form_out(_("Go >>"));

}

$xtpl->sbar_out(_("Manage VPS"));

} else $xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
?>
