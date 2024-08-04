<?php

if (isLoggedIn()) {
    switch ($_GET['to']) {
        case 'payset':
            switch ($_GET['from']) {
                case 'payment':
                    $p = $api->user_payment->show($_GET['id']);
                    redirect('?page=adminm&action=payset&id=' . $p->user_id);
                    break;
            }
            break;

        case 'ip_address':
            switch ($_GET['from']) {
                case 'host_ip_address':
                    $hostIp = $api->host_ip_address->show($_GET['id']);
                    redirect('?page=networking&action=route_edit&id=' . $hostIp->ip_address_id);
                    break;
            }
            break;
    }

    $xtpl->perex(_('Redirect failed'), _('The redirect request was invalid.'));

} else {
    $xtpl->perex(
        _("Access forbidden"),
        _("You have to log in to be able to access vpsAdmin's functions")
    );
}
