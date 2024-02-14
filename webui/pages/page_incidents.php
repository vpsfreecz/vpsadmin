<?php

if (isLoggedIn()) {
    switch ($_GET['action']) {
        case 'list':
            incident_list();

            if ($_GET['return']) {
                $xtpl->sbar_add(_('Back'), $_GET['return']);
            }

            break;

        case 'show':
            incident_show($_GET['id']);
            $xtpl->sbar_add(_('Back'), '?page=incidents&action=list');
            break;

        case 'new':
            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();

                $params = [
                    'vps' => $_GET['vps'],
                    'subject' => $_POST['subject'],
                    'text' => $_POST['text'],
                    'codename' => $_POST['codename'] ? $_POST['codename'] : null,
                    'detected_at' => date('c', strtotime($_POST['detected_at'])),
                ];

                if ($_POST['ip_address_assignment']) {
                    $params['ip_address_assignment'] = $_POST['ip_address_assignment'];
                }

                if ($_POST['cpu_limit']) {
                    $params['cpu_limit'] = $_POST['cpu_limit'];
                }

                try {
                    $api->incident_report->create($params);

                    notify_user(_('Incident report sent'), '');
                    redirect('?page=adminvps&action=show&veid=' . $_GET['vps']);
                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Incident report save failed'), $e->getResponse());
                    incident_new($_GET['vps']);
                }
            } else {
                incident_new($_GET['vps']);
            }
            $xtpl->sbar_add(_('Back'), '?page=adminvps&action=info&veid=' . $_GET['vps']);
            break;

        default:
            break;
    }

    $xtpl->sbar_out(_('Incident reports'));

} else {
    $xtpl->perex(
        _("Access forbidden"),
        _("You have to log in to be able to access vpsAdmin's functions")
    );
}
