<?php

/*
    ./index.php

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
include '/etc/vpsadmin/config.php';
session_start();
define("CRON_MODE", false);
define("DEBUG", false);

// Include libraries
include WWW_ROOT . 'vendor/autoload.php';
include WWW_ROOT . 'lib/version.lib.php';
include WWW_ROOT . 'lib/xtemplate.lib.php';
include WWW_ROOT . 'lib/functions.lib.php';
include WWW_ROOT . 'lib/transact.lib.php';
include WWW_ROOT . 'lib/vps.lib.php';
include WWW_ROOT . 'lib/cluster.lib.php';
include WWW_ROOT . 'lib/mail.lib.php';
include WWW_ROOT . 'lib/helpbox.lib.php';
include WWW_ROOT . 'lib/security.lib.php';
include WWW_ROOT . 'lib/munin.lib.php';
include WWW_ROOT . 'lib/login.lib.php';
include WWW_ROOT . 'lib/pagination.lib.php';

include WWW_ROOT . 'forms/backup.forms.php';
include WWW_ROOT . 'forms/cluster.forms.php';
include WWW_ROOT . 'forms/dataset.forms.php';
include WWW_ROOT . 'forms/export.forms.php';
include WWW_ROOT . 'forms/vps.forms.php';
include WWW_ROOT . 'forms/users.forms.php';
include WWW_ROOT . 'forms/lifetimes.forms.php';
include WWW_ROOT . 'forms/object_history.forms.php';
include WWW_ROOT . 'forms/networking.forms.php';
include WWW_ROOT . 'forms/outage.forms.php';
include WWW_ROOT . 'forms/monitoring.forms.php';
include WWW_ROOT . 'forms/userns.forms.php';
include WWW_ROOT . 'forms/oom_reports.forms.php';
include WWW_ROOT . 'forms/node.forms.php';
include WWW_ROOT . 'forms/incidents.forms.php';
include WWW_ROOT . 'forms/dns.forms.php';
include WWW_ROOT . 'forms/userdata.forms.php';

include WWW_ROOT . 'lib/gettext_stream.lib.php';
include WWW_ROOT . 'lib/gettext_inc.lib.php';
include WWW_ROOT . 'lib/gettext_lang.lib.php';
// include configuration
include WWW_ROOT . 'config_cfg.php';

$api = new \HaveAPI\Client(INT_API_URL, API_VERSION, getClientIdentity(), [
    'verify' => defined('API_SSL_VERIFY') ? API_SSL_VERIFY : true,
]);
$api->registerDescriptionChangeFunc('api_description_changed');

if (isset($_SESSION["api_description"]) && $_SESSION["api_description"]) {
    $api->setDescription($_SESSION["api_description"]);
}

// Create a template class
$xtpl = new XTemplate(WWW_ROOT . 'template/template.html');
// Create a langauge class
$lang = new Lang($langs, $xtpl);

$xtpl->assign("VERSION", getVersionLink());
$xtpl->assign("L_LOGIN", _("Log in"));
$xtpl->assign("L_LOGGING_IN", _("Signing in..."));
$xtpl->assign("L_LOGOUT", _("Logout"));
$xtpl->assign("L_LOGOUT_SWITCH", _("Switch user"));
$xtpl->assign('YEAR', date('Y'));

$api_cluster = null;
$config = null;

try {
    if (isLoggedIn()) {
        savePastUserAccounts();

        switch ($_SESSION['auth_type']) {
            case 'oauth2':
                $api->authenticate('oauth2', ['access_token' => $_SESSION['access_token']], false);
                break;
            case 'token':
                $api->authenticate('token', ['token' => $_SESSION['session_token']], false);
                break;
            default:
                die("Unknown authentication method");
        }

        try {
            $api_cluster = $api->cluster->show();

            if (!isset($_SESSION["context_switch"]) || !$_SESSION["context_switch"]) {
                $api->user->touch($_SESSION["user"]["id"]);
            }

        } catch (\HaveAPI\Client\Exception\AuthenticationFailed $e) {
            unset($_SESSION);
            session_destroy();
            $_GET["page"] = "";
        }
    }

    $config = new SystemConfig($api);

    $_GET["page"] ??= false;

    if (($_GET["page"] != "login") &&
                    ($_GET["page"] != "lang") &&
                    ($_GET["page"] != "about") &&
                    (!isAdmin()) &&
                    $api_cluster && $api_cluster->maintenance_lock) {
        $request_page = "";
        include WWW_ROOT . 'pages/page_index.php';
        $xtpl->perex(_("Maintenance mode"), _("vpsAdmin is currently in maintenance mode, any actions are disabled. <br />
											This is usually used during outage to prevent data corruption.<br />")
                                        . "<br>" . ($api_cluster->maintenance_lock_reason ? _('Reason') . ': ' . $api_cluster->maintenance_lock_reason . '<br><br>' : '')
                                        . _("Please be patient."));
    } else {
        show_notification();

        if (!isLoggedIn() && !isset($_SESSION['access_url'])) {
            $_SESSION["access_url"] = $_SERVER["REQUEST_URI"];
        }

        switch ($_GET["page"]) {
            case 'adminvps':
                include WWW_ROOT . 'pages/page_adminvps.php';
                break;
            case 'about':
                include WWW_ROOT . 'pages/page_about.php';
                break;
            case 'login':
                include WWW_ROOT . 'pages/page_login.php';
                break;
            case 'adminm':
                include WWW_ROOT . 'pages/page_adminm.php';
                break;
            case 'transactions':
                include WWW_ROOT . 'pages/page_transactions.php';
                break;
            case 'networking':
                include WWW_ROOT . 'pages/page_networking.php';
                break;
            case 'cluster':
                include WWW_ROOT . 'pages/page_cluster.php';
                break;
            case 'log':
                include WWW_ROOT . 'pages/page_log.php';
                break;
            case 'dataset':
                include WWW_ROOT . 'pages/page_dataset.php';
                break;
            case 'export':
                include WWW_ROOT . 'pages/page_export.php';
                break;
            case 'backup':
                include WWW_ROOT . 'pages/page_backup.php';
                break;
            case 'nas':
                include WWW_ROOT . 'pages/page_nas.php';
                break;
            case 'incidents':
                include WWW_ROOT . 'pages/page_incidents.php';
                break;
            case 'lang':
                $lang->change($_GET['newlang']);
                break;
            case 'console':
                include WWW_ROOT . 'pages/page_console.php';
                break;
            case 'jumpto':
                include WWW_ROOT . 'pages/page_jumpto.php';
                break;
            case 'lifetimes':
                include WWW_ROOT . 'pages/page_lifetimes.php';
                break;
            case 'reminder':
                include WWW_ROOT . 'pages/page_reminder.php';
                break;
            case 'history':
                include WWW_ROOT . 'pages/page_history.php';
                break;
            case 'redirect':
                include WWW_ROOT . 'pages/page_redirect.php';
                break;
            case 'outage':
                include WWW_ROOT . 'pages/page_outage.php';
                break;
            case 'monitoring':
                include WWW_ROOT . 'pages/page_monitoring.php';
                break;
            case 'userns':
                include WWW_ROOT . 'pages/page_userns.php';
                break;
            case 'oom_reports':
                include WWW_ROOT . 'pages/page_oom_reports.php';
                break;
            case 'node':
                include WWW_ROOT . 'pages/page_node.php';
                break;
            case 'dns':
                include WWW_ROOT . 'pages/page_dns.php';
                break;
            case 'userdata':
                include WWW_ROOT . 'pages/page_userdata.php';
                break;
            default:
                include WWW_ROOT . 'pages/page_index.php';
        }
        $request_page = $_GET["page"];
    }

} catch (\Httpful\Exception\ConnectionErrorException $e) {
    $xtpl->perex(_('Error occured'), _('Unable to connect to the API server. Please contact the support.'));

} catch (\HaveAPI\Client\Exception\Base $e) {
    $xtpl->perex(_('Error occured'), _('An unhandled error occured in communication with the API. Please contact the support.'));
    throw $e;
} catch (\CsrfTokenInvalid $e) {
    $xtpl->perex(_('Token invalid'), _('Your security token is either invalid or expired. Please try to repeat the action, you will be given a new, valid token.'));
}

if (isLoggedIn()) {
    $xtpl->menu_add(_("Status"), '?page=', ($_GET["page"] == ''));
    $xtpl->menu_add(_("Members"), '?page=adminm', ($_GET["page"] == 'adminm'));
    $xtpl->menu_add(_("VPS"), '?page=adminvps', ($_GET["page"] == 'adminvps'));
    if (isAdmin()) {
        $xtpl->menu_add(_("Backups"), '?page=backup', ($_GET["page"] == 'backup'));

        if (NAS_PUBLIC || isAdmin()) {
            $xtpl->menu_add(_("NAS"), '?page=nas', ($_GET["page"] == 'nas'));
        }

        $xtpl->menu_add(_("Exports"), '?page=export', ($_GET["page"] == 'export'));
        $xtpl->menu_add(_("Networking"), '?page=networking', ($_GET["page"] == 'networking'));
        $xtpl->menu_add(_("DNS"), '?page=dns', ($_GET["page"] == 'dns'));
        $xtpl->menu_add(_("Cluster"), '?page=cluster', ($_GET["page"] == 'cluster'));
        $xtpl->menu_add(_("Transaction log"), '?page=transactions', ($_GET["page"] == 'transactions'), true);
    } else {
        $xtpl->menu_add(_("Backups"), '?page=backup', ($_GET["page"] == 'backup'));

        if (NAS_PUBLIC || isAdmin()) {
            $xtpl->menu_add(_("NAS"), '?page=nas', ($_GET["page"] == 'nas'));
        }

        if (isExportPublic()) {
            $xtpl->menu_add(_("Exports"), '?page=export', ($_GET["page"] == 'export'));
        }

        if (USERNS_PUBLIC) {
            $xtpl->menu_add(_("User namespaces"), '?page=userns', ($_GET["page"] == 'userns'));
        }

        $xtpl->menu_add(_("Networking"), '?page=networking', ($_GET["page"] == 'networking'));
        $xtpl->menu_add(_("DNS"), '?page=dns', ($_GET["page"] == 'dns'));
        $xtpl->menu_add(_("Transaction log"), '?page=transactions', ($_GET["page"] == 'transactions'), true);
    }

    try {
        list_transaction_chains();

    } catch (\HaveAPI\Client\Exception\AuthenticationFailed $e) {
        unset($_SESSION);
        session_destroy();
        $_GET["page"] = "";
    }

} else {
    $xtpl->menu_add(_("Status"), '?page=', ($_GET["page"] == ''));
    $xtpl->menu_add(_("About vpsAdmin"), '?page=about', ($_GET["page"] == 'about'), true);
}

$xtpl->logbox(
    isLoggedIn(),
    isset($_SESSION["user"]) ? $_SESSION["user"]["login"] : false,
    isAdmin(),
    $api_cluster ? $api_cluster->maintenance_lock : false
);

if ($config) {
    $xtpl->adminbox($config->get("webui", "sidebar"));
}

try {
    $help = get_helpbox();
} catch (\Httpful\Exception\ConnectionErrorException $e) {
}

if (isAdmin()) {
    $help .= '<p><a href="?page=cluster&action=helpboxes_add&help_page=' . ($_GET["page"] ?? '') . '&help_action=' . ($_GET["action"] ?? '') . '" title="' . _("Edit") . '"><img src="template/icons/edit.png" title="' . _("Edit") . '">' . _("Edit help box") . '</a></p>';
}

if ($help) {
    $xtpl->helpbox(_("Help"), nl2br($help));
}

$lang->lang_switcher();

if ($config) {
    $xtpl->assign('PAGE_TITLE', $config->get("webui", "document_title"));
}

$xtpl->assign('API_SPENT_TIME', round($api->getSpentTime(), 3));

if (defined('TRACKING_CODE')) {
    $xtpl->assign('TRACKING_CODE', TRACKING_CODE);
}
$xtpl->parse('main');
$xtpl->out('main');
