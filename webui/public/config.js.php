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
    $language = webui_current_api_language($langs);
    ?>
(function(root) {
	root.vpsAdmin = {
		api: {
			url: <?php echo json_encode(EXT_API_URL, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>,
			version: <?php echo json_encode(API_VERSION, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>,
			oauth2TrustedOrigins: <?php echo json_encode(getApiOAuth2TrustedOrigins(), JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>,
			language: <?php echo json_encode($language, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>
		},
		webui: {
			url: <?php echo json_encode(getSelfUri(), JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>
		},
		csrf: {
			sessionTimeZone: <?php echo json_encode(csrf_token('session_time_zone'), JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>
		},
		user: {
			id: <?php echo json_encode($_SESSION['user']['id'] ?? null, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>,
			timeZone: <?php echo json_encode($_SESSION['user']['time_zone'] ?? null, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>,
			language: <?php echo json_encode($language, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>
		},
		serverTimeZone: <?php echo json_encode(VPSADMIN_SERVER_TIME_ZONE, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>,
	<?php if ($_SESSION['auth_type'] == 'oauth2') { ?>
		accessToken: <?php echo json_encode($_SESSION['access_token']['access_token'], JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>,
	<?php } elseif ($_SESSION['auth_type'] == 'token') { ?>
		sessionToken: <?php echo json_encode($_SESSION['session_token'], JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>,
	<?php } ?>
	sessionLength: <?php echo $_SESSION['user']['session_length'] ?>,
	logoutUrl: <?php echo json_encode('?page=login&action=logout&timeout=1&t=' . csrf_token()) ?>,
	description: <?php echo json_encode($_SESSION['api_description']) ?>,
	sessionManagement: true
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
