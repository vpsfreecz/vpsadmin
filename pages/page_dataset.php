<?php

// $ds = $api->dataset->find($_GET['id']);

$quotas = array('quota', 'refquota');

switch ($_GET['action']) {
	case 'new':
		if (isset($_POST['name'])) {
			$params = array(
				'name' => $_POST['name'],
				'dataset' => $_POST['dataset'],
				'automount' => $_POST['automount'] ? true : false
			);
			
			foreach ($quotas as $quota) {
				if (isset($_POST[$quota]))
					$params[$quota] = $_POST[$quota] * (2 << $NAS_UNITS_TR[$_POST["quota_unit"]]);
			}
			
			foreach ($DATASET_PROPERTIES as $p) {
				if ($_POST['override_'.$p])
					$params[$p] = $_POST[$p];
			}
			
			try {
				$api->dataset->create($params);
				
				notify_user(_('Dataset created'). '');
				redirect($_POST['return'] ? $_POST['return'] : '?page=');
				
			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Dataset creation failed'), $e->getResponse());
				dataset_create_form();
			}
			
		} else {
			dataset_create_form();
		}
		break;
	
	case 'edit':
		if (isset($_POST['return'])) {
			$ds = $api->dataset->find($_GET['id']);
			$params = array();
			
			foreach ($quotas as $quota) {
				if (isset($_POST[$quota]))
					$params[$quota] = $_POST[$quota] * (2 << $NAS_UNITS_TR[$_POST["quota_unit"]]);
			}
			
			foreach ($DATASET_PROPERTIES as $p) {
				if ($_POST['override_'.$p])
					$params[$p] = $_POST[$p];
			}
			
			try {
				$ds->update($params);
				
				notify_user(_('Dataset updated'). '');
				redirect($_POST['return'] ? $_POST['return'] : '?page=');
				
			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Dataset save failed'), $e->getResponse());
				dataset_edit_form();
			}
			
		} else {
			dataset_edit_form();
		}
		break;
	
	case 'destroy':
		break;
	
	default:
		
}
