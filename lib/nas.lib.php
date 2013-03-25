<?php

$STORAGE_TYPES = array("per_member" => _("Per member"), "per_vps" => _("Per VPS"));
$STORAGE_MOUNT_TYPES = array("bind" => _("Bind"), "nfs" => _("NFS"));
$STORAGE_MOUNT_MODES = array("none" => _("None"), "ro" => _("Read only"), "rw" => _("Read and write"));
$STORAGE_MOUNT_MODES_RO = array("ro" => _("Read only"));
$STORAGE_MOUNT_MODES_RO_RW = array("ro" => _("Read only"), "rw" => _("Read and write"));
$NAS_QUOTA_UNITS = array("m" => "MiB", "g" => "GiB", "t" => "TiB");
$NAS_UNITS_TR = array("m" => 19, "g" => 29, "t" => 39);

function nas_root_list_where($cond) {
	global $db;
	
	$sql = "SELECT id, label FROM servers s INNER JOIN storage_root r ON s.server_id = r.node_id WHERE server_type = 'storage'";
	
	if($cond)
		$sql .= " AND " . $cond;
	
	$ret = array();
	$rs = $db->query($sql);
	
	while ($row = $db->fetch_array($rs)) {
		$ret[$row["id"]] = $row["label"];
	}
	
	return $ret;
}

function get_nas_export_list($default) {
	global $db;
	
	if($_SESSION["is_admin"])
		$sql = "SELECT e.id, r.label, e.path FROM storage_export e
				INNER JOIN storage_root r ON r.id = e.root_id
				INNER JOIN servers s ON s.server_id = r.node_id
				WHERE server_type = 'storage' AND `default` IN (".($default ? "'member','vps','no'" : "'no'").") ORDER BY s.server_id ASC, path ASC";
	else
		$sql = "SELECT e.id, r.label, e.path FROM storage_export e
				INNER JOIN storage_root r ON r.id = e.root_id
				INNER JOIN servers s ON s.server_id = r.node_id
				WHERE server_type = 'storage' AND e.member_id = '".$db->check($_SESSION["member"]["m_id"])."'
				ORDER BY s.server_id ASC, path ASC";
	
	$ret = array();
	$rs = $db->query($sql);
	
	while ($row = $db->fetch_array($rs)) {
		$ret[$row["id"]] = $row["label"].": ".$row["path"];
	}
	
	return $ret;
}

function nas_list_default_exports($type) {
	global $db;
	
	$ret = array();
	
	$rs = $db->query("SELECT *, e.id AS export_id, e.quota AS export_quota, e.used AS export_used, e.avail AS export_avail
		FROM storage_export e
		INNER JOIN storage_root r ON r.id = e.root_id
		INNER JOIN servers s ON r.node_id = s.server_id
		LEFT JOIN members m ON m.m_id = e.member_id
		WHERE `default` ".(($type == "member" || $type == "vps") ? "= '$type'" : "!= 'no'")."
		ORDER BY s.server_id ASC, path ASC");
	
	while($row = $db->fetch_array($rs))
		$ret[] = $row;
	
	return $ret;
}

function nas_list_default_mounts() {
	global $db;
	
	$ret = array();

	$rs = $db->query("SELECT m.*, e.*, s.*, m.id AS mount_id, r.node_id AS export_server_id, es.server_name AS export_server_name, r.label AS root_label,
						e.quota AS export_quota, e.used AS export_used, e.avail AS export_avail
					FROM vps_mount m
					LEFT JOIN servers s ON m.server_id = s.server_id
					LEFT JOIN storage_export e ON m.storage_export_id = e.id
					LEFT JOIN storage_root r ON e.root_id = r.id
					LEFT JOIN servers es ON r.node_id = es.server_id
					WHERE m.`default` = 1");
	
	while($row = $db->fetch_array($rs))
		$ret[] = $row;
	
	return $ret;
}

function nas_get_export_by_id($id) {
	global $db;
	
	$rs = $db->query("SELECT *, e.id AS export_id, e.quota AS export_quota, e.used AS export_used, e.avail AS export_avail
					FROM storage_export e
					INNER JOIN storage_root r ON r.id = e.root_id
					INNER JOIN servers s ON s.server_id = r.node_id
					WHERE server_type = 'storage' AND e.id = '".$db->check($id)."'");
	return $db->fetch_array($rs);
}

function nas_root_add($node_id, $label, $dataset, $path, $type, $user_export, $user_mount, $quota, $share_options) {
	global $db;
	
	$db->query("INSERT INTO storage_root SET
					node_id = '".$db->check($node_id)."',
					label = '".$db->check($label)."',
					root_dataset = '".$db->check($dataset)."',
					root_path = '".$db->check($path)."',
					type = '".$db->check($type)."',
					user_export = '".$db->check($user_export)."',
					user_mount = '".$db->check($user_mount)."',
					quota = '".$db->check($quota)."',
					share_options = '".$db->check($share_options)."'");
	
	$params = array(
		"dataset" => $dataset,
		"share_options" => $share_options,
		"quota" => $quota,
	);
	
	add_transaction($_SESSION["member"]["m_id"], $node_id, 0, T_STORAGE_EXPORT_CREATE, $params);
}

function nas_root_update($root_id, $label, $dataset, $path, $type, $user_export, $user_mount, $quota, $share_options) {
	global $db;
	
	$db->query("UPDATE storage_root SET
					label = '".$db->check($label)."',
					root_dataset = '".$db->check($dataset)."',
					root_path = '".$db->check($path)."',
					type = '".$db->check($type)."',
					user_export = '".$db->check($user_export)."',
					user_mount = '".$db->check($user_mount)."',
					quota = '".$db->check($quota)."',
					share_options = '".$db->check($share_options)."'
				WHERE id = '".$db->check($root_id)."'
	");
	
	$params = array(
		"dataset" => $dataset,
		"share_options" => $share_options,
		"quota" => $quota,
	);
	
	add_transaction($_SESSION["member"]["m_id"], nas_node_id_by_root($root_id), 0, T_STORAGE_EXPORT_UPDATE, $params);
}

function nas_node_id_by_root($root_id) {
	global $db;
	
	$node = $db->fetch_array($db->query("SELECT node_id FROM storage_root WHERE id = '".$db->check($root_id)."'"));
	return $node["node_id"];
}

function nas_export_add($member, $root, $dataset, $path, $quota, $user_editable, $default = "no", $member_prefix = true) {
	global $db;
	
	if ($dataset === NULL)
		$dataset = $path;
	
	$n = new cluster_node(nas_node_id_by_root($root));
	
	if($default == "no" && $member_prefix)
		foreach($n->storage_roots as $r) {
			if ($r["id"] == $root && $r["type"] == "per_member") {
				$dataset = $member."/".$dataset;
				$path = $member."/".$path;
				break;
			}
		}
	
	$db->query("INSERT INTO storage_export SET
				member_id = '".$db->check($member)."',
				root_id = '".$db->check($root)."',
				dataset = '".$db->check($dataset)."',
				path = '".$db->check($path)."',
				quota = '".$db->check($quota)."',
				user_editable = '".( $user_editable == -1 ? '1' : ($user_editable ? '1' : '0') )."',
				`default` = '".$db->check($default)."'");
	
	$export_id = $db->insertId();
	
	foreach($n->storage_roots as $r) {
		if ($r["id"] == $root) {
			$dataset = $r["root_dataset"]."/".$dataset;
			break;
		}
	}
	
	if($default != "no")
		return $export_id;
	
	$params = array(
		"dataset" => $dataset,
		"quota" => $quota,
	);
	
	add_transaction($_SESSION["member"]["m_id"], $n->s["server_id"], 0, T_STORAGE_EXPORT_CREATE, $params);
	
	return $export_id;
}

function nas_export_update($id, $quota, $user_editable) {
	global $db;
	
	$update = "";
	
	if ($user_editable != -1)
		$update = ", user_editable = ".($user_editable ? '1' : '0')."";
	
	$db->query("UPDATE storage_export SET quota = '".$db->check($quota)."' ".$update." WHERE id = '".$db->check($id)."'");
	
	$node = $db->fetch_array($db->query("SELECT r.node_id, e.dataset, r.root_dataset FROM storage_root r INNER JOIN storage_export e ON e.root_id = r.id WHERE e.id = '".$db->check($id)."'"));
	
	$e = nas_get_export_by_id($id);
	
	if($e["default"] != "no")
		return;
	
	$params = array(
		"dataset" => $node["root_dataset"]."/".$node["dataset"],
		"quota" => $quota,
	);
	
	add_transaction($_SESSION["member"]["m_id"], $node["node_id"], 0, T_STORAGE_EXPORT_UPDATE, $params);
}

function nas_export_delete($id) {
	global $db;
	
	$e = nas_get_export_by_id($id);
	$children = nas_get_export_children($id);
	$vpses = array();
	
	foreach($children as $child) {
		nas_delete_export_mounts($child["id"], $vpses);
		nas_export_delete_direct($child, false);
	}
	
	nas_delete_export_mounts($id, $vpses);
	nas_export_delete_direct($e, true);
	
	$params = array(
		"path" => $e["root_dataset"]."/".$e["dataset"],
		"recursive" => true,
	);
	
	add_transaction($_SESSION["member"]["m_id"], $e["node_id"], 0, T_STORAGE_EXPORT_DELETE, $params);
	
	foreach($vpses as $veid) {
		$vps = new vps_load($veid);
		$vps->mount_regen();
	}
}

function nas_delete_export_mounts($id, &$vpses) {
	$mounts = nas_get_mounts_for_export($id);
	
	foreach($mounts as $m) {
		nas_mount_delete($m["id"], true, false);
		
		if(!in_array($m["vps_id"], $vpses))
			$vpses[] = $m["vps_id"];
	}
}

function nas_delete_mounts_for_vps($veid) {
	global $db;
	
	$vps = new vps_load($veid);
	$rs = $db->query("SELECT * FROM vps_mount WHERE vps_id = '".$db->check($veid)."'");
	
	while($m = $db->fetch_array($rs))
		nas_mount_delete($m["id"], true, false);
	
	$vps->mount_regen();
}

function nas_export_delete_direct($export, $commit) {
	global $db;
	
	$db->query("DELETE FROM storage_export WHERE id = '".$db->check($export["export_id"])."'");
}

function nas_get_export_children($id) {
	global $db;
	
	$e = nas_get_export_by_id($id);
	
	$ret = array();
	$rs = $db->query("SELECT *
				FROM storage_export e1
				WHERE dataset LIKE '".$db->check($e["dataset"])."/%'
					AND root_id = '".$e["root_id"]."'
				ORDER BY dataset");
	
	while($row = $db->fetch_array($rs))
		$ret[] = $row;
	
	return $ret;
}

function nas_get_mounts_for_export($id) {
	global $db;
	
	$ret = array();
	$rs = $db->query("SELECT * FROM vps_mount WHERE storage_export_id = '".$db->check($id)."' ORDER BY vps_id");
	
	while($row = $db->fetch_array($rs))
		$ret[] = $row;
	
	return $ret;
}

function nas_get_mount_by_id($id) {
	global $db;
	
	$rs = $db->query("SELECT m.*, r.root_path, e.path, m.id AS mount_id,
					s.server_ip4 AS mount_server_ip4, es.server_ip4 AS export_server_ip4, me.m_id
					FROM vps_mount m
					LEFT JOIN storage_export e ON e.id = m.storage_export_id
					LEFT JOIN storage_root r ON e.root_id = r.id
					LEFT JOIN servers es ON es.server_id = r.node_id
					LEFT JOIN servers s ON m.server_id = s.server_id
					LEFT JOIN vps v ON v.vps_id = m.vps_id
					LEFT JOIN members me ON v.m_id = me.m_id
					WHERE m.id = '".$id."'");
	return $db->fetch_array($rs);
}

function nas_mount_add($e_id, $vps_id, $access, $node_id, $src, $dst, $m_opts, $u_opts, $type, $premount, $postmount, $preumount, $postumount, $now, $default = false) {
	global $db, $cluster_cfg;
	
	if ($m_opts === NULL)
		$m_opts = $cluster_cfg->get("nas_default_mount_options");
	
	if ($u_opts === NULL)
		$u_opts = $cluster_cfg->get("nas_default_umount_options");
	
	if($e_id) {
		$export = nas_get_export_by_id($e_id);
		
		if($export["user_mount"] == "ro")
			$access = "ro";
	}
	
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
				cmd_postumount = '".$db->check($postumount)."',
				`default` = ".($default ? 1 : 0)."
	");
	
	if($default)
		return;
	
	$mount_id = $db->insertId();
	
	$vps = new vps_load($vps_id);
	$vps->mount_regen();
	
	if ($now) {
		$vps->mount(nas_get_mount_by_id($mount_id));
	}
}

function nas_mount_update($m_id, $e_id, $vps_id, $access, $node_id, $src, $dst, $m_opts, $u_opts, $type, $premount, $postmount, $preumount, $postumount, $now, $default = false) {
	global $db;
	
	$vps = new vps_load($vps_id);
	$old = nas_get_mount_by_id($m_id);
	
	if($old["dst"] != $dst)
		$vps->umount($old);
	
	if($e_id) {
		$export = nas_get_export_by_id($e_id);
		
		if($export["user_mount"] == "ro")
			$access = "ro";
	}
	
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
	
	if($default)
		return;
	
	$vps->mount_regen();
	
	if ($now) {
		$vps->remount(nas_get_mount_by_id($m_id));
	}
}

function nas_mount_delete($id, $umount, $regen = true) {
	global $db;
	
	$m = nas_get_mount_by_id($id);
	$vps = new vps_load($m["vps_id"]);
	
	if($umount)
		$vps->umount($m);
	
	$db->query("DELETE FROM vps_mount WHERE id = '".$db->check($id)."'");
	
	if($regen)
		$vps->mount_regen();
}

function nas_list_exports() {
	global $db;
	
	if ($_SESSION["is_admin"])
		$sql = "SELECT *, e.id AS export_id, e.quota AS export_quota, e.used AS export_used, e.avail AS export_avail
				FROM storage_export e
				INNER JOIN storage_root r ON r.id = e.root_id
				INNER JOIN servers s ON r.node_id = s.server_id
				LEFT JOIN members m ON m.m_id = e.member_id
				WHERE e.`default` = 'no'
				ORDER BY s.server_id ASC, path ASC";
	else $sql = "SELECT *, e.id AS export_id, e.quota AS export_quota, e.used AS export_used, e.avail AS export_avail
				FROM storage_export e
				INNER JOIN storage_root r ON r.id = e.root_id
				INNER JOIN servers s ON r.node_id = s.server_id
				LEFT JOIN members m ON m.m_id = e.member_id
				WHERE e.`default` = 'no' AND e.member_id = " . $db->check($_SESSION["member"]["m_id"])."
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
		$sql = "SELECT m.*, e.*, s.*, m.id AS mount_id, r.node_id AS export_server_id, es.server_name AS export_server_name, r.label AS root_label,
					e.quota AS export_quota, e.used AS export_used, e.avail AS export_avail
				FROM vps_mount m
				LEFT JOIN servers s ON m.server_id = s.server_id
				LEFT JOIN storage_export e ON m.storage_export_id = e.id
				LEFT JOIN storage_root r ON e.root_id = r.id
				LEFT JOIN servers es ON r.node_id = es.server_id
				WHERE m.`default` = 'no'";
	else $sql = "SELECT m.*, e.*, s.*, m.id AS mount_id, r.node_id AS export_server_id, es.server_name AS export_server_name, r.label AS root_label,
					e.quota AS export_quota, e.used AS export_used, e.avail AS export_avail
				FROM vps_mount m
				LEFT JOIN servers s ON m.server_id = s.server_id
				LEFT JOIN storage_export e ON m.storage_export_id = e.id
				LEFT JOIN storage_root r ON e.root_id = r.id
				LEFT JOIN servers es ON r.node_id = es.server_id
				WHERE m.`default` = 'no' AND e.member_id = ".$db->check($_SESSION["member"]["m_id"]);
	
	$ret = array();
	$rs = $db->query($sql);
	
	while ($row = $db->fetch_array($rs))
		$ret[] = $row;
	
	return $ret;
}

function nas_can_user_manage_export($e) {
	return $e && (($e["user_editable"] && $e["member_id"] == $_SESSION["member"]["m_id"]) || $_SESSION["is_admin"]);
}

function nas_can_user_add_mount($e, $vps) {
	return $e && ($e["member_id"] == $_SESSION["member"]["m_id"] || $_SESSION["is_admin"]) && $vps->exists && $e["default"] == "no";
}

function nas_can_user_manage_mount($m, $vps) {
	return $m && ($m["m_id"] == $_SESSION["member"]["m_id"] || $_SESSION["is_admin"]) && $vps->exists;
}

function nas_quota_to_val_unit($val) {
	$units = array("t" => 39, "g" => 29, "m" => 19);
	
	foreach ($units as $u => $ex) {
		if ($val >= (2 << $ex))
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

function nas_mount_params($mnt, $cmds = true) {
	$src = "";
		
	if ($mnt["storage_export_id"]) {
		$src = $mnt["export_server_ip4"].":".$mnt["root_path"]."/".$mnt["path"];
	} else if ($mnt["server_id"]) {
		$src = $mnt["mount_server_ip4"].":".$mnt["src"];
	} else {
		$src = $mnt["src"];
	}
	
	$ret = array(
		"src" => $src,
		"dst" => $mnt["dst"],
		"mount_opts" => $mnt["mount_opts"],
		"umount_opts" => $mnt["umount_opts"],
		"mode" => $mnt["mode"],
	);
	
	if($cmds) {
		$ret = $ret + array(
			"premount" => $mnt["cmd_premount"],
			"postmount" => $mnt["cmd_postmount"],
			"preumount" => $mnt["cmd_preumount"],
			"postumount" => $mnt["cmd_postumount"],
		);
	}
	
	return $ret;
}

function nas_create_default_exports($type, $obj) {
	$exports = nas_list_default_exports($type);
	$mapping = array();
	
	foreach ($exports as $e) {
		$ds = str_replace("%member_id%", $obj["m_id"], $e["dataset"]);
		$ds = str_replace("%veid%", $obj["vps_id"], $ds);
		
		$path = str_replace("%member_id%", $obj["m_id"], $e["path"]);
		$path = str_replace("%veid%", $obj["vps_id"], $path);
		
		$new_id = nas_export_add(
			$e["member_id"] ? $e["member_id"] : $obj["m_id"],
			$e["root_id"],
			$ds,
			$path,
			$e["export_quota"],
			$e["user_editable"],
			"no",
			false
		);
		
		$mapping[$e["export_id"]] = $new_id;
	}
	
	return $mapping;
}

function nas_create_default_mounts($obj, $mapping = array()) {
	$mounts = nas_list_default_mounts();
	
	foreach ($mounts as $m) {
		$src = str_replace("%member_id%", $obj["m_id"], $m["src"]);
		$src = str_replace("%veid%", $obj["vps_id"], $src);
		
		$storage_export_id = $m["storage_export_id"];
		
		if($storage_export_id) {
			$e = nas_get_export_by_id($storage_export_id);
			
			if($e["default"] != "no")
				$storage_export_id = $mapping[$storage_export_id];
		}
		
		nas_mount_add(
			$storage_export_id,
			$m["vps_id"] ? $m["vps_id"] : $obj["vps_id"],
			$m["mode"],
			$m["server_id"],
			$src,
			$m["dst"],
			$m["mount_opts"],
			$m["umount_opts"],
			$m["type"],
			$m["cmd_premount"],
			$m["cmd_postmount"],
			$m["cmd_preumount"],
			$m["cmd_postumount"],
			false,
			false
		);
	}
}
