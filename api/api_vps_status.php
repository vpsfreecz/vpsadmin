<?php

switch ($reqbody["cmd"]) {

case 'list':
	$whereCond = array();
	$whereCond[] = 1;

	api_parse_filter(&$reqbody, &$whereCond, array("vps_id" => PARAM_ARRAY,
																								 ));

	$count = 0;
	$list = array();
	
	$limit = (isset($reqbody["filter"]["vps_id"]) && is_array($reqbody["filter"]["vps_id"]))
					 ? count($reqbody["filter"]["vps_id"]) : 1;
	
	while ($vps = $db->find("vps", $whereCond)) {
		$count++;
		
		$item = null;
		
		$item = $db->find("vps_status",
											'vps_id = "' . $db->check($vps["vps_id"]) . '"',
											'id DESC',
											1,
											0,
											true);

		api_clean_db_item($item);

		$list[] = $item;
	}
	
	api_echo(print_r($reqbody, true));
	api_echo(print_r($whereCond, true));
	api_reply(RET_OK, array("list" => $list, "count" => $count));
	break;

case '':
	break;

default:
	api_reply(RET_ENI);
}