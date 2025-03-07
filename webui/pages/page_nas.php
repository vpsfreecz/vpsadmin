<?php

if (isLoggedIn() && (NAS_PUBLIC || isAdmin())) {
    if (isAdmin()) {
        // Filter form & query
        $xtpl->table_title(_('Filters'));
        $xtpl->form_create('', 'get', 'nas-filter', false);

        $xtpl->form_set_hidden_fields([
            'page' => 'nas',
            'action' => 'list',
        ]);

        $xtpl->form_add_input(_("Limit") . ':', 'text', '40', 'limit', get_val('limit', '25'), '');
        $xtpl->form_add_input(_("From ID") . ':', 'text', '40', 'from_id', get_val('from_id', '0'), '');
        $xtpl->form_add_input(_("Member ID") . ':', 'text', '40', 'user', get_val('user'), _('Show datasets owned by user'));
        $xtpl->form_add_input(_("Dataset") . ':', 'text', '40', 'dataset', get_val('dataset'), _('Show dataset subtree'));

        $xtpl->form_out(_('Show'));

        if (isset($_GET['action'])) {
            dataset_list(
                'primary',
                null,
                $_GET['user'],
                $_GET['dataset'],
                $_GET['limit'],
                $_GET['from_id']
            );
        }

    } else {
        dataset_list('primary');
    }

    $xtpl->sbar_out(_("Manage NAS"));

} else {
    $xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
}
