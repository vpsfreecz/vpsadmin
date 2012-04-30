<?php

function update_server_status() {
    global $db;
	$sql = 'INSERT INTO servers_status
			SET server_id = "'.SERVER_ID.'",
			    timestamp = "'.time().'",
			    ram_free_mb = "'.get_server_mem_free_mb().'",
			    disk_vz_free_gb = "0",
			    cpu_load = "'.get_server_cpuload().'",
			    daemon = "'.get_daemon_status().'",
			    vpsadmin_version = "'.VERSION.'"';
	$db->query($sql);
}

function cat_server_file($filename) {
    $command = 'cat '.$filename;
    exec ($command, $output);
    return $output;
}

/* Following functions are highly inspired from phpSysInfo */
function get_daemon_status() {
	exec("ls /proc/`cat /var/run/vpsadmin.pid`/status", $null, $return);

	if ($return != 0)
		proc_close(proc_open ("/etc/init.d/vpsadmin restart", array(), $null));

	return $return;
}

function get_server_cpuload() {
	if ($buf = cat_server_file('/proc/loadavg')) {
		$array = explode(" ", $buf[0]);
		return $array[0];
	} else return false;
  }

function get_server_mem_free_mb() {
    $return = false;
    if ((array)$bufe = cat_server_file('/proc/meminfo')) {
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
    return $return['free'];
}

function get_server_disk_vz_free_gb() {
    $this_server = new cluster_node(SERVER_ID);
    $command = 'df -Pk | grep -m 1 "'.$this_server->s["server_path_vz"].'" | awk \'{printf $4;}\'';
    exec ($command, $output);
    return round($output[0]/1024/1024, 2);
}
?>
