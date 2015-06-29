<?php
/*
    ./lib/functions.lib.php

    vpsAdmin
    Web-admin interface for OpenVZ (see http://openvz.org)
    Copyright (C) 2008-2009 Pavel Snajdr, snajpa@snajpa.net

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

$DATA_SIZE_UNITS = array("k" => "KiB", "m" => "MiB", "g" => "GiB", "t" => "TiB");


function get_free_ip_list ($v = 4, $vps) {
	global $api;
	
	$ret = array();
	$filters = array(
		'version' => $v,
		'vps' => null,
		'location' => $vps->node->location_id
	);
	
	if (!$_SESSION['is_admin']) {
		// Limit the number of shown IP addresses by a number
		// of user's IP addresses left.
		
		$resources = $vps->user->cluster_resource->list(array(
			'environment' => $vps->node->environment_id,
			'meta' => array('includes' => 'cluster_resource')
		));
		
		foreach ($resources as $r) {
			if ($r->cluster_resource->name == "ipv$v") {
				$filters['limit'] = $r->free;
				break;
			}
		}
	}
	
	foreach($api->ip_address->list($filters) as $ip) {
		$ret[$ip->id] = $ip->addr . ($ip->user_id == $vps->user_id ? ' (owned)' : '');
	}
	
	return $ret;
}

function list_configs($empty = false) {
	global $db;
	
	$sql = "SELECT id, `label` FROM config ORDER BY name";
	$ret = $empty ? array(0 => '---') : array();
	
	if ($result = $db->query($sql))
		while ($row = $db->fetch_array($result))
			$ret[$row["id"]] = $row["label"];
	
	return $ret;
}

function list_templates($disabled = true) {
    global $db;
    $sql = 'SELECT * FROM cfg_templates '.($disabled ? '' : 'WHERE templ_enabled = 1').' ORDER BY templ_label ASC';
    if ($result = $db->query($sql))
	while ($row = $db->fetch_array($result)) {
	    $ret[$row["templ_id"]] = $row["templ_label"];
	    if (!$row["templ_enabled"])
			$ret[$row["templ_id"]] .= ' '._('(IMPORTANT: This template is currently disabled, it cannot be used)');
	}
    return $ret;
}

function template_by_id ($id) {
    global $db;
    $sql = 'SELECT * FROM cfg_templates WHERE templ_id="'.$db->check($id).'" LIMIT 1';
    if ($result = $db->query($sql))
	if ($row = $db->fetch_array($result))
	    return $row;
    return false;
}

function list_servers($without_id = false, $roles = NULL) {
    global $db, $NODE_TYPES;
    
	if ($roles === NULL)
		$roles = $NODE_TYPES;
	
	if ($without_id)
		$sql = 'SELECT * FROM servers WHERE server_id != \''.$db->check($without_id).'\' AND server_type IN (\''.implode("','", $roles).'\') ORDER BY server_location,server_id';
	else
		$sql = 'SELECT * FROM servers WHERE server_type IN (\''.implode("','", $roles).'\') ORDER BY server_location,server_id';
	
    if ($result = $db->query($sql))
	while ($row = $db->fetch_array($result))
	    $ret[$row["server_id"]] = $row["server_name"];
    return $ret;
}

function server_by_id ($id) {
    global $db;
    $sql = 'SELECT * FROM servers WHERE server_id="'.$db->check($id).'" LIMIT 1';
    if ($result = $db->query($sql))
	if ($row = $db->fetch_array($result))
	    return $row;
    return false;
}

function notify_user($title, $msg) {
	$_SESSION["notification"] = array(
		"title" => $title,
		"msg" => $msg,
	);
}

function show_notification() {
	global $xtpl;
	
	if(!isset($_SESSION["notification"]))
		return;
	
	$xtpl->perex($_SESSION["notification"]["title"], $_SESSION["notification"]["msg"]);
	unset($_SESSION["notification"]);
}

function redirect($loc) {
	header('Location: '.$loc);
	exit;
}

function format_duration($interval) {
	$d = $interval / 86400;
	$h = $interval / 3600 % 24;
	$m = $interval / 60 % 60;
	$s = $interval % 60;
	
	if($d >= 1)
		return sprintf("%d days, %02d:%02d:%02d", round($d), $h, $m, $s);
	else
		return sprintf("%02d:%02d:%02d", $h, $m, $s);
}

function tolocaltz($datetime, $format = "Y-m-d H:i:s") {
	$t = new DateTime($datetime);
	$t->setTimezone(new DateTimeZone(date_default_timezone_get()));
	return $t->format($format);
}

function toutc($datetime) {
	$t = new DateTime($datetime);
	return $t->setTimezone(new DateTimeZone('UTC'));
}

function random_string($len) {
	$str = "";
	$chars = array_merge(range(0, 9), range('a', 'z'), range('A', 'Z'));
	
	for($i = 0; $i < $len; $i++)
		$str .= $chars[array_rand($chars)];
	
	return $str;
}

function request_by_id($id) {
	global $db;
	
	$rs = $db->query("SELECT c.*, IFNULL(applicant.m_nick, c.m_nick) AS applicant_nick, IFNULL(applicant.m_name, c.m_name) AS current_name,
						IFNULL(applicant.m_mail, c.m_mail) AS current_mail, IFNULL(applicant.m_address, c.m_address) AS current_address,
						applicant.m_id AS applicant_id, admin.m_id AS admin_id, admin.m_nick AS admin_nick
						FROM members_changes c
						LEFT JOIN members applicant ON c.m_applicant = applicant.m_id
						LEFT JOIN members admin ON c.m_changed_by = admin.m_id
						WHERE c.m_id = ".$db->check($id)."");
	
	return $db->fetch_array($rs);
}

function format_data_rate($n, $suffix) {
	$units = array(
		2 << 29 => 'G',
		2 << 19 => 'M',
		2 << 9 => 'k',
	);
	
	$ret = "";
	$selected = 0;
	
	foreach($units as $threshold => $unit) {
		if($n > $threshold) {
			return round(($n / $threshold), 2)."&nbsp;$unit$suffix";
		}
	}
	
	return round($n, 2)."&nbsp;$suffix";
}

function client_identity() {
	return  "vpsadmin-www v".VERSION;
}

function api_description_changed($api) {
	$_SESSION["api_description"] = $api->getDescription();
}

function maintenance_lock_icon($type, $obj) {
	$m_icon_on = '<img alt="'._('Turn maintenance OFF.').'" src="template/icons/maintenance_mode.png">';
	$m_icon_off = '<img alt="'._('Turn maintenance ON.').'" src="template/icons/transact_ok.png">';
	
	switch ($obj->maintenance_lock) {
		case 'no':
			return '<a href="?page=cluster&action=maintenance_lock&type='.$type.'&obj_id='.$obj->id.'&lock=1">'
			       .$m_icon_off
			       .'</a>';
		
		case 'lock':
			return '<a href="?page=cluster&action=set_maintenance_lock&type='.$type.'&obj_id='.$obj->id.'&lock=0"
			           title="'._('Maintenance lock reason').': '.htmlspecialchars($obj->maintenance_lock_reason).'">'
			        .$m_icon_on
			        .'</a>';
		
		case 'master_lock':
			return '<img alt="'._('Under maintenance.').'"
			             title="'._('Under maintenance').': '.htmlspecialchars($obj->maintenance_lock_reason).'"
			             src="template/icons/maintenance_mode.png">';
	}
}

function resource_list_to_options($list, $id = 'id', $label = 'label', $empty = true, $label_callback = null) {
	$ret = array();
	
	if ($empty)
		$ret[0] = '---';
	
	foreach ($list as $item)
		$ret[ $item->{$id} ] = $label_callback ? $label_callback($item) : $item->{$label};
	
	return $ret;
}

function boolean_icon($val) {
	if ($val) {
		return '<img src="template/icons/transact_ok.png" />';
	} else {
		return '<img src="template/icons/transact_fail.png" />';
	}
}

function api_param_to_form_pure($name, $desc, $v = null, $label_callback = null) {
	global $xtpl, $api;
	
	if ($v === null)
		$v = $desc->default === '_nil' ? null : $desc->default;
	
	if (isset($_POST[$name]))
		$v = $_POST[$name];
		
	switch ($desc->type) {
		case 'String':
		case 'Integer':
			if ($desc->choices)
				$xtpl->form_add_select_pure($name, $desc->choices, array_search($v, $desc->choices));
			else
				$xtpl->form_add_input_pure('text', '30', $name, $v);
			break;
		
		case 'Text':
			$xtpl->form_add_textarea_pure(80, 10, $name, $v);
			break;
		
		case 'Boolean':
			$xtpl->form_add_checkbox_pure($name, '1', $v);
			break;
		
		case 'Datetime':
			$xtpl->form_add_datetime_pure($name, $v, false);
			break;
		
		case 'Resource':
			$xtpl->form_add_select_pure(
				$name,
				resource_list_to_options(
					$api[ implode('.', $desc->resource) ]->index(),
					$desc->value_id,
					$desc->value_label,
					true,
					$label_callback
				),
				$v
			);
		
		default:
			continue;
	}
}

function api_param_to_form($name, $desc, $v = null, $label_callback = null) {
	global $xtpl;
	
	$xtpl->table_td($desc->label.':');
	api_param_to_form_pure($name, $desc, $v, $label_callback);
	
	if ($desc->description)
		$xtpl->table_td($desc->description);
	
	$xtpl->table_tr();
}

function api_params_to_form($action, $direction, $label_callbacks = null) {
	$params = $action->getParameters($direction);
	
	foreach ($params as $name => $desc) {
		api_param_to_form($name, $desc, null, $label_callbacks ? $label_callbacks[$name] : null);
	}
}

function api_create_form($resource) {
	api_params_to_form($resource->create, 'input');
}

function api_update_form($obj) {
	$params = $obj->update->getParameters('input');
	
	foreach ($params as $name => $desc) {
		api_param_to_form($name, $desc, post_val($name, $obj->{$name}), $label_callbacks ? $label_callbacks[$name] : null);
	}
}

function client_params_to_api($action, $from = null) {
	if (!$from)
		$from = $_POST;
	
	$params = $action->getParameters('input');
	$ret = array();
	
	foreach ($params as $name => $desc) {
		if (isset($from[ $name ])) {
			switch ($desc->type) {
				case 'Integer':
					$v = (int) $from[$name];
					break;
				
				case 'Boolean':
					$v = true;
					break;
				
				case 'Resource':
					if (!$from[$name])
						continue;
				
				default:
					$v = $from[ $name ];
			}
			
			$ret[ $name ] = $v;
		}
	}
	
	return $ret;
}

function unit_for_cluster_resource($name) {
	switch ($name) {
		case 'cpu':
			return _('cores');
		
		case 'ipv4':
		case 'ipv6':
			return _('addresses');
		
		default:
			return 'MiB';
	}
}

function data_size_unitize($val) {
	$units = array("t" => 19, "g" => 9, "m" => 0);
	
	if (!$val)
		return array(0, "g");
	
	foreach ($units as $u => $ex) {
		if ($val >= (2 << $ex))
			return array($val / (2 << $ex), $u);
	}
	
	return array($val, "m");
}

function data_size_to_humanreadable($val) {
	global $DATA_SIZE_UNITS;
	
	if (!$val)
		return _("none");
	
	$res = data_size_unitize($val);
	return round($res[0], 2) . " " . $DATA_SIZE_UNITS[$res[1]];
}

function get_val($name, $default = '') {
	if (isset($_GET[$name]))
		return $_GET[$name];
	return $default;
}

function post_val($name, $default = '') {
	if (isset($_POST[$name]))
		return $_POST[$name];
	return $default;
}

function transaction_concern_class($klass) {
	$tr = array(
		'Vps' => 'VPS'
	);
	
	if (array_key_exists($klass, $tr))
		return $tr[$klass];
	
	return $klass;
}

function transaction_concern_link($klass, $row_id) {
	switch ($klass) {
		case 'Vps':
			return '<a href="?page=adminvps&action=info&veid='.$row_id.'">'.$row_id.'</a>';
		
		default:
			return "$row_id";
	}
}

function transaction_chain_concerns($chain, $limit = 10) {
	if (!$chain->concerns)
		return '---';
	
	switch ($chain->concerns->type) {
		case 'affect':
			$o = $chain->concerns->objects[0];
			return transaction_concern_class($o[0]).' '.transaction_concern_link($o[0], $o[1]);
			
		case 'transform':
			$src = $chain->concerns->objects[0];
			$dst = $chain->concerns->objects[1];
			
			return transaction_concern_class($src[0]).' '.transaction_concern_link($src[0], $src[1]).' -> '.transaction_concern_link($dst[0], $dst[1]);
		
		default:
			return _('Unknown');
	}
}

function get_all_users() {
	global $api;
	
	$cnt = $api->user->list(array(
		'limit' => 0,
		'meta' => array('count' => true)
	))->getTotalCount();
	
	return $api->user->list(array(
		'limit' => $cnt + 10
	));
}

function vps_label ($vps) {
	return '#'.$vps->id.' '.$vps->hostname;
}

function user_label ($user) {
	return '#'.$user->id.' '.$user->login;
}

?>
