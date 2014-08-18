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
		$sql .= " WHERE m_id = {$db->check($_SESSION["member"]["m_id"])} AND vps_deleted IS NULL";
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

function get_user_vps_list($exclude = array()) {
	global $db;
	
	$ret = array();
	$sql = "";
	
	if($exclude)
		$cond = "vps_id NOT IN (".implode(",", $exclude).")";
	
	if ($_SESSION["is_admin"])
		$sql = "SELECT * FROM vps INNER JOIN members m ON vps.m_id = m.m_id ".($cond ? "WHERE $cond" : "")." ORDER BY vps_id ASC";
	else
		$sql = "SELECT * FROM vps INNER JOIN members m ON vps.m_id = m.m_id WHERE vps.m_id = '".$db->check($_SESSION["member"]["m_id"])."' ".($cond ? "AND $cond" : "")." ORDER BY vps_id ASC";
	
	$rs = $db->query($sql);
	
	while ($row = $db->fetch_array($rs))
		$ret[$row["vps_id"]] = $row["m_nick"].": #".$row["vps_id"]." ".$row["vps_hostname"];
		
	return $ret;
}

function get_vps_swap_list($vps) {
	global $db;
	
	if($_SESSION["is_admin"])
		return get_user_vps_list(array($vps->veid));
	
	$sql = "SELECT vps_id, vps_hostname FROM vps v
	        INNER JOIN servers s ON v.vps_server = s.server_id
		    INNER JOIN locations l ON s.server_location = l.location_id
		    WHERE
		      m_id = ".$db->check($_SESSION["member"]["m_id"])."
		      AND
		      v.vps_deleted IS NULL
		      AND
		      s.server_maintenance = 0
		      AND
		      l.location_type = '".( $vps->is_playground() ? 'production' : 'playground' )."'";
	
	$rs = $db->query($sql);
	$ret = array();
	
	while( $row = $db->fetch_array($rs) ) {
		$ret[$row["vps_id"]] ="#".$row["vps_id"]." ".$row["vps_hostname"];
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
  public $deleted = false;

  function vps_load($ve_id = 'none') {
	global $db, $request_page;
	if(is_numeric($ve_id)) {
		if ($_SESSION["is_admin"]) {
			$sql = 'SELECT * FROM vps,servers,members,cfg_templates WHERE vps.vps_template = cfg_templates.templ_id AND vps.m_id = members.m_id AND server_id = vps_server AND vps_id = "'.$db->check($ve_id).'"';
		} else {
			$sql = 'SELECT * FROM vps,servers,members,cfg_templates WHERE vps.m_id = "'.$_SESSION["member"]["m_id"].'" AND vps.vps_template = cfg_templates.templ_id AND vps.m_id = members.m_id AND server_id = vps_server AND vps_id = "'.$db->check($ve_id).'"';
		}
		if ($result = $db->query($sql)) {
			if ($tmpve = $db->fetch_array($result)) {
				if (empty($request_page) || ($tmpve["vps_id"] == $ve_id) && (($tmpve["m_id"] == $_SESSION["member"]["m_id"]) || $_SESSION["is_admin"])) {
					if($tmpve["vps_deleted"]) {
						$this->exists = false;
						$this->deleted = true;
					} else $this->exists = true;
					
					$this->veid = $ve_id;
					$this->ve = $tmpve;
					
					if(!$_SESSION["is_admin"] && !$this->is_manipulable())
						$this->exists = false;
					
					}
				else  {
				    die ("Hacking attempt. This incident will be reported.");
				}
			} else $this->exists = false;
		} else $this->exists = false;
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
				    dns_resolver_id ="'.$db->check($cluster->get_first_suitable_dns($location["location_id"])).'",
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
		$this->ve["m_id"] = $m_id;
		$this->ve["vps_id"] = $this->veid;
		
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
		$this->mount_regen();
		$sql = 'UPDATE vps SET  vps_features_enabled=0
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
  function passwd ($user) {
		global $db;
		if ($this->exists) {
			$new_pass = random_string(15);
			
			$command = array('user' => $user, 'password' => $new_pass);
			add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_EXEC_PASSWD, $command);
			
			return $new_pass;
		}
  }

  function stop ($dep = NULL, $fallback = array()) {
	global $db;
	if ($this->exists) {
	    $db->query('UPDATE vps SET vps_onstartall = 0 WHERE vps_id='.$db->check($this->veid));
	    add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_STOP_VE, array(), NULL, $dep, $fallback);
	}
  }

  function start () {
	global $db;
	if ($this->exists) {
	    $db->query('UPDATE vps SET vps_onstartall = 1 WHERE vps_id='.$db->check($this->veid));
	    $server = $db->findByColumnOnce("servers", "server_id", $this->ve["vps_server"]);
	    $location = $db->findByColumnOnce("locations", "location_id", $server["server_location"]);
	    $params = array("onboot" => $location["location_vps_onboot"]);
	    add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_START_VE, $params);
	}
  }

  function restart () {
	global $db;
	if ($this->exists) {
	    $server = $db->findByColumnOnce("servers", "server_id", $this->ve["vps_server"]);
	    $location = $db->findByColumnOnce("locations", "location_id", $server["server_location"]);
	    $params = array("onboot" => $location["location_vps_onboot"]);
	    add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_RESTART_VE, $params);
	}
  }

  function restore_run_state() {
	$this->info();
	
	if($this->ve["vps_onstartall"] && !$this->ve["vps_up"])
		$this->start();
	else if(!$this->ve["vps_onstartall"] && $this->ve["vps_up"])
		$this->stop();
  }
  
  function is_owner ($m_id) {
	global $db;
	if ($this->exists) {
		return ($this->ve["m_id"] == $m_id);
	}
  }

  function set_hostname($new_hostname, $dep = NULL) {
    global $db;
    if ($this->exists) {
	$sql = 'UPDATE vps SET vps_hostname = "'.$db->check($new_hostname).'" WHERE vps_id='.$db->check($this->veid);
	if ($result = $db->query($sql)) {
	    $command = array('hostname' => $new_hostname);
	    add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_EXEC_HOSTNAME, $command, NULL, $dep);
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


  function destroy($lazy, $force = false) {
	global $db;
	if (($this->exists || $this->deleted) && ($_SESSION["is_admin"] || $force)) {
		
		if($lazy) {
			if($db->query("UPDATE vps SET vps_deleted = ".time()." WHERE vps_id = ". $db->check($this->veid))) {
				if($this->is_playground())
					$this->delete_all_ips(true);
					
				$this->exists = false;
				
				return true;
				
			} else return false;
			
		} else {
			$sql = 'DELETE FROM vps WHERE vps_id='.$db->check($this->veid);

			nas_delete_mounts_for_vps($this->veid);

			if ($result = $db->query($sql)) {
				if ($this->delete_all_ips(true)) {
					$this->exists = false;
					add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_DESTROY_VE);
					return true;
				} else return false;
			} else return false;
		}
	}
  }
  
  function delete_all_ips($trans = false) {
	global $db;
	
	if($trans) {
		$ips = $this->iplist();
		
		foreach($ips as $ip)
			$this->ipdel($ip["ip_addr"]);
			
		return true;
		
	} else
		return $db->query('UPDATE vps_ip SET vps_id = 0 WHERE vps_id='.$db->check($this->veid));
  }
  
  function revive() {
	global $db;
	
	$db->query("UPDATE vps SET vps_deleted = NULL WHERE vps_id = ".$this->veid);
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

function ipadd($ip, $type = 4, $dep = NULL) {
	global $db;
	if ($this->exists) {
	    if ($ipadr = ip_exists_in_table($ip)) {
		$sql = 'UPDATE vps_ip
			SET vps_id = "'.$db->check($this->veid).'"
			WHERE ip_id = "'.$db->check($ipadr["ip_id"]).'"';
		$db->query($sql);
		if ($db->affected_rows() > 0) {
		    $command = array(
				'addr' => $ip,
				'version' => $ipadr['ip_v'],
				'shaper' => array(
					'class_id' => $ipadr['class_id'],
					'max_tx' => $ipadr['max_tx'],
					'max_rx' => $ipadr['max_rx']
				)
			);
		    add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_EXEC_IPADD, $command, NULL, $dep);
		    return $db->insertId();
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
		$ipadr = ip_exists_in_table($ip);
		$sql = 'UPDATE vps_ip SET vps_id = 0 WHERE ip_addr="'.$db->check($ip).'"';
		if ($result = $db->query($sql)) {
			$command = array(
				'addr' => $ip,
				'version' => $ipadr['version'],
				'shaper' => array(
					'class_id' => $ipadr['class_id']
				)
			);
			add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_EXEC_IPDEL, $command, NULL, $dep);
			return $db->insertId();
		} else
			return NULL;
	}
  }

  function nameserver($nameserver, $dep = NULL) {
	global $db, $cluster;
	if ($this->exists) {
	  $sql = 'UPDATE vps SET dns_resolver_id = '.$db->check($nameserver).' WHERE vps_id = '.$db->check($this->veid);
	  $db->query($sql);
	  
	  $resolver = $cluster->get_dns_server_by_id($nameserver);
	  
	  $nameservers = explode(",", $resolver['dns_ip']);
	  $command = array("nameservers" => array());
	  foreach ($nameservers as $ns) {
      $command["nameserver"][] = $ns;
	  }
	  $this->ve["vps_nameserver"] = $resolver['dns_ip'];
	  $this->ve["dns_resolver_id"] = $nameserver;
	  add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_EXEC_DNS, $command, NULL, $dep);
	}
  }

  function offline_migrate($target_id, $stop = false, $dep = NULL) {
	return $this->migrate(false, $target_id, $stop, $dep);
  }

  function online_migrate($target_id) {
	return $this->migrate(true, $target_id);
  }
  
  function migrate($online, $target_id, $stop = false, $dep = NULL) {
	global $db, $cluster;
	if ($this->exists) {
		$servers = list_servers();
		if (isset($servers[$target_id])) {
// 			$sql = 'UPDATE vps SET vps_server = "'.$db->check($target_id).'" WHERE vps_id = '.$db->check($this->veid);
// 			$db->query($sql);
			$this_loc = $this->get_location();
			$this->info();
			
			$source_server = new cluster_node($this->ve["vps_server"]);
			$target_server = new cluster_node($target_id);
			
			$params["src_node_type"] = $source_server->role["fstype"];
			$params["dst_node_type"] = $target_server->role["fstype"];
			$params["src_addr"] = $source_server->s["server_ip4"];
			$params["src_ve_private"] = str_replace("%{veid}", $this->veid, $source_server->role["ve_private"]);
			$params["start"] = $this->ve["vps_onstartall"] == 1 || $this->ve["vps_up"];
			$params["stop"] = (bool)$stop;
			$params["online"] = $online;
			
			$fallback = array(
				"transactions" => array(
				array( // start VE on source node when anything fails
					"t_type" => 1001,
					"t_m_id" => $_SESSION["member"]["m_id"],
					"t_server" => $source_server->s["server_id"],
					"t_vps" => $this->veid,
					"t_urgent" => 1,
					"t_priority" => 100,
					"t_param" => array("onboot" => $this_loc["location_vps_onboot"]),
				))
			);
			
			add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_MIGRATE_PREPARE, $params, NULL, $dep);
			$migration_id = $db->insertId();
			
			add_transaction($_SESSION["member"]["m_id"], $target_server->s["server_id"], $this->veid, T_MIGRATE_PART1, $params, NULL, $migration_id);
			$migration_id = $db->insertId();
			
			if ($online) {
				add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_SUSPEND_VE, $params, NULL, $migration_id, $fallback);
				$migration_id = $db->insert_id();
				
			} else {
				add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_STOP_VE, array(), NULL, $migration_id, $fallback);
				$migration_id = $db->insert_id();
			}
			
			add_transaction($_SESSION["member"]["m_id"], $target_server->s["server_id"], $this->veid, T_MIGRATE_PART2, $params, NULL, $migration_id, $fallback, true);
			$migration_id = $db->insertId();
			
			$this->ve["vps_server"] = $target_server->s["server_id"];
			$this->applyconfigs($migration_id);
			
			$ips = $this->iplist();
			
			foreach($ips as $ip) {
				$migration_id = $this->shaper_set($ip, $migration_id);
			}
			
			$this->ve["vps_server"] = $source_server->s["server_id"];
			
			foreach($ips as $ip) {
				$migration_id = $this->shaper_unset($ip, $migration_id);
			}
			
			if ($source_server->role["fstype"] != $target_server->role["fstype"])
			{
				$e = nas_get_export_by_id($this->ve["vps_backup_export"]);
				
				$trash = array(
					"dataset" => $e["root_dataset"]."/".$e["dataset"],
				);
				
				add_transaction($_SESSION["member"]["m_id"], $e["node_id"], $this->veid, T_BACKUP_TRASH, $trash, NULL, $migration_id);
			}
			
			add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_MIGRATE_CLEANUP, $params, NULL, $migration_id);
			$migration_id = $db->insertId();
			
			//$this->ve["vps_server"] = $target_id;
			
			if ($this_loc != $cluster->get_location_of_server($target_id)) {
				$ips = $this->iplist();
				
				$this->ve["vps_server"] = $target_server->s["server_id"];
				if($ips) {
					foreach($ips as $ip)
						$this->ipdel($ip["ip_addr"], $migration_id);
				}
				$this->ve["vps_server"] = $source_server->s["server_id"];
			}
			
			return $migration_id;
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
  
  function update_custom_config($cfg, $dep = NULL) {
	global $db;
	
	$db->query("UPDATE vps SET vps_config = '".$db->check($cfg)."' WHERE vps_id = '".$db->check($this->veid)."'");
	
	add_transaction_clusterwide($_SESSION["member"]["m_id"], $this->veid, T_CLUSTER_CONFIG_CREATE, array("name" => "vps-".$this->veid, "config" => $cfg), array('node'));
	$this->applyconfigs($dep);
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
  
  function configs_change_notify($reason) {
	global $db, $cluster_cfg;

	$subject = $cluster_cfg->get("mailer_tpl_limits_change_subj");
	$subject = str_replace("%member%", $this->ve["m_nick"], $subject);
	$subject = str_replace("%vpsid%", $this->veid, $subject);
	
	$content = $cluster_cfg->get("mailer_tpl_limits_changed");
	$content = str_replace("%member%", $this->ve["m_nick"], $content);
	$content = str_replace("%vpsid%", $this->veid, $content);
	$content = str_replace("%reason%", $reason, $content);
	
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
  
  function set_backuper($how, $export, $exclude, $force = false) {
  	global $db;
	
	/**
	 * how: do not touch if NULL
	 * export: do not touch if === NULL
	 * exclude: do not touch if === false
	 */
	
	$update = array();
	
	if ($_SESSION["is_admin"] || $force) {
		if ($how !== NULL) {
			$update[] = "vps_backup_enabled = " . ($how ? '1' : '0');
			$this->ve["vps_backup_enabled"] = (bool)$how;
		}
		
		if ($export !== NULL) {
			$update[] = "vps_backup_export = '".$db->check($export)."'";
			$this->ve["vps_backup_export"] = $export;
		}
		
		if ($exclude !== false)
		{
			$update[] = "vps_backup_exclude = '".$db->check($exclude)."'";
			$this->ve["vps_backup_exclude"] = $exclude;
		}
		
		if (!count($update))
			return;
		
		$sql = 'UPDATE vps SET '.implode(",", $update).' WHERE vps_id = '.$db->check($this->veid);
  	} else {
		$this->ve["vps_backup_exclude"] = $exclude;
		$sql = 'UPDATE vps SET vps_backup_exclude = "'.$db->check($exclude).'" WHERE vps_id = '.$db->check($this->veid);
	}
  	
  	$db->query($sql);
  }
  
  function set_backup_lock($lock) {
	global $db;
	
	$sql = 'UPDATE vps SET vps_backup_lock = '.($lock ? '1' : '0').' WHERE vps_id = '.$db->check($this->veid);
	
  	$db->query($sql);
  }
  
  function backup($type) {
	global $db;
	
	$node = new cluster_node($this->ve["vps_server"]);
	$backuper = $this->get_backuper_server();
	$e = nas_get_export_by_id($this->ve["vps_backup_export"]);
	
	$dataset = $e["root_dataset"] . "/" . $e["dataset"];
	$path = $e["root_path"] . "/" . $e["path"];
  
	$params = array(
		"src_node_type" => $node->role["fstype"],
		"dst_node_type" => "zfs", # FIXME
		"server_name" => $this->ve["server_name"],
		"node_addr" => $this->ve["server_ip4"],
		"exclude" => preg_split ("/(\r\n|\n|\r)/", $this->ve["vps_backup_exclude"]),
		"dataset" => $dataset,
		"path" => $path,
		"backuper" => $backuper["server_id"],
		"set_dependency" => $restore_id,
		"backup_type" => $type,
		"rotate_backups" => false,
	);
	
	if($node->role["fstype"] == "zfs") {
		add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_BACKUP_SNAPSHOT, $params);
		
	} else {
		add_transaction($_SESSION["member"]["m_id"], $backuper["server_id"], $this->veid, $type, $params);
	}
	
	return $db->insertId();
  }
  
  function restore($timestamp, $backup_first = false) {
	if(!$this->exists)
		return NULL;
  
	global $db;
	
	$node = new cluster_node($this->ve["vps_server"]);
	$backup_id = NULL;
	$restore_id = NULL;
	$backuper = $this->get_backuper_server();
	$e = nas_get_export_by_id($this->ve["vps_backup_export"]);
	
	$dataset = $e["root_dataset"] . "/" . $e["dataset"];
	$path = $e["root_path"] . "/" . $e["path"];
	
	$restore_params = array(
		"src_node_type" => $node->role["fstype"],
		"dst_node_type" => "zfs", # FIXME
		"datetime" => strftime("%Y-%m-%dT%H:%M:%S", (int)$timestamp),
		"backuper" => $backuper["server_name"],
		"server_name" => $this->ve["server_name"],
		"node_addr" => $this->ve["server_ip4"],
		"dataset" => $dataset,
		"path" => $path,
	);
	
	if ($backup_first)
	{
		if($node->role["fstype"] == "zfs")
			$restore_id = $this->restore_transactions($backuper["server_id"], $restore_params, -1);
		
		$backup_id = $this->backup(T_BACKUP_SCHEDULE);
		
		if($node->role["fstype"] != "zfs")
			$this->restore_transactions($backuper["server_id"], $restore_params, $backup_id);
		
	} else
		$this->restore_transactions($backuper["server_id"], $restore_params, $backup_id);
  }
  
  function restore_transactions($backuper, $params, $dep) {
	global $db;
	
	add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_BACKUP_RESTORE_PREPARE, $params, NULL, $dep);
	$prepare_id = $db->insertId();
	
	add_transaction($_SESSION["member"]["m_id"], $backuper, $this->veid, T_BACKUP_RESTORE_RESTORE, $params, NULL, $prepare_id);
	$restore_id = $db->insertId();
	
	add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_BACKUP_RESTORE_FINISH, $params, NULL, $restore_id);
	
	return $prepare_id;
  }
  
  function download_backup($timestamp) {
	if(!$this->exists)
		return NULL;
	
	global $db, $cluster_cfg;
	
	$node = new cluster_node($this->ve["vps_server"]);
	$backuper = $this->get_backuper_server();
	$e = nas_get_export_by_id($this->ve["vps_backup_export"]);
	$secret = hash("sha256", $this->veid . $timestamp . time() . rand(0, 99999999));
	$params = array(
		"src_node_type" => $node->role["fstype"],
		"dst_node_type" => "zfs", # FIXME,
		"secret" => $secret,
		"dataset" => $e["root_dataset"] . "/" . $e["dataset"],
		"path" => $e["root_path"] . "/" . $e["path"],
		"node_addr" => $this->ve["server_ip4"],
	);
	
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
				dns_resolver_id ="'.$db->check($this->ve["dns_resolver_id"]).'",
				vps_server ="'.$db->check($server_id).'",
				vps_onboot ="'.$db->check($this->ve["vps_onboot"]).'",
				vps_onstartall = '.$db->check($this->ve["vps_onstartall"]).',
				vps_features_enabled = '.$db->check($features ? $this->ve["vps_features_enabled"] : 0).',
				vps_backup_enabled = '.$db->check($backuper ? $this->ve["vps_backup_enabled"] : 1).',
				vps_backup_exclude = "'.$db->check($backuper ? $this->ve["vps_backup_exclude"] : '').'",
				vps_config = "'.$db->check($configs ? $this->ve["vps_config"] : '').'"';
	
	$db->query($sql);
	$clone = vps_load($db->insert_id());
	
	$src_node = new cluster_node($this->ve["vps_server"]);
	$dst_node = new cluster_node($server_id);
	
	$params = array(
		"src_veid" => $this->veid,
		"src_addr" => $this->ve["server_ip4"],
		"src_node_type" => $src_node->role["fstype"],
		"dst_node_type" => $dst_node->role["fstype"],
	);
	
	add_transaction($_SESSION["member"]["m_id"], $server_id, $clone->veid, $server_id == $this->ve["vps_server"] ? T_CLONE_VE_LOCAL : T_CLONE_VE_REMOTE, $params);
	
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
	
	// Clone mounts - exports are the same, except backup, that must be created
	$db->query("INSERT INTO vps_mount (vps_id, src, dst, mount_opts, umount_opts, type, server_id, storage_export_id, mode, cmd_premount, cmd_postmount, cmd_preumount, cmd_postumount)
	            SELECT ".$clone->veid." AS vps_id, src, dst, mount_opts, umount_opts, type, server_id, storage_export_id, mode, cmd_premount, cmd_postmount, cmd_preumount, cmd_postumount
	            FROM vps_mount
	            WHERE vps_id = ".$db->check($this->veid));
	
	$def_exports = nas_list_default_exports("vps");
	$cloned_backup_export = 0;
	
	foreach($def_exports as $e) {
		if($e["export_type"] == "backup") {
			$cloned_backup_export = nas_export_add(
				$clone->ve["m_id"],
				$e["root_id"],
				nas_resolve_vars($e["dataset"], $clone->ve),
				nas_resolve_vars($e["path"], $clone->ve),
				$e["export_quota"],
				$e["user_editable"],
				$e["export_type"]
			);
			break;
		}
	}
	
	if($cloned_backup_export) {
		$db->query("UPDATE vps_mount SET storage_export_id = ".$db->check($cloned_backup_export)."
		            WHERE vps_id = ".$db->check($clone->veid)." AND storage_export_id = ".$db->check($this->ve["vps_backup_export"]));
		
		$clone->set_backuper(NULL, $cloned_backup_export, false, true);
	}
	
	$clone->mount_regen();
	
	$clone->set_hostname($hostname);
	
	if ($features && $this->ve["vps_features_enabled"])
		add_transaction($_SESSION["member"]["m_id"], $server_id, $clone->veid, T_ENABLE_FEATURES);
		
	$this->info();
	if ($this->ve["vps_up"])
		$clone->start();
	
	return $clone;
  }
  
  function swap($with, $owner, $hostname, $ips, $configs, $expiration, $backups, $dns) {
	global $db;
	
	$with_server = $with->ve["vps_server"];
	
	if($ips) {
		$with_ips = $with->iplist();
		$my_ips = $this->iplist();
	}
	
	if($with_server != $this->ve["vps_server"]) {
		$t_with_id = $with->offline_migrate($this->ve["vps_server"]);
		$with->ve["vps_server"] = $this->ve["vps_server"];
		
		if($ips) {
			if($this->ve["server_location"] == $with->ve["server_location"]) {
				foreach($with_ips as $ip)
					$with->ipdel($ip["ip_addr"], $t_with_id);
			}
			
			foreach($my_ips as $ip) {
				$t = $this->ipdel($ip["ip_addr"], $t_with_id);
				$with->ipadd($ip["ip_addr"], $ip["ip_v"], $t);
			}
			
		}
		
		$t_my_id = $this->offline_migrate($with_server, false, $t_with_id);
		$this->ve["vps_server"] = $with_server;
		
		if($ips) {
			foreach($with_ips as $ip)
				$this->ipadd($ip["ip_addr"], $ip["ip_v"], $t_my_id);
		}
		
	} else if($ips) {
		foreach($my_ips as $ip) {
			$t = $this->ipdel($ip["ip_addr"]);
			$with->ipadd($ip["ip_addr"], $ip["ip_v"], $t);
		}
		
		foreach($with_ips as $ip) {
			$t = $with->ipdel($ip["ip_addr"]);
			$this->ipadd($ip["ip_addr"], $ip["ip_v"], $t);
		}
	}
	
	if($owner) {
		$my_owner = $this->ve["m_id"];
		$with_owner = $with->ve["m_id"];
		
		$this->vchown($with_owner);
		$with->vchown($my_owner);
	}
	
	if($hostname) {
		$my_h = $this->ve["vps_hostname"];
		$with_h = $with->ve["vps_hostname"];
		
		$this->set_hostname($with_h, $t_my_id);
		$with->set_hostname($my_h, $t_with_id);
	}
	
	if($configs) {
		$my_configs = $this->get_configs();
		$with_configs = $with->get_configs();
		$my_custom = $this->ve["vps_config"];
		$with_custom = $with->ve["vps_config"];
		
		$db->query("DELETE FROM vps_has_config WHERE vps_id = ".$db->check($this->veid)." OR vps_id = ".$db->check($with->veid));
		
		$i = 1;
		
		foreach($my_configs as $id => $label)
			$db->query("INSERT INTO vps_has_config SET vps_id = ".$db->check($with->veid).", config_id = ".$db->check($id).", `order` = ".$i++);
		
		$i = 1;
		
		foreach($with_configs as $id => $label)
			$db->query("INSERT INTO vps_has_config SET vps_id = ".$db->check($this->veid).", config_id = ".$db->check($id).", `order` = ".$i++);
		
		if($my_custom != $with_custom)
		{
			$this->update_custom_config($with_custom, $t_my_id);
			$with->update_custom_config($my_custom, $t_with_id);
		}
		
		$this->applyconfigs($t_my_id);
		$with->applyconfigs($t_with_id);
	}
	
	if($expiration) {
		$my_e = $this->ve["vps_expiration"];
		$with_e = $with->ve["vps_expiration"];
		
		$this->set_expiration($with_e);
		$with->set_expiration($my_e);
	}
	
	if($backups) {
		$my_enabled = $this->ve["vps_backup_enabled"];
		$my_exclude = $this->ve["vps_backup_exclude"];
		
		$with_enabled = $with->ve["vps_backup_enabled"];
		$with_exclude = $with->ve["vps_backup_exclude"];
		
		$this->set_backuper($with_enabled, NULL, $with_exclude, true);
		$with->set_backuper($my_enabled, NULL, $my_exclude, true);
	}
	
	if($dns) {
		$my_d = $this->ve["dns_resolver_id"];
		$with_d = $with->ve["dns_resolver_id"];
		
		$this->nameserver($with_d, $t_my_id);
		$with->nameserver($my_d, $t_with_id);
	}
  }
  
  function mount_regen() {
	global $db;
	
	$params = array( "mounts" => array() );
	$rs = $db->query("SELECT m.src, m.dst, m.mount_opts, m.umount_opts, m.mode, m.storage_export_id, m.server_id, r.root_path, e.path,
						s.server_ip4 AS mount_server_ip4, es.server_ip4 AS export_server_ip4
					FROM vps_mount m
					LEFT JOIN storage_export e ON e.id = m.storage_export_id
					LEFT JOIN storage_root r ON e.root_id = r.id
					LEFT JOIN servers es ON es.server_id = r.node_id
					LEFT JOIN servers s ON m.server_id = s.server_id
					WHERE m.vps_id = " . $db->check($this->veid) . " AND m.`default` = 0 ORDER BY m.id ASC");
	
	while($mnt = $db->fetch_array($rs)) {
		$params["mounts"][] = nas_mount_params($mnt, false);
	}
	
	add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_NAS_VE_MOUNT_GEN, $params);
  }
  
  function get_mounts() {
	global $db;
	
	$ret = array();
	$rs = $db->query("SELECT * FROM vps_mount m LEFT JOIN servers s ON m.server_id = s.server_id WHERE vps_id = " . $db->check($this->veid));
	
	while ($row = $db->fetch_array($rs))
		$ret[] = $row;
	
	return $ret;
  }
  
  function mount($mount) {
	global $db;
	
	add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_NAS_VE_MOUNT, nas_mount_params($mount));
  }
  
  function umount($mount) {
	global $db;
	
	add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_NAS_VE_UMOUNT, nas_mount_params($mount));
  }
  
  function remount($mount) {
	global $db;
	
	add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_NAS_VE_REMOUNT, nas_mount_params($mount));
  }
  
  function delete_all_backups() {
	global $db;
	
	$db->query("DELETE FROM vps_backups WHERE vps_id = ". $this->veid);
  }
  
  function get_backuper_server() {
	global $db;
	$e = nas_get_export_by_id($this->ve["vps_backup_export"]);
	$n = new cluster_node($e["node_id"]);
	return $n->s;
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
  
  function set_expiration($timestamp) {
	global $db;
	
	$db->query("UPDATE vps SET vps_expiration = ".$db->check($timestamp ? (int)$timestamp : "NULL")." WHERE vps_id = ".$db->check($this->veid));
  }
  
  function is_playground() {
	global $db;
	
	$l = $db->findByColumnOnce("locations", "location_id", $this->ve["server_location"]);
	
	return $l["location_type"] == "playground";
  }
  
  function is_manipulable() {
	return $_SESSION["is_admin"] || !$this->ve["server_maintenance"];
  }
  
  function shaper_set($ip, $dep = null) {
	global $db;
	
	$params = array(
		'addr' => $ip['ip_addr'],
		'version' => $ip['ip_v'],
		'shaper' => array(
			'class_id' => $ip['class_id'],
			'max_tx' => $ip['max_tx'],
			'max_rx' => $ip['max_rx']
		)
	);
	
	add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_EXEC_SHAPER_SET, $params, null, $dep);
	return $db->insertId();
  }
  
  function shaper_unset($ip, $dep = null) {
	global $db;
	
	$params = array(
		'addr' => $ip['ip_addr'],
		'version' => $ip['ip_v'],
		'shaper' => array(
			'class_id' => $ip['class_id']
		)
	);
	
	add_transaction($_SESSION["member"]["m_id"], $this->ve["vps_server"], $this->veid, T_EXEC_SHAPER_UNSET, $params, null, $dep);
	return $db->insertId();
  }
}
?>
