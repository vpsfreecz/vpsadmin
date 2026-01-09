<?php

function setup_vnc_console()
{
    global $xtpl, $api;

    try {
        $vps = $api->vps->find($_GET['veid'], [
            'meta' => ['includes' => 'node__location'],
        ]);

    } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
        $xtpl->perex_format_errors(_('VPS not found'), $e->getResponse());
        return;
    }

    if ($vps->vm_type != 'qemu_full') {
        $xtpl->perex(
            _('VNC console unavailable'),
            _('This VPS uses remote console access instead of VNC.')
        );
        return;
    }

    try {
        $token = $vps->vnc_token->create();

    } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
        $xtpl->perex_format_errors(_('Unable to acquire VNC token'), $e->getResponse());
        return;
    }

    $server = $vps->node->location->remote_vnc_server;

    if (!$server) {
        $xtpl->perex(_('No VNC server available'), _('There is no VNC server for this location.'));
        return;
    }

    $query = http_build_query([
        'client_token' => $token->client_token,
        'auth_type' => $_SESSION['auth_type'],
        'auth_token' => getAuthenticationToken(),
        'api_url' => EXT_API_URL,
        'api_version' => API_VERSION,
    ]);

    $url = rtrim($server, '/') . '/console?' . $query;
    $popup_features = 'noopener,noreferrer,toolbar=no,menubar=no,location=no,status=no,scrollbars=yes,resizable=yes,width=1200,height=900';

    $xtpl->perex(
        _('VNC console for VPS') . ' <a href="?page=adminvps&action=info&veid=' . $vps->id . '">#' . $vps->id . '</a>',
        '<p>' . _('Opening VNC console in a new window...') . '</p>'
        . '<p id="vnc-popup-note">' . _('If nothing opened, your browser may have blocked the popup. Use the button below.') . '</p>'
        . '<p><a id="vnc-fallback" href="' . h($url) . '" target="_blank" rel="noopener noreferrer">' . _('Open VNC console') . '</a></p>'
        . '<script type="text/javascript">
(function() {
    var url = ' . json_encode($url) . ';
    var popup = window.open(url, "_blank", ' . json_encode($popup_features) . ');

    if (popup) {
        popup.focus();
        var note = document.getElementById("vnc-popup-note");
        if (note) {
            note.style.display = "none";
        }
    }
})();
</script>'
    );

    $xtpl->sbar_add('<img src="template/icons/vps_restart.png" title="' . _("Restart") . '" /> ' . _("Restart"), '?page=adminvps&action=info&run=restart&veid=' . $vps->id . '&t=' . csrf_token());
    $xtpl->sbar_add('<img src="template/icons/vps_stop.png" title="' . _("Stop") . '" /> ' . _("Stop"), '?page=adminvps&action=info&run=stop&veid=' . $vps->id . '&t=' . csrf_token());
    $xtpl->sbar_add('<img src="template/icons/vps_start.png" title="' . _("Start") . '" /> ' . _("Start"), '?page=adminvps&action=info&run=start&veid=' . $vps->id . '&t=' . csrf_token());
    $xtpl->sbar_out(_("Manage VPS"));
}

if (isLoggedIn()) {
    csrf_check();
    setup_vnc_console();

} else {
    $xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
}
