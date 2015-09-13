<?php

function get_helpbox($page = null, $action = null) {
	global $db;
	
	if (!$page) $page = $_GET["page"];
	if (!$action) $action = $_GET["action"];
	
	$rs = $db->query(
		"SELECT content
		FROM helpbox
		WHERE
		  (page='".$db->check($page)."'
		    AND (action='".$db->check($action)."' OR action='*')
	          )
		  OR
		  (page='*'
		    AND (action='".$db->check($action)."' OR action='*')
	          )"
	);

	$ret = '';
	
	while ($row = $db->fetch_array($rs))
		$ret .= $row['content'].'<br>';
	
	return $ret;
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
