<?php

function log_add($date, $msg) {
	global $db;
	
	$db->query("INSERT INTO `log` SET `timestamp` = '".$db->check(strtotime($date))."', msg = '".$db->check($msg)."'");
}

function log_save($id, $date, $msg) {
	global $db;
	
	$db->query("UPDATE `log` SET `timestamp` = '".$db->check(strtotime($date))."', msg = '".$db->check($msg)."' WHERE id = ".$db->check($id));
}

function log_del($id) {
	global $db;
	
	$db->query("DELETE FROM `log` WHERE id = ".$db->check($id));
}
