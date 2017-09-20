<?php
if ($_SESSION['logged_in']) {
	switch ($_GET['action']) {
	case 'list':
		monitoring_list();
		break;

	case 'show':
		monitoring_event();
		$xtpl->sbar_add(_('Back'), '?page=monitoring&action=list');
		break;

	case 'ack':
		if ($_SERVER['REQUEST_METHOD'] === 'POST' && $_POST['confirm']) {
			csrf_check();

			try {
				$api->monitored_event->acknowledge($_GET['id'], array(
					'until' => $_POST['until'] ? date('c', strtotime($_POST['until'])) : null,
				));

				notify_user(_('Event acknowledged'), _('The issue has been successfully acknowledged.'));
				redirect('?page=monitoring&action=list');

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors('Acknowledge failed', $e->getResponse());
				monitoring_ack_form($_GET['id']);
				$xtpl->sbar_add(_('Back'), '?page=monitoring&action=list');
			}

		} else {
			monitoring_ack_form($_GET['id']);
			$xtpl->sbar_add(_('Back'), '?page=monitoring&action=list');
		}

		break;

	case 'ignore':
		if ($_SERVER['REQUEST_METHOD'] === 'POST' && $_POST['confirm']) {
			csrf_check();

			try {
				$api->monitored_event->ignore($_GET['id'], array(
					'until' => $_POST['until'] ? date('c', strtotime($_POST['until'])) : null,
				));

				notify_user(_('Event ignored'), _('The issue has been successfully ignored.'));
				redirect('?page=monitoring&action=list');

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors('Ignore failed', $e->getResponse());
				monitoring_ignore_form($_GET['id']);
				$xtpl->sbar_add(_('Back'), '?page=monitoring&action=list');
			}

		} else {
			monitoring_ignore_form($_GET['id']);
			$xtpl->sbar_add(_('Back'), '?page=monitoring&action=list');
		}
		break;
	}

	$xtpl->sbar_out(_('Monitoring'));

} else {
	$xtpl->perex(
		_("Access forbidden"),
		_("You have to log in to be able to access vpsAdmin's functions")
	);
}
