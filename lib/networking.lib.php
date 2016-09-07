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

function get_live_traffic_by_ip($limit_cnt, $limit_ip = false, $limit_vps = false, $limit_member = false) {
	global $db;
	
	$ips = array();
	$for_sort = array();
	
	$sql = "
		SELECT
		tr_ip, tr_proto, tr_packets_in, tr_packets_out, tr_bytes_in, tr_bytes_out, tr_date, vps_ip.vps_id
		FROM transfered_recent r1
		INNER JOIN vps_ip ON ip_addr = r1.tr_ip
		INNER JOIN networks n ON n.id = vps_ip.network_id
		".($limit_member ? 'INNER JOIN vps ON vps.vps_id = vps_ip.vps_id
		                    INNER JOIN members ON vps.m_id = members.m_id' : '')."
		WHERE
		  n.role = 0
		  AND tr_date > DATE_SUB(NOW(), INTERVAL 60 SECOND)
		  ".($limit_ip ? "AND tr_ip = '".$db->check($limit_ip)."'" : '')."
		  ".($limit_vps ? 'AND vps_id = '.$db->check($limit_vps) : '')."
		  ".($limit_member ? 'AND members.m_id = '.$db->check($limit_member) : '')."
		GROUP BY tr_ip, tr_proto
		ORDER BY tr_date DESC
		LIMIT ".$db->check($limit_cnt)."
	";
	
	$rs = $db->query($sql);
	
	while($row = $db->fetch_array($rs)) {
		$row['tr_date_diff'] = 10;
		
		if(!$row['tr_date_diff'] || $row['tr_date_diff'] > 60)
			continue;
		
		if(!array_key_exists($row['tr_ip'], $ips)) {
			$ips[$row['tr_ip']] = array(
				'ip_addr' => $row['tr_ip'],
				'vps_id' => $row['vps_id'],
				'protocols' => array(
					'tcp' => array(
						'bps' => array('in' => 0, 'out' => 0),
						'pps' => array('in' => 0, 'out' => 0),
					),
					'udp' => array(
						'bps' => array('in' => 0, 'out' => 0),
						'pps' => array('in' => 0, 'out' => 0),
					),
					'others' => array(
						'bps' => array('in' => 0, 'out' => 0),
						'pps' => array('in' => 0, 'out' => 0),
					),
					'all' => array(
						'bps' => array('in' => 0, 'out' => 0),
						'pps' => array('in' => 0, 'out' => 0),
					),
				),
			);
		}
		
		$ips[$row['tr_ip']]['protocols'][$row['tr_proto']]['bps']['in'] = $row['tr_bytes_in'] / $row['tr_date_diff'];
		$ips[$row['tr_ip']]['protocols'][$row['tr_proto']]['bps']['out'] = $row['tr_bytes_out'] / $row['tr_date_diff'];
		$ips[$row['tr_ip']]['protocols'][$row['tr_proto']]['pps']['in'] = $row['tr_packets_in'] / $row['tr_date_diff'];
		$ips[$row['tr_ip']]['protocols'][$row['tr_proto']]['pps']['out'] = $row['tr_packets_out'] / $row['tr_date_diff'];
	}
	
	foreach($ips as $addr => &$ip) {
		$ip['protocols']['others']['bps']['in'] = $ip['protocols']['all']['bps']['in'];
		$ip['protocols']['others']['bps']['out'] = $ip['protocols']['all']['bps']['out'];
		$ip['protocols']['others']['pps']['in'] = $ip['protocols']['all']['pps']['in'];
		$ip['protocols']['others']['pps']['out'] = $ip['protocols']['all']['pps']['out'];
		
// 		print_r($ip);
		
		foreach($ip['protocols'] as $proto => &$data) {
			if($proto == 'others' || $proto == 'all')
				continue;
			
			$ip['protocols']['all']['bps']['in'] += $data['bps']['in'];
			$ip['protocols']['all']['bps']['out'] += $data['bps']['out'];
			$ip['protocols']['all']['pps']['in'] += $data['pps']['in'];
			$ip['protocols']['all']['pps']['out'] += $data['pps']['out'];
		}
		unset($data);
		
		$for_sort[$addr] = $ip['protocols']['all']['bps']['in']
			+ $ip['protocols']['all']['bps']['out']
			+ $ip['protocols']['all']['pps']['in']
			+ $ip['protocols']['all']['pps']['out'];
	}
	unset($ip);
	
	arsort($for_sort);
	
	$ret = array();
	
	foreach($for_sort as $addr => &$data) {
		$ret[] = $ips[$addr];
	}
	
	return $ret;
}

}
$accounting = new net_accounting();
?>
