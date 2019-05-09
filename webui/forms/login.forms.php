<?php

function totp_login_form() {
	global $xtpl;

	$xtpl->title(_('Two-factor authentication'));
	$xtpl->form_create('?page=login&action=totp', 'post');
	$xtpl->form_add_input(_('TOTP code').':', 'code', '30', 'code');
	$xtpl->form_out(_('Login'));
}
