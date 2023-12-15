<?php

function setupOAuth2ForLogin() {
	global $api;

	$api->authenticate('oauth2', [
		'client_id' => OAUTH2_CLIENT_ID,
		'client_secret' => OAUTH2_CLIENT_SECRET,
		'redirect_uri' => getOAuth2RedirectUri(),
		'scope' => 'all',
	]);
}

function loginUser($access_url) {
	global $xtpl, $api;

	session_destroy();
	session_start();

	$m = $api->user->current();

	$_SESSION["user"]["id"] = $m->id;

	$_SESSION['api_description'] = $api->getDescription();
	$_SESSION["logged_in"] = true;
	$_SESSION["auth_type"] = "oauth2";
	$_SESSION["access_token"] = $api->getAuthenticationProvider()->jsonSerialize();
	$_SESSION["user"] = [
		'id' => $m->id,
		'login' => $m->login,
	];
	$_SESSION["is_user"] =       ($m->level >= PRIV_USER) ?       true : false;
	$_SESSION["is_poweruser"] =  ($m->level >= PRIV_POWERUSER) ?  true : false;
	$_SESSION["is_admin"] =      ($m->level >= PRIV_ADMIN) ?      true : false;
	$_SESSION["is_superadmin"] = ($m->level >= PRIV_SUPERADMIN) ? true : false;

	csrf_init();

	$api->user->touch($m->id);

	if ($access_url
		&& strpos($access_url, "?page=login&action=login") === false
		&& strpos($access_url, "?page=jumpto") === false) {

		redirect($access_url);

	} elseif (isAdmin()) {
		redirect('?page=cluster');

	} else {
		redirect('?page=');
	}
}

function logoutUser() {
	global $xtpl, $api;

	$_SESSION["logged_in"] = false;
	$_SESSION["auth_type"] = NULL;
	$_SESSION["access_token"] = NULL;
	$_SESSION["session_token"] = NULL;
	unset($_SESSION["user"]);

	$api->logout();

	$xtpl->perex(_("Goodbye"), _("Logout successful"));

	session_destroy();
}

function switchUserContext($target_user_id) {
	global $xtpl, $api;

	$admin = $_SESSION;

	try {
		$user = $api->user->show($target_user_id);

		// Get a token for target user
		$token = $api->session_token->create([
			'user' => $user->id,
			'label' => client_identity().'(context switch)',
			'lifetime' => 'renewable_auto',
			'interval' => USER_LOGIN_INTERVAL,
		]);

		session_destroy();
		session_start();

		// Do this to reload description from the API
		$api->authenticate('token', ['token' => $token->token]);

		$_SESSION["logged_in"] = true;
		$_SESSION["auth_type"] = "token";
		$_SESSION["session_token"] = $token->token;
		$_SESSION["borrowed_token"] = true;
		$_SESSION["user"] = [
			'id' => $user->id,
			'login' => $user->login,
		];
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

function regainAdminUser() {
	global $api;

	$admin = $_SESSION["original_admin"];

	if ($_SESSION["borrowed_token"]) {
		try {
			$api->logout();
			$api->authenticate('oauth2', ['access_token' => $admin['access_token']]);

		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			notify_user(_('Failed to destroy borrowed token'), $e->getResponse());
		}
	}

	session_destroy();
	session_start();

	$_SESSION = $admin;

	redirect($_GET["next"]);
}

function getOAuth2RedirectUri() {
	return getSelfUri().'/?page=login&action=callback';
}

function getSelfUri() {
	$ret = 'http';

	if (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'])
		$ret .= 's';

	$ret .= '://';

	if ($_SERVER['SERVER_PORT'] != '80')
		$ret .= $_SERVER['SERVER_NAME'].':'.$_SERVER['SERVER_PORT'];
	else
		$ret .= $_SERVER['SERVER_NAME'];

	return $ret;
}
