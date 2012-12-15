<?php
/*
    ./lib/cluster.lib.php

    vpsAdmin
    Web-admin interface for OpenVZ (see http://openvz.org)
    Copyright (C) 2008-2011 Pavel Snajdr, snajpa@snajpa.net
*/

class cluster_node {
    // Server descriptor
    public $s;
    // True if exists
    protected $exists;

    function cluster_node ($server_id) {
	global $db;
	$sql = 'SELECT * FROM servers WHERE server_id="'.$db->check($server_id).'" LIMIT 1';
	if ($result = $db->query($sql))
	    if ($row = $db->fetch_array($result)) {
		$this->s = $row;
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
    /**
      * Run command while in CRON_MODE
      * WARNING: Ment to use only in CRON_MODE
      * @param $command - Shell command to run
      * @return true if success, false on fail or if not in CRON_MODE
      */
    function execute($command) {
	if (CRON_MODE) {
	    exec_wrapper ($command, $dumb, $retval);
	    return ($retval == 0);
	} else {
	    return false;
	}
    }
    /**
      * WARNING: Ment to use only in CRON_MODE
      * Write content to file while in CRON_MODE, if file exists it will be overwritten
      * @param $path - Absolute file path
      * @param $content - New file content (string)
      */
    function write_file($path, $content) {
	$handle = fopen($path, "w");
	fwrite($handle, $content);
	fclose($handle);
    }
    /**
      * Startup Cluster storage and mount it
      * If not in CRON_MODE, add transaction to do it
      * @return true if success, false on fail
      */
    function startup_cluster_storage() {
	global $cluster_cfg;
	if ($this->s[server_cluster_storage_sw_installed] && CRON_MODE) {
	    if ($this->execute("glusterfsd -s /etc/glusterfs/glusterfs-server.vol -l /var/log/glusterfsd.log")) {
		if ($this->execute("modprobe fuse")) {
		    if ($this->execute("glusterfs -f /etc/glusterfs/glusterfs-client.vol {$this->s["server_path_vz"]}/cluster_mount/")) {
			$cluster_cfg->set("cluster_storage_running_{$this->s["server_id"]}", true);
			return true;
		    } else return false;
		} else return false;
	    } else return false;
	} elseif (!CRON_MODE) {
	    if (!$cluster_cfg->get("cluster_storage_running_{$this->s["server_id"]}")) {
		add_transaction($_SESSION["member"]["m_id"], $this->s["server_id"], 0, T_CLUSTER_STORAGE_STARTUP);
		return true;
	    }
	}
    }
    /**
      * Unmount and stop all daemons for Cluster storage
      * If not in CRON_MODE, add transaction to do it
      * @return true if success, false on fail
      */
    function shutdown_cluster_storage() {
	global $cluster_cfg;
	if (CRON_MODE) {
	    if ($cluster_cfg->get("cluster_storage_running_{$this->s["server_id"]}")) {
		if ($this->execute("umount {$this->s["server_path_vz"]}/cluster_mount/")) {
		    $this->execute("killall glusterfsd");
		    $cluster_cfg->set("cluster_storage_running_{$this->s["server_id"]}", false);
		    return true;
		} else {
		    return false;
		}
	    } else {
		return false;
	    }
	} else {
	    add_transaction($_SESSION["member"]["m_id"], $this->s["server_id"], 0, T_CLUSTER_STORAGE_SHUTDOWN);
	    return true;
	}
    }
    /**
      * Install Cluster storage, assumes FUSE & GlusterFS v2 is already installed
      * If not in CRON_MODE, add transaction to do it
      * @return true if success, false on fail
      */
    function install_cluster_storage_software() {
	global $db;
	if (CRON_MODE) {
	    $this->execute("mkdir -p {$this->s["server_path_vz"]}/cluster_storage");
	    $this->execute("mkdir -p {$this->s["server_path_vz"]}/cluster_mount");
	    $this->execute("mkdir -p /etc/glusterfs/");
	    $server_config = '
volume posix
  type storage/posix
  option directory '.$this->s["server_path_vz"].'/cluster_storage
end-volume

volume locks
  type features/locks
  subvolumes posix
end-volume

volume brick
  type performance/io-threads
  option thread-count 8
  subvolumes locks
end-volume

volume server
  type protocol/server
  option transport-type tcp
  option auth.addr.brick.allow *
  subvolumes brick
end-volume
';
	    $this->write_file('/etc/glusterfs/glusterfs-server.vol', $server_config);
	    $sql = 'UPDATE servers SET server_cluster_storage_sw_installed=1 WHERE server_id='.$db->check($this->s["server_id"]);
	    $db->query($sql);
	    $this->s["server_cluster_storage_sw_installed"] = 1;
	    add_transaction_clusterwide(0, 0, T_CLUSTER_STORAGE_CFG_RELOAD);
	    return true;
	} else {
	    add_transaction($_SESSION["member"]["m_id"], $this->s["server_id"], 0, T_CLUSTER_STORAGE_SOFTWARE_INSTALL);
	    return true;
	}
    }
    /**
      * Update glusterfs-client.vol file to reflect changes in Cluster storage nodes
      * WARNING: Ment to use only in CRON_MODE
      * @return true if success, false on fail or if not in CRON_MODE
      */
    function regenerate_cluster_storage_client_config() {
	global $db;
	if (CRON_MODE) {
	    if ($this->s["server_cluster_storage_sw_installed"]) {
		$sql = 'SELECT * FROM servers WHERE server_cluster_storage_sw_installed=1';
		$content = "";
		$node_line = "";
		if ($result = $db->query($sql)) {
		    while ($row = $db->fetch_array($result)) {
			$content .= '
volume remote'.$row["server_id"].'
  type protocol/client
  option transport-type tcp
  option remote-host '.$row["server_ip4"].'
  option remote-subvolume brick
end-volume
';
			$node_line .= ' remote'.$row["server_id"];
		    }
		    if ($content != "") {
			$content .= '
volume replicate
  type cluster/replicate
  subvolumes'.$node_line.'
end-volume

volume writebehind
  type performance/write-behind
  option window-size 1MB
  subvolumes replicate
end-volume

volume cache
  type performance/io-cache
  option cache-size 512MB
  subvolumes writebehind
end-volume
';
			$this->write_file('/etc/glusterfs/glusterfs-client.vol');
			return true;
		    } else {
			return false;
		    }
		}
		$this->write_file($content);
	    }
	} else {
	    return false;
	}
    }
    /**
      * Uses 'scp' to copy template from remote node
      * WARNING: Ment to use only in CRON_MODE
      * @param $templ_id - template id in DB
      * @param $remote_server_id - source server id in DB
      * @return TBD
      */
    function fetch_remote_template($templ_id, $remote_server_id) {
	global $cluster;
	if (CRON_MODE) {
	    if ($remote_node = new cluster_node($remote_server_id)) {
		if ($template = $cluster->get_template_by_id($templ_id)) {
		    return $this->execute('scp '.$remote_node->s["server_ip4"].':'.
					    $remote_node->s["server_path_vz"].'/template/cache/'.$template["templ_name"].'.*'.
					    ' '.$this->s["server_path_vz"].'/template/cache/'
					    );
		}
	    }
	} else {
	    return false;
	}
    }
    /**
      * Deletes local copy of template
      * WARNING: Ment to use only in CRON_MODE
      * @param $templ_id - template id in DB
      */
    function delete_template($templ_id) {
	global $cluster, $db;
	if (CRON_MODE) {
	    if ($template = $cluster->get_template_by_id($templ_id)) {
		return $this->execute('rm -f '.$this->s["server_path_vz"].'/template/cache/'.$template["templ_name"].'.*');
	    }
	} else {
	    $sql = 'DELETE FROM cfg_templates WHERE templ_id = '.$db->check($templ_id);
	    $db->query($sql);
	    $params["templ_id"] = $templ_id;
	    add_transaction($_SESSION["member"]["m_id"], $this->s["server_id"], 0, T_CLUSTER_TEMPLATE_DELETE, $params);
	    return true;
	}
    }
    /**
      * TODO: Install vpsAdmin backend on foreign fresh node
      * @param TBD
      * @return TBD
      */
    function install_vpsadmin_backend() {
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
		return stripslashes(unserialize($row["cfg_value"]));
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
	    $sql = 'UPDATE sysconfig SET cfg_value = "'.addslashes(serialize($value)).'" WHERE cfg_name = "'.$db->check($setting).'"';
	else
    	    $sql = 'INSERT INTO sysconfig SET cfg_value = "'.addslashes(serialize($value)).'", cfg_name = "'.$db->check($setting).'"';
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
    function list_hddlimits() {
	global $db;
	$sql = 'SELECT * FROM cfg_diskspace';
	if ($result = $db->query($sql))
	    while ($row = $db->fetch_array($result))
		$ret[$row["d_id"]] = $row["d_label"];
	return $ret;
    }
    function get_hddlimits() {
	global $db;
	$sql = 'SELECT * FROM cfg_diskspace';
	if ($result = $db->query($sql))
	    while ($row = $db->fetch_array($result))
		$ret[] = $row;
	return $ret;
    }
    function get_hddlimit_usage($d_id) {
	global $db;
	$sql = 'SELECT COUNT(*) AS count FROM vps WHERE vps_diskspace='.$db->check($d_id);
	if ($result = $db->query($sql)) {
	    $row = $db->fetch_array($result);
	    return $row["count"];
	} else {
	    return false;
	}
    }
    function get_hddlimit_by_id($d_id) {
	global $db;
	$sql = 'SELECT * FROM cfg_diskspace WHERE d_id='.$db->check($d_id);
	$ret = false;
	if ($result = $db->query($sql))
	    $ret = $db->fetch_array($result);
	return $ret;
    }
    function set_hddlimit($id = NULL, $label, $d_gb) {
	global $db;
	if ($id != NULL)
	    $sql = 'UPDATE cfg_diskspace
			SET d_label = "'.$db->check($label).'",
			    d_gb =    "'.$db->check($d_gb).'"
			WHERE d_id = "'.$db->check($id).'"';
	else
	    $sql = 'INSERT INTO cfg_diskspace
			SET d_label = "'.$db->check($label).'",
			    d_gb = "'.$db->check($d_gb).'"';
	return ($db->query($sql));
    }
    function delete_hddlimit($d_id) {
	global $db;
	if ($this->get_hddlimit_usage($d_id) <= 0) {
	    $sql = 'DELETE FROM cfg_diskspace
			WHERE d_id = "'.$db->check($d_id).'"';
	    $db->query($sql);
	}
    }
    function list_ramlimits() {
	global $db;
	$sql = 'SELECT * FROM cfg_privvmpages'.(($force) ? ' WHERE vm_usable=1' : '');
	if ($result = $db->query($sql))
	    while ($row = $db->fetch_array($result))
		$ret[$row["vm_id"]] = $row["vm_label"];
	return $ret;
    }
    function get_ramlimits() {
	global $db;
	$sql = 'SELECT * FROM cfg_privvmpages'.(($force) ? ' WHERE vm_usable=1' : '');
	if ($result = $db->query($sql))
	    while ($row = $db->fetch_array($result))
		$ret[] = $row;
	return $ret;
    }
    function get_ramlimit_usage($vm_id) {
	global $db;
	$sql = 'SELECT COUNT(*) AS count FROM vps WHERE vps_privvmpages='.$db->check($vm_id);
	if ($result = $db->query($sql)) {
	    $row = $db->fetch_array($result);
	    return $row["count"];
	} else {
	    return false;
	}
    }
    function get_ramlimit_by_id($vm_id) {
	global $db;
	$sql = 'SELECT * FROM cfg_privvmpages WHERE vm_id='.$db->check($vm_id);
	$ret = false;
	if ($result = $db->query($sql))
	    $ret = $db->fetch_array($result);
	return $ret;
    }
    function set_ramlimit($id = NULL, $label, $softlimit, $hardlimit) {
	global $db;
	if ($id != NULL)
	    $sql = 'UPDATE cfg_privvmpages
			SET vm_label = "'.$db->check($label).'",
			    vm_lim_soft =    "'.$db->check($softlimit).'",
			    vm_lim_hard =    "'.$db->check($hardlimit).'"
			WHERE vm_id = "'.$db->check($id).'"';
	else
	    $sql = 'INSERT INTO cfg_privvmpages
			SET vm_label = "'.$db->check($label).'",
			    vm_lim_soft =    "'.$db->check($softlimit).'",
			    vm_lim_hard =    "'.$db->check($hardlimit).'"';
	return ($db->query($sql));
    }
    function delete_ramlimit($vm_id) {
	global $db;
	if ($this->get_ramlimit_usage($vm_id) <= 0) {
	    $sql = 'DELETE FROM cfg_privvmpages
			WHERE vm_id = "'.$db->check($vm_id).'"';
	    $db->query($sql);
	}
    }
     function list_cpulimits() {
	global $db;
	$sql = 'SELECT * FROM cfg_cpulimits'.(($force) ? ' WHERE cpu_usable=1' : '');
	if ($result = $db->query($sql))
	    while ($row = $db->fetch_array($result))
		$ret[$row["vm_id"]] = $row["vm_label"];
	return $ret;
    }
    function get_cpulimits() {
	global $db;
	$sql = 'SELECT * FROM cfg_cpulimits'.(($force) ? ' WHERE cpu_usable=1' : '');
	if ($result = $db->query($sql))
	    while ($row = $db->fetch_array($result))
		$ret[] = $row;
	return $ret;
    }
    function get_cpulimit_usage($cpu_id) {
	global $db;
	$sql = 'SELECT COUNT(*) AS count FROM vps WHERE vps_cpulimit='.$db->check($cpu_id);
	if ($result = $db->query($sql)) {
	    $row = $db->fetch_array($result);
	    return $row["count"];
	} else {
	    return false;
	}
    }
    function get_cpulimit_by_id($cpu_id) {
	global $db;
	$sql = 'SELECT * FROM cfg_cpulimits WHERE cpu_id='.$db->check($cpu_id);
	$ret = false;
	if ($result = $db->query($sql))
	    $ret = $db->fetch_array($result);
	return $ret;
    }
    function set_cpulimit($id = NULL, $label, $limit, $cpus) {
	global $db;
	if ($id != NULL)
	    $sql = 'UPDATE cfg_cpulimits
			SET cpu_label = "'.$db->check($label).'",
			    cpu_limit =    "'.$db->check($limit).'",
			    cpu_cpus =    "'.$db->check($cpus).'"
			WHERE cpu_id = "'.$db->check($id).'"';
	else
	    $sql = 'INSERT INTO cfg_cpulimits
			SET cpu_label = "'.$db->check($label).'",
			    cpu_limit =    "'.$db->check($limit).'",
			    cpu_cpus =    "'.$db->check($cpus).'"';
	return ($db->query($sql));
    }
    function delete_cpulimit($cpu_id) {
	global $db;
	if ($this->get_ramlimit_usage($cpu_id) <= 0) {
	    $sql = 'DELETE FROM cfg_cpulimits
			WHERE cpu_id = "'.$db->check($cpu_id).'"';
	    $db->query($sql);
	}
    }
    function get_location_by_id ($location_id) {
	global $db;
	$sql = 'SELECT * FROM locations WHERE location_id = "'.$db->check($location_id).'"';
	if ($result = $db->query($sql))
	    if ($row = $db->fetch_array($result))
		return $row;
	return false;
    }
    function set_location($id = NULL, $label, $type, $has_ipv6 = false, $onboot, $has_ospf, $has_rdiff, $backuper,
    						$rd_hist, $rd_sshfs, $rd_archfs, $tpl_sync_path, $remote_console_server) {
	global $db;
	if ($id != NULL)
	    $sql = 'UPDATE locations
			SET location_label = "'.$db->check($label).'",
			    location_type = "'.$db->check($type).'",
			    location_has_ipv6 = "'.$db->check($has_ipv6).'",
			    location_has_ospf = "'.$db->check($has_ospf).'",
			    location_has_rdiff_backup = "'.$db->check($has_rdiff).'",
			    location_backup_server_id = "'.$db->check($backuper).'",
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
			    location_backup_server_id = "'.$db->check($backuper).'",
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
