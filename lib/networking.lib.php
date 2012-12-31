<?php
/*
    ./lib/networking.lib.php

    vpsAdmin
    Web-admin interface for OpenVZ (see http://openvz.org)
    Copyright (C) 2008-2009 Pavel Snajdr, snajpa@snajpa.net
	Copyright (C) 2009 Frantisek Kucera, franta@vpsfree.cz

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

class net_accounting {

function get_traffic_by_ip_this_day ($ip, $generated = false) {
	global $db;
	if (!$generated)
		$generated = time();
	$year = date('Y', $generated);
	$month = date('m', $generated);
	$day = date('d', $generated);
	// hour, minute, second, month, day, year
	$this_day = mktime (0, 0, 0, $month, $day, $year);
	$sql = 'SELECT * FROM transfered WHERE tr_time >= "'.$db->check($this_day).'" AND tr_ip = "'.$db->check($ip).'" ORDER BY tr_id DESC LIMIT 1';
	$ret['in']    = 0;
	$ret['out']   = 0;
	if ($result = $db->query($sql)) {
		if ($row = $db->fetch_array($result)) {
			$ret['in']    += $row['tr_in'];
			$ret['out']   += $row['tr_out'];
			$ret['tr_id'] = $row['tr_id'];
			$ret['tr_ip'] = $row['tr_ip'];
		}
		else return false;
	}
	else return false;
	return $ret;
}
function get_traffic_by_ip_this_month ($ip, $generated = false) {
	global $db;
	$ret = array();
	if (!$generated){
	    $generated = time();
	    $ret = array();
	    $year = date('Y', $generated);
	    $month = date('m', $generated);
	    $this_month = mktime (0, 0, 0, $month, 0, $year);
	    $sql = 'SELECT * FROM transfered WHERE tr_time >= "'.$db->check($this_month).'" AND tr_ip = "'.$db->check($ip).'" ORDER BY tr_id DESC';
	} else {
	    $year = date('Y', $generated);
	    $month = date('m', $generated);
	    $this_month = mktime (0, 0, 0, $month, 0, $year);
	    $time_lastmonth = mktime (0, 0, 0, $month+1, 0, $year);
	    $sql = 'SELECT * FROM transfered WHERE tr_time < "'.$time_lastmonth.'" AND tr_time >= "'.$db->check($this_month).'" AND tr_ip = "'.$db->check($ip).'" ORDER BY tr_id DESC';
	}
	// hour, minute, second, month, day, year
	$ret['in']    = 0;
	$ret['out']   = 0;
	if ($result = $db->query($sql)) {
		while ($row = $db->fetch_array($result)) {
			$ret['in']    += $row['tr_in'];
			$ret['out']   += $row['tr_out'];
		}
	}
	else return false;
	return $ret;
}
}
$accounting = new net_accounting();
?>
