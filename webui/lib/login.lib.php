<?php

define('PAST_USER_ACCOUNTS_COOKIE', 'vpsAdmin-userAccounts');

function setupOAuth2ForLogin()
{
    global $api;

    $api->authenticate('oauth2', [
        'client_id' => OAUTH2_CLIENT_ID,
        'client_secret' => OAUTH2_CLIENT_SECRET,
        'redirect_uri' => getOAuth2RedirectUri(),
        'scope' => 'all',
    ]);
}

function loginUser($access_url)
{
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
        'session_length' => $m->preferred_session_length,
    ];
    $_SESSION["is_user"] =       ($m->level >= PRIV_USER) ? true : false;
    $_SESSION["is_poweruser"] =  ($m->level >= PRIV_POWERUSER) ? true : false;
    $_SESSION["is_admin"] =      ($m->level >= PRIV_ADMIN) ? true : false;
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

function destroySession()
{
    $_SESSION["logged_in"] = false;
    $_SESSION["auth_type"] = null;
    $_SESSION["access_token"] = null;
    $_SESSION["session_token"] = null;
    unset($_SESSION["user"]);

    session_destroy();
}

function logoutUser()
{
    global $xtpl, $api;

    csrf_check();
    destroySession();

    $api->logout();

    $xtpl->perex(_("Goodbye"), _("Logout successful"));
}

function logoutAndSwitchUser()
{
    global $xtpl, $api;

    csrf_check();

    if ($_SESSION["auth_type"] != "oauth2") {
        $xtpl->perex(_('Unable to switch user while impersonating user'), '');
        return;
    }

    destroySession();

    $api->getAuthenticationProvider()->revokeAccessToken(['close_sso' => '1']);

    $redirectPath = '?page=login&action=login';

    if (isset($_GET['user']) && $_GET['user']) {
        $redirectPath .= '&user=' . urlencode($_GET['user']);
    }

    redirect($redirectPath);
}

function switchUserContext($target_user_id)
{
    global $xtpl, $api;

    $admin = $_SESSION;

    try {
        $user = $api->user->show($target_user_id);

        // Get a token for target user
        $new_session = $api->user_session->create([
            'user' => $user->id,
            'label' => getClientIdentity() . '(context switch)',
            'token_lifetime' => 'renewable_auto',
            'token_interval' => 20 * 60,
        ]);

        session_destroy();
        session_start();

        // Do this to reload description from the API
        $api->authenticate('token', ['token' => $new_session->token_full]);

        $_SESSION["logged_in"] = true;
        $_SESSION["auth_type"] = "token";
        $_SESSION["session_token"] = $new_session->token_full;
        $_SESSION["borrowed_token"] = true;
        $_SESSION["user"] = [
            'id' => $user->id,
            'login' => $user->login,
            'session_length' => 20 * 60,
        ];
        $_SESSION["is_user"] =       ($user->level >= PRIV_USER) ? true : false;
        $_SESSION["is_poweruser"] =  ($user->level >= PRIV_POWERUSER) ? true : false;
        $_SESSION["is_admin"] =      ($user->level >= PRIV_ADMIN) ? true : false;
        $_SESSION["is_superadmin"] = ($user->level >= PRIV_SUPERADMIN) ? true : false;

        $_SESSION["context_switch"] = true;
        $_SESSION["original_admin"] = $admin;

        notify_user(
            _("Change to") . ' ' . $user->login . ' ' . _('was successful'),
            _("Your privilege level: ")
                . $cfg_privlevel[$user->level]
        );

        redirect($_GET["next"]);

    } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
        $xtpl->perex_format_errors(_('Failed to switch context'), $e->getResponse());
    }
}

function regainAdminUser()
{
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

function getOAuth2RedirectUri()
{
    return getSelfUri() . '/?page=login&action=callback';
}

function isHttps()
{
    return ($_SERVER['HTTPS'] ?? false) || (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] == 'https');
}

function getSelfUri()
{
    $ret = 'http';

    if (isHttps()) {
        $ret .= 's';
    }

    $ret .= '://';

    if ($_SERVER['SERVER_PORT'] != '80') {
        $ret .= $_SERVER['SERVER_NAME'] . ':' . $_SERVER['SERVER_PORT'];
    } else {
        $ret .= $_SERVER['SERVER_NAME'];
    }

    return $ret;
}

function getAuthenticationToken()
{
    global $api;

    $provider = $api->getAuthenticationProvider();

    switch ($_SESSION['auth_type']) {
        case 'oauth2':
            return $provider->jsonSerialize()['access_token'];
        case 'token':
            return $provider->getToken();
        default:
            throw "Unknown authentication type";
    }
}

function savePastUserAccounts()
{
    $userAccounts = [];
    $hasCookie = isset($_COOKIE[PAST_USER_ACCOUNTS_COOKIE]);

    if ($hasCookie) {
        $userAccounts = explode(',', $_COOKIE[PAST_USER_ACCOUNTS_COOKIE]);
    }

    if (isset($_SESSION["context_switch"]) && $_SESSION["context_switch"]) {
        $isSaved = true;
    } else {
        $isSaved = in_array($_SESSION['user']['login'], $userAccounts);
    }

    if (!$isSaved) {
        $userAccounts[] = $_SESSION['user']['login'];
        sort($userAccounts);
    }

    $_SESSION['user_accounts'] = $userAccounts;

    if ($hasCookie && $isSaved) {
        return;
    }

    setcookie(
        PAST_USER_ACCOUNTS_COOKIE,
        implode(',', $userAccounts),
        [
            'expires' => time() + 7 * 24 * 60 * 60,
            'secure' => isHttps(),
        ]
    );
}

function getPastUserAccounts()
{
    return $_SESSION['user_accounts'];
}
