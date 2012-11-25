<?php

if ($_SESSION["logged_in"]) {
	$vps = vps_load($_GET["veid"]);
	
	if($vps->exists) {
		if ($session = $vps->create_console_session()) {
			$xtpl->perex(_('Remote Console for VPS #' . $vps->veid),'
				<iframe src="'. $vps->get_console_server() .'/console/'.$vps->veid.'?session='.$session.'" width="100%" height="500px" border="1"></iframe>
			');
			
			$xtpl->assign('AJAX_SCRIPT', $xtpl->vars['AJAX_SCRIPT'] . '
<script type="text/javascript">
function ajax_vps(cmd) {
	var myRequest = new Request({
		method: \'get\',
		url: \'ajax.php?page=vps&action=\' + cmd + \'&veid='.$vps->veid.'\'
	});
	myRequest.send();
}
</script>
');
			$xtpl->sbar_add('<img src="template/icons/vps_start.png"  title="'._("Start").'" /> ' . _("Start"), "javascript:ajax_vps('start');");
			$xtpl->sbar_add('<img src="template/icons/vps_stop.png"  title="'._("Stop").'" /> ' . _("Stop"), "javascript:ajax_vps('stop');");
			$xtpl->sbar_add('<img src="template/icons/vps_restart.png"  title="'._("Restart").'" /> ' . _("Restart"), "javascript:ajax_vps('restart');");
			$xtpl->sbar_out(_("Manage VPS"));
		} else $xtpl->perex(_("Failed to create session"), '');
	} else {
		$xtpl->perex(_("Access forbidden"), _("You have no access to this VPS."));
	}
} else {
	$xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
}
