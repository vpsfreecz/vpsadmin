<?php
/*
    ./lib/cluster.lib.php

    vpsAdmin
    Web-admin interface for OpenVZ (see http://openvz.org)
    Copyright (C) 2008-2011 Pavel Snajdr, snajpa@snajpa.net
*/

$NODE_TYPES = array('node', 'mailer', 'storage');
$NODE_FSTYPES = array("ext4" => "Ext4", "zfs" => "ZFS", "zfs_compat" => "ZFS in compatibility mode");

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
}

$cluster = new cluster();
?>
