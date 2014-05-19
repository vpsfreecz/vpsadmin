<?php

function is_mount_dst_valid($dst) {
	$dst = trim($dst);
	
	if(!preg_match("/^[a-zA-Z0-9\_\-\/\.]+$/", $dst) || preg_match("/\.\./", $dst))
		return false;
	
	if (strpos($dst, "/") !== 0)
		$dst = "/" . $dst;
	
	return $dst;
}

function is_ds_valid($p) {
	$p = trim($p);
	
	if(preg_match("/^\//", $p))
		return false;
	
	if(!preg_match("/^[a-zA-Z0-9\/\-\:\.\_]+$/", $p))
		return false;
	
	if(preg_match("/\/\//", $p))
		return false;
	
	return $p;
}

function export_add_form($target, $default = false) {
	global $xtpl, $NAS_QUOTA_UNITS, $NAS_EXPORT_TYPES;
	
	$empty = array(0 => ($_GET["for"] == "member" ? "--- new member ---" : "--- VPS owner ---"));
	$members = members_list();
	$ds_help = _("Allowed chars: a-z A-Z 0-9 _ : . - /<br>".
	             "Must NOT start with '/'.<br>".
	             "Must NOT contain more '/' in row.<br>".
	             "Create child exports using '/'. They will share parent's quota.");
	
	if($default) {
		$members = $empty + $members;
		$ds_help .= "<br>%member_id% - ID of newly created member";
		if($_GET["for"] == "vps")
			$ds_help .= "<br>%veid% - ID of newly created VPS";
	}
	
	$xtpl->table_title(_("Add export"));
	$xtpl->form_create($target, 'post');
	if ($_SESSION["is_admin"])
		$xtpl->form_add_select(_("Member").':', 'member', $members, $_POST["member"]);
	$xtpl->form_add_select(_("Pool").':', 'root_id', nas_root_list_where($_SESSION["is_admin"] ? '' : "user_export = 1"), $_POST["root_id"]);
	if ($_SESSION["is_admin"])
		$xtpl->form_add_input(_("Dataset").':', 'text', '30', 'dataset', $_POST["dataset"], $ds_help);
	$xtpl->form_add_input(_("Path").':', 'text', '30', 'path', $_POST["path"], $ds_help);
	
	$xtpl->table_td(_("Quota").':');
	$xtpl->form_add_input_pure('text', '30', 'quota_val', $_POST["quota_val"] ? $_POST["quota_val"] : '0');
	$xtpl->form_add_select_pure('quota_unit', $NAS_QUOTA_UNITS, $_POST["quota_unit"]);
	$xtpl->table_td(_("0 is none"));
	$xtpl->table_tr();
	
	if ($_SESSION["is_admin"]) {
		$xtpl->form_add_checkbox(_("User editable").':', 'user_editable', '1', $_POST["user_editable"]);
		$xtpl->form_add_select(_("Type").':', 'type', $NAS_EXPORT_TYPES, $_POST["type"]);
	}
	
	$xtpl->form_out(_("Export"));
}

function export_edit_form($target, $e) {
	global $xtpl, $NAS_EXPORT_TYPES;
	
	$q = nas_quota_to_val_unit($e["export_quota"]);
	
	$xtpl->table_title(_("Edit export")." ".$e["server_name"].": ". $e["path"]);
	$xtpl->form_create($target . '&id='.$_GET["id"], 'post');
	$xtpl->table_td(_("Quota").':');
	$xtpl->form_add_input_pure('text', '30', 'quota_val', $q[0]);
	$xtpl->form_add_select_pure('quota_unit', array("m" => "MiB", "g" => "GiB", "t" => "TiB"), $q[1]);
	$xtpl->table_td(_("0 is none"));
	$xtpl->table_tr();
	if ($_SESSION["is_admin"]) {
		$xtpl->form_add_checkbox(_("User editable").':', 'user_editable', '1', $e["user_editable"]);
		$xtpl->form_add_select(_("Type").':', 'type', $NAS_EXPORT_TYPES, $e["export_type"]);
	}
	$xtpl->form_out(_("Save"));
}

function mount_add_form($target_e, $target_c, $default = false) {
	global $STORAGE_MOUNT_MODES_RO_RW, $STORAGE_MOUNT_TYPES, $xtpl, $cluster_cfg;
	
	$vps_list = get_user_vps_list();
	
	if($default)
		$vps_list = array(0 => _("--- new VPS ---")) + $vps_list;
	
	$xtpl->table_title(_("Mount export"));
	$xtpl->form_create($target_e, 'post');
	$xtpl->form_add_select(_("Export").':', 'export_id', get_nas_export_list($default), $_POST["export_id"]);
	$xtpl->form_add_select(_("VPS").':', 'vps_id', $vps_list, $_POST["vps_id"]);
	$xtpl->form_add_select(_("Access mode").':', 'access_mode', $STORAGE_MOUNT_MODES_RO_RW, $_POST["access_mode"]);
	$xtpl->form_add_input(_("Destination").':', 'text', '50', 'dst', $_POST["dst"], _("Path is relative to VPS root"));
	if ($_SESSION["is_admin"]) {
		$xtpl->form_add_input(_("Mount options").':', 'text', '50', 'm_opts', $_POST["m_opts"] ? $_POST["m_opts"] : $cluster_cfg->get("nas_default_mount_options"), '');
		$xtpl->form_add_input(_("Umount options").':', 'text', '50', 'u_opts', $_POST["u_opts"] ? $_POST["u_opts"] : $cluster_cfg->get("nas_default_umount_options"), '');
	}
	$xtpl->form_add_input(_("Pre-mount command").':', 'text', '50', 'cmd_premount', $_POST["cmd_premount"], _("Command that is executed within VPS context <strong>before</strong> mount"));
	$xtpl->form_add_input(_("Post-mount command").':', 'text', '50', 'cmd_postmount', $_POST["cmd_postmount"], _("Command that is executed within VPS context <strong>after</strong> mount"));
	$xtpl->form_add_input(_("Pre-umount command").':', 'text', '50', 'cmd_preumount', $_POST["cmd_preumount"], _("Command that is executed within VPS context <strong>before</strong> umount"));
	$xtpl->form_add_input(_("Post-umount command").':', 'text', '50', 'cmd_postumount', $_POST["cmd_postumount"], _("Command that is executed within VPS context <strong>after</strong> umount"));
	$xtpl->form_add_checkbox(_("Mount on save").':', 'mount_immediately', '1', $_POST["mount_immediately"] ? $_POST["mount_immediately"] : true);
	$xtpl->form_out(_("Add mount"));
	
	if ($_SESSION["is_admin"]) {
		$nodes = list_servers();
		$empty = array("" => "---");
		
		$xtpl->table_title(_("Custom mount"));
		$xtpl->form_create($target_c, 'post');
		$xtpl->form_add_select(_("VPS").':', 'vps_id', $vps_list, $_POST["vps_id"]);
		$xtpl->form_add_select(_("Access mode").':', 'access_mode', $STORAGE_MOUNT_MODES_RO_RW, $_POST["access_mode"]);
		$xtpl->form_add_select(_("Source node").':', 'source_node_id', array_merge($empty, $nodes), $_POST["source_node_id"], '');
		$xtpl->form_add_input(_("Source").':', 'text', '50', 'src', $_POST["src"], _("Path is relative to source node root if specified, otherwise absolute"));
		$xtpl->form_add_input(_("Destination").':', 'text', '50', 'dst', $_POST["dst"], _("Path is relative to VPS root"));
		$xtpl->form_add_input(_("Mount options").':', 'text', '50', 'm_opts', $_POST["m_opts"] ? $_POST["m_opts"] : $cluster_cfg->get("nas_default_mount_options"), '');
		$xtpl->form_add_input(_("Umount options").':', 'text', '50', 'u_opts', $_POST["u_opts"] ? $_POST["u_opts"] : $cluster_cfg->get("nas_default_umount_options"), '');
		$xtpl->form_add_select(_("Type").':', 'type', $STORAGE_MOUNT_TYPES, $_POST["type"]);
		$xtpl->form_add_input(_("Pre-mount command").':', 'text', '50', 'cmd_premount', $_POST["cmd_premount"], _("Command that is executed within VPS context <strong>before</strong> mount"));
		$xtpl->form_add_input(_("Post-mount command").':', 'text', '50', 'cmd_postmount', $_POST["cmd_postmount"], _("Command that is executed within VPS context <strong>after</strong> mount"));
		$xtpl->form_add_input(_("Pre-umount command").':', 'text', '50', 'cmd_preumount', $_POST["cmd_preumount"], _("Command that is executed within VPS context <strong>before</strong> umount"));
		$xtpl->form_add_input(_("Post-umount command").':', 'text', '50', 'cmd_postumount', $_POST["cmd_postumount"], _("Command that is executed within VPS context <strong>after</strong> umount"));
		$xtpl->form_add_checkbox(_("Mount on save").':', 'mount_immediately', '1', $_POST["mount_immediately"] ? $_POST["mount_immediately"] : true);
		$xtpl->form_out(_("Add mount"));
	}
}

function mount_edit_form($target, $m, $default = false) {
	global $STORAGE_MOUNT_MODES_RO_RW, $STORAGE_MOUNT_TYPES, $xtpl;
	
	$e_list = get_nas_export_list($default);
	$nodes = list_servers();
	$empty = array("" => "---");
	
	$xtpl->table_title(_("Edit mount")." ".$m["dst"]);
	$xtpl->form_create($target . '&id='.$_GET["id"], 'post');
	$xtpl->form_add_select(_("Export").':', 'export_id', $empty + $e_list, $_POST["export_id"] ? $_POST["export_id"] : (int)$m["storage_export_id"]);
	$xtpl->form_add_select(_("VPS").':', 'vps_id', get_user_vps_list(), $_POST["vps_id"] ? $_POST["vps_id"] : $m["vps_id"]);
	$xtpl->form_add_select(_("Access mode").':', 'access_mode', $STORAGE_MOUNT_MODES_RO_RW, $_POST["mode"] ? $_POST["mode"] : $m["mode"]);
	if ($_SESSION["is_admin"]) {
		$xtpl->form_add_select(_("Source node").':', 'source_node_id', $empty + $nodes, $_POST["source_node_id"] ? $_POST["source_node_id"] : $m["server_id"], _("Has no effect if export is selected."));
		$xtpl->form_add_input(_("Source").':', 'text', '50', 'src', $_POST["src"] ? $_POST["src"] : $m["src"], _("Path is relative to source node root if specified, otherwise absolute. Has no effect if export is selected."));
	}
	$xtpl->form_add_input(_("Destination").':', 'text', '50', 'dst', $_POST["dst"] ? $_POST["dst"] : $m["dst"], _("Path is relative to VPS root,<br>allowed chars: a-Z A-Z 0-9 _ - . /"));
	if ($_SESSION["is_admin"]) {
		$xtpl->form_add_input(_("Mount options").':', 'text', '50', 'm_opts', $_POST["m_opts"] ? $_POST["m_opts"] : $m["mount_opts"], '');
		$xtpl->form_add_input(_("Umount options").':', 'text', '50', 'u_opts', $_POST["u_opts"] ? $_POST["u_opts"] : $m["umount_opts"], '');
		$xtpl->form_add_select(_("Type").':', 'type', $STORAGE_MOUNT_TYPES, $_POST["type"] ? $_POST["type"] : $m["mount_type"]);
	}
	$xtpl->form_add_input(_("Pre-mount command").':', 'text', '50', 'cmd_premount', $_POST["cmd_premount"] ? $_POST["cmd_premount"] : $m["cmd_premount"], _("Command that is executed within VPS context <strong>before</strong> mount"));
	$xtpl->form_add_input(_("Post-mount command").':', 'text', '50', 'cmd_postmount', $_POST["cmd_postmount"] ? $_POST["cmd_postmount"] : $m["cmd_postmount"], _("Command that is executed within VPS context <strong>after</strong> mount"));
	$xtpl->form_add_input(_("Pre-umount command").':', 'text', '50', 'cmd_preumount', $_POST["cmd_preumount"] ? $_POST["cmd_preumount"] : $m["cmd_preumount"], _("Command that is executed within VPS context <strong>before</strong> umount"));
	$xtpl->form_add_input(_("Post-umount command").':', 'text', '50', 'cmd_postumount', $_POST["cmd_postumount"] ? $_POST["cmd_postumount"] : $m["cmd_postumount"], _("Command that is executed within VPS context <strong>after</strong> umount"));
	$xtpl->form_add_checkbox(_("Remount on save").':', 'remount_immediately', '1', $_POST["type"] ? $_POST["remount_immediately"] : true, "<strong>"._("Recommended")."</strong>");
	$xtpl->form_out(_("Save"));
}
