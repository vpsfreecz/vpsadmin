<?php

if (isLoggedIn()) {
    switch ($_GET['action'] ?? 'events') {
        case 'rules':
            redirect('?page=notifications&action=routes' . notifications_user_qs(api_get_uint('user')));
            break;

        case 'endpoints':
            redirect('?page=notifications&action=receivers' . notifications_user_qs(api_get_uint('user')));
            break;

        case 'routes':
            notifications_routes_list(api_get_uint('user'));
            break;

        case 'route_new':
            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();
                $user_id = notifications_target_user_id();

                try {
                    $route = $api->event_route->create(notifications_route_params(true));

                    notify_user(_('Route added'), '');
                    redirect('?page=notifications&action=route_edit&id=' . $route->id . notifications_user_qs($user_id));
                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Failed to add route'), $e->getResponse());
                    notifications_route_new($user_id, notifications_nullable_id('parent_id'));
                }
            } else {
                notifications_route_new(api_get_uint('user'), api_get_uint('parent'));
            }
            break;

        case 'route_edit':
            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();

                try {
                    $api->event_route->update($_GET['id'], notifications_route_params());

                    notify_user(_('Route updated'), '');
                    redirect('?page=notifications&action=route_edit&id=' . $_GET['id'] . notifications_user_qs());
                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Failed to update route'), $e->getResponse());
                    notifications_route_edit($_GET['id']);
                }
            } else {
                notifications_route_edit($_GET['id']);
            }
            break;

        case 'route_delete':
            csrf_check();

            try {
                $route = $api->event_route->show($_GET['id']);
                $api->event_route->delete($_GET['id']);

                notify_user(_('Route deleted'), '');
                redirect('?page=notifications&action=routes' . notifications_user_qs($route->user_id));
            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to delete route'), $e->getResponse());
                notifications_routes_list(api_get_uint('user'));
            }
            break;

        case 'route_toggle':
            csrf_check();

            try {
                $route = $api->event_route->show($_GET['id']);
                $api->event_route->update($route->id, [
                    'enabled' => !$route->enabled,
                ]);

                notify_user(_('Route updated'), '');
                redirect('?page=notifications&action=routes' . notifications_user_qs($route->user_id));
            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to update route'), $e->getResponse());
                notifications_routes_list(api_get_uint('user'));
            }
            break;

        case 'route_move':
            csrf_check();

            try {
                $user_id = notifications_route_move($_GET['id'], $_GET['direction']);
                redirect('?page=notifications&action=routes' . notifications_user_qs($user_id));
            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to reorder routes'), $e->getResponse());
                notifications_routes_list(api_get_uint('user'));
            }
            break;

        case 'route_reorder':
            csrf_check();

            $user_id = notifications_target_user_id();

            try {
                $reordered = $user_id && notifications_route_reorder(
                    $user_id,
                    notifications_nullable_id('parent_id'),
                    notifications_posted_ids()
                );
            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                if (notifications_is_ajax()) {
                    notifications_ajax_response(false, _('Failed to reorder routes'));
                }

                $xtpl->perex_format_errors(_('Failed to reorder routes'), $e->getResponse());
                $reordered = false;
            }

            if (!$reordered) {
                if (notifications_is_ajax()) {
                    notifications_ajax_response(false, _('Invalid route order'));
                }

                $xtpl->perex(_('Failed to reorder routes'), _('Invalid route order'));
                notifications_routes_list($user_id);
            } else {
                if (notifications_is_ajax()) {
                    notifications_ajax_response(true);
                }

                redirect('?page=notifications&action=routes' . notifications_user_qs($user_id));
            }
            break;

        case 'matcher_new':
            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();

                try {
                    $route = $api->event_route->show($_GET['route']);
                    $route->matcher->create(notifications_matcher_new_params());

                    notify_user(_('Matcher added'), '');
                    redirect('?page=notifications&action=route_edit&id=' . $route->id . notifications_user_qs($route->user_id));
                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Failed to add matcher'), $e->getResponse());
                    notifications_matcher_new($_GET['route'], api_get('event_type'));
                }
            } else {
                notifications_matcher_new($_GET['route'], api_get('event_type'));
            }
            break;

        case 'matcher_save':
            csrf_check();

            try {
                $route = $api->event_route->show($_GET['route']);

                if (isset($_POST['add_matcher'])) {
                    $route->matcher->create(notifications_matcher_new_params());
                    notify_user(_('Matcher added'), '');
                } elseif (isset($_POST['save_matchers']) && isset($_POST['matchers']) && is_array($_POST['matchers'])) {
                    foreach ($_POST['matchers'] as $id => $row) {
                        if (!ctype_digit((string) $id) || !is_array($row)) {
                            continue;
                        }

                        $route->matcher->update($id, notifications_matcher_params_from_row($row));
                    }

                    notify_user(_('Matchers updated'), '');
                }

                redirect('?page=notifications&action=route_edit&id=' . $route->id . notifications_user_qs($route->user_id));
            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to save matchers'), $e->getResponse());
                notifications_route_edit($_GET['route']);
            }
            break;

        case 'matcher_delete':
            csrf_check();

            try {
                $route = $api->event_route->show($_GET['route']);
                $route->matcher->delete($_GET['id']);

                notify_user(_('Matcher deleted'), '');
                redirect('?page=notifications&action=route_edit&id=' . $route->id . notifications_user_qs($route->user_id));
            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to delete matcher'), $e->getResponse());
                notifications_route_edit($_GET['route']);
            }
            break;

        case 'receivers':
            notifications_receivers(api_get_uint('user'));
            break;

        case 'receiver_new':
            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();
                $user_id = notifications_target_user_id();

                try {
                    $api->notification_receiver->create(notifications_receiver_params(true));

                    notify_user(_('Receiver added'), '');
                    redirect('?page=notifications&action=receivers' . notifications_user_qs($user_id));
                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Failed to add receiver'), $e->getResponse());
                    notifications_receivers($user_id);
                }
            } else {
                notifications_receivers(api_get_uint('user'));
            }
            break;

        case 'receiver_edit':
            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();

                try {
                    $receiver = $api->notification_receiver->show($_GET['id']);
                    $api->notification_receiver->update($receiver->id, notifications_receiver_params());

                    notify_user(_('Receiver updated'), '');
                    redirect('?page=notifications&action=receiver_edit&id=' . $receiver->id . notifications_user_qs($receiver->user_id));
                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Failed to update receiver'), $e->getResponse());
                    notifications_receiver_edit($_GET['id']);
                }
            } else {
                notifications_receiver_edit($_GET['id']);
            }
            break;

        case 'receiver_toggle':
            csrf_check();

            try {
                $receiver = $api->notification_receiver->show($_GET['id']);
                $api->notification_receiver->update($receiver->id, [
                    'enabled' => !$receiver->enabled,
                ]);

                notify_user(_('Receiver updated'), '');
                redirect('?page=notifications&action=receivers' . notifications_user_qs($receiver->user_id));
            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to update receiver'), $e->getResponse());
                notifications_receivers(api_get_uint('user'));
            }
            break;

        case 'receiver_delete':
            csrf_check();

            try {
                $receiver = $api->notification_receiver->show($_GET['id']);
                $api->notification_receiver->delete($receiver->id);

                notify_user(_('Receiver deleted'), '');
                redirect('?page=notifications&action=receivers' . notifications_user_qs($receiver->user_id));
            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to delete receiver'), $e->getResponse());
                notifications_receivers(api_get_uint('user'));
            }
            break;

        case 'receiver_action_save':
            csrf_check();

            try {
                $receiver = $api->notification_receiver->show($_GET['receiver']);
                redirect('?page=notifications&action=receiver_edit&id=' . $receiver->id . notifications_user_qs($receiver->user_id));
            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to update action'), $e->getResponse());
                notifications_receiver_edit($_GET['receiver']);
            }
            break;

        case 'receiver_action_new':
            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();

                try {
                    $receiver = $api->notification_receiver->show($_GET['receiver']);
                    $action_type = notifications_receiver_action_type_from_request($receiver);

                    if ($action_type === null) {
                        $xtpl->perex(_('Failed to add action'), _('Invalid action type'));
                        notifications_receiver_action_new($receiver->id);
                        break;
                    }

                    $receiver->action->create(notifications_receiver_action_params($action_type, true));

                    notify_user(_('Action added'), '');
                    redirect('?page=notifications&action=receiver_edit&id=' . $receiver->id . notifications_user_qs($receiver->user_id));
                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Failed to add action'), $e->getResponse());
                    notifications_receiver_action_new($_GET['receiver'], api_post('action_type') ?: api_get('type'));
                }
            } else {
                notifications_receiver_action_new($_GET['receiver'], api_get('type'));
            }
            break;

        case 'receiver_action_edit':
            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();

                try {
                    $receiver = $api->notification_receiver->show($_GET['receiver']);
                    $action = $receiver->action->show($_GET['id']);
                    $receiver->action->update($action->id, notifications_receiver_action_params($action->action));

                    notify_user(_('Action updated'), '');
                    redirect('?page=notifications&action=receiver_edit&id=' . $receiver->id . notifications_user_qs($receiver->user_id));
                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Failed to update action'), $e->getResponse());
                    notifications_receiver_action_edit($_GET['receiver'], $_GET['id']);
                }
            } else {
                notifications_receiver_action_edit($_GET['receiver'], $_GET['id']);
            }
            break;

        case 'receiver_action_delete':
            csrf_check();

            try {
                $receiver = $api->notification_receiver->show($_GET['receiver']);
                $receiver->action->delete($_GET['id']);

                notify_user(_('Action deleted'), '');
                redirect('?page=notifications&action=receiver_edit&id=' . $receiver->id . notifications_user_qs($receiver->user_id));
            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to delete action'), $e->getResponse());
                notifications_receiver_edit($_GET['receiver']);
            }
            break;

        case 'events':
            notifications_events();
            break;

        case 'delivery_queue':
            notifications_deliveries_admin('queue');
            break;

        case 'delivery_log':
            notifications_deliveries_admin('log');
            break;

        case 'event_show':
            notifications_event_show($_GET['id']);
            break;

        case 'delivery_show':
            notifications_delivery_show(api_get_uint('event'), api_get_uint('id'));
            break;

        case 'delivery_retry':
            csrf_check();

            $event_id = api_get_uint('event');
            $delivery_id = api_get_uint('id');

            try {
                $event = $api->event->show($event_id);
                $event->delivery($delivery_id)->retry();

                notify_user(_('Delivery retry scheduled'), '');
                redirect(notifications_delivery_url($event_id, $delivery_id));
            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to retry delivery'), $e->getResponse());
                notifications_delivery_show($event_id, $delivery_id);
            }
            break;

        case 'event_types':
            notifications_event_types(api_get_uint('user'));
            break;

        case 'test':
            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();
                $params = [
                    'event_type' => api_post('event_type'),
                    'subject' => api_post('subject'),
                    'summary' => api_post('summary'),
                    'parameters_json' => api_post('parameters_json'),
                ];

                if (isAdmin()) {
                    $params['user'] = notifications_target_user_id();
                }

                try {
                    $event = $api->event->test($params);

                    notify_user(_('Test event created'), '');
                    redirect('?page=notifications&action=event_show&id=' . $event->id);
                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Failed to create test event'), $e->getResponse());
                    notifications_test_event(notifications_target_user_id());
                }
            } else {
                notifications_test_event(api_get_uint('user'));
            }
            break;

        default:
            notifications_events();
    }

    $xtpl->sbar_out(_('Notifications'));
} else {
    $xtpl->perex(
        _('Access forbidden'),
        _("You have to log in to be able to access vpsAdmin's functions")
    );
}
