<?php

$vps = vps_load($_GET["veid"]);
$member_of_session = member_load($_SESSION["member"]["m_id"]);

if(!$vps->exists || (!$member_of_session->m["m_state"] == "active" && $cluster_cfg->get("payments_enabled")))
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
