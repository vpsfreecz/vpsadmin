<?php

if ($_SESSION['logged_in']) {
	$quotas = array('quota', 'refquota');

	switch ($_GET['action']) {
		case 'new':
			if (isset($_POST['name'])) {
				$params = array(
					'name' => $_POST['name'],
					'dataset' => $_POST['dataset'] ? $_POST['dataset'] : $_GET['parent'],
					'automount' => $_POST['automount'] ? true : false
				);
				
				foreach ($quotas as $quota) {
					if (isset($_POST[$quota]))
						$params[$quota] = $_POST[$quota] * (2 << $DATASET_UNITS_TR[$_POST["quota_unit"]]);
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
						$params[$quota] = $_POST[$quota] * (2 << $DATASET_UNITS_TR[$_POST["quota_unit"]]);
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
			if (isset($_POST['confirm']) && $_POST['confirm']) {
				try {
					$api->dataset($_GET['id'])->delete();
					
					notify_user(_('Dataset destroyed'), _('Dataset was successfully destroyed.'));
					redirect($_POST['return'] ? $_POST['return'] : '?page=');
					
				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('Failed to destroy dataset'), $e->getResponse());
					$show_info=true;
				}
				
			} else {
				try {
					$ds = $api->dataset->find($_GET['id']);
					
					$xtpl->table_title(_('Confirm the destroyal of dataset').' '.$ds->name);
					$xtpl->form_create('?page=dataset&action=destroy&id='.$ds->id, 'post');
					
					$xtpl->table_td(_("Confirm") . ' ' .
						'<input type="hidden" name="return" value="'.($_GET['return'] ? $_GET['return'] : $_POST['return']).'">'
					);
					$xtpl->form_add_checkbox_pure('confirm', '1', false);
					$xtpl->table_td(_('The dataset will be destroyed along with all its descendants.
									<strong>This action is irreversible!</strong>'));
					$xtpl->table_tr();
					
					$xtpl->form_out(_('Destroy dataset'));
					
				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('Dataset cannot be found'), $e->getResponse());
					$show_info=true;
				}
			}
			
			break;
		
		case 'mount':
			if (isset($_POST[''])) {
				
				
			} else {
				mount_create_form();
			}
		
		default:
			
	}
	
} else {
	$xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
}
