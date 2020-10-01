<?php

if (isLoggedIn()) {
	switch ($_GET['action']) {
	case 'show':
		oom_reports_show($_GET['id']);
		break;

	case 'list':
	default:
		oom_reports_list();
	}

	$xtpl->sbar_out(_('OOM Reports'));

} else {
	$xtpl->perex(
		_("Access forbidden"),
		_("You have to log in to be able to access vpsAdmin's functions")
	);
}
