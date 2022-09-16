<?php

if (isLoggedIn()) {
	$xtpl->sbar_add(_('Back to status'), '?page=');
	$xtpl->sbar_out(_('Node'));

	node_details_table($_GET['id']);

} else {
	$xtpl->perex(
		_("Access forbidden"),
		_("You have to log in to be able to access vpsadmin's functions")
	);
}
