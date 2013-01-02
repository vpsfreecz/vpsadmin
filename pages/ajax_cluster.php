<?php
if (!$_SESSION["is_admin"])
	exit;

switch ($_GET["action"]) {
	case "default_configs_order":
		if (isset($_POST['order'])) {
			$raw_order = explode('&', $_POST['order']);
			$new_order = array();
			
			foreach($raw_order as $item) {
				$item = explode('=', $item);
				
				if (!$item[1] || $item[1] == "add_config")
					continue;
				
				$order = explode('_', $item[1]);
				
				$new_order[] = $order[1];
			}
			
			$cluster_cfg->set("default_config_chain", $new_order);
			
			echo json_encode(array('error' => false));
		} else echo json_encode(array('error' => true));
		
		break;
	case "playground_default_configs_order":
		if (isset($_POST['order'])) {
			$raw_order = explode('&', $_POST['order']);
			$new_order = array();
			
			foreach($raw_order as $item) {
				$item = explode('=', $item);
				
				if (!$item[1] || $item[1] == "add_config")
					continue;
				
				$order = explode('_', $item[1]);
				
				$new_order[] = $order[1];
			}
			
			$cluster_cfg->set("playground_default_config_chain", $new_order);
			
			echo json_encode(array('error' => false));
		} else echo json_encode(array('error' => true));
		
		break;
	default:
		break;
}
