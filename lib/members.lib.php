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
  $sql = 'SELECT m_id FROM members '. (($_SESSION["is_admin"]) ? '' : " WHERE m_id = {$db->check($_SESSION["member"]["m_id"])}");
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
  public $mid;

  function member_load($m_id) {
    global $db;
    if(is_numeric($m_id)) {
      $sql = 'SELECT * FROM members WHERE m_id = "'.$db->check($m_id).'"';
      if ($result = $db->query($sql))
        if ($tmpm = $db->fetch_array($result))
          if ($tmpm["m_id"] == $m_id && (($tmpm["m_id"] == $_SESSION["member"]["m_id"]) || $_SESSION["is_admin"])) {
            $this->m["m_info"] = stripslashes($this->m["m_info"]);
            $this->exists = true;
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
                m_info = "'.$db->check($this->m["m_info"]).'"';
      $db->query($sql);
      if ($db->affected_rows() > 0) {
        $this->exists = true;
        $this->mid = $db->insert_id();
        $this->m["m_id"] = $this->mid;
        $headers  = "From: ".$cluster_cfg->get("mailer_from")."\n";
        $headers .= "Reply-To: ".$cluster_cfg->get("mailer_from")."\n";
        $headers .= "Return-Path: ".$cluster_cfg->get("mailer_from")."\n";
        if ($cluster_cfg->get("mailer_admins_in_cc")) {
            $headers .= "BCC: ".$cluster_cfg->get("mailer_admins_cc_mails")."\n";
        }
        $headers .= "X-Mailer: vpsAdmin\n";
        $headers .= "MIME-Version: 1.0\n";
        $headers .= "Content-type: text/plain; charset=UTF-8\n";

        $subject = $cluster_cfg->get("mailer_tpl_member_added_subj");
        $subject = str_replace("%member%", $this->m["m_nick"], $subject);

        $content = $cluster_cfg->get("mailer_tpl_member_added");
        $content = str_replace("%member%", $this->m["m_nick"], $content);
        $content = str_replace("%memberid%", $this->m["m_id"], $content);
        $content = str_replace("%pass%", $item["m_pass"], $content);

        $mail = array();
        $mail["sentTime"] = time();
        $mail["member_id"] = $this->m["m_id"];
        $mail["type"] = "member_added";
        $mail["details"] .= "TO: {$this->m["m_mail"]}\n";
        $mail["details"] .= $headers;
        $mail["details"] .= "\nSUBJECT: $subject\n\n";
        $mail["details"] .= $content;

        mail($this->m["m_mail"], $subject, $content, $headers);

        $db->save(true, $mail, "mailer");

        return true;
      }
      else return false;
    } else return false;
  }

  /**
    * Destroy member from database
    * @return true on success, false if fails
    */
  function destroy() {
    global $db, $cluster_cfg;
    if ($this->exists) {
      $sql = 'DELETE FROM members WHERE m_id='.$db->check($_GET["id"]);
      $db->query($sql);
      if ($db->affected_rows() > 0) {
        $this->exists = false;
        return true;
        }
      else return false;
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
              m_monthly_payment = "'.$db->check($this->m["m_monthly_payment"]).'"
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
}
?>
