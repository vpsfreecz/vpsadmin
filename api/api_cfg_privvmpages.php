<?php

switch ($reqbody["cmd"]) {

case 'list':
	$whereCond = array();
	$whereCond[] = 1;
	
	api_parse_filter(&$reqbody, &$whereCond, array("vm_id" => PARAM_ARRAY));

	$count = 0;
	$list = array();
	
	while ($item = $db->find("cfg_privvmpages", $whereCond)) {
		$count++;
		
		api_clean_db_item($item);
		
		$list[] = $item;
	}
	
	api_reply(RET_OK, array("list" => $list, "count" => $count));
	break;

case '':
	break;

default:
	api_reply(RET_ENI);
}