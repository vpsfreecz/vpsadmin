<?php
/*
    ./lib/vps.lib.php

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

function get_vps_array($by_m_id = false, $by_server = false){
	global $db;
	//$sql = 'SELECT vps_id FROM vps '. (($_SESSION[is_admin]) ? 'ORDER BY m_id ASC' : " WHERE m_id = {$db->check($_SESSION[member][m_id])} ");
//	$sql = 'SELECT vps.*,cfg_templates.templ_label FROM vps LEFT JOIN cfg_templates ON vps.vps_template=cfg_templates.templ_id';
	$sql = 'SELECT vps_id FROM vps';
	if ($_SESSION["is_admin"]) {
		if ($by_server)
			$sql .= " WHERE vps_server = $by_server ";
		$sql .= ' ORDER BY vps_server,m_id,vps_id ASC';
	} else {
		$sql .= " WHERE m_id = {$db->check($_SESSION["member"]["m_id"])}";
		if ($by_server)
			$sql .= " AND vps_server = $by_server";
	}

	$ret = array();
	if ($result = $db->query($sql))
		while ($row = $db->fetch_array($result)) {
			$ret [] = new vps_load($row["vps_id"]);
		}
	return $ret;
}

function vps_load ($veid = false) {
	$vps = new vps_load($veid);
	return $vps;
}


class vps_load {

  public $veid = 0;
  public $ve = array();
  public $exists = false;

  function vps_load($ve_id = 'none') {
	global $db, $request_page;
	if(is_numeric($ve_id)) {
		if ($_SESSION["is_admin"]) {
			$sql = 'SELECT * FROM vps,servers,members,cfg_templates WHERE vps.vps_template = cfg_templates.templ_id AND vps.m_id = members.m_id AND server_id = vps_server AND vps_id = "'.$db->check($ve_id).'"';
		} else {
			$sql = 'SELECT * FROM vps,servers,members,cfg_templates WHERE vps.m_id = "'.$_SESSION["member"]["m_id"].'" AND vps.vps_template = cfg_templates.templ_id AND vps.m_id = members.m_id AND server_id = vps_server AND vps_id = "'.$db->check($ve_id).'"';
		}
		if ($result = $db->query($sql))
			if ($tmpve = $db->fetch_array($result))
				if (empty($request_page) || ($tmpve["vps_id"] == $ve_id) && (($tmpve["m_id"] == $_SESSION["member"]["m_id"]) || $_SESSION["is_admin"])) {
					$this->exists = true;
					$this->veid = $ve_id;
					$this->ve = $tmpve;
					}
				else  {
				    die ("Hacking attempt. This incident will be reported.");
				}
			else $this->exists = false;
		else $this->exists = false;
	} else $this->exists = false;
	return true;
  }

  function create_new($server_id, $template_id, $hostname, $m_id, $info) {
	global $db, $cluster;
	if (!$this->exists && $template = template_by_id($template_id)) {
		$server = $db->findByColumnOnce("servers", "server_id", $server_id);
		$location = $db->findByColumnOnce("locations", "location_id", $server["server_location"]);
		$sql = 'INSERT INTO vps
				SET m_id = "'.$db->check($m_id).'",
				    vps_created = "'.$db->check(time()).'",
				    vps_template = "'.$db->check($template["templ_id"]).'",
				    vps_info ="'.$db->check(addslashes($info)).'",
				    vps_nameserver ="'.$db->check($cluster->get_first_suitable_dns($location["location_id"])).'",
				    vps_hostname ="'.$db->check($hostname).'",
				    vps_server ="'.$db->check($server_id).'",
				    vps_onboot ="'.$db->check($location["location_vps_onboot"]).'",
				    vps_onstartall = 1';
		$db->query($sql);
		$this->veid = $db->insert_id();
		$this->exists = true;
		$params["hostname"] = $hostname;
		$params["template"] = $template["templ_name"];
		$params["onboot"] = $location["location_vps_onboot"];
    $this->ve["vps_nameserver"] = "8.8.8.8";
    $params["nameserver"] = $this->ve["vps_nameserver"];
		$this->ve["vps_server"] = $server_id;
		$this->ve["vps_nameserver"] = $params["nameserver"];
		$this->ve["vps_template"] = $template["templ_name"];
		$this->ve["vps_onboot"] = $location["location_vps_onboot"];
		add_transaction($_SESSION["member"]["m_id"], $server_id, $this->veid, T_CREATE_VE, $params);
    $this->nameserver($cluster->get_first_suitable_dns($cluster->get_location_of_server($server_id)));
	}
  }
  function reinstall(){
	global $cluster, $db;
	if ($this->exists) {
		$ips = $this->iplist();
		$params = array("ip_addrs" => array());
		if ($ips)
			foreach ($ips as $ip) {
				$params["ip_addrs"][] = $ip["ip_addr"];
			}
		$template = template_by_id($this->ve["vps_template"]);
		$params["hostname"] = $this->ve["vps_hostname"];
		$params["template"] = $template["templ_name"];
		$this->ve["vps_nameserver"] = "8.8.8.8";
		$params["nameserver"] = $this->ve["vps_nameserver"];
		add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_REINSTALL_VE, $params);
		$this->applyconfigs();
		$sql = 'UPDATE vps SET  vps_features_enabled=0,
					vps_specials_installed = ""
					WHERE vps_id='.$db->check($this->veid);
		$result = $db->query($sql);
    		$this->nameserver($cluster->get_first_suitable_dns($cluster->get_location_of_server($this->ve["vps_server"])));
	}
  }
  function change_distro_before_reinstall($template_id) {
	global $db;
	$sql = 'UPDATE vps SET vps_template = "'.$db->check($template_id).'" WHERE vps_id='.$db->check($this->veid);
	if ($result = $db->query($sql)) {
	    $this->ve["vps_template"] = $template_id;
	}
  }
  function passwd ($user, $new_pass) {
		global $db;
		if ($this->exists) {
			$command = array('userpasswd' => $user.':'.$db->check($new_pass));
			add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_EXEC_PASSWD, $command);
		}
  }

  function stop () {
	global $db;
	if ($this->exists) {
	    $db->query('UPDATE vps SET vps_onstartall = 0 WHERE vps_id='.$db->check($this->veid));
	    add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_STOP_VE);
	}
  }

  function start () {
	global $db;
	if ($this->exists) {
	    $db->query('UPDATE vps SET vps_onstartall = 1 WHERE vps_id='.$db->check($this->veid));
	    $server = $db->findByColumnOnce("servers", "server_id", $this->ve["vps_server"]);
	    $location = $db->findByColumnOnce("locations", "location_id", $server["server_location"]);
	    $params = array("onboot" => $location["location_vps_onboot"], "backup_mount" => $this->ve["vps_backup_mount"]);
	    add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_START_VE, $params);
	}
  }

  function restart () {
	global $db;
	if ($this->exists) {
	    $server = $db->findByColumnOnce("servers", "server_id", $this->ve["vps_server"]);
	    $location = $db->findByColumnOnce("locations", "location_id", $server["server_location"]);
	    $params = array("onboot" => $location["location_vps_onboot"], "backup_mount" => $this->ve["vps_backup_mount"]);
	    add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_RESTART_VE, $params);
	}
  }

  function is_owner ($m_id) {
	global $db;
	if ($this->exists) {
		return ($this->ve["m_id"] == $m_id);
	}
  }

  function set_hostname($new_hostname) {
    global $db;
    if ($this->exists) {
	$sql = 'UPDATE vps SET vps_hostname = "'.$db->check($new_hostname).'" WHERE vps_id='.$db->check($this->veid);
	if ($result = $db->query($sql)) {
	    $command = array('hostname' => $new_hostname);
	    add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_EXEC_HOSTNAME, $command);
	}
    }
  }

  function info() {
    global $db;
    $sql = 'SELECT * FROM vps_status WHERE vps_id ='.$db->check($this->veid).' ORDER BY id DESC LIMIT 1';
    if ($result = $db->query($sql))
	if ($s = $db->fetch_array($result)) {
	    $this->ve["vps_up"] = $s["vps_up"];
	    $this->ve["vps_nproc"] = $s["vps_nproc"];
	    $this->ve["vps_vm_used_mb"] = $s["vps_vm_used_mb"];
	    $this->ve["vps_disk_used_mb"] = $s["vps_disk_used_mb"];
	}
  }


  function destroy($force = false) {
	global $db;
	if ($this->exists && ($_SESSION["is_admin"] || $force)) {
	  $sql = 'DELETE FROM vps WHERE vps_id='.$db->check($this->veid);
	  $sql2 = 'UPDATE vps_ip SET vps_id = 0 WHERE vps_id='.$db->check($this->veid);
	  if ($result = $db->query($sql))
	  	if ($result2 = $db->query($sql2)) {
			$this->exists = false;
	  		add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_DESTROY_VE);
			}
	  	else return false;
	  else return false;
	}
  }

  function iplist($v = false) {
	global $db;
	if ($this->exists) {
	  if ($v) {
	    $sql = 'SELECT * FROM vps_ip WHERE vps_id="'.$db->check($this->veid).'" AND ip_v="'.$db->check($v).'"
		ORDER BY ip_v ASC';
	  } else {
	    $sql = 'SELECT * FROM vps_ip WHERE vps_id="'.$db->check($this->veid).'" ORDER BY ip_v ASC';
	  }
	  if ($result = $db->query($sql)) {
		while ($row = $db->fetch_array($result)) {
			$ret[] = $row;
			}
		return $ret;
		}
	  else
		return NULL;
	}
  }

function ipadd($ip, $type = 4) {
	global $db;
	if ($this->exists) {
	    if ($ipadr = ip_exists_in_table($ip)) {
		$sql = 'UPDATE vps_ip
			SET vps_id = "'.$db->check($this->veid).'"
			WHERE ip_id = "'.$db->check($ipadr["ip_id"]).'"';
		$db->query($sql);
		if ($db->affected_rows() > 0) {
		    $command = array('ipadd' => $ip);
		    add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_EXEC_IPADD, $command);
		} else
		    return NULL;
	    }
	}
}

  function add_first_available_ip($loc, $v) {
	global $db;
	
	$rs = $db->query("SELECT ip_addr FROM vps_ip WHERE vps_id = 0 AND ip_v = '".$db->check($v)."' AND ip_location = '".$db->check($loc)."' ORDER BY ip_id LIMIT 1");
	$ip = $db->fetch_array($rs);
	
	if ($ip)
		$this->ipadd($ip["ip_addr"], $v);
  }

  function ipdel($ip, $dep = NULL) {
	global $db;
	if ($this->exists) {
	  $sql = 'UPDATE vps_ip SET vps_id = 0 WHERE ip_addr="'.$db->check($ip).'"';
	  if ($result = $db->query($sql)) {
	  	$command = array('ipdel' => $ip);
		add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_EXEC_IPDEL, $command, NULL, $dep);
	  	}
	  else
	  	return NULL;
	}
  }

  function nameserver($nameserver) {
	global $db;
	if ($this->exists) {
	  $sql = 'UPDATE vps SET vps_nameserver = "'.$db->check($nameserver).'" WHERE vps_id = '.$db->check($this->veid);
	  $db->query($sql);
	  $nameservers = explode(",", $nameserver);
	  $command = array("nameservers" => array());
	  foreach ($nameservers as $ns) {
      $command["nameserver"][] = $ns;
	  }
	  $this->ve["vps_nameserver"] = $nameserver;
	  add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_EXEC_DNS, $command);
	}
  }

  function offline_migrate($target_id, $stop = false) {
	global $db, $cluster;
	if ($this->exists) {
		$servers = list_servers();
		if (isset($servers[$target_id])) {
		$sql = 'UPDATE vps SET vps_server = "'.$db->check($target_id).'" WHERE vps_id = '.$db->check($this->veid);
		$db->query($sql);
		$this_loc = $this->get_location();
		$target_server = server_by_id($target_id);
		$loc["location_has_shared_storage"] = false;
		if ($this_loc == $cluster->get_location_of_server($target_id)) {
			$loc = $db->findByColumnOnce("locations", "location_id", $this_loc);
			if ($loc["location_has_shared_storage"]) {
				$params["on_shared_storage"] = true;
				$params["target_id"] = $target_id;
			}
		}
		
		$params["target"] = $target_server["server_ip4"];
		$params["stop"] = (bool)$stop;
		add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_MIGRATE_OFFLINE, $params);
		$migration_id = $db->insertId();
		
		$this->ve["vps_server"] = $target_id;
		
		if ($this_loc != $cluster->get_location_of_server($target_id)) {
			$ips = $this->iplist();
			
			foreach($ips as $ip)
				$this->ipdel($ip["ip_addr"], $migration_id);
		}
	  }
	}
  }

  function online_migrate($target_id) {
	global $db;
	if ($this->exists) {
	  $servers = list_servers();
	  if (isset($servers[$target_id])) {
		$sql = 'UPDATE vps SET vps_server = "'.$db->check($target_id).'" WHERE vps_id = '.$db->check($this->veid);
		$db->query($sql);
		$target_server = server_by_id($target_id);
		$params["target"] = $target_server["server_ip4"];
		$params["target_id"] = $target_id;
		$loc = $db->findByColumnOnce("locations", "location_id", $this->get_location());
		if ($loc["location_has_shared_storage"]) {
			$params["on_shared_storage"] = true;
		}
		add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_MIGRATE_ONLINE, $params);
		$this->ve["vps_server"] = $target_id;
	  }
	}
  }
  function change_server($target_id) {
	global $db;
	if ($this->exists) {
	  $servers = list_servers();
	  if (isset($servers[$target_id])) {
		$sql = 'UPDATE vps SET vps_server = "'.$db->check($target_id).'" WHERE vps_id = '.$db->check($this->veid);
		$db->query($sql);
		$this->ve["vps_server"] = $target_id;
	  }
	}

  }

  function vchown($m_id) {
	global $db;
	if ($this->exists && $_SESSION["is_admin"]) {
	  $sql = 'UPDATE vps SET m_id = '.$db->check($m_id).' WHERE vps_id = '.$db->check($this->veid);
	  $db->query($sql);
	  if ($db->affected_rows() == 1) {
		$this->ve["m_id"] = $m_id;
		return true;
	  } else return false;
	}
  }
  
  function get_configs() {
	global $db;
	
	$sql = "SELECT config_id, c.label FROM vps_has_config vhc
	        INNER JOIN config c ON c.id = vhc.config_id
	        WHERE vhc.vps_id = ".$db->check($this->veid)."
	        ORDER BY vhc.order ASC";
	$ret = array();
	
	if ($result = $db->query($sql))
		while ($row = $db->fetch_array($result))
			$ret[$row["config_id"]] = $row["label"];
	
	return $ret;
  }
  
  function update_configs($configs, $cfg_order, $new_cfgs) {
	global $db;
	
	if (!$db->query("DELETE FROM vps_has_config WHERE vps_id = ".$db->check($this->veid))) {
		return false;
	}
	
	$i = 1;
	
	if ($cfg_order) {
		foreach($cfg_order as $cfg) {
			$db->query("INSERT INTO vps_has_config SET vps_id = ".$db->check($this->veid).", config_id = ".$db->check($cfg).", `order` = ".$i++."");
		}
	} else {
		foreach($configs as $cfg) {
			$db->query("INSERT INTO vps_has_config SET vps_id = ".$db->check($this->veid).", config_id = ".$db->check($cfg).", `order` = ".$i++."");
		}
		
		foreach($new_cfgs as $cfg) {
			if ($cfg)
				$db->query("INSERT INTO vps_has_config SET vps_id = ".$db->check($this->veid).", config_id = ".$db->check($cfg).", `order` = ".$i++."");
		}
	}
	
	$this->applyconfigs();
	
	return true;
  }
  
  function config_del($cfg) {
	global $db;
	
	if ($db->query("DELETE FROM vps_has_config WHERE vps_id = ".$db->check($this->veid)." AND config_id = ".$db->check($cfg)."")) {
		$this->applyconfigs();
		return true;
	}
	return false;
  }
  
  function update_custom_config($cfg) {
	global $db;
	
	$db->query("UPDATE vps SET vps_config = '".$db->check($cfg)."' WHERE vps_id = '".$db->check($this->veid)."'");
	
	add_transaction_clusterwide($_SESSION["member"]["m_id"], $this->veid, T_CLUSTER_CONFIG_CREATE, array("name" => "vps-".$this->veid, "config" => $cfg), array('node'));
	$this->applyconfigs();
  }
  
  function add_default_configs($cfg_name) {
	global $db, $cluster_cfg;
	
	$chain = $cluster_cfg->get($cfg_name);
	$i = 1;
	foreach ($chain as $cfg) {
		$db->query("INSERT INTO vps_has_config SET vps_id = '".$db->check($this->veid)."', config_id = '".$db->check($cfg)."', `order` = ".$i++."");
	}
	
	$this->applyconfigs();
  }
  
  function applyconfigs($dep = NULL) {
	global $db;
	
	$sql = "SELECT c.name FROM vps_has_config vhc
	        INNER JOIN config c ON c.id = vhc.config_id
	        WHERE vhc.vps_id = ".$db->check($this->veid)."
	        ORDER BY vhc.order ASC";
	$cmd = array("configs" => array());
	
	if ($result = $db->query($sql))
		while ($row = $db->fetch_array($result))
			$cmd["configs"][] = $row["name"];
			
	if ($this->ve["vps_config"])
		$cmd["configs"][] = "vps-".$this->veid;
	
	add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_EXEC_APPLYCONFIG, $cmd, NULL, $dep);
  }
  
  function configs_change_notify() {
	global $db, $cluster_cfg;

	$subject = $cluster_cfg->get("mailer_tpl_limits_change_subj");
	$subject = str_replace("%member%", $this->ve["m_nick"], $subject);
	$subject = str_replace("%vpsid%", $this->veid, $subject);
	
	$content = $cluster_cfg->get("mailer_tpl_limits_changed");
	$content = str_replace("%member%", $this->ve["m_nick"], $content);
	$content = str_replace("%vpsid%", $this->veid, $content);
	
	$configs_str = "";
	$configs = $this->get_configs();
	
	foreach($configs as $id => $label)
		$configs_str .= "\t- $label\n";
	
	$content = str_replace("%configs%", $configs_str, $content);
	
	send_mail($this->ve["m_mail"], $subject, $content, array(), $cluster_cfg->get("mailer_admins_in_cc") ? explode(",", $cluster_cfg->get("mailer_admins_cc_mails")) : array());
  }

  function enable_features() {
		global $db;
	  $sql = 'UPDATE vps SET vps_features_enabled = "1"
						WHERE vps_id = '.$db->check($this->veid);
	  $db->query($sql);
	  if ($db->affected_rows() == 1) {
			add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_ENABLE_FEATURES);
	  }
  }
  function special_setup_ispcp($params) {
    global $db;
    $this->ve["vps_specials_installed"] .= 'ispcp ';
    $sql = 'UPDATE vps SET vps_specials_installed = "'.$this->ve["vps_specials_installed"].'" WHERE vps_id = '.$db->check($this->veid);
    $db->query($sql);
    if ($db->affected_rows() == 1) {
	add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_SPECIAL_ISPCP, $params);
    }
  }

  function backuper_change_notify() {
	global $db, $cluster_cfg;

	$subject = $cluster_cfg->get("mailer_tpl_backuper_change_subj");
	$subject = str_replace("%member%", $this->ve["m_nick"], $subject);
	$subject = str_replace("%vpsid%", $this->veid, $subject);
	
	$content = $cluster_cfg->get("mailer_tpl_backuper_changed");
	$content = str_replace("%member%", $this->ve["m_nick"], $content);
	$content = str_replace("%vpsid%", $this->veid, $content);
	$content = str_replace("%backuper%", $this->ve["vps_backup_enabled"] ? _("enabled") : _("disabled"), $content);
	
	send_mail($this->ve["m_mail"], $subject, $content, array(), $cluster_cfg->get("mailer_admins_in_cc") ? explode(",", $cluster_cfg->get("mailer_admins_cc_mails")) : array());
  }
  
  function set_backuper($how, $mount, $exclude, $force = false) {
  	global $db;
	
	/**
	 * how: do not touch if NULL
	 * mount: do not touch if NULL
	 * exclude: do not touch if === false
	 */
	
	$update = array();
	
	if ($mount !== NULL) {
		$this->ve["vps_backup_mount"] = $mount;
		$update[] = "vps_backup_mount = '".($mount ? '1' : '0')."'";
	}
	
	if ($_SESSION["is_admin"] || $force) {
		if ($how !== NULL) {
			$update[] = "vps_backup_enabled = " . ($how ? '1' : '0');
			$this->ve["vps_backup_enabled"] = (bool)$how;
		}
		
		if ($exclude !== false)
		{
			$update[] = "vps_backup_exclude = '".$db->check($exclude)."'";
			$this->ve["vps_backup_exclude"] = $exclude;
		}
		
		if (!count($update))
			return;
		
		$sql = 'UPDATE vps SET '.implode(",", $update).' WHERE vps_id = '.$db->check($this->veid);
  	} else
		$sql = 'UPDATE vps SET vps_backup_exclude = "'.$db->check($exclude).'", '.implode(",", $update).' WHERE vps_id = '.$db->check($this->veid);
  	
  	$db->query($sql);
  }
  
  function set_backup_lock($lock) {
	global $db;
	
	$sql = 'UPDATE vps SET vps_backup_lock = '.($lock ? '1' : '0').' WHERE vps_id = '.$db->check($this->veid);
	
  	$db->query($sql);
  }
  
  function backup_mount() {
	add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_BACKUP_VE_MOUNT);
  }
  
  function backup_umount() {
	add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_BACKUP_VE_UMOUNT);
  }
  
  function backup_remount() {
	add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_BACKUP_VE_REMOUNT);
  }
  
  function backup_generate_scripts() {
	add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_BACKUP_VE_GENERATE_MOUNT_SCRIPTS, array("backup_mount" => $this->ve["vps_backup_mount"]));
  }
  
  function restore($timestamp, $backup_first = false) {
	if(!$this->exists)
		return NULL;
  
	global $db;
	$backup_id = NULL;
	$backuper = $this->get_backuper_server();
	
	if ($backup_first)
	{
		$params = array(
			"server_name" => $this->ve["server_name"],
			"exclude" => preg_split ("/(\r\n|\n|\r)/", $this->ve["vps_backup_exclude"]),
		);
		
		add_transaction($_SESSION["member"]["m_id"], $backuper["server_id"], $this->veid, T_BACKUP_SCHEDULE, $params);
		$backup_id = $db->insertId();
	}
	
	$params = array(
		"datetime" => strftime("%Y-%m-%dT%H:%M:%S", (int)$timestamp),
		"backuper" => $backuper["server_name"],
		"server_name" => $this->ve["server_name"],
	);
	add_transaction($_SESSION["member"]["m_id"], $backuper["server_id"], $this->veid, T_BACKUP_RESTORE_PREPARE, $params, NULL, $backup_id);
	$prepare_id = $db->insertId();
	
	add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_BACKUP_RESTORE_FINISH, $params, NULL, $prepare_id);
  }
  
  function download_backup($timestamp) {
	if(!$this->exists)
		return NULL;
	
	global $db, $cluster_cfg;
	
	$backuper = $this->get_backuper_server();
	$secret = hash("sha256", $this->veid . $timestamp . time() . rand(0, 99999999));
	$params = array("secret" => $secret);
	
	if ($timestamp == "current") {
		$params["filename"] = "{$this->veid}-current.tar.gz";
		$params["server_name"] = $this->ve["server_name"];
	} else {
		$params["filename"] = "{$this->veid}-".strftime("%Y-%m-%d--%H-%M", (int)$timestamp).".tar.gz";
		$params["datetime"] = strftime("%Y-%m-%dT%H:%M:%S", (int)$timestamp);
	}
	
	add_transaction($_SESSION["member"]["m_id"], $backuper["server_id"], $this->veid, T_BACKUP_DOWNLOAD, $params);
	$dl_id = $db->insertId();
	
	$subj = $cluster_cfg->get("mailer_tpl_dl_backup_subj");
	$subj = str_replace("%member%", $this->ve["m_nick"], $subj);
	$subj = str_replace("%vpsid%", $this->veid, $subj);
	
	$content = $cluster_cfg->get("mailer_tpl_dl_backup");
	$content = str_replace("%member%", $this->ve["m_nick"], $content);
	$content = str_replace("%vpsid%", $this->veid, $content);
	$content = str_replace("%url%", "https://vpsadmin.vpsfree.cz/backup/$secret/" . $params["filename"], $content);
	$content = str_replace("%datetime%", $timestamp == "current" ? _("current VPS state") : strftime("%Y-%m-%d %H:%M", $timestamp), $content);
	
	send_mail($this->ve["m_mail"], $subj, $content, array(), array(), true, $dl_id);
  }
  
  function clone_vps($m_id, $server_id, $hostname, $configs, $features, $backuper) {
	global $db;
	$sql = 'INSERT INTO vps
			SET m_id = "'.$db->check($m_id).'",
				vps_created = "'.$db->check(time()).'",
				vps_template = "'.$db->check($this->ve["vps_template"]).'",
				vps_info ="'.$db->check("Cloned from {$this->veid}").'",
				vps_hostname ="'.$db->check($hostname).'",
				vps_nameserver ="'.$db->check($this->ve["vps_nameserver"]).'",
				vps_server ="'.$db->check($server_id).'",
				vps_onboot ="'.$db->check($this->ve["vps_onboot"]).'",
				vps_onstartall = '.$db->check($this->ve["vps_onstartall"]).',
				vps_features_enabled = '.$db->check($features ? $this->ve["vps_features_enabled"] : 0).',
				vps_backup_enabled = '.$db->check($backuper ? $this->ve["vps_backup_enabled"] : 1).',
				vps_backup_mount = '.$db->check($backuper ? $this->ve["vps_backup_mount"] : 1).',
				vps_backup_exclude = "'.$db->check($backuper ? $this->ve["vps_backup_exclude"] : '').'",
				vps_config = "'.$db->check($configs ? $this->ve["vps_config"] : '').'"';
	
	$db->query($sql);
	$clone = vps_load($db->insert_id());
	
	$params = array(
		"src_veid" => $this->veid,
		"src_server_ip" => $this->ve["server_ip4"],
		"is_local" => $server_id == $this->ve["vps_server"],
		"template" => $clone->ve["templ_name"],
		"hostname" => $clone->ve["vps_hostname"],
		"nameserver" => $clone->ve["vps_nameserver"],
	);
	
	add_transaction($_SESSION["member"]["m_id"], $server_id, $clone->veid, T_CLONE_VE, $params);
	
	switch($configs) {
		case 0:
			$clone->add_default_configs("default_config_chain");
			break;
		case 1:
			$db->query("INSERT INTO vps_has_config (vps_id, config_id, `order`) SELECT '".$db->check($clone->veid)."' AS vps_id, config_id, `order` FROM vps_has_config WHERE vps_id = '".$db->check($this->veid)."'");
			
			if ($clone->ve["vps_config"])
				$clone->update_custom_config($clone->ve["vps_config"]); // applyconfig called inside
			else
				$clone->applyconfigs();
			break;
		case 2:
			$clone->add_default_configs("playground_default_config_chain");
			break;
	}
	
	if ($features && $this->ve["vps_features_enabled"])
		add_transaction($_SESSION["member"]["m_id"], $server_id, $clone->veid, T_ENABLE_FEATURES);
		
	$this->info();
	if ($this->ve["vps_up"])
		$clone->start();
	
	return $clone;
  }
  
  function get_backuper_server() {
	global $db;
	$sql = "SELECT s.* FROM locations l INNER JOIN servers s ON s.server_id = l.location_backup_server_id WHERE location_id = '".$db->check($this->ve["server_location"])."'";
	if ($result = $db->query($sql)) {
		if ($row = $db->fetch_array($result)) {
			return $row;
		}
	}
	
	return NULL;
  }

  function get_location() {
	global $cluster;
	return $cluster->get_location_of_server($this->ve["vps_server"]);
  }
  
  function create_console_session() {
	global $db;
	
	$key = hash('sha256', $vps->veid . time() . rand(0, 99999999));
	$sql = "INSERT INTO vps_console SET vps_id = ".$db->check($this->veid).", `key` = '".$db->check($key)."', expiration = ADDDATE(NOW(), INTERVAL 30 SECOND)";
	
	if ($db->query($sql))
		return $key;
	else return false;
  }
  
  function get_console_server() {
	global $db;
	
	$sql = "SELECT location_remote_console_server FROM locations WHERE location_id = '".$db->check($this->ve["server_location"])."'";
	if ($result = $db->query($sql)) {
		if ($row = $db->fetch_array($result)) {
			return $row["location_remote_console_server"];
		}
	}
	
	return NULL;
  }
}
?>
