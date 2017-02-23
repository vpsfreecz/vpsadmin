<?php

if ($_SESSION['logged_in']) {
	switch ($_GET['to']) {
	case 'payset':
		switch ($_GET['from']) {
		case 'payment':
			$p = $api->user_payment->show($_GET['id']);
			redirect('?page=adminm&action=payset&id='.$p->user_id);
			break;
		}
		break;
	}

	$xtpl->perex(_('Redirect failed'), _('The redirect request was invalid.'));

} else {
	$xtpl->perex(
		_("Access forbidden"),
		_("You have to log in to be able to access vpsAdmin's functions")
	);
}
