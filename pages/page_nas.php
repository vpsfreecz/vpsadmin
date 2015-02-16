<?php
if ($_SESSION["logged_in"] && (NAS_PUBLIC || $_SESSION["is_admin"])) {
	if ($_SESSION['is_admin']) {
		// Filter form & query
		$xtpl->table_title(_('Filters'));
		$xtpl->form_create('', 'get', 'nas-filter', false);
		
		$xtpl->table_td(_("Limit").':'.
			'<input type="hidden" name="page" value="nas">'.
			'<input type="hidden" name="action" value="list">'
		);
		$xtpl->form_add_input_pure('text', '40', 'limit', get_val('limit', '25'), '');
		$xtpl->table_tr();
		
		$xtpl->form_add_input(_("Offset").':', 'text', '40', 'offset', get_val('offset', '0'), '');
		$xtpl->form_add_input(_("Member ID").':', 'text', '40', 'user', get_val('user'), _('Show datasets owned by user'));
		$xtpl->form_add_input(_("Dataset").':', 'text', '40', 'dataset', get_val('dataset'), _('Show dataset subtree'));
		
		$xtpl->form_out(_('Show'));
		
		if (isset($_GET['action'])) {
			dataset_list(
				'primary',
				null,
				$_GET['user'],
				$_GET['dataset'],
				$_GET['limit'],
				$_GET['offset']
			);
		}
		
	} else {
		dataset_list('primary');
	}
	
	$xtpl->sbar_out(_("Manage NAS"));
	
} else {
	$xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
}
