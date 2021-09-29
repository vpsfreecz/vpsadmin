<?php
include '/etc/vpsadmin/config.php';

session_start();

include WWW_ROOT.'lib/version.lib.php';
include WWW_ROOT.'lib/members.lib.php';
include WWW_ROOT.'lib/functions.lib.php';

header('Content-Type: text/javascript');

if(isLoggedIn()) {
?>
(function(root) {
root.vpsAdmin = {
	api: {
		url: "<?php echo EXT_API_URL ?>",
		version: "<?php echo API_VERSION ?>"
	},
	sessionToken: "<?php echo $_SESSION['session_token'] ?>",
	sessionLength: <?php echo USER_LOGIN_INTERVAL ?>,
	description: <?php echo json_encode($_SESSION['api_description']) ?>,
	sessionManagement: true
};

var chainTimeout;
var api = root.apiClient = new HaveAPI.Client(root.vpsAdmin.api.url, {version: root.vpsAdmin.api.version});
api.useDescription(root.vpsAdmin.description);
api.authenticate('token', {token: root.vpsAdmin.sessionToken}, function(){}, false);

<?php include 'js/transaction-chains.js'; ?>
<?php include 'js/session-countdown.js'; ?>

})(window);
<?php } ?>
