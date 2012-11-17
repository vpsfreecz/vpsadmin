<?php
function send_mail($to, $subject, $msg, $cc = array(), $bcc = array(), $html = false, $dep = NULL) {
	add_transaction($_SESSION["member"]["m_id"], 1, 0, T_MAIL_SEND, array(
		"to" => $to,
		"subject" => $subject,
		"msg" => $msg,
		"cc" => $cc,
		"bcc" => $bcc,
		"html" => $html,
	), NULL, $dep);
}
