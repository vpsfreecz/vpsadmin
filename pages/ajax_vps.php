<?php

$vps = vps_load($_GET["veid"]);

if(!$vps->exists)
	exit;

switch ($_GET["action"]) {
	case "start":
		$vps->start();
		break;
	case "stop":
		$vps->stop();
		break;
	case "restart":
		$vps->restart();
		break;
	default:
		break;
}
