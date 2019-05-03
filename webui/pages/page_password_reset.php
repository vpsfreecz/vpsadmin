<?php

function change_password_form () {
	global $xtpl;

	$xtpl->title(_('Change password'));
	$xtpl->form_create('?page=password_reset', 'post');
	$xtpl->form_add_input(_('New password').':', 'password', '30', 'new_password', '', '', -8);
	$xtpl->form_add_input(_('Repeat new password').':', 'password', '30', 'new_password2', '', '', -8);
	$xtpl->form_out(_('Save'));
}

function update_changed_password () {
	global $api, $xtpl;

	if ($_POST['new_password'] != $_POST['new_password2']) {
		$xtpl->perex(_('The two passwords do not match.'), '');
		change_password_form();
	} else {
		try {
			$params = [
				'password' => $_SESSION['user']['password'],
				'new_password' => $_POST['new_password'],
			];

			$u = $api->user->update($_SESSION['user']['id'], $params);
			$_SESSION['user']['password_reset'] = $u->password_reset;
			$_SESSION['user']['password'] = null;

			notify_user(_('Password set'), _('The password was successfully changed.'));
			redirect('?page=');

		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			$xtpl->perex_format_errors(_('Password change failed'), $e->getResponse());
			change_password_form();
		}
	}
}

if (isLoggedIn()) {
	if ($_POST['new_password']) {
		update_changed_password();
	} else {
		change_password_form();
	}
} else {
	$xtpl->perex(
		_('Access forbidden'),
		_("You have to log in to be able to access vpsAdmin's functions")
	);
}
