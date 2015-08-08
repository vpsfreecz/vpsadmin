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
					$params['expiration_date'] = date('c', strtotime($_POST['expiration_date']));
				
				if ($_POST['change_reason'])
					$params['change_reason'] = $_POST['change_reason'];
				
				$api[ $_GET['resource'] ]->update($_GET['id'], $params);
				
				notify_user(
					_('State set'),
					_('Object state was successfully set to').' '.$state.'. '.
					_('You may need to wait a few moments before the change takes effect.')
				);
				redirect($_GET['return'] ? $_GET['return'] : '?page=');
				
			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('State change failed'), $e->getResponse());
				lifetimes_set_state_form($_GET['resource'], $_GET['id']);
			}
			
			break;
		
		case 'changelog':
			$states = $api[$_GET['resource']]->state_log->list($_GET['id'], array(
				'meta' => array('includes' => 'user')
			));
			
			$xtpl->table_title(_('State log for').' '.$_GET['resource'].' #'.$_GET['id']);
			
			$xtpl->table_add_category(_('Date'));
			$xtpl->table_add_category(_('State'));
			$xtpl->table_add_category(_('Expiration'));
			$xtpl->table_add_category(_('Admin'));
			
			foreach ($states as $s) {
				$xtpl->table_td($s->changed_at);
				$xtpl->table_td($s->state);
				$xtpl->table_td($s->expiration);
				
				if ($s->user_id)
					$xtpl->table_td('<a href="?page=members&action=edit&id='.$s->user->id.'">'.$s->user->login.'</a>');
				else
					$xtpl->table_td('---');
				
				$xtpl->table_tr();
				$xtpl->table_td(
					_('Reason').': '.nl2br($s->reason),
					false, false, 4
				);
				$xtpl->table_tr();
			}
			
			$xtpl->table_out();
			
			$xtpl->sbar_add(_('Back'), $_GET['return']);
			$xtpl->sbar_out(_('Manage VPS'));
			
			break;
	}
	
} else {
	$xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
}
