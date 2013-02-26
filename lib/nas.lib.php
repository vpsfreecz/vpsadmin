<?php

$STORAGE_TYPES = array("per_member" => _("Per member"), "per_vps" => _("Per VPS"));
$STORAGE_MOUNT_TYPES = array("bind" => _("Bind"), "nfs" => _("NFS"));
$STORAGE_MOUNT_MODES = array("none" => _("None"), "ro" => _("Read only"), "rw" => _("Read and write"));
$STORAGE_MOUNT_MODES_RO_RW = array("ro" => _("Read only"), "rw" => _("Read and write"));
$NAS_QUOTA_UNITS = array("m" => "MiB", "g" => "GiB", "t" => "TiB");
$NAS_UNITS_TR = array("m" => 19, "g" => 29, "t" => 39);

function get_nas_nodes_where($cond) {
	global $db;
	
	$ret = array();
	$rs = $db->query("SELECT * FROM servers s INNER JOIN node_storage ns ON s.server_id = ns.node_id WHERE server_type = 'storage' AND " . $cond);
	
	while ($row = $db->fetch_array($rs)) {
		$ret[] = $row;
	}
	
	return $ret;
}

function get_nas_node_list_where($cond) {
	$nodes = get_nas_nodes_where($cond);
	$ret = array();
	
	foreach ($nodes as $n)
		$ret[$n["server_id"]] = $n["server_name"];
	
	return $ret;
}

function get_nas_export_list() {
	global $db;
	
	$ret = array();
	$rs = $db->query("SELECT * FROM storage_export e INNER JOIN servers s ON s.server_id = e.server_id WHERE server_type = 'storage' ORDER BY s.server_id ASC, path ASC");
	
	while ($row = $db->fetch_array($rs)) {
		$ret[$row["id"]] = $row["server_name"].": ".$row["path"];
	}
	
	return $ret;
}

function nas_get_export_by_id($id) {
	global $db;
	
	$rs = $db->query("SELECT * FROM storage_export e INNER JOIN servers s ON s.server_id = e.server_id WHERE server_type = 'storage' AND e.id = '".$db->check($id)."'");
	return $db->fetch_array($rs);
}

function nas_export_add($member, $node, $dataset, $path, $quota, $user_editable) {
	global $db;
	
	if ($dataset === NULL)
		$dataset = $path;
	
	$db->query("INSERT INTO storage_export SET
				member_id = '".$db->check($member)."',
				server_id = '".$db->check($node)."',
				dataset = '".$db->check($dataset)."',
				path = '".$db->check($path)."',
				quota = '".$db->check($quota)."',
				user_editable = '".$db->check( $user_editable === NULL ? '1' : $user_editable )."'");
	
	// FIXME: add transact to do zfs create & zfs set sharenfs
}

function nas_export_update($id, $quota, $user_editable) {
	global $db;
	
	$update = "";
	
	if ($user_editable !== NULL)
		$update = ", user_editable = '".$db->check($user_editable)."'";
	
	$db->query("UPDATE storage_export SET quota = '".$db->check($quota)."' ".$update." WHERE id = '".$db->check($id)."'");
}

function nas_get_mount_by_id($id) {
	global $db;
	
	$rs = $db->query("SELECT m.*, s.*, me.m_id FROM vps_mount m
					LEFT JOIN servers s ON s.server_id = m.server_id
					INNER JOIN vps v ON v.vps_id = m.vps_id
					INNER JOIN members me ON v.m_id = me.m_id
					WHERE m.id = '".$db->check($id)."'");
	return $db->fetch_array($rs);
}

function nas_mount_add($e_id, $vps_id, $access, $node_id, $src, $dst, $m_opts, $u_opts, $type, $premount, $postmount, $preumount, $postumount, $now) {
	global $db, $cluster_cfg;
	
	if ($m_opts === NULL)
		$m_opts = $cluster_cfg->get("nas_default_mount_options");
	
	if ($u_opts === NULL)
		$u_opts = $cluster_cfg->get("nas_default_umount_options");
	
	$db->query("INSERT INTO vps_mount SET
				storage_export_id = '".$db->check($e_id)."',
				vps_id = '".$db->check($vps_id)."',
				src = '".$src."',
				dst = '".$db->check($dst)."',
				mount_opts = '".$db->check($m_opts)."',
				umount_opts = '".$db->check($u_opts)."',
				type = '".$db->check($type)."',
				server_id = '".$db->check($node_id)."',
				mode = '".$db->check($access)."',
				cmd_premount = '".$db->check($premount)."',
				cmd_postmount = '".$db->check($postmount)."',
				cmd_preumount = '".$db->check($preumount)."',
				cmd_postumount = '".$db->check($postumount)."'
	");
	
	// FIXME: add transact gen mounts & umounts action scripts
	
	if ($now) {
		// add mount transact
	}
}

function nas_mount_update($m_id, $e_id, $vps_id, $access, $node_id, $src, $dst, $m_opts, $u_opts, $type, $premount, $postmount, $preumount, $postumount, $now) {
	global $db;
	
	$sql = "UPDATE vps_mount SET
			storage_export_id = '".$db->check($e_id)."',
			vps_id = '".$db->check($vps_id)."',
			dst = '".$db->check($dst)."',
			mode = '".$db->check($access)."',
			cmd_premount = '".$db->check($premount)."',
			cmd_postmount = '".$db->check($postmount)."',
			cmd_preumount = '".$db->check($preumount)."',
			cmd_postumount = '".$db->check($postumount)."'";
	
	if ($node_id !== NULL)
		$sql .= ", server_id = '".$db->check($node_id)."'";
	
	if ($src !== NULL)
		$sql .= ", src = '".$src."'";
	
	if ($m_opts !== NULL)
		$sql .= ", mount_opts = '".$db->check($m_opts)."'";
	
	if ($u_opts !== NULL)
		$sql .= ", umount_opts = '".$db->check($u_opts)."'";
	
	if ($type !== NULL)
		$sql .= ", type = '".$db->check($type)."'";
	
	$sql .= " WHERE id = '".$db->check($m_id)."'";
	
	$db->query($sql);
	
	// FIXME: add transact gen mounts & umounts action scripts
	
	if ($now) {
		// add mount transact
	}
}

function nas_list_exports() {
	global $db;
	
	if ($_SESSION["is_admin"])
		$sql = "SELECT * FROM storage_export e
				INNER JOIN servers s ON e.server_id = s.server_id
				INNER JOIN node_storage ns ON ns.node_id = s.server_id
				LEFT JOIN members m ON m.m_id = e.member_id
				ORDER BY s.server_id ASC, path ASC";
	else $sql = "SELECT * FROM storage_export e
				INNER JOIN servers s ON e.server_id = s.server_id
				INNER JOIN node_storage ns ON ns.node_id = s.server_id
				LEFT JOIN members m ON m.m_id = e.member_id
				WHERE e.member_id = " . $db->check($_SESSION["member"]["m_id"])."
				ORDER BY s.server_id ASC, path ASC";
	
	$ret = array();
	$rs = $db->query($sql);
	
	while ($row = $db->fetch_array($rs))
		$ret[] = $row;
	
	return $ret;
}

function nas_list_mounts() {
	global $db;
	
	if ($_SESSION["is_admin"])
		$sql = "SELECT m.*, e.*, s.*, m.id AS mount_id, e.server_id AS export_server_id, es.server_name AS export_server_name
				FROM vps_mount m
				LEFT JOIN servers s ON m.server_id = s.server_id
				LEFT JOIN storage_export e ON m.storage_export_id = e.id
				LEFT JOIN servers es ON e.server_id = es.server_id";
	else $sql = "SELECT m.*, e.*, s.*, m.id AS mount_id, e.server_id AS export_server_id, es.server_name AS export_server_name
				FROM vps_mount m
				LEFT JOIN servers s ON m.server_id = s.server_id
				LEFT JOIN storage_export e ON m.storage_export_id = e.id
				LEFT JOIN servers es ON e.server_id = es.server_id
				WHERE e.member_id = ".$db->check($_SESSION["member"]["m_id"]);
	
	$ret = array();
	$rs = $db->query($sql);
	
	while ($row = $db->fetch_array($rs))
		$ret[] = $row;
	
	return $ret;
}

function nas_quota_to_val_unit($val) {
	$units = array("t" => 39, "g" => 29, "m" => 19);
	
	foreach ($units as $u => $ex) {
		if ($val > (2 << $ex))
			return array($val / (2 << $ex), $u);
	}
	
	return array($val, "m");
}

function nas_size_to_humanreadable($val) {
	global $NAS_QUOTA_UNITS;
	
	if (!$val)
		return _("none");
	
	$res = nas_quota_to_val_unit($val);
	return $res[0] . " " . $NAS_QUOTA_UNITS[$res[1]];
}
