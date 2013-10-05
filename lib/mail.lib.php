<?php
function send_mail($to, $subject, $msg, $cc = array(), $bcc = array(), $html = false, $dep = NULL,
                   $message_id = NULL, $in_reply_to = NULL, $references = array()) {
	global $cluster, $cluster_cfg;
	$mailers = $cluster->list_servers_with_type("mailer");
	$ids = array_keys($mailers);
	
	add_transaction($_SESSION["member"]["m_id"], $ids[0], 0, T_MAIL_SEND, array(
		"from_name" => $cluster_cfg->get("mailer_from_name"),
		"from_mail" => $cluster_cfg->get("mailer_from_mail"),
		"to" => $to,
		"subject" => $subject,
		"msg" => $msg,
		"cc" => $cc,
		"bcc" => $bcc,
		"html" => $html,
		"msg_id" => $message_id,
		"in_reply_to" => $in_reply_to,
		"references" => $references,
	), NULL, $dep);
}

function request_change_mail_all($request, $state, $mail) {
	request_change_mail_admins($request, $state);
	request_change_mail_member($request, $state, $mail);
	request_mail_last_update($request);
}

function request_change_mail_admins($request, $state) {
	global $cluster_cfg;
	
	$admins = explode(",", $cluster_cfg->get("mailer_requests_sendto"));
	
	foreach($admins as $admin) {
		request_change_mail_send($request, $state, "admin", array(
				"m_id" => $request["applicant_id"],
				"m_nick" => $request["applicant_nick"]
			), array(
				"m_id" => $request["admin_id"],
				"m_nick" => $request["admin_nick"]
			), $admin
		);
	}
}

function request_change_mail_member($request, $state, $mail) {
	request_change_mail_send($request, $state, "member", array(
			"m_id" => $request["applicant_id"],
			"m_nick" => $request["applicant_nick"]
		), array(
			"m_id" => $request["admin_id"],
			"m_nick" => $request["admin_nick"]
		), $mail
	);
}

function request_change_mail_send($request, $state, $who, $member, $admin, $mail) {
	global $cluster_cfg;
	
	$subject = $cluster_cfg->get("mailer_requests_${who}_sub");
	$text = $cluster_cfg->get("mailer_requests_${who}_text");
	
	$subject = str_replace("%request_id%", $request["m_id"], $subject);
	$subject = str_replace("%type%", $request["m_type"], $subject);
	$subject = str_replace("%state%", $state, $subject);
	$subject = str_replace("%member_id%", $member["m_id"], $subject);
	$subject = str_replace("%member%", $member["m_nick"], $subject);
	$subject = str_replace("%name%", $request["m_type"] == "change" ? $request["current_name"] : $request["m_name"], $subject);
	
	$text = str_replace("%created%", strftime("%Y-%m-%d %H:%M", $request["m_created"]), $text);
	$text = str_replace("%changed_at%", $request["m_changed_at"] ? strftime("%Y-%m-%d %H:%M", $request["m_changed_at"]) : "-", $text);
	$text = str_replace("%request_id%", $request["m_id"], $text);
	$text = str_replace("%type%", $request["m_type"], $text);
	$text = str_replace("%state%", $state, $text);
	$text = str_replace("%member_id%", $member["m_id"], $text);
	$text = str_replace("%member%", $member["m_nick"], $text);
	$text = str_replace("%admin_id%", $admin["m_id"], $text);
	$text = str_replace("%admin%", $admin["m_nick"], $text);
	$text = str_replace("%reason%", $request["m_reason"], $text);
	$text = str_replace("%admin_response%", $request["m_admin_response"], $text);
	$text = str_replace("%ip%", $request["m_addr"], $text);
	$text = str_replace("%ptr%", $request["m_addr_reverse"], $text);
	
	$changed_info = "";
	
	if($request["m_type"] == "change") {
		$changed_info .= '   Name: "'.$request["current_name"].'" -> "'.$request["m_name"]."\"\n";
		$changed_info .= ' E-mail: "'.$request["current_mail"].'" -> "'.$request["m_mail"]."\"\n";
		$changed_info .= 'Address: "'.$request["current_address"].'" -> "'.$request["m_address"]."\"\n";
	}
	
	$text = str_replace("%changed_info%", $changed_info, $text);
	
	$msg_id = "vpsadmin-request-".$request["m_id"]."-".($request["m_last_mail_id"]+1)."@vpsadmin.vpsfree.cz";
	
	$reply_to = "";
	$references = array();
	
	if($request["m_last_mail_id"]) {
		$reply_to = "vpsadmin-request-".$request["m_id"]."-".$request["m_last_mail_id"]."@vpsadmin.vpsfree.cz";
		$references = array($reply_to);
	}
	
	send_mail($mail, $subject, $text, array(), array(), false, NULL,
	          $msg_id, $reply_to, $references
	);
}

function request_mail_last_update($request) {
	global $db;
	
	$db->query("UPDATE members_changes SET m_last_mail_id = m_last_mail_id + 1 WHERE m_id = ".$db->check($request["m_id"]));
}
