<?php
/*
    ./lib/cluster.lib.php

    vpsAdmin
    Web-admin interface for OpenVZ (see http://openvz.org)
    Copyright (C) 2008-2011 Pavel Snajdr, snajpa@snajpa.net
*/

$NODE_TYPES = array('node', 'mailer', 'storage');

class cluster_node {
    // Server descriptor
    public $s;
    // True if exists
    public $exists;
    public $role = array();
    public $storage_roots = array();

    function cluster_node ($server_id) {
	global $db;
	$sql = 'SELECT * FROM servers WHERE server_id="'.$db->check($server_id).'" LIMIT 1';
	if ($result = $db->query($sql))
	    if ($row = $db->fetch_array($result)) {
		$this->s = $row;
		
		switch ($row["server_type"]) {
			case "node":
				$this->role = $db->findByColumnOnce("node_node", "node_id", $row["server_id"]);
				break;
				
			case "storage":
				$this->role = array(); // FIXME: remove
				
				$roots = array();
				$rs = $db->query("SELECT * FROM storage_root WHERE node_id = ".$db->check($row["server_id"]));
				
				while($r = $db->fetch_array($rs))
					$roots[] = $r;
				
				$this->storage_roots = $roots;
				break;
				
			default:break;
		}
		
		$this->exists = true;
	    } else {
		$this->exists = false;
	    }
	return $this->exists;
    }
    
    /**
      * Get node's location label
      * @return string of location_label
      */
    function get_location_label() {
	global $db;
	$sql = 'SELECT * FROM locations WHERE location_id = "'.$db->check($this->s["server_location"]).'"';
	if ($result = $db->query($sql)) {
	    if ($row = $db->fetch_array($result))
		return $row["location_label"];
	}
	return false;
    }
    
    function update_settings($data) {
		global $db;
		
		$sql = 'UPDATE servers SET
				server_name = "'.$db->check($data["server_name"]).'",
				server_type = "'.$db->check($data["server_type"]).'",
				server_location = "'.$db->check($data["server_location"]).'",
				server_availstat = "'.$db->check($data["server_availstat"]).'",
				server_ip4 = "'.$db->check($data["server_ip4"]).'"
				WHERE server_id = '.$this->s["server_id"];
		
		$db->query($sql);
		
		switch ($data["server_type"]) {
			case "node":
				$sql = "UPDATE node_node SET
				        max_vps = '".$db->check($data["max_vps"])."',
				        ve_private = '".$db->check($data["ve_private"])."'
				        WHERE node_id = ".$db->check($this->s["server_id"]);
				$db->query($sql);
				break;
			
			default:break;
		}
    }
}

class cluster_cfg {
    function cluster_cfg() {
	return true;
    }
    /**
      * Test wether config item exists
      * @param $setting - setting name
      * @return true if exists, false if not or error occurs
      */
    function exists($setting) {
		global $db;
		$sql = 'SELECT * FROM sysconfig WHERE cfg_name="'.$db->check($setting).'"';
		
		if ($result = $db->query($sql)) {
			if ($row = $db->fetch_array($result)) {
				return true;
			} else return false;
		} else return false;
    }
    /**
      * Get value of saved setting
      * @param $setting - setting name
      * @return original setting content if success, false if error occurs
      * WARNING: returns false also if original setting content was false
      */
    function get($setting) {
	global $db;
	$sql = 'SELECT * FROM sysconfig WHERE cfg_name="'.$db->check($setting).'"';
	if ($result = $db->query($sql)) {
	    if ($row = $db->fetch_array($result)) {
		return json_decode($row["cfg_value"]);
	    } else return false;
	} else return false;
    }
    /**
      * Save setting
      * @param $setting - setting name
      * @param $value - its value in natural form (eg. array etc), basically everything that could be serialized
      * @return SQL result descriptor
      */
    function set($setting, $value) {
	global $db;
	if ($this->exists($setting))
	    $sql = 'UPDATE sysconfig SET cfg_value = "'.$db->check(json_encode($value)).'" WHERE cfg_name = "'.$db->check($setting).'"';
	else
    	    $sql = 'INSERT INTO sysconfig SET cfg_value = "'.$db->check(json_encode($value)).'", cfg_name = "'.$db->check($setting).'"';
	
	return ($db->query($sql));
    }
}
$cluster_cfg = new cluster_cfg();

class cluster {
    function cluster() {
    }
    /**
      * Get array of all cluster nodes, suitable for xtemplate form select
      * @param $without_id - server_id to exclude
      * @return array of [server_id] = server_name, empty array on error
      */
    function list_servers($without_id = false, $only_location = false, $only_show_warning_at_other_loc=false) {
	global $db;
	$ret = array();
	if ($only_show_warning_at_other_loc) {
	    $warning_loc = $only_location;
	    $only_location = false;
	}
	$sql = 'SELECT * FROM servers';
	if ($without_id || $only_location)
	    $sql .= ' WHERE ';
	if ($without_id)
	    $sql .= 'server_id != '.$db->check($without_id);
	if ($without_id && $only_location)
	    $sql .= ' AND ';
	if ($only_location)
	    $sql .= 'server_location = '.$db->check($only_location);
	$sql .= ' ORDER BY server_name ASC';
	if ($result = $db->query($sql))
	    while ($row = $db->fetch_array($result)) {
		if ($only_show_warning_at_other_loc && ($row["server_location"] != $warning_loc))
		    $ret[$row["server_id"]] = $row["server_name"].' '._("WARNING: All IPs will be removed from VPS!");
		else
		    $ret[$row["server_id"]] = $row["server_name"];
	    }
	return $ret;
    }
    /**
      * Get array of all cluster nodes, suitable for xtemplate form select
      * @param $location_id - filter to location
      * @return array of [server_id] = server_name, empty array on error
      */
    function list_servers_by_location($location_id) {
	global $db;
	$ret = array();
	$sql = 'SELECT * FROM servers WHERE server_location = '.$db->check($location_id);
	if ($result = $db->query($sql))
	    while ($row = $db->fetch_array($result))
		$ret[$row["server_id"]] = $row["server_name"];
	return $ret;
    }
    /**
      * Get array of all cluster nodes
      * @param $without_id - server_id to exclude
      * @return array of server arrays, false on error
      */
    function list_servers_full($without_id = false) {
	global $db;
	$ret = false;
	    if ($without_id)
		    $sql = 'SELECT * FROM servers WHERE server_id != '.$db->check($without_id);
	    else
		    $sql = 'SELECT * FROM servers';
	if ($result = $db->query($sql))
	    while ($row = $db->fetch_array($result))
		$ret[$row["server_id"]] = $row;
	return $ret;
    }
    /**
      * Get array of cluster_node instances of all cluster nodes
      * @param $without_id - server_id to exclude
      * @return array of cluster_node instances of server arrays, false on error
      */
    function list_servers_class($without_id = false) {
	global $db;
	$ret = false;
	    if ($without_id)
		    $sql = 'SELECT * FROM servers WHERE server_id != '.$db->check($without_id);
	    else
		    $sql = 'SELECT * FROM servers';
	if ($result = $db->query($sql))
	    while ($row = $db->fetch_array($result))
		$ret[$row["server_id"]] = new cluster_node($row["server_id"]);
	return $ret;
    }
    
     function list_servers_with_type($type, $location_id = NULL) {
		global $db;
		
		$ret = array();
		$conds = array("server_type = '". $db->check($type)."'");
		
		if($location_id)
			$conds[] = "server_location = '".$db->check($location_id)."'";
		
		while ($row = $db->find("servers", $conds, "server_id"))
			$ret[$row["server_id"]] = $row["server_name"];
		
		return $ret;
    }
    
    function exists_playground_location() {
		global $db;
		
		$rs = $db->query("SELECT COUNT(location_id) AS cnt FROM locations WHERE location_type = 'playground'");
		$row = $db->fetch_array($rs);
		
		return $row["cnt"] > 0;
    }
    
    function list_playground_servers($location_id = NULL) {
		global $db;
		
		$ret  = array();
		$rs = $db->query("SELECT s.* FROM servers s INNER JOIN locations ON server_location = location_id WHERE location_type = 'playground'");
		
		while ($row = $db->fetch_array($rs))
			$ret[] = $row;
		
		return $ret;
    }
    
    /**
      * Get array of templates Cluster-wide available
      * @return array of template arrays, empty array on error
      */
    function get_templates() {
	global $db;
	$sql = 'SELECT * FROM cfg_templates';
	$ret = array();
	if ($result = $db->query($sql))
	    while ($row = $db->fetch_array($result))
		$ret[] = $row;
	return $ret;
    }
    /**
      * Get template descriptor by templ_id
      * @param $templ_id - template ID
      * @return template array, empty array on error
      */
    function get_template_by_id($templ_id) {
	global $db;
	$sql = 'SELECT * FROM cfg_templates WHERE templ_id='.$db->check($templ_id);
	$ret = false;
	if ($result = $db->query($sql))
	    $ret = $db->fetch_array($result);
	return $ret;
    }
    /**
      * Get array of templates for list in HTML select in xtemplate
      * @return array["templ_id"] = "templ_label", empty array on error
      */
    function list_templates() {
	global $db;
	$sql = 'SELECT * FROM cfg_templates';
	$ret = array();
	if ($result = $db->query($sql))
	    while ($row = $db->fetch_array($result))
		$ret[$row[templ_id]] = $row[templ_label];
	return $ret;
    }
    /**
      * Get number of template uses
      * @param $templ_id - ID of template
      * @return number of uses, false on fail
      */
    function get_template_usage($templ_id) {
	global $db;
	$sql = 'SELECT COUNT(*) AS count FROM vps WHERE vps_template='.$db->check($templ_id);
	if ($result = $db->query($sql)) {
	    $row = $db->fetch_array($result);
	    return $row["count"];
	} else {
	    return false;
	}
    }
    /**
      * Set template, creates new is does not exists, update if does
      * @param $id - ID of template, use false if creating new one
      * @param $name - Filename without extension
      * @param $label - User friendly label
      * @param $info - Note for admins
      * @return descriptor of SQL result
      */
    function set_template($id = NULL, $name, $label, $info = "", $special = "", $enabled = 1) {
	global $db;
	if ($id != NULL)
	    $sql = 'UPDATE cfg_templates
			SET templ_name = "'.$db->check($name).'",
			    templ_label = "'.$db->check($label).'",
			    templ_info = "'.$db->check($info).'",
			    special = "'.$db->check($special).'",
			    templ_enabled = "'.$db->check($enabled).'"
			WHERE templ_id = "'.$db->check($id).'"';
	else
	    $sql = 'INSERT INTO cfg_templates
			SET templ_name = "'.$db->check($name).'",
			    templ_label = "'.$db->check($label).'",
			    templ_info = "'.$db->check($info).'",
			    special = "'.$db->check($special).'",
			    templ_enabled = "'.$db->check($enabled).'"';
	return ($db->query($sql));
    }
    /**
      * Copies template to all cluster nodes
      * @param $templ_id - ID of template
      * @param $source_node - server_id of source node
      * @return ---
      */
    function copy_template_to_all_nodes($templ_id, $source_node) {
	global $db;
	$nodes = $this->list_servers_class($source_node);
	foreach ($nodes as $node) {
	    $params = array();
	    $params["templ_id"] = $templ_id;
	    $params["remote_server_id"] = $source_node;
	    add_transaction($_SESSION["member"]["m_id"], $node->s["server_id"], 0, T_CLUSTER_TEMPLATE_COPY, $params);
	}
    }
    function delete_template($templ_id) {
	global $db;
	if ($this->get_template_by_id($templ_id)) {
	    $nodes = $this->list_servers_class($source_node);
	    foreach ($nodes as $node) {
		$node->delete_template($templ_id);
	    }
	}
    }
    function save_config($id, $name, $label, $config, $reapply = false) {
		global $db;
		
		$params = array("name" => $name, "config" => $config);
		
		if($id != NULL) {
			$sql = "UPDATE `config` SET name = '".$db->check($name)."',
			        label = '".$db->check($label)."',
			        `config` = '".$db->check($config)."'
			        WHERE id = '".$db->check($id)."'";
			$c = $db->findByColumnOnce("config", "id", $id);
			
			if ($c["name"] != $name)
				$params["old_name"] = $c["name"];
		} else
			$sql = "INSERT INTO `config` SET name = '".$db->check($name)."',
			        label = '".$db->check($label)."',
			        `config` = '".$db->check($config)."'";
		
		$db->query($sql);
		
		$servers = list_servers(false, array('node'));
		
		foreach ($servers as $sid => $name) {
			add_transaction($_SESSION["member"]["m_id"], $sid, 0, T_CLUSTER_CONFIG_CREATE, $params);
			$dep = $db->insertId();
			
			if ($reapply) {
				$rs = $db->query("SELECT v.vps_id FROM vps v INNER JOIN vps_has_config c ON v.vps_id = c.vps_id WHERE c.config_id = ".$db->check($id)." AND vps_server = ".$db->check($sid));
				
				while ($row = $db->fetch_array($rs)) {
					$vps = vps_load($row["vps_id"]);
					$vps->applyconfigs($dep);
				}
			}
		}
    }
    
    function delete_config($id) {
		global $db;
		
		if($cfg = $db->findByColumnOnce("config", "id", $id)) {
			$db->query('DELETE FROM vps_has_config WHERE config_id = "'.$db->check($id).'"');
			$db->query('DELETE FROM `config` WHERE id = "'.$db->check($id).'"');
			
			add_transaction_clusterwide($_SESSION["member"]["m_id"], 0, T_CLUSTER_CONFIG_DELETE, array("name" => $cfg["name"]));
		}
    }
    
    function regenerate_all_configs() {
		global $db;
		
		while ($cfg = $db->find("config", NULL, "name")) {
			$params = array("name" => $cfg["name"], "config" => $cfg["config"]);
			add_transaction_clusterwide($_SESSION["member"]["m_id"], 0, T_CLUSTER_CONFIG_CREATE, $params, array('node'));
		}
    }
    
    function save_default_configs($configs, $cfg_order, $new_cfgs, $syscfg_name) {
		global $cluster_cfg;
		
		$res = array();
		
		if ($cfg_order) {
			$res = $cfg_order;
		} else {
			$res = $configs;
			
			foreach($new_cfgs as $cfg)
				if ($cfg)
					$res[] = $cfg;
		}
		
		$cluster_cfg->set($syscfg_name, $res);
		
		return true;
	}
    
    function get_location_by_id ($location_id) {
	global $db;
	$sql = 'SELECT * FROM locations WHERE location_id = "'.$db->check($location_id).'"';
	if ($result = $db->query($sql))
	    if ($row = $db->fetch_array($result))
		return $row;
	return false;
    }
    function set_location($id = NULL, $label, $type, $has_ipv6 = false, $onboot, $has_ospf, $has_rdiff,
    						$rd_hist, $rd_sshfs, $rd_archfs, $tpl_sync_path, $remote_console_server) {
	global $db;
	if ($id != NULL)
	    $sql = 'UPDATE locations
			SET location_label = "'.$db->check($label).'",
			    location_type = "'.$db->check($type).'",
			    location_has_ipv6 = "'.$db->check($has_ipv6).'",
			    location_has_ospf = "'.$db->check($has_ospf).'",
			    location_has_rdiff_backup = "'.$db->check($has_rdiff).'",
			    location_rdiff_history = "'.$db->check($rd_hist).'",
			    location_rdiff_mount_sshfs = "'.$db->check($rd_sshfs).'",
			    location_rdiff_mount_archfs = "'.$db->check($rd_archfs).'",
			    location_tpl_sync_path = "'.$db->check($tpl_sync_path).'",
			    location_remote_console_server = "'.$db->check($remote_console_server).'",
			    location_vps_onboot = "'.$db->check($onboot).'"
			WHERE location_id = "'.$db->check($id).'"';
	else
	    $sql = 'INSERT INTO locations
			SET location_label = "'.$db->check($label).'",
			    location_type = "'.$db->check($type).'",
			    location_has_ipv6 = "'.$db->check($has_ipv6).'",
			    location_has_ospf = "'.$db->check($has_ospf).'",
			    location_has_rdiff_backup = "'.$db->check($has_rdiff).'",
			    location_rdiff_history = "'.$db->check($rd_hist).'",
			    location_rdiff_mount_sshfs = "'.$db->check($rd_sshfs).'",
			    location_rdiff_mount_archfs = "'.$db->check($rd_archfs).'",
			    location_tpl_sync_path = "'.$db->check($tpl_sync_path).'",
			    location_remote_console_server = "'.$db->check($remote_console_server).'",
			    location_vps_onboot = "'.$db->check($onboot).'"';
	return ($db->query($sql));
    }
    function list_locations($ipv6_only = false) {
	global $db;
	$sql = 'SELECT * FROM locations';
	if ($ipv6_only) $sql .= ' WHERE location_has_ipv6=1';
	if ($result = $db->query($sql)) {
	    while ($row = $db->fetch_array($result)) {
		$ret[$row["location_id"]] = $row["location_label"];
	    }
	return $ret;
	}
    }
    function get_locations() {
	global $db;
	$sql = 'SELECT * FROM locations';
	if ($result = $db->query($sql)) {
	    while ($row = $db->fetch_array($result)) {
		$ret[] = $row;
	    }
	return $ret;
	}
    }
    function get_server_count_in_location($location_id) {
	global $db;
	$sql = 'SELECT COUNT(*) AS count FROM servers WHERE server_location="'.$db->check($location_id).'"';
	if ($result = $db->query($sql))
	    if ($ret = $db->fetch_array($result))
		return $ret["count"];
	return false;
    }
    function delete_location($id) {
	global $db;
	if ($this->get_server_count_in_location($id) <= 0) {
	    $sql = 'DELETE FROM locations
			WHERE location_id = "'.$db->check($id).'"';
	    $db->query($sql);
	}
    }
    function get_location_of_server($server_id) {
	global $db;
	$sql = 'SELECT server_location FROM servers WHERE server_id="'.$db->check($server_id).'"';
	if ($result = $db->query($sql))
	    if ($row = $db->fetch_array($result))
		return $row["server_location"];
	return false;
    }
    
    function get_dns_server_by_id($dns_id) {
	global $db;
	$sql = 'SELECT * FROM cfg_dns WHERE dns_id='.$db->check($dns_id);
	$ret = false;
	if ($result = $db->query($sql))
	    $ret = $db->fetch_array($result);
	return $ret;
    }
    function get_dns_servers() {
	global $db;
	$sql = 'SELECT * FROM cfg_dns';
	if ($result = $db->query($sql)) {
	    while ($row = $db->fetch_array($result)) {
		$ret[] = $row;
	    }
	return $ret;
	}
    }
    function list_dns_servers($location_id = false) {
	global $db;
	$sql = 'SELECT * FROM cfg_dns';
	if ($location_id)
	    $sql .= ' WHERE dns_location="'.$db->check($location_id).'" OR dns_is_universal=1';
	if ($result = $db->query($sql)) {
	    while ($row = $db->fetch_array($result)) {
		$ret[$row["dns_ip"]] = $row["dns_label"];
	    }
	return $ret;
	}
    }
    function set_dns_server($id = NULL, $ip, $label, $is_universal, $location) {
	global $db;
	if ($id != NULL)
	    $sql = 'UPDATE cfg_dns
			SET dns_ip = "'.$db->check($ip).'",
			    dns_label = "'.$db->check($label).'",
			    dns_is_universal = "'.$db->check($is_universal).'",
			    dns_location = "'.$db->check($location).'"
			WHERE dns_id = "'.$db->check($id).'"';
	else
	    $sql = 'INSERT INTO cfg_dns
			SET dns_ip = "'.$db->check($ip).'",
			    dns_label = "'.$db->check($label).'",
			    dns_is_universal = "'.$db->check($is_universal).'",
			    dns_location = "'.$db->check($location).'"';
	return ($db->query($sql));
    }
    function delete_dns_server($id) {
	global $db;
	$sql = 'DELETE FROM cfg_dns
		    WHERE dns_id = "'.$db->check($id).'"';
	$db->query($sql);
    }
    function get_first_suitable_dns($location) {
	global $db;
	$sql = 'SELECT * FROM cfg_dns WHERE (dns_location="'.$db->check($location).'") AND (dns_is_universal = 0) LIMIT 1';
	if ($result = $db->query($sql))
	    if ($row = $db->fetch_array($result))
		return $row["dns_ip"];
	    else die (_("Please define some DNS servers in Manage cluster."));
	else die (_("Please define some DNS servers in Manage cluster."));
    }
}

$cluster = new cluster();
?>
