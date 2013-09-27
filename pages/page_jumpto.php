<?php

if ($_SESSION["logged_in"] && $_SESSION["is_admin"]) {
	unset($_SESSION["jumpto"]);
	$_SESSION["jumpto"] = array();
	
	if ($_POST["member"]) {
		$m = null;
		
		if(is_numeric($_POST["member"])) {
			$member = new member_load($_POST["member"]);
			
			if($member->exists || $member->deleted)
				$m = $member->m["m_id"];
		
		} else {
			$rs = $db->query("SELECT m_id FROM members WHERE m_nick = '".$db->check($_POST["member"])."'
			                  UNION ALL
			                  SELECT m_id FROM members WHERE m_name = '".$db->check($_POST["member"])."'
			                  UNION ALL
			                  SELECT m_id FROM members WHERE m_mail = '".$db->check($_POST["member"])."'");
			
			if($rs && ($row = $db->fetch_array($rs)))
				$m = $row["m_id"];
		}
		
		$_SESSION["jumpto"]["member"] = $_POST["member"];
		
		if($m)
			redirect("?page=adminm&section=members&action=edit&id=".$m);
		else
			$xtpl->perex(_("Member not found"), _("Sorry bro."));
		
	} elseif ($_POST["vps"]) {
		$v = null;
		
		if(is_numeric($_POST["vps"])) {
			$vps = new vps_load($_POST["vps"]);
			
			if($vps->exists || $vps->deleted)
				$v = $vps->veid;
			
		} else {
			$rs = $db->query("SELECT vps_id FROM vps_ip WHERE vps_id != 0 AND ip_addr = '".$db->check($_POST["vps"])."'
			                  UNION ALL
			                  SELECT vps_id FROM vps WHERE vps_hostname = '".$db->check($_POST["vps"])."'");
			
			if($rs && ($row = $db->fetch_array($rs)))
				$v = $row["vps_id"];
		}
		
		$_SESSION["jumpto"]["vps"] = $_POST["vps"];
		
		if($v)
			redirect("?page=adminvps&action=info&veid=".$v);
		else
			$xtpl->perex(_("VPS not found"), _("Sorry bro."));
		
	} else {
		redirect($_SERVER["HTTP_REFERER"]);
	}
	
} else {
	$xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
}
