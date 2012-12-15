<?php

// TODO: there are still some functions in lib/functions.lib.php which should not be there. Those functions should be in this class instead as static methods. -- toms
abstract class Cluster_ip {
  protected $type;
  protected $xtpl;
  protected $db;

  function __construct (&$xtpl, &$db) {
    $this->xtpl = $xtpl;
    $this->db   = $db;
  }

  public function table_used_out($title=null, $actions=false) {
    $sql = 'SELECT * FROM vps_ip
	    LEFT JOIN vps
	    ON vps_ip.vps_id = vps.vps_id
	    LEFT JOIN members
	    ON vps.m_id = members.m_id
	    LEFT JOIN locations
	    ON vps_ip.ip_location = locations.location_id
	    WHERE vps_ip.vps_id != 0 AND vps_ip.ip_v ='. $this->type;
    if (isset($title))
      $this->xtpl->table_begin("<h2>".$title."</h2>");
    $this->xtpl->table_add_category(strtoupper(_("nick")));
    $this->xtpl->table_add_category('VPS ID');
    $this->xtpl->table_add_category(_("IPv").$this->type.' '.strtoupper(_("Address")));
    $this->xtpl->table_add_category(_("Location"));
    if ($actions) {
    $this->xtpl->table_add_category("&nbsp;");
    $this->xtpl->table_add_category("&nbsp;");
    }
    if ($result = $this->db->query($sql))
      while ($row = $this->db->fetch_array($result)) {
        $this->xtpl->table_td('<a href="?page=adminm&action=edit&id='.$row["m_id"].'">'.$row["m_nick"].'</a>');
        $this->xtpl->table_td('<a href="?page=adminvps&action=info&veid='.$row["vps_id"].'">'.$row["vps_id"].' ('.$row["vps_hostname"].')</a>');
        $this->xtpl->table_td($row["ip_addr"]);
	$this->xtpl->table_td($row["location_label"]);
        if ($actions) {
          $this->xtpl->table_td('<a href="?page=cluster&action=ipaddr_delete&v='. $this->type .'&ip_id='. $row['ip_id'] .'&vps_id='. $row['vps_id'] .'"><img src="template/icons/m_delete.png"  title="'. _("Delete from cluster") .'" /></a>');
          $this->xtpl->table_td('<a href="?page=cluster&action=ipaddr_remove&v='. $this->type .'&ip_id='. $row['ip_id'] .'&vps_id='. $row['vps_id'] .'"><img src="template/icons/m_remove.png"  title="'. _("Remove from VPS") .'" /></a>');
        }
      $this->xtpl->table_tr();
    }
    $this->xtpl->table_out();
  }

  public function delete($ip_id, $vps_id = -1) {
    $sql = 'DELETE FROM `vps_ip` WHERE `ip_id`=\''. $ip_id .'\';';
    $res = $this->db->query($sql);

    if ($vps_id != -1) {
      $this->remove_from_vps ($ip_id, $vps_id);
      $sql = 'DELETE FROM `firewall` WHERE `ip`=\''. $ip_id .'\';';
      $res = $this->db->query($sql);
    }
    return $res;
  }

  public function remove_from_vps($ip_id, $vps_id) {
    $vps = vps_load($vps_id);
    $ip_addr = $this->get_ip_from_id($ip_id);
    $this->xtpl->perex_cmd_output(_("Deletion of IP planned")." {$ip_addr}", $vps->ipdel($ip_addr));
  }

  public function get_ip_from_id($ip_id) {
    $sql = 'SELECT `ip_addr` FROM `vps_ip` WHERE `ip_id`=\''. ($ip_id*1)  .'\';';
    if ($res = $this->db->query($sql))
      while ($row = $this->db->fetch_array($res))
        return $row['ip_addr'];
    return -1;
  }

  public function table_unused_out($title=null, $actions=false) {
    $sql = 'SELECT * FROM vps_ip
	    LEFT JOIN locations
	    ON vps_ip.ip_location = locations.location_id
	    WHERE vps_ip.ip_v ='. $this->type .' AND vps_id = 0;';
    if (isset($title))
      $this->xtpl->table_begin("<h2>".$title."</h2>");
    $this->xtpl->table_add_category(_("IPv").$this->type.' '.strtoupper(_("Address")));
    $this->xtpl->table_add_category(_("Location"));
    if ($actions)
    $this->xtpl->table_add_category("&nbsp;");

    if ($result = $this->db->query($sql))
      while ($row = $this->db->fetch_array($result)) {
        $this->xtpl->table_td($row["ip_addr"]);
        $this->xtpl->table_td($row["location_label"]);
        if ($actions) {
          $this->xtpl->table_td('<a href="?page=cluster&action=ipaddr_delete&ip_id='. $row['ip_id'] .'&v='.$this->type.'"><img src="template/icons/m_delete.png"  title="'. _("Delete from cluster") .'" /></a>');
        }
        $this->xtpl->table_tr();
      }

    $this->xtpl->table_out();
  }

  public function table_add_1($previous_ips = false, $previous_location=false) {
    global $cluster;
    $this->xtpl->title(_("Add IPv").$this->type);
    $this->xtpl->sbar_add(_("Back"), '?page=cluster&action=ipv'.$this->type.'addr');

    $this->xtpl->table_add_category('&nbsp;');
    $this->xtpl->table_add_category('&nbsp;');
    $this->xtpl->form_create('?page=cluster&action=ipaddr_add2&v='.$this->type, 'post');
    $this->xtpl->form_add_textarea(_("IPv").$this->type.':', 40, 10, 'm_ip', (($previous_ips) ? $previous_ips : ''));
    $this->xtpl->form_add_select(_("Location").':', 'm_location', $cluster->list_locations(), (($previous_location) ? $previous_location : ''),  '');
    $this->xtpl->form_out(_("Add"));
  }

  public function table_add_2($ip_addrs, $location_id) {
	$raw_ips = preg_split("/(\r\n|\n|\r)/", $ip_addrs);
	$out = array();
	$insert = array();
	$cleaned = array();
	$err = true;
	
	foreach ($raw_ips as $ip_addr) {
		if (!$this->check_syntax($ip_addr))
			$out[] = _("Bad format") . ": '$ip_addr'";
		else if (ip_exists_in_table($ip_addr))
			$out[] = "IP '$ip_addr' is already in database";
		else {
			$out[] = _("Added IP") . " $ip_addr";
			$insert[] = "({$this->type}, ".$this->db->check($location_id).", 0, '{$ip_addr}')";
			$cleaned[] = array("ver" => $this->type, "addr" => $ip_addr);
			$err = false;
		}
	}
	
	if($err) {
		$this->xtpl->perex(_("Operation not successful"), implode("<br/>", $out));
		return;
	}
	
	if(!count($insert))
		return;
		
	$sql = "INSERT INTO vps_ip (ip_v, ip_location, vps_id, ip_addr) VALUES " . implode(",", $insert);
	
	if ($this->db->query($sql)) {
		$params = array("ip_addrs" => $cleaned);
	    add_transaction_locationwide($_SESSION["member"]["m_id"], 0, T_CLUSTER_IP_REGISTER, $params, $location_id);
	    $this->xtpl->perex(_("Operation successful"), implode("<br/>", $out));
	} else {
	    $this->xtpl->perex(_("Operation not successful"), _("Insert into database failed."));
	}
  }

   //abstract public function check_syntax($ip_addr);
}

class Cluster_ipv4 extends Cluster_ip {
  protected $type = 4;

  public function check_syntax($ip_addr) {
	  //first of all the format of the ip address is matched
	  if(preg_match("/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/",$ip_addr)) {
	  	//now all the intger values are separated
	  	$parts=explode(".",$ip_addr);
	  	//now we need to check each part can range from 0-255
	  	foreach($parts as $ip_parts) {
	  		if(intval($ip_parts)>255 || intval($ip_parts)<0)
	  		  return false; //if number is not within range of 0-255
	  	}
	  	return true;
	  }
	  else
	  	return false; //if format of ip address doesn't matches
  }

}

class Cluster_ipv6 extends Cluster_ip {
  protected $type = 6;

  public function check_syntax ($ip_addr) {
      $value = $ip_addr;
	  if (substr_count($value, ":") < 2)
      	return false; // has to contain ":" at least twice like in ::1 or 1234::abcd
	  if (substr_count($value, "::") > 1)
      	return false; // only 1 double colon allowed
	  $groups = explode(':', $value);
	  $num_groups = count($groups);
	  if (($num_groups > 8) || ($num_groups < 3))
      	return false; // 3-8 groups of 0-4 digits (1 group has to be at leas 1 digit)
	  $empty_groups = 0;
	  foreach ($groups as $group) {
	  	$group = trim($group);
	  	if (!empty($group) && !(is_numeric($group) && ($group == 0))) {
	  		if (!preg_match('#([a-fA-F0-9]{0,4})#', $group))
          		return false;
	  	} else ++$empty_groups;
	  }
	  return ($empty_groups < $num_groups) ? true : false; // the unspecified address :: is not valid in this case
  }
}
?>
