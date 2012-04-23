<?php

switch ($reqbody["cmd"]) {

case 'list':
	$whereCond = array();
	$whereCond[] = 1;

	api_parse_filter(&$reqbody, &$whereCond, array("location_id" => PARAM_ARRAY,
																								 "location_has_ipv6" => PARAM_SINGLE,
																								 "location_has_ospf" => PARAM_SINGLE
																								 ));

	$count = 0;
	$list = array();
	
	while ($item = $db->find("locations", $whereCond)) {
		$count++;
		
		api_clean_db_item($item);
		
		$list[] = $item;
	}
	
	api_reply(RET_OK, array("list" => $list, "count" => $count));
	break;

default:
	api_reply(RET_ENI);
}