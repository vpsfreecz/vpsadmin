<?php
$show_help = false;

if (isset($argv[2])) switch($argv[2]) {
	case 'whereis':
		if (isset($argv[3])) {
			if ($vps = $db->findByColumnOnce('vps', 'vps_id', $argv[3])) {
				if ($server = $db->findByColumnOnce('servers', 'server_id', $vps["vps_server"])) {
					print ("{$server["server_name"]}\n");
				} else print ("Server not found.\n");
			} else print ("VPS not found.\n");
		} else $show_help = true;
		break;
	case 'show':
		if (isset($argv[3])) {
			if ($vps = $db->findByColumnOnce('vps', 'vps_id', $argv[3])) {
				print_array_formatted($vps);
			} else print ("VPS not found.\n");
		} else $show_help = true;
		break;
	case 'list':
		break;
/*	case 'whereis':
		if (isset($argv[3]) && is_int($argv[3])) {
		
		} else $show_help = true;
		break;*/
	default:
		$show_help = true;
} else $show_help = true;

if ($show_help) {
echo 'vpsAdmin '.VERSION.' CLI
  vps command usage:

  vpsadmin vps <params>

  Params:
      whereis <vps_id>
        Prints a server_name of the VPS.
      show <vps_id>
        Prints detailed DB item of the VPS.
';
}
