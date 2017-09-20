<?php
/*
    ./pages/page_login.php

    vpsAdmin
    Web-admin interface for OpenVZ (see http://openvz.org)
    Copyright (C) 2008-2009 Pavel Snajdr, snajpa@snajpa.net

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

if ($_GET["action"] == 'login') {
	$access_url = $_SESSION["access_url"];

	if ($_POST["passwd"] && $_POST["username"]) {
		try {
			session_destroy();
			session_start();

			$api->authenticate('token', array(
				'username' => $_POST['username'],
				'password' => $_POST['passwd'],
				'lifetime' => 'renewable_auto',
				'interval' => USER_LOGIN_INTERVAL
			));

			$m = $api->user->current();

			$_SESSION["user"]["id"] = $m->id;

			$_SESSION["logged_in"] = true;
			$_SESSION["auth_token"] = $api->getAuthenticationProvider()->getToken();
			$_SESSION["user"] = array(
				'id' => $m->id,
				'login' => $m->login
			);
			$_SESSION["is_user"] =       ($m->level >= PRIV_USER) ?       true : false;
			$_SESSION["is_poweruser"] =  ($m->level >= PRIV_POWERUSER) ?  true : false;
			$_SESSION["is_admin"] =      ($m->level >= PRIV_ADMIN) ?      true : false;
			$_SESSION["is_superadmin"] = ($m->level >= PRIV_SUPERADMIN) ? true : false;

			csrf_init($_POST['username'], $_POST['passwd']);

			$xtpl->perex(_("Welcome, ").$member->m["m_nick"],
					_("Login successful <br /> Your privilege level: ")
					. $cfg_privlevel[$m->level]);

			$api->user->touch($m->id);

			if($access_url
				&& strpos($access_url, "?page=login&action=login") === false
				&& strpos($access_url, "?page=jumpto") === false) {

				redirect($access_url);

			} elseif ($_SESSION["is_admin"]) {
				redirect('?page=cluster');

			} else {
				redirect('?page=');
			}

		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			$xtpl->perex(_("Error"), _("Wrong username or password."));
		}

	} else $xtpl->perex(_("Error"), _("Wrong username or password"));
}

if ($_GET["action"] == 'logout') {

	$_SESSION["logged_in"] = false;
	$_SESSION["auth_token"] = NULL;
	unset($_SESSION["user"]);

	$api->logout();

	$xtpl->perex(_("Goodbye"), _("Logout successful"));

	session_destroy();
}

if ($_SESSION["is_admin"] && ($_GET["action"] == 'drop_admin')) {
	$_SESSION["context_switch"] = true;
	$_SESSION["original_admin"] = $_SESSION;
	$_SESSION["is_admin"] = false;

	$xtpl->perex(_("Dropped admin privileges"), '');
	redirect($_GET["next"]);
}

if ($_SESSION["is_admin"] && ($_GET["action"] == 'switch_context') && isset($_GET["m_id"]) && !$_SESSION["context_switch"]) {

	$admin = $_SESSION;

	try {
		$user = $api->user->show($_GET['m_id']);

		// Get a token for target user
		$token = $api->auth_token->create(array(
			'user' => $user->id,
			'label' => client_identity().'(context switch)',
			'lifetime' => 'renewable_auto',
			'interval' => USER_LOGIN_INTERVAL
		));

		session_destroy();
		session_start();

		// Do this to reload description from the API
		$api->authenticate('token', array('token' => $token->token));

		$_SESSION["logged_in"] = true;
		$_SESSION["auth_token"] = $token->token;
		$_SESSION["borrowed_token"] = true;
		$_SESSION["user"] = array(
			'id' => $user->id,
			'login' => $user->login,
		);
		$_SESSION["is_user"] =       ($user->level >= PRIV_USER) ?       true : false;
		$_SESSION["is_poweruser"] =  ($user->level >= PRIV_POWERUSER) ?  true : false;
		$_SESSION["is_admin"] =      ($user->level >= PRIV_ADMIN) ?      true : false;
		$_SESSION["is_superadmin"] = ($user->level >= PRIV_SUPERADMIN) ? true : false;

		$_SESSION["context_switch"] = true;
		$_SESSION["original_admin"] = $admin;

		notify_user(_("Change to").' '.$user->login.' '._('was successful'),
				_("Your privilege level: ")
				. $cfg_privlevel[$user->level]);

		redirect($_GET["next"]);

	} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
		$xtpl->perex_format_errors(_('Failed to switch context'), $e->getResponse());
	}
}

if ($_GET["action"] == "regain_admin" && $_SESSION["context_switch"]) {
	$admin = $_SESSION["original_admin"];

	if($_SESSION["borrowed_token"]) {
		try {
			$api->logout();
			$api->authenticate('token', array('token' => $admin['auth_token']));

		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			notify_user(_('Failed to destroy borrowed token'), $e->getResponse());
		}
	}

	session_destroy();
	session_start();

	$_SESSION = $admin;

	redirect($_GET["next"]);
}
