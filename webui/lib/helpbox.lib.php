<?php

function get_helpbox($page = null, $action = null) {
	global $api;

	if (!$api->help_box){
		return '';
	}

	if (!$page){
		$page = isset($_GET["page"]) ? $_GET["page"] : null;
	}

	if (!$action){
		$action = isset($_GET["action"]) ? $_GET["action"] : null;
	}

	$boxes = $api->help_box->list(array(
		'page' => $page ? $page : null,
		'action' => $action ? $action : null,
	));

	$ret = '';

	foreach ($boxes as $box)
		$ret .= $box->content.'<br>';

	return $ret;
}
