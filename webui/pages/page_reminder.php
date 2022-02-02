<?php

if (isLoggedIn()) {

	switch ($_GET['action'] ?? null) {
		case 'set':
			$now = new DateTime("now");
			$date = null;
			$error = false;

			switch ($_POST['remind_in']) {
			case '1w':
				$date = $now;
				$date->add(new DateInterval('P1W'));
				break;
			case '2w':
				$date = $now;
				$date->add(new DateInterval('P2W'));
				break;
			case 'date':
				$date = new DateTime($_POST['remind_after_date']);
				break;
			case 'never':
				$date = $now;
				$date->add(new DateInterval('P1Y'));
				break;
			default:
				$error = true;
			}

			if ($error) {
				$xtpl->perex(_("Unable to determine remind date"), '');
				lifetimes_reminder_form($_GET['resource'], $_GET['id']);
			} else {
				try {
					$api[$_GET['resource']]->update($_GET['id'], [
						'remind_after_date' => $date->format('c')
					]);

					notify_user(
						_('Mail reminder set'),
						_('vpsAdmin will not remind you until').' '.$date->format("Y-m-d").'.'
					);
					redirect('?page=reminder&resource='.$_GET['resource'].'&id='.$_GET['id']);

				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors(_('Reminder change failed'), $e->getResponse());
					lifetimes_reminder_form($_GET['resource'], $_GET['id']);
				}
			}

			break;

		default:
			lifetimes_reminder_form($_GET['resource'], $_GET['id']);
			break;
	}

} else {
	$xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
}
