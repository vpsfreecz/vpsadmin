<?php

function update_all_vps_status () {
    global $db;
    $vps_list = get_vps_array(false, SERVER_ID);
    if (is_array($vps_list))
    foreach ($vps_list as $vps) {
	if ($vps->exists) {
	  if (DEMO_MODE) {
	    $out["ve_id"] = $vps->veid;
	    $out["ve_nproc"] = '42';
	    $out["ve_status"] = 'running';
	    $out["ve_hostname"] = $vps->ve["ve_hostname"];
	    $memusage = '1234';
	    $diskusage = '1234';
	  } else {
	    echo ("{$vps->veid}\n");
	    $vzlist = NULL;
	    exec (BIN_VZLIST.' '.$vps->veid.' | tr -s " "', $vzlist);
	    $tds = explode(' ',trim($vzlist[1]));
	    $out["ve_id"] = $tds[0];
	    $out["ve_nproc"] = $tds[1];
	    $out["ve_status"] = $tds[2];
	    $out["ve_hostname"] = $tds[4];
	    $memusage = get_mem_usage($vps->veid);
	    $diskusage = get_disk_usage($vps->veid);
	  }
	}
	(int)$up = (int)($out["ve_status"] == 'running');
	if ($ret = $db->query("SELECT * FROM vps_status WHERE vps_id = {$db->check($vps->veid)} ORDER BY id DESC LIMIT 1")) {
		if ($row = $db->fetch_array($ret)) {
			$sql = 'UPDATE vps_status
					SET vps_id = "'.$db->check($vps->veid).'",
							timestamp = "'.time().'",
							vps_up = "'.$up.'",
							vps_nproc = "'.$db->check($out["ve_nproc"]).'",
							vps_vm_used_mb = "'.$memusage['used'].'",
							vps_disk_used_mb = "'.$db->check($diskusage).'",
							vps_admin_ver ="'.VERSION.'"
					WHERE id = "'.$row['id'].'"';
		} else {
			$sql = 'INSERT INTO vps_status
					SET vps_id = "'.$db->check($vps->veid).'",
							timestamp = "'.time().'",
							vps_up = "'.$up.'",
							vps_nproc = "'.$db->check($out["ve_nproc"]).'",
							vps_vm_used_mb = "'.$memusage['used'].'",
							vps_disk_used_mb = "'.$db->check($diskusage).'",
							vps_admin_ver ="'.VERSION.'"';
		}
	} else {
		$sql = 'INSERT INTO vps_status
				SET vps_id = "'.$db->check($vps->veid).'",
						timestamp = "'.time().'",
						vps_up = "'.$up.'",
						vps_nproc = "'.$db->check($out["ve_nproc"]).'",
						vps_vm_used_mb = "'.$memusage['used'].'",
						vps_disk_used_mb = "'.$db->check($diskusage).'",
						vps_admin_ver ="'.VERSION.'"';
	}
	$db->query($sql);
    }
    echo ("vps status complete\n");
}

function cat_file($id, $filename) {
    $command = BIN_VZCTL.' exec '.$id.' "cat '.$filename.'"';
    exec ($command, $output);
    return $output;
}

/* Following functions are highly inspired from phpSysInfo */
function get_cpuload($id, $wait = true) {
	if ($buf = cat_file($id, '/proc/stat')) {
		sscanf($buf[0], "%*s %Ld %Ld %Ld %Ld", $ab, $ac, $ad, $ae);
		// Find out the CPU load
		// user + sys = load
		// total = total
		$load = $ab+$ac+$ad; // cpu.user + cpu.sys
		$total = $ab+$ac+$ad+$ae; // cpu.total
		// we need a second value, wait 1 second befor getting (< 1 second no good value will occour)
		if ($wait)sleep(1);
		$buf = cat_file($id, '/proc/stat');
		sscanf($buf[0], "%*s %Ld %Ld %Ld %Ld", $ab, $ac, $ad, $ae);
		$load2 = $ab+$ac+$ad;
		$total2 = $ab+$ac+$ad+$ae;
		return (100*($load2-$load))/($total2-$total);
	} else return false;
  }

function get_mem_usage($id) {
    $return = false;
    if ((array)$bufe = cat_file($id,'/proc/meminfo')) {
	foreach($bufe as $buf) {
	    if (preg_match('/^MemTotal:\s+(.*)\s*kB/i', $buf, $ar_buf)) {
		if ($ar_buf[1] != 0) $return['total'] = round($ar_buf[1]/1024);
		else $return['total'] = 0;
	    } else if (preg_match('/^MemFree:\s+(.*)\s*kB/i', $buf, $ar_buf)) {
		if ($ar_buf[1] != 0) $return['free'] = round($ar_buf[1]/1024);
		else $return['free'] = 0;
	    }
	}
	$return['used'] = $return['total']-$return['free'];
    }
    return $return;
}

function get_disk_usage($id) {
	$command = BIN_VZCTL.' exec '.$id.' "df -k /" | grep -v Filesystem | awk \'{printf $3;}\'';
    exec ($command, $output);
    return ceil($output[0]/1024);
}
?>
