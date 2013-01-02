<?php

$vps = vps_load($_GET["veid"]);
$member_of_session = member_load($_SESSION["member"]["m_id"]);

if(!$vps->exists || (!$member_of_session->is_new() && !$member_of_session->has_paid_now() && $cluster_cfg->get("payments_enabled")))
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
	case "configs_order":
		if (isset($_POST['order'])) {
			$raw_order = explode('&', $_POST['order']);
			
			$i = 1;
			
			foreach($raw_order as $item) {
				$item = explode('=', $item);
				
				if (!$item[1] || $item[1] == "add_config")
					continue;
				
				$order = explode('_', $item[1]);
				
				$db->query("UPDATE vps_has_config SET `order` = ".$i++." WHERE vps_id = ".$db->check($vps->veid)." AND config_id = ".$db->check($db->check($order[1]))."");
			}
			
			$vps->applyconfigs();
			
			echo json_encode(array('error' => false));
		} else echo json_encode(array('error' => true));
		
		break;
	default:
		break;
}
