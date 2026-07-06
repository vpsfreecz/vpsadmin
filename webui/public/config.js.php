<?php
include '/etc/vpsadmin/config.php';

session_start();

include WEBUI_ROOT . 'lib/version.lib.php';
include WEBUI_ROOT . 'lib/functions.lib.php';
include WEBUI_ROOT . 'lib/security.lib.php';
include WEBUI_ROOT . 'lib/login.lib.php';
include WEBUI_ROOT . 'lib/gettext_stream.lib.php';
include WEBUI_ROOT . 'lib/gettext_inc.lib.php';
include WEBUI_ROOT . 'lib/gettext_lang.lib.php';
include WEBUI_ROOT . 'config_cfg.php';

header('Content-Type: text/javascript');

if (isLoggedIn()) {
    $webuiLocale = Lang::detect($langs);
    Lang::activate($webuiLocale);
    $language = Lang::apiCodeForLocale($langs, $webuiLocale);
    ?>
(function(root) {
	root.vpsAdmin = {
		api: {
			url: <?php echo webui_json(EXT_API_URL) ?>,
			version: <?php echo webui_json(API_VERSION) ?>,
			oauth2TrustedOrigins: <?php echo webui_json(getApiOAuth2TrustedOrigins()) ?>,
			language: <?php echo webui_json($language) ?>
		},
		webui: {
			url: <?php echo webui_json(getSelfUri()) ?>
		},
		csrf: {
			sessionTimeZone: <?php echo webui_json(csrf_token('session_time_zone')) ?>
		},
		user: {
			id: <?php echo webui_json($_SESSION['user']['id'] ?? null) ?>,
			timeZone: <?php echo webui_json($_SESSION['user']['time_zone'] ?? null) ?>,
			language: <?php echo webui_json($language) ?>
		},
		serverTimeZone: <?php echo webui_json(VPSADMIN_SERVER_TIME_ZONE) ?>,
	<?php if ($_SESSION['auth_type'] == 'oauth2') { ?>
		accessToken: <?php echo webui_json($_SESSION['access_token']['access_token']) ?>,
	<?php } elseif ($_SESSION['auth_type'] == 'token') { ?>
		sessionToken: <?php echo webui_json($_SESSION['session_token']) ?>,
	<?php } ?>
	sessionLength: <?php echo $_SESSION['user']['session_length'] ?>,
	logoutUrl: <?php echo webui_json('?page=login&action=logout&timeout=1&t=' . csrf_token()) ?>,
	description: <?php echo webui_json($_SESSION['api_description']) ?>,
	sessionManagement: true,
	sessionCountdown: <?php echo webui_json(webui_session_countdown_labels()) ?>
};

var chainTimeout;
var api = root.apiClient = new HaveAPI.Client(root.vpsAdmin.api.url, {
	version: root.vpsAdmin.api.version,
	oauth2TrustedOrigins: root.vpsAdmin.api.oauth2TrustedOrigins,
	language: root.vpsAdmin.api.language
});
api.useDescription(root.vpsAdmin.description);

<?php if ($_SESSION['auth_type'] == 'oauth2') { ?>
api.authenticate('oauth2', {access_token: {access_token: root.vpsAdmin.accessToken}}, function(){}, false);
<?php } elseif ($_SESSION['auth_type'] == 'token') { ?>
api.authenticate('token', {token: root.vpsAdmin.sessionToken}, function(){}, false);
<?php } ?>

<?php include __DIR__ . '/js/keepalive.js'; ?>
<?php include __DIR__ . '/js/transaction-chains.js'; ?>
<?php include __DIR__ . '/js/session-countdown.js'; ?>

})(window);
<?php } ?>
