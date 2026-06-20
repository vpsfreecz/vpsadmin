<?php

function oom_reports_redirect_to_notifications($vps_id = null)
{
    global $api;

    $user_id = null;

    if ($vps_id) {
        $vps = $api->vps->show($vps_id);
        $user_id = $vps->user_id;
    }

    notify_user(
        _('OOM report rules moved'),
        _('OOM report delivery and suppression are configured using notification routes.')
    );
    redirect('?page=notifications&action=routes' . notifications_user_qs($user_id));
}

if (isLoggedIn()) {
    switch ($_GET['action'] ?? null) {
        case 'show':
            oom_reports_show($_GET['id']);
            break;

        case 'rule_list':
            oom_reports_redirect_to_notifications(api_get_uint('vps'));
            break;

        case 'rule_new':
            oom_reports_redirect_to_notifications(api_get_uint('vps'));
            break;

        case 'rule_edit':
            oom_reports_redirect_to_notifications(api_get_uint('vps'));
            break;

        case 'rule_delete':
            oom_reports_redirect_to_notifications(api_get_uint('vps'));
            break;

        case 'list':
        default:
            oom_reports_list();
    }

    $xtpl->sbar_out(_('OOM Reports'));

} else {
    $xtpl->perex(
        _("Access forbidden"),
        _("You have to log in to be able to access vpsAdmin's functions")
    );
}
