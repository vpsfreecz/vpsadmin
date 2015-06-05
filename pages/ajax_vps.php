<?php

$vps = $api->vps->find($_GET["veid"], array('meta' => array('includes' => 'user')));

if ($vps->object_state != 'active' || $vps->user->object_state != 'active')
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
