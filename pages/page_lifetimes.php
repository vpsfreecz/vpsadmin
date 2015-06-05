<?php

if ($_SESSION['logged_in'] && $_SESSION['is_admin']) {
	
	switch ($_GET['action']) {
		case 'set_state':
			try {
				$choices = $api[$_GET['resource']]->update->getParameters('input')->object_state->choices;
				$state = $choices[(int) $_POST['object_state']];
				$params = array(
					'object_state' => $state
				);
				
				if ($_POST['expiration_date'])
					$params['expiration_date'] = $_POST['expiration_date'];
				
				if ($_POST['change_reason'])
					$params['change_reason'] = $_POST['change_reason'];
				
				$api[ $_GET['resource'] ]->update($_GET['id'], $params);
				
				notify_user(
					_('State set'),
					_('Object state was successfully set to').' '.$state].'. '.
					_('You may need to wait a few moments before the change takes effect.')
				);
				redirect($_GET['return'] ? $_GET['return'] : '?page=');
				
			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('State change failed'), $e->getResponse());
				lifetimes_set_state_form($_GET['resource'], $_GET['id']);
			}
			
			break;
	}
	
} else {
	$xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
}
