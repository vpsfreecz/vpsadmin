<?php

function get_helpbox($page = null, $action = null) {
	global $db;
	
	if (!$page) $page = $_GET["page"];
	if (!$action) $action = $_GET["action"];
	
	$rs = $db->query("SELECT id, content FROM helpbox WHERE page='".$db->check($page)."' AND action='".$db->check($action)."' LIMIT 1");
	return $db->fetch_array($rs);
}

function helpbox_add($page, $action, $content) {
	global $db;
	
	$db->query("INSERT INTO helpbox SET page='".$db->check($page)."', action='".$db->check($action)."', content='".$db->check($content)."'");
}

function helpbox_save($id, $page, $action, $content) {
	global $db;
	
	$db->query("UPDATE helpbox SET page='".$db->check($page)."', action='".$db->check($action)."', content='".$db->check($content)."' WHERE id=".$db->check($id));
}

function helpbox_del($id) {
	global $db;
	
	$db->query("DELETE FROM helpbox WHERE id=".$db->check($id));
}
