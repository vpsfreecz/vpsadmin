<?php

switch ($reqbody["cmd"]) {

case 'list':
	$whereCond = array();
	$whereCond[] = 1;

	api_parse_filter(&$reqbody, &$whereCond, array("t_id" => PARAM_ARRAY,
																								 "t_m_id" => PARAM_ARRAY,
																								 "t_server" => PARAM_ARRAY,
																								 "t_vps" => PARAM_ARRAY,
																								 "t_type" => PARAM_ARRAY,
																								 "t_done" => PARAM_SINGLE,
																								 "t_success" => PARAM_SINGLE
																								 ));

	$count = 0;
	$list = array();

	while ($item = $db->find("transactions", $whereCond)) {
		$count++;

		api_clean_db_item($item);

		$list[] = $item;
	}

	api_reply(RET_OK, array("list" => $list, "count" => $count));
	break;

default:
	api_reply(RET_ENI);
}