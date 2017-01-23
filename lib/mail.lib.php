<?php
function send_mail($to, $subject, $msg, $cc = array(), $bcc = array(), $html = false, $dep = NULL,
                   $message_id = NULL, $in_reply_to = NULL, $references = array()) {
	global $config;
	
	$from_name = $config->get("webui", "mailer_from_name");
	$from_mail = $config->get("webui", "mailer_from_mail");
	
	$headers = "From: $from_name <$from_mail>\r\nDate: ".date("r")."\r\n";
	
	if ($cc)
		$headers .= "CC: ".implode(", ", $cc)."\r\n";
	
	if ($bcc)
		$headers .= "BCC: ".implode(", ", $bcc)."\r\n";
	
	if ($message_id)
		$headers .= "Message-ID: $message_id\r\n";
	
	if ($in_reply_to)
		$headers .= "In-Reply-To: $in_reply_to\r\n";
	
	if ($references)
		$headers .= "References: ".implode(", ", $references)."\r\n";

	$headers .= "MIME-Version: 1.0\r\n";
	$headers .= "Content-type: text/plain; charset=UTF-8\r\n";
	
	mail(
		$to,
		$subject,
		$msg,
		$headers
	);
}
