<?php
function send_mail($to, $subject, $msg, $cc = array(), $bcc = array(), $html = false, $dep = NULL) {
	global $cluster;
	$mailers = $cluster->list_servers_with_type("mailer");
	$ids = array_keys($mailers);
	
	add_transaction($_SESSION["member"]["m_id"], $ids[0], 0, T_MAIL_SEND, array(
		"to" => $to,
		"subject" => $subject,
		"msg" => $msg,
		"cc" => $cc,
		"bcc" => $bcc,
		"html" => $html,
	), NULL, $dep);
}
