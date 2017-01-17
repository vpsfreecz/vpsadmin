<?php

if ($_SESSION["logged_in"] && $_SESSION["is_admin"]) {
	unset($_SESSION["jumpto"]);
	$_SESSION["jumpto"] = array();
	
	if ($_POST["member"]) {
		$u = null;
		
		if(is_numeric($_POST["member"])) {
			try {
				$u = $api->user->find($_POST['member'])->id;
				
			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				// nothing
			}
		
		} else {
			$rs = $db->query("SELECT id FROM users WHERE login = '".$db->check($_POST["member"])."'
			                  UNION ALL
			                  SELECT id FROM users WHERE full_name = '".$db->check($_POST["member"])."'
			                  UNION ALL
			                  SELECT id FROM users WHERE email = '".$db->check($_POST["member"])."'
			                  UNION ALL
			                  SELECT user_id AS id FROM ip_addresses WHERE ip_addr = '".$db->check($_POST["member"])."' AND user_id IS NOT NULL
			                  UNION ALL
			                  SELECT v.m_id AS id FROM ip_addresses i INNER JOIN vps v ON i.vps_id = v.vps_id WHERE ip_addr = '".$db->check($_POST["member"])."'");
			
			if($rs && ($row = $db->fetch_array($rs)))
				$u = $row["id"];
		}
		
		$_SESSION["jumpto"]["member"] = $_POST["member"];
		
		if($u)
			redirect("?page=adminm&section=members&action=edit&id=".$u);
		else
			$xtpl->perex(_("User not found"), _("Sorry bro."));
		
	} elseif ($_POST["vps"]) {
		$v = null;
		
		if(is_numeric($_POST["vps"])) {
			try {
				$v = $api->vps->find($_POST["vps"])->id;
				
			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				// nothing
			}
			
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
