<?php
include '/etc/vpsadmin/config.php';

session_start();

include WWW_ROOT.'lib/version.lib.php';
include WWW_ROOT.'lib/functions.lib.php';
include WWW_ROOT.'lib/login.lib.php';

header('Content-Type: text/javascript');

if(isLoggedIn()) {
?>
(function(root) {
root.vpsAdmin = {
	api: {
		url: "<?php echo EXT_API_URL ?>",
		version: "<?php echo API_VERSION ?>"
	},
	webui: {
		url: "<?php echo getSelfUri() ?>"
	},
<?php if ($_SESSION['auth_type'] == 'oauth2') { ?>
	accessToken: "<?php echo $_SESSION['access_token']['access_token'] ?>",
<?php } elseif ($_SESSION['auth_type'] == 'token') { ?>
	sessionToken: "<?php echo $_SESSION['session_token'] ?>",
<?php } ?>
	sessionLength: <?php echo $_SESSION['user']['session_length'] ?>,
	description: <?php echo json_encode($_SESSION['api_description']) ?>,
	sessionManagement: true
};

var chainTimeout;
var api = root.apiClient = new HaveAPI.Client(root.vpsAdmin.api.url, {version: root.vpsAdmin.api.version});
api.useDescription(root.vpsAdmin.description);

<?php if ($_SESSION['auth_type'] == 'oauth2') { ?>
api.authenticate('oauth2', {access_token: {access_token: root.vpsAdmin.accessToken}}, function(){}, false);
<?php } elseif ($_SESSION['auth_type'] == 'token') { ?>
api.authenticate('token', {token: root.vpsAdmin.sessionToken}, function(){}, false);
<?php } ?>

<?php include 'js/keepalive.js'; ?>
<?php include 'js/transaction-chains.js'; ?>
<?php include 'js/session-countdown.js'; ?>

})(window);
<?php } ?>
