<?php
/*
    ./lib/members.lib.php

    vpsAdmin
    Web-admin interface for OpenVZ (see http://openvz.org)
    Copyright (C) 2008-2011 Pavel Snajdr, snajpa@snajpa.net
*/
define ('MEMBER_SESSION_TIMEOUT_SECS', 1800);

/**
  * Get array of all members in DB
  * @return array of instances of member_load
  */
function get_members_array(){
  global $db;
  $sql = "SELECT m_id FROM members WHERE m_state != 'deleted' ". ($_SESSION["is_admin"] ? '' : " AND m_id = ".$db->check($_SESSION["member"]["m_id"]));
  if ($result = $db->query($sql))
    while ($row = $db->fetch_array($result)) {
      $ret [] = new member_load($row["m_id"]);
    }
  return $ret;
}
/**
  * Load member
  * @param $mid - ID of member
  * @return instance of member_load class
  */
function member_load ($mid = false) {
  $m = new member_load($mid);
  return $m;
}


class member_load {

  public $m;
  public $exists;
  public $deleted = false;
  public $mid;

  function member_load($m_id) {
    global $db;
    if(is_numeric($m_id)) {
      $sql = 'SELECT * FROM members WHERE m_id = "'.$db->check($m_id).'"';
      if ($result = $db->query($sql))
        if ($tmpm = $db->fetch_array($result))
          if ($tmpm["m_id"] == $m_id && (($tmpm["m_id"] == $_SESSION["member"]["m_id"]) || $_SESSION["is_admin"])) {
            $this->m["m_info"] = stripslashes($this->m["m_info"]);
            
            if($tmpm["m_state"] == "deleted") {
              $this->exists = false;
              $this->deleted = true;
            } else $this->exists = true;
            $this->mid = $m_id;
            $this->m = $tmpm;
            }
          else  {
              die ("Hacking attempt. This incident will be reported. #m");
          }
        else $this->exists = false;
      else $this->exists = false;
    } else $this->exists = false;
    return true;
  }
  /**
    * Creates new member
    * @param $item - array descriptor of new member
    * @return true on success, false if fails
    */
  function create_new($item) {
    global $db, $cluster_cfg;
    if (!$this->exists) {
      $this->m["m_nick"] = $item["m_nick"];
      $this->m["m_level"] = $item["m_level"];
      $this->m["m_name"] = $item["m_name"];
      $this->m["m_mail"] = $item["m_mail"];
      $this->m["m_mailer_enable"] = $item["m_mailer_enable"];
      $this->m["m_playground_enable"] = $item["m_playground_enable"];
      $this->m["m_pass"] = md5($item["m_nick"].$item["m_pass"]);
      $this->m["m_address"] = $item["m_address"];
      $this->m["m_info"] = "";
      $this->m["m_created"] = time();
      $sql = 'INSERT INTO members
              SET m_nick = "'.$db->check($this->m["m_nick"]).'",
                m_created = "'.$db->check($this->m["m_created"]).'",
                m_level = "'.$db->check($this->m["m_level"]).'",
                m_pass = "'.$db->check($this->m["m_pass"]).'",
                m_name = "'.$db->check($this->m["m_name"]).'",
                m_mail = "'.$db->check($this->m["m_mail"]).'",
                m_address = "'.$db->check($this->m["m_address"]).'",
                m_mailer_enable = "'.$db->check($this->m["m_mailer_enable"]).'",
				m_playground_enable = "'.$db->check($this->m["m_playground_enable"]).'",
                m_info = "'.$db->check($this->m["m_info"]).'"';
      $db->query($sql);
      if ($db->affected_rows() > 0) {
        $this->exists = true;
        $this->mid = $db->insert_id();
        $this->m["m_id"] = $this->mid;

        $subject = $cluster_cfg->get("mailer_tpl_member_added_subj");
        $subject = str_replace("%member%", $this->m["m_nick"], $subject);

        $content = $cluster_cfg->get("mailer_tpl_member_added");
        $content = str_replace("%member%", $this->m["m_nick"], $content);
        $content = str_replace("%memberid%", $this->m["m_id"], $content);
        $content = str_replace("%pass%", $item["m_pass"], $content);

        send_mail($this->m["m_mail"], $subject, $content, array(), $cluster_cfg->get("mailer_admins_in_cc") ? explode(",", $cluster_cfg->get("mailer_admins_cc_mails")) : array());

        return true;
      }
      else return false;
    } else return false;
  }

  /**
    * Destroy member from database
    * @return true on success, false if fails
    */
  function destroy($lazy) {
	global $db, $cluster_cfg;
	
	if ($this->exists || $this->deleted) {
		if($lazy)
			$sql = "UPDATE members SET m_state = 'deleted', m_deleted = ".time()." WHERE m_id=".$db->check($this->mid);
		else {
			$sql = 'DELETE FROM members WHERE m_id='.$db->check($this->mid);
			
			nas_delete_members_exports($this->mid);
		}
		$db->query($sql);
	
		if ($db->affected_rows() > 0) {
			$this->exists = false;
			return true;
		} else return false;
	} else return false;
  }
  /**
    * Saves $this->m to the DB
    * @return true on success, false if fails
    */
  function save_changes() {
    global $db;
    if ($this->exists) {
      if (!$_SESSION["is_admin"]){
          $this->m["m_level"] = PRIV_USER;
          $sql = 'UPDATE members
          SET m_pass = "'.$db->check($this->m["m_pass"]).'",
              m_name = "'.$db->check($this->m["m_name"]).'",
              m_mail = "'.$db->check($this->m["m_mail"]).'",
              m_address = "'.$db->check($this->m["m_address"]).'",
              m_mailer_enable = "'.$db->check($this->m["m_mailer_enable"]).'",
              m_lang = "'.$db->check($this->m["m_lang"]).'"
          WHERE m_id="'.$db->check($this->mid).'"';
      } else {
          $sql = 'UPDATE members
          SET m_nick = "'.$db->check($this->m["m_nick"]).'",
              m_level = "'.$db->check($this->m["m_level"]).'",
              m_pass = "'.$db->check($this->m["m_pass"]).'",
              m_name = "'.$db->check($this->m["m_name"]).'",
              m_mail = "'.$db->check($this->m["m_mail"]).'",
              m_address = "'.$db->check($this->m["m_address"]).'",
              m_lang = "'.$db->check($this->m["m_lang"]).'",
              m_info = "'.$db->check(addslashes($this->m["m_info"])).'",
              m_paid_until = "'.$db->check($this->m["m_paid_until"]).'",
              m_mailer_enable = "'.$db->check($this->m["m_mailer_enable"]).'",
              m_monthly_payment = "'.$db->check($this->m["m_monthly_payment"]).'",
              m_playground_enable = "'.$db->check($this->m["m_playground_enable"]).'"
          WHERE m_id="'.$db->check($this->mid).'"';
      }
      $db->query($sql);
      if ($db->affected_rows() > 0)
        return true;
      else return false;
    }
  }
  /**
    * Check, if member has paid right now
    * @return true if yes, false if no, (-1) if fails
    */
  function has_paid_now() {
    if (isset($this->m["m_paid_until"]))
      if (time() > $this->m["m_paid_until"])
        return 0;
      else return 1;
    else return 0;
  }
  /**
    * Save date, until the member has paid
    * @param $Y_m_d - Date in "Y-m-d" format, eg. 2012-12-21
    * @return true on success, false if fails
    */
  function set_paid_until($Y_m_d) {
    list ($y, $m, $d) = explode ('-',$Y_m_d);
    $this_payment_until = mktime(0, 0, 0, $m, $d, $y);
    if (true){ //$this->m["m_paid_until"] < $this_payment_until
      $this->m["m_paid_until"] = $this_payment_until;
      if ($this->save_changes())
        return true;
      else return false;
    } else return false;
  }
  function set_paid_add_months($months) {
    $y = date('Y', $this->m["m_paid_until"]);
    $m = date('m', $this->m["m_paid_until"]);
    $d = date('d', $this->m["m_paid_until"]);
    $m += $months;
    $this_payment_until = mktime(0, 0, 0, $m, $d, $y);
    if (true){ //$this->m["m_paid_until"] < $this_payment_until
      $this->m["m_paid_until"] = $this_payment_until;
      if ($this->save_changes())
        return true;
      else return false;
    } else return false;
  }

  /**
    * Save member's last activity time
    */
  function touch_activity() {
      global $db;
      $sql = 'UPDATE members SET m_last_activity = '.time().' WHERE m_id = '.$db->check($this->m["m_id"]);
      $db->query($sql);
  }
  /**
    * Test if member has expired in activity
    * @return true is has, false if has not
    */
  function has_not_expired_activity() {
      return (time() < (MEMBER_SESSION_TIMEOUT_SECS + $this->m["m_last_activity"]));
  }

  function get_vps_count() {
      global $db;
      $sql = 'SELECT COUNT(*) AS count FROM vps WHERE m_id ='.$db->check($this->m["m_id"]);
      if ($result = $db->query($sql)) {
    if ($row = $db->fetch_array($result)) {
        return $row["count"];
    }
      }
      return false;
  }

  function is_new() {
    return isset($this->m["m_created"]) && ((time() - $this->m["m_created"]) <= 3600*24*7);
  }
  
  function can_use_playground() {
	global $db;
	
	if (!$this->exists || !$this->m["m_playground_enable"] || $this->m["m_state"] != "active")
		return false;
	
	$sql = "SELECT COUNT(vps_id) AS count
		FROM vps
		INNER JOIN servers ON vps_server = server_id
		INNER JOIN locations ON location_id = server_location
		WHERE m_id = ".$db->check($this->m["m_id"])." AND location_type = 'playground'";
	if ($result = $db->query($sql)) {
		if ($row = $db->fetch_array($result)) {
			return $row["count"] < 1;
		}
	}
	
	return false;
  }
  
  function start_all_vpses() {
	global $db;
	
	while($row = $db->findByColumn("vps", "m_id", $this->m["m_id"])) {
		$vps = new vps_load($row["vps_id"]);
		$vps->info();
		
		if (!$vps->ve["vps_up"])
			$vps->start();
	}
  }
  
  function stop_all_vpses() {
	global $db;
	
	while($row = $db->findByColumn("vps", "m_id", $this->m["m_id"])) {
		$vps = new vps_load($row["vps_id"]);
		$vps->stop();
	}
  }
  
  function delete_all_vpses($lazy) {
	global $db;
	
	if($this->exists || $this->deleted) {
		while($row = $db->findByColumn("vps", "m_id", $this->m["m_id"])) {
			$vps = new vps_load($row["vps_id"]);
			$vps->stop();
			$vps->destroy($lazy);
		}
	}
  }
  
  function set_info($info) {
	global $db;
	
	$db->query('UPDATE members SET m_info = "'.$db->check($info).'" WHERE m_id = '.$db->check($this->m["m_id"]).'');
  }
  
  function suspend($reason) {
	global $db;
	
	$db->query('UPDATE members SET m_state = \'suspended\', m_suspend_reason = "'.$db->check($reason).'" WHERE m_id = '.$db->check($this->m["m_id"]).'');
  }
  
  function restore() {
	global $db;
	
	$db->query("UPDATE members SET m_state = 'active', m_suspend_reason = '' WHERE m_id = ".$db->check($this->m["m_id"]));
  }
  
  function notify_suspend($reason) {
	global $db, $cluster_cfg;

	$subject = $cluster_cfg->get("mailer_tpl_suspend_account_subj");
	$subject = str_replace("%member%", $this->m["m_nick"], $subject);
	
	$content = $cluster_cfg->get("mailer_tpl_suspend_account");
	$content = str_replace("%member%", $this->m["m_nick"], $content);
	$content = str_replace("%reason%", $reason, $content);
	
	send_mail($this->m["m_mail"], $subject, $content, array(), $cluster_cfg->get("mailer_admins_in_cc") ? explode(",", $cluster_cfg->get("mailer_admins_cc_mails")) : array());
  }
  
  function notify_restore() {
	global $db, $cluster_cfg;

	$subject = $cluster_cfg->get("mailer_tpl_restore_account_subj");
	$subject = str_replace("%member%", $this->m["m_nick"], $subject);
	
	$content = $cluster_cfg->get("mailer_tpl_restore_account");
	$content = str_replace("%member%", $this->m["m_nick"], $content);
	
	send_mail($this->m["m_mail"], $subject, $content, array(), $cluster_cfg->get("mailer_admins_in_cc") ? explode(",", $cluster_cfg->get("mailer_admins_cc_mails")) : array());
  }
  
  function notify_delete($lazy) {
	// FIXME: lazy
	global $db, $cluster_cfg;

	$subject = $cluster_cfg->get("mailer_tpl_delete_member_subj");
	$subject = str_replace("%member%", $this->m["m_nick"], $subject);
	
	$content = $cluster_cfg->get("mailer_tpl_delete_member");
	$content = str_replace("%member%", $this->m["m_nick"], $content);
	
	send_mail($this->m["m_mail"], $subject, $content, array(), $cluster_cfg->get("mailer_admins_in_cc") ? explode(",", $cluster_cfg->get("mailer_admins_cc_mails")) : array());
  }
}
?>
