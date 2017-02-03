<?php

function setup_console() {
	global $xtpl, $api;

	try {
		$vps = $api->vps->find($_GET['veid'], array(
			'meta' => array('includes', 'node__location')
		));

	} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
		$xtpl->perex_format_errors(_('VPS not found'), $e->getResponse());
		return;
	}

	try {
		$t = $vps->console_token->create();

	} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
		$xtpl->perex_format_errors(_('Unable to acquire console token'), $e->getResponse());
		return;
	}

	$server = $vps->node->location->remote_console_server;

	if (!$server) {
		$xtpl->perex(_('No console server available'), _('There is no console server for this location.'));
		return;
	}

	$xtpl->perex(_('Remote Console for VPS').' <a href="?page=adminvps&action=info&veid='.$vps->id.'">#'.$vps->id.'</a>',
		'<iframe src="'.$server.'/console/'.$vps->id.'?token='.$_SESSION['auth_token'].'&session='.$t->token.'" width="100%" height="500px" border="1" id="vpsadmin-console-frame"></iframe>
<script type="text/javascript">
var _theframe = document.getElementById("vpsadmin-console-frame");
_theframe.contentWindow.location.href = _theframe.src;
</script>
'
	);

	$xtpl->assign('AJAX_SCRIPT', $xtpl->vars['AJAX_SCRIPT'] . '
<script type="text/javascript">
function vps_do(cmd) {
	apiClient.after("authenticated", function() {
		apiClient.vps[cmd]('.$vps->id.', function(c, reply) {
			if (!reply.isOk())
				alert(cmd + " failed: " + reply.apiResponse().message());
		});
	});
}
</script>
');
	$xtpl->sbar_add('<img src="template/icons/vps_start.png"  title="'._("Start").'" /> ' . _("Start"), "javascript:vps_do('start');");
	$xtpl->sbar_add('<img src="template/icons/vps_stop.png"  title="'._("Stop").'" /> ' . _("Stop"), "javascript:vps_do('stop');");
	$xtpl->sbar_add('<img src="template/icons/vps_restart.png"  title="'._("Restart").'" /> ' . _("Restart"), "javascript:vps_do('restart');");
	$xtpl->sbar_out(_("Manage VPS"));
}

if ($_SESSION["logged_in"]) {
	csrf_check();
	setup_console();

} else {
	$xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
}
