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
class net_firewall {
	private $su = false;
	function net_firewall() {
	$this->su = ($_SESSION["cli_mode"]);
}

function commit_rule($rule) {
	global $db;
	if ($this->su) {
		exec ('iptables '.$db->check($rule), $out, $ret);
	} else $ret = 1;
	return ($ret == 0);
}

function commit_rule6($rule) {
	global $db;
	if ($this->su) {
		exec ('ip6tables '.$db->check($rule), $out, $ret);
	} else $ret = 1;
	return ($ret == 0);
}

function flush_all() {
	if ($this->su)
		return $this->commit_rule('-F');
}

}
$firewall = new net_firewall();


define ('IP_ALL', "0.0.0.0/0");
define ('IP6_ALL', "::/0");
class net_accounting {
	public $su = false;
function __construct() {
	$this->su = ($_SESSION["cli_mode"]);
}
function load_accounting() {
	if ($this->su) {
		exec ('sh '.WWW_ROOT.'scripts/accounting_load.sh '.WWW_ROOT.'scripts/nix_subnets.txt');
	}
}
function all_ip4_add() {
	global $firewall;
	$all_ips = get_all_ip_list(4);
	if ($all_ips)
		foreach ($all_ips as $ip) {
			$firewall->commit_rule("-A aztotal -s $ip");
			$firewall->commit_rule("-A aztotal -d $ip");
		}
}
function all_ip6_add() {
	global $firewall;
	$all_ips = get_all_ip_list(6);
	if ($all_ips)
		foreach ($all_ips as $ip) {
			$firewall->commit_rule6("-A aztotal -s $ip");
			$firewall->commit_rule6("-A aztotal -d $ip");
		}
}

function update_traffic_table () {
	global $firewall;
	if ($this->su) {
		exec("iptables -L aztotal -nvx", $output);
		exec("ip6tables -L aztotal -nvx", $output6);
		$this->process_iptables_output($output, $output6, time());
	}
	$firewall->commit_rule("-Z aztotal");
	$firewall->commit_rule6("-Z aztotal");
}

function process_iptables_output ($v4, $v6, $generated) {
	$ret = array();
	foreach ($v4 as $row) {
		$row = preg_split("/[ ]+/", $row);
		$amount = $row[2];
		$source = $row[7];
		$destination = $row[8];
		if ($source == IP_ALL && $amount > 0)
			$ret[$destination]['in'] = $amount;
		else if ($destination == IP_ALL && $amount > 0)
			$ret[$source]['out'] = $amount;
	}
	foreach ($v6 as $row) {
		$row = preg_split("/[ ]+/", $row);
		$amount = $row[2];
		$destination = preg_replace("/\/128/", "", $row[7]);
		$source = preg_replace("/\/128/", "", $row[6]);
		if ($source == IP6_ALL && $amount > 0)
			$ret[$destination]['in'] = $amount;
		else if ($destination == IP6_ALL && $amount > 0)
			$ret[$source]['out'] = $amount;
	}
	$this->save_traffic_to_this_day($ret, $generated);
}
function save_traffic_to_this_day ($diff, $generated) {
	global $db;
	foreach ($diff as $ip => $ip_diff) {
		if ($this_day = $this->get_traffic_by_ip_this_day($ip)) {
			$sql = 'UPDATE transfered
						SET tr_out = "'.($this_day['tr_out'] + $db->check( $ip_diff['out'] )).'",
								tr_in  = "'.($this_day['tr_in'] + $db->check( $ip_diff['in']  )).'"
						WHERE tr_id = "'.$this_day['tr_id'].'"';
		} else {
			$sql = 'INSERT INTO transfered
						SET tr_out = "'.$db->check( $ip_diff['out'] ).'",
								tr_in  = "'.$db->check( $ip_diff['in']  ).'",
								tr_ip      = "'.$db->check( $ip                ).'",
								tr_time    = "'.$db->check( $generated         ).'"';
		}
		$db->query($sql);
	}
}
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
