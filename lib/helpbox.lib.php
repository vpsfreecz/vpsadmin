<?php

function get_helpbox($page = null, $action = null) {
	global $api;

	if (!$api->help_box)
		return '';
	
	if (!$page) $page = $_GET["page"];
	if (!$action) $action = $_GET["action"];

	$boxes = $api->help_box->list(array(
		'page' => $page ? $page : null,
		'action' => $action ? $action : null,
	));

	$ret = '';

	foreach ($boxes as $box)	
		$ret .= $box->content.'<br>';
	
	return $ret;
}
