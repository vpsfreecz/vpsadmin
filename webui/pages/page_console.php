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
		'<iframe src="'.$server.'/console/'.$vps->id.'?token='.$_SESSION['session_token'].'&session='.$t->token.'" width="100%" height="500px" border="1" id="vpsadmin-console-frame"></iframe>
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
function vps_passwd(cmd) {
	apiClient.after("authenticated", function() {
		apiClient.vps.passwd(
			'.$vps->id.',
			{
				params: {type: "simple"},
				onReply: function(c, reply) {
					if (reply.isOk()) {
						$("#root-password").text("configuring password...");
					} else {
						alert("Password change failed: " + reply.message());
					}
				},
				onDone: function(c, reply) {
					if (reply.isOk()) {
						$("#root-password").text(reply.response().password);
					} else {
						alert("Password change failed: " + reply.message());
					}
				},
			}
		);
	});
}
function vps_boot(cmd) {
	apiClient.after("authenticated", function() {
		var tpl = $("select[name=\"os_template\"]").val();
		var mnt = $("input[name=\"root_mountpoint\"]").val();

		apiClient.vps.boot(
			'.$vps->id.',
			{
				params: {os_template: tpl, mount_root_dataset: mnt},
				onReply: function(c, reply) {
					if (reply.isOk()) {
						$("#boot-button").text("'._('Booting...').'")
					} else {
						alert("Boot failed: " + reply.apiResponse().message());
					}
				},
				onDone: function(c, reply) {
					if (reply.isOk()) {
						$("#boot-button").text("'._('Boot').'")
					} else {
						alert("Boot failed: " + reply.apiResponse().message());
					}
				},
			}
		);
	});
}
</script>
');
	$xtpl->sbar_add('<img src="template/icons/vps_start.png"  title="'._("Start").'" /> ' . _("Start"), "javascript:vps_do('start');");
	$xtpl->sbar_add('<img src="template/icons/vps_stop.png"  title="'._("Stop").'" /> ' . _("Stop"), "javascript:vps_do('stop');");
	$xtpl->sbar_add('<img src="template/icons/vps_restart.png"  title="'._("Restart").'" /> ' . _("Restart"), "javascript:vps_do('restart');");

	$xtpl->sbar_add_fragment(
		'<h3>'._('Set password').'</h3>'.
		'<table>'.
		'<tr><td>'._('User').': </td><td>root</td></tr>'.
		'<tr>'.
		'<td>'._('Password').': </td>'.
		'<td><span id="root-password">'._('will be generated').'</span></td>'.
		'</tr><tr><td colspan="2"><strong>'._('Change the password to something secure when finished!').'</strong></td></tr>'.
		'<tr>'.
		'<td></td><td><button onclick="vps_passwd();">'._('Generate password').'</button></td>'.
		'</tr></table>'
	);

	if ($vps->node->hypervisor_type == "vpsadminos") {
		$os_templates = list_templates($vps);

		$xtpl->sbar_add_fragment(
			'<h3>'._('Rescue mode').'</h3>'.
			'<table>'.
			'<tr>'.
			'<td>'._('Distribution').': </td>'.
			'<td>'.$xtpl->form_select_html('os_template', $os_templates, $vps->os_template_id).'</td>'.
			'</tr><tr>'.
			'<td>'._('Root dataset mountpoint').': </td>'.
			'<td><input type="text" name="root_mountpoint" value="/mnt/vps"></td>'.
			'</tr><tr>'.
			'<td></td><td><button id="boot-button" onclick="vps_boot();">'._('Boot').'</button></td>'.
			'</tr></table>'
		);
	}

	$xtpl->sbar_out(_("Manage VPS"));
}

if ($_SESSION["logged_in"]) {
	csrf_check();
	setup_console();

} else {
	$xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
}
