<?php
/*
    ./pages/page_login.php

    vpsAdmin
    Web-admin interface for vpsAdminOS (see https://vpsadminos.org)
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


// Redirect to OAuth2 authorization server
if ($_GET["action"] == 'login') {
    setupOAuth2ForLogin();
    $api->getAuthenticationProvider()->requestAuthorizationCode();
    exit;
}

// Callback from the OAuth2 authorization server
if ($_SERVER['REQUEST_METHOD'] === 'GET' && $_GET["action"] == 'callback') {
    if (isset($_GET['code'])) {
        setupOAuth2ForLogin();
        $provider = $api->getAuthenticationProvider();

        try {
            $provider->requestAccessToken();
            loginUser($_SESSION['access_url']);
        } catch (Exception $e) {
            $xtpl->perex(
                _('Authentication error'),
                _('vpsAdmin was unable to obtain access token from the authorization server, please contact support if the error persists.')
            );
        }

    } else {
        $xtpl->perex(
            _('Authentication error'),
            _('Authorization server reports: ') . h($_GET['error_description'] ?? $_GET['error'] ?? _('unknown error')) . '<br>' .
            _('Please try to sign in again or contact support if the error persists.')
        );
    }
}

// Revoke access token
if ($_GET["action"] == 'logout') {
    logoutUser();
} elseif ($_GET["action"] == 'switch_user') {
    logoutAndSwitchUser();
}

if (isAdmin() && ($_GET["action"] == 'drop_admin')) {
    $_SESSION["context_switch"] = true;
    $_SESSION["original_admin"] = $_SESSION;
    $_SESSION["is_admin"] = false;

    $xtpl->perex(_("Dropped admin privileges"), '');
    redirect($_GET["next"]);
}

if (isAdmin() && ($_GET["action"] == 'switch_context') && isset($_GET["m_id"]) && !$_SESSION["context_switch"]) {
    switchUserContext($_GET['m_id']);
}

if ($_GET["action"] == "regain_admin" && $_SESSION["context_switch"]) {
    regainAdminUser();
}
