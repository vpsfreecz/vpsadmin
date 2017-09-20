<?php
session_start();

include '/etc/vpsadmin/config.php';
include WWW_ROOT.'lib/version.lib.php';
include WWW_ROOT.'lib/members.lib.php';

header('Content-Type: text/javascript');

if($_SESSION['logged_in']) {
?>
(function(root) {
root.vpsAdmin = {
	api: {
		url: "<?php echo EXT_API_URL ?>",
		version: "<?php echo API_VERSION ?>"
	},
	authToken: "<?php echo $_SESSION['auth_token'] ?>",
	sessionLength: <?php echo USER_LOGIN_INTERVAL ?>,
	description: <?php echo json_encode($_SESSION['api_description']) ?>,
	sessionManagement: <?php echo $_SESSION['is_admin'] ? 'true' : 'false' ?>
};

var chainTimeout;
var api = root.apiClient = new HaveAPI.Client(root.vpsAdmin.api.url, {version: root.vpsAdmin.api.version});
api.useDescription(root.vpsAdmin.description);
api.authenticate('token', {token: root.vpsAdmin.authToken}, function(){}, false);

<?php include 'js/transaction-chains.js'; ?>
<?php include 'js/session-countdown.js'; ?>

})(window);
<?php } ?>
