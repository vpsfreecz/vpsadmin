<?php

function api_echo($msg) {
	echo "/* $msg */\n";
}

function api_reply($retval, $return = null) {
	global $RET_MSG;
	
	if (is_array($return)) {
		$ret = $return;
	} else {
		$ret = array();
	}

	$ret["return"] = $retval;
	$ret["return_msg"] = $RET_MSG[$retval];

	echo json_encode($ret) . "\n";

	exit($retval);

}

function api_clean_db_item(&$item) {
	
	if (array_key_exists("_meta_tableName", $item)) {
		unset($item["_meta_tableName"]);
	}
}

function api_parse_filter(&$reqbody, &$whereCond, $filters) {
	global $db;
	
	if (isset($reqbody["filter"])) {
	
		foreach ($filters as $filter => $can_be_array) {
			if (isset($reqbody["filter"][$filter])) {
				if (is_array($reqbody["filter"][$filter])) {
					
					if ($can_be_array) {
						$cond = '0 ';
						
						foreach ($reqbody["filter"][$filter] as $param) {
							$cond .= ' OR (' . $filter . ' = "' . $db->check($param) . '")';
						}
						
						$whereCond[] = $cond;
						
					} else {
						api_reply(RET_EPINVALID);
					}
				
				} else {
					$whereCond[] = $filter . ' = "' . $db->check($reqbody["filter"][$filter]) . '"';
				}
			}
		}
	}

}