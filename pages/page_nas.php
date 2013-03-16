<?php

function export_add_form() {
	global $xtpl, $NAS_QUOTA_UNITS;
	
	$xtpl->table_title(_("Add export"));
	$xtpl->form_create('?page=nas&action=export_add_save', 'post');
	if ($_SESSION["is_admin"])
		$xtpl->form_add_select(_("Member").':', 'member', members_list(), $_POST["member"]);
	$xtpl->form_add_select(_("Server").':', 'root_id', nas_root_list_where($_SESSION["is_admin"] ? '' : "user_export = 1"), $_POST["root_id"]);
	if ($_SESSION["is_admin"])
		$xtpl->form_add_input(_("Dataset").':', 'text', '30', 'dataset', $_POST["dataset"], _("Allowed chars: a-z A-Z 0-9 _ : . -"));
	$xtpl->form_add_input(_("Path").':', 'text', '30', 'path', $_POST["path"], _("Allowed chars: a-z A-Z 0-9 _ : . -"));
	
	$xtpl->table_td(_("Quota").':');
	$xtpl->form_add_input_pure('text', '30', 'quota_val', $_POST["quota_val"] ? $_POST["quota_val"] : '0');
	$xtpl->form_add_select_pure('quota_unit', $NAS_QUOTA_UNITS, $_POST["quota_unit"]);
	$xtpl->table_tr();
	
	if ($_SESSION["is_admin"])
		$xtpl->form_add_checkbox(_("User editable").':', 'user_editable', '1', $_POST["user_editable"]);
	
	$xtpl->form_out(_("Export"));
	
	$xtpl->sbar_add(_("Back"), '?page=nas');
}

if ($_SESSION["logged_in"]) {
	
	$list_nas = false;
	
	$xtpl->title(_("Network-attached storage"));
	
	switch ($_GET["action"]) {
		case "export_add":
			export_add_form();
			break;
			
		case "export_add_save":
			if ($_POST["node"] && $_POST["path"])
				
				$ok = false;
				$m = new member_load($_SESSION["is_admin"] ? $_POST["member"] : $_SESSION["member"]["m_id"]);
				
				foreach (nas_root_list_where($_SESSION["is_admin"] ? '' : "user_export = 1") as $r_id => $r) {
					if ($r_id == $_POST["root_id"])
						$ok = true;
				}
				
				$allowed = "/^[a-zA-Z0-9\/\-\:\.\_]+$/";
				$path = trim($_POST["path"]);
				$ds = trim($_POST["dataset"]);
				
				if (!preg_match($allowed, $path)) {
					$xtpl->perex(_("Path contains forbidden characters"), '');
					export_add_form();
				} else if ($_SESSION["is_admin"] && !preg_match($allowed, $ds)) {
					$xtpl->perex(_("Dataset contains forbidden characters"), '');
					export_add_form();
				} else if ($ok && $m->exists) {
					nas_export_add(
						$_SESSION["is_admin"] ? $_POST["member"] : $_SESSION["member"]["m_id"],
						$_POST["root_id"],
						$_SESSION["is_admin"] ? $ds : NULL,
						$path,
						$_POST["quota_val"] * (2 << $NAS_UNITS_TR[$_POST["quota_unit"]]),
						$_SESSION["is_admin"] ? $_POST["user_editable"] : -1
					);
					
					$list_nas = true;
				}
			break;
		
		case "export_edit":
			$e = nas_get_export_by_id($_GET["id"]);
			
			if (nas_can_user_manage_export($e)) {
				$q = nas_quota_to_val_unit($e["export_quota"]);
				
				$xtpl->table_title(_("Edit export")." ".$e["server_name"].": ". $e["path"]);
				$xtpl->form_create('?page=nas&action=export_edit_save&id='.$_GET["id"], 'post');
				$xtpl->table_td(_("Quota").':');
				$xtpl->form_add_input_pure('text', '30', 'quota_val', $q[0]);
				$xtpl->form_add_select_pure('quota_unit', array("m" => "MiB", "g" => "GiB", "t" => "TiB"), $q[1]);
				$xtpl->table_tr();
				if ($_SESSION["is_admin"])
					$xtpl->form_add_checkbox(_("User editable").':', 'user_editable', '1', $e["user_editable"]);
				$xtpl->form_out(_("Save"));
			}
			
			$xtpl->sbar_add(_("Back"), '?page=nas');
			break;
			
		case "export_edit_save":
			if ($_GET["id"] && $_POST["quota_val"] && $_POST["quota_unit"]) {
				$e = nas_get_export_by_id($_GET["id"]);
				// FIXME: control if quota is not less than used
				
				if (nas_can_user_manage_export($e))
					nas_export_update($_GET["id"], $_POST["quota_val"] * (2 << $NAS_UNITS_TR[$_POST["quota_unit"]]), $_SESSION["is_admin"] ? $_POST["user_editable"] : -1);
				
				$xtpl->perex(_("Export updated."), '');
			}
			
			$list_nas = true;
			break;
		
		case "export_del":
			break;
		
		case "mount_add":
			$xtpl->table_title(_("Mount export"));
			$xtpl->form_create('?page=nas&action=mount_export_add_save', 'post');
			$xtpl->form_add_select(_("Export").':', 'export_id', get_nas_export_list());
			$xtpl->form_add_select(_("VPS").':', 'vps_id', get_user_vps_list());
			$xtpl->form_add_select(_("Access mode").':', 'access_mode', $STORAGE_MOUNT_MODES_RO_RW);
			$xtpl->form_add_input(_("Destination").':', 'text', '50', 'dst', '', _("Path is relative to VPS root"));
			if ($_SESSION["is_admin"]) {
				$xtpl->form_add_input(_("Mount options").':', 'text', '50', 'm_opts', $cluster_cfg->get("nas_default_mount_options"), '');
				$xtpl->form_add_input(_("Umount options").':', 'text', '50', 'u_opts', $cluster_cfg->get("nas_default_umount_options"), '');
			}
			$xtpl->form_add_input(_("Pre-mount command").':', 'text', '50', 'cmd_premount', '', _("Command that is executed within VPS context <strong>before</strong> mount"));
			$xtpl->form_add_input(_("Post-mount command").':', 'text', '50', 'cmd_postmount', '', _("Command that is executed within VPS context <strong>after</strong> mount"));
			$xtpl->form_add_input(_("Pre-umount command").':', 'text', '50', 'cmd_preumount', '', _("Command that is executed within VPS context <strong>before</strong> umount"));
			$xtpl->form_add_input(_("Post-umount command").':', 'text', '50', 'cmd_postumount', '', _("Command that is executed within VPS context <strong>after</strong> umount"));
			$xtpl->form_add_checkbox(_("Mount immediately").':', 'mount_immediately', '1', true);
			$xtpl->form_out(_("Add mount"));
			
			if ($_SESSION["is_admin"]) {
				$nodes = list_servers();
				$empty = array("" => "---");
				
				$xtpl->table_title(_("Custom mount"));
				$xtpl->form_create('?page=nas&action=mount_custom_add_save', 'post');
				$xtpl->form_add_select(_("VPS").':', 'vps_id', get_user_vps_list());
				$xtpl->form_add_select(_("Access mode").':', 'access_mode', $STORAGE_MOUNT_MODES_RO_RW);
				$xtpl->form_add_select(_("Source node").':', 'source_node_id', array_merge($empty, $nodes), '', '');
				$xtpl->form_add_input(_("Source").':', 'text', '50', 'src', '', _("Path is relative to source node root if specified, otherwise absolute"));
				$xtpl->form_add_input(_("Destination").':', 'text', '50', 'dst', '', _("Path is relative to VPS root"));
				$xtpl->form_add_input(_("Mount options").':', 'text', '50', 'm_opts', $cluster_cfg->get("nas_default_mount_options"), '');
				$xtpl->form_add_input(_("Umount options").':', 'text', '50', 'u_opts', $cluster_cfg->get("nas_default_umount_options"), '');
				$xtpl->form_add_select(_("Type").':', 'type', $STORAGE_MOUNT_TYPES);
				$xtpl->form_add_input(_("Pre-mount command").':', 'text', '50', 'cmd_premount', '', _("Command that is executed within VPS context <strong>before</strong> mount"));
				$xtpl->form_add_input(_("Post-mount command").':', 'text', '50', 'cmd_postmount', '', _("Command that is executed within VPS context <strong>after</strong> mount"));
				$xtpl->form_add_input(_("Pre-umount command").':', 'text', '50', 'cmd_premount', '', _("Command that is executed within VPS context <strong>before</strong> umount"));
				$xtpl->form_add_input(_("Post-umount command").':', 'text', '50', 'cmd_postmount', '', _("Command that is executed within VPS context <strong>after</strong> umount"));
				$xtpl->form_add_checkbox(_("Mount immediately").':', 'mount_immediately', '1', true);
				$xtpl->form_out(_("Add mount"));
			}
			
			$xtpl->sbar_add(_("Back"), '?page=nas');
			break;
		
		case "mount_export_add_save":
			if ($_POST["export_id"] && $_POST["dst"] && $_POST["vps_id"]) {
				$e = nas_get_export_by_id($_POST["export_id"]);
				$vps = new vps_load($_POST["vps_id"]);
				
				if (nas_can_user_add_mount($e, $vps))
					nas_mount_add(
						$_POST["export_id"],
						$_POST["vps_id"],
						$_POST["access_mode"],
						0,
						"",
						$_POST["dst"],
						$_SESSION["is_admin"] ? $_POST["m_opts"] : NULL,
						$_SESSION["is_admin"] ? $_POST["u_opts"] : NULL,
						"nfs",
						$_POST["cmd_premount"],
						$_POST["cmd_postmount"],
						$_POST["cmd_preumount"],
						$_POST["cmd_postumount"],
						$_POST["mount_immediately"]
					);
			}
			
			$list_nas = true;
			break;
		
		case "mount_custom_add_save":
			if ($_SESSION["is_admin"] && $_POST["vps_id"] && $_POST["src"] && $_POST["dst"]) {
				$e = nas_get_export_by_id($_POST["export_id"]);
				$vps = new vps_load($_POST["vps_id"]);
				
				if (nas_can_user_add_mount($e, $vps))
					nas_mount_add(
						0,
						$_POST["vps_id"],
						$_POST["access_mode"],
						$_POST["source_node_id"],
						$_POST["src"],
						$_POST["dst"],
						$_POST["m_opts"],
						$_POST["u_opts"],
						$_POST["type"],
						$_POST["cmd_premount"],
						$_POST["cmd_postmount"],
						$_POST["cmd_preumount"],
						$_POST["cmd_postumount"],
						$_POST["mount_immediately"]
					);
			}
			break;
		
		case "mount_edit":
			$m = nas_get_mount_by_id($_GET["id"]);
			$vps = new vps_load($m["vps_id"]);
			
			if (nas_can_user_manage_mount($m, $vps)) {
				$e_list = get_nas_export_list();
				$nodes = list_servers();
				$empty = array("" => "---");
				
				$xtpl->table_title(_("Edit mount")." ".$m["dst"]);
				$xtpl->form_create('?page=nas&action=mount_edit_save&id='.$_GET["id"], 'post');
				$xtpl->form_add_select(_("Export").':', 'export_id', $empty + $e_list, (int)$m["storage_export_id"]);
				$xtpl->form_add_select(_("VPS").':', 'vps_id', get_user_vps_list(), $m["vps_id"]);
				$xtpl->form_add_select(_("Access mode").':', 'access_mode', $STORAGE_MOUNT_MODES_RO_RW, $m["mode"]);
				if ($_SESSION["is_admin"]) {
					$xtpl->form_add_select(_("Source node").':', 'source_node_id', $empty + $nodes, $m["server_id"], _("Has no effect if export is selected."));
					$xtpl->form_add_input(_("Source").':', 'text', '50', 'src', $m["src"], _("Path is relative to source node root if specified, otherwise absolute. Has no effect if export is selected."));
				}
				$xtpl->form_add_input(_("Destination").':', 'text', '50', 'dst', $m["dst"], _("Path is relative to VPS root"));
				if ($_SESSION["is_admin"]) {
					$xtpl->form_add_input(_("Mount options").':', 'text', '50', 'm_opts', $m["mount_opts"], '');
					$xtpl->form_add_input(_("Umount options").':', 'text', '50', 'u_opts', $m["umount_opts"], '');
					$xtpl->form_add_select(_("Type").':', 'type', $STORAGE_MOUNT_TYPES, $m["type"]);
				}
				$xtpl->form_add_input(_("Pre-mount command").':', 'text', '50', 'cmd_premount', $m["cmd_premount"], _("Command that is executed within VPS context <strong>before</strong> mount"));
				$xtpl->form_add_input(_("Post-mount command").':', 'text', '50', 'cmd_postmount', $m["cmd_postmount"], _("Command that is executed within VPS context <strong>after</strong> mount"));
				$xtpl->form_add_input(_("Pre-umount command").':', 'text', '50', 'cmd_preumount', $m["cmd_preumount"], _("Command that is executed within VPS context <strong>before</strong> umount"));
				$xtpl->form_add_input(_("Post-umount command").':', 'text', '50', 'cmd_postumount', $m["cmd_postumount"], _("Command that is executed within VPS context <strong>after</strong> umount"));
				$xtpl->form_add_checkbox(_("Remount immediately").':', 'remount_immediately', '1', true, "<strong>"._("Recommended")."</strong>");
				$xtpl->form_out(_("Save"));
			}
			
			$xtpl->sbar_add(_("Back"), '?page=nas');
			break;
		
		case "mount_edit_save":
			if ($_GET["id"] && ($_POST["export_id"] || $_POST["src"])) {
				$m = nas_get_mount_by_id($_GET["id"]);
				$vps = new vps_load($_POST["vps_id"]);
				
				if (nas_can_user_manage_mount($m, $vps))
					nas_mount_update(
						$_GET["id"],
						$_POST["export_id"],
						$_POST["vps_id"],
						$_POST["access_mode"],
						$_SESSION["is_admin"] ? $_POST["source_node_id"] : NULL,
						$_SESSION["is_admin"] ? $_POST["src"] : NULL,
						$_POST["dst"],
						$_SESSION["is_admin"] ? $_POST["m_opts"] : NULL,
						$_SESSION["is_admin"] ? $_POST["u_opts"] : NULL,
						$_SESSION["is_admin"] ? $_POST["type"] : NULL,
						$_POST["cmd_premount"],
						$_POST["cmd_postmount"],
						$_POST["cmd_preumount"],
						$_POST["cmd_postumount"],
						$_POST["mount_immediately"]
					);
				
				$xtpl->perex(_("Mount updated."), '');
			} else $xtpl->perex(_("Mount NOT updated."), '');
			
			$list_nas = true;
			break;
		
		case "mount_del":
			break;
		
		default:
			$list_nas = true;
			break;
	}
	
	if ($list_nas) {
		$xtpl->sbar_add(_("Add export"), '?page=nas&action=export_add');
		$xtpl->sbar_add(_("Add mount"), '?page=nas&action=mount_add');
			
		$xtpl->table_title(_("Exports"));
		$xtpl->table_add_category(_("Member"));
		$xtpl->table_add_category(_("Server"));
		if ($_SESSION["is_admin"])
			$xtpl->table_add_category(_("Dataset"));
		$xtpl->table_add_category(_("Path"));
		$xtpl->table_add_category(_("Quota"));
		$xtpl->table_add_category(_("Used"));
		$xtpl->table_add_category(_("Available"));
		$xtpl->table_add_category('');
		$xtpl->table_add_category('');
		
		$exports = nas_list_exports();
		
		foreach ($exports as $e) {
			$xtpl->table_td($e["m_nick"]);
			$xtpl->table_td($e["label"]);
			if ($_SESSION["is_admin"])
				$xtpl->table_td($e["dataset"]);
			$xtpl->table_td($e["path"]);
			$xtpl->table_td(nas_size_to_humanreadable($e["export_quota"]));
			$xtpl->table_td(nas_size_to_humanreadable($e["export_used"]));
			$xtpl->table_td(nas_size_to_humanreadable($e["export_avail"]));
			
			if (nas_can_user_manage_export($e)) {
				$xtpl->table_td('<a href="?page=nas&action=export_edit&id='.$e["export_id"].'"><img src="template/icons/edit.png" title="'._("Edit").'"></a>');
				$xtpl->table_td('<a href="?page=nas&action=export_del&id='.$e["export_id"].'"><img src="template/icons/delete.png" title="'._("Delete").'"></a>');
			} else {
				$xtpl->table_td('');
				$xtpl->table_td('');
			}
			
			$xtpl->table_tr();
		}
		
		$xtpl->table_out();
		
		$xtpl->table_title(_("Mounts"));
		$xtpl->table_add_category(_("VEID"));
		$xtpl->table_add_category(_("Source"));
		$xtpl->table_add_category(_("Destination"));
// 		$xtpl->table_add_category(_("Options"));
		$xtpl->table_add_category(_("Mount"));
		$xtpl->table_add_category(_("Umount"));
		$xtpl->table_add_category('');
		$xtpl->table_add_category('');
		
		$mounts = nas_list_mounts();
		
		foreach ($mounts as $m) {
			$xtpl->table_td($m["vps_id"]);
			$xtpl->table_td($m["storage_export_id"] ? $m["root_label"].":".$m["path"] : $m["server_name"].":".$m["src"]);
			$xtpl->table_td($m["dst"]);
// 			$xtpl->table_td($m["options"]);
			$xtpl->table_td('<a href="?page=nas&action=mount&id='.$m["mount_id"].'">'._("Mount").'</a>');
			$xtpl->table_td('<a href="?page=nas&action=umount&id='.$m["mount_id"].'">'._("Umount").'</a>');
			$xtpl->table_td('<a href="?page=nas&action=mount_edit&id='.$m["mount_id"].'"><img src="template/icons/edit.png" title="'._("Edit").'"></a>');
			$xtpl->table_td('<a href="?page=nas&action=mount_del&id='.$m["mount_id"].'"><img src="template/icons/delete.png" title="'._("Delete").'"></a>');
			$xtpl->table_tr();
		}
		
		$xtpl->table_out();
	}
	
	$xtpl->sbar_out(_("Manage NAS"));
	
} else {
	$xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
}
