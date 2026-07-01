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

        case 'targets':
            notifications_targets(api_get_uint('user'));
            break;

        case 'target_new':
            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();

                $receiver_id = api_get_uint('receiver');
                $receiver = $receiver_id ? $api->notification_receiver->show($receiver_id) : null;
                $user_id = $receiver ? $receiver->user_id : notifications_target_user_id();
                $action_type = notifications_target_type_from_request($user_id);

                if ($action_type === null) {
                    $xtpl->perex(_('Failed to add target'), _('Invalid target type'));
                    notifications_target_new($user_id, null, $receiver_id);
                    break;
                }

                try {
                    $params = notifications_target_params($action_type, true);
                    if (isAdmin()) {
                        $params['user'] = $user_id;
                    }

                    $target = $api->notification_target->create($params);
                    if ($receiver) {
                        $receiver->target->create([
                            'notification_target_id' => $target->id,
                        ]);
                    }

                    notify_user(_('Target added'), '');
                    $show_target_detail = $action_type === 'telegram'
                        || $action_type === 'sms'
                        || ($action_type === 'email' && ($params['target_kind'] ?? null) === 'custom');
                    if ($show_target_detail) {
                        redirect(notifications_target_url($target->id, $user_id, $receiver ? $receiver->id : null));
                    }

                    if ($receiver) {
                        redirect(notifications_receiver_url($receiver->id, $receiver->user_id));
                    }

                    redirect('?page=notifications&action=targets' . notifications_user_qs($user_id));
                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Failed to add target'), $e->getResponse());
                    notifications_target_new($user_id, api_post('action_type') ?: api_get('type'), $receiver_id);
                }
            } else {
                notifications_target_new(api_get_uint('user'), api_get('type'), api_get_uint('receiver'));
            }
            break;

        case 'target_edit':
            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();
                $receiver_id = api_get_uint('receiver');

                try {
                    $target = $api->notification_target->show($_GET['id']);
                    $receiver = notifications_target_context_receiver($target, $receiver_id);
                    $params = notifications_target_params($target->action);
                    $api->notification_target->update($target->id, $params);

                    notify_user(_('Target updated'), '');
                    $show_target_detail = $target->action === 'telegram'
                        || $target->action === 'sms'
                        || ($target->action === 'email' && ($params['target_kind'] ?? null) === 'custom');
                    if ($show_target_detail) {
                        redirect(notifications_target_url($target->id, $target->user_id, $receiver ? $receiver->id : null));
                    }

                    if ($receiver) {
                        redirect(notifications_receiver_url($receiver->id, $receiver->user_id));
                    }

                    redirect('?page=notifications&action=targets' . notifications_user_qs($target->user_id));
                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Failed to update target'), $e->getResponse());
                    notifications_target_edit($_GET['id'], $receiver_id);
                }
            } else {
                notifications_target_edit($_GET['id'], api_get_uint('receiver'));
            }
            break;

        case 'target_toggle':
            csrf_check();

            try {
                $target = $api->notification_target->show($_GET['id']);
                $api->notification_target->update($target->id, [
                    'enabled' => !$target->enabled,
                ]);

                notify_user(_('Target updated'), '');
                redirect('?page=notifications&action=targets' . notifications_user_qs($target->user_id));
            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to update target'), $e->getResponse());
                notifications_targets(api_get_uint('user'));
            }
            break;

        case 'target_pairing_token':
            csrf_check();
            $receiver_id = api_get_uint('receiver');

            try {
                $target = $api->notification_target->show($_GET['id']);
                $api->notification_target($target->id)->create_pairing_token();

                notify_user(_('Pairing command created'), '');
                redirect(notifications_target_url($target->id, $target->user_id, $receiver_id));
            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to create pairing token'), $e->getResponse());
                notifications_target_edit($_GET['id'], $receiver_id);
            }
            break;

        case 'target_email_send':
            csrf_check();
            $receiver_id = api_get_uint('receiver');

            try {
                $target = $api->notification_target->show($_GET['id']);
                $api->notification_target($target->id)->send_email_verification();

                notify_user(_('Verification e-mail sent'), '');
                redirect(notifications_target_url($target->id, $target->user_id, $receiver_id));
            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to send verification e-mail'), $e->getResponse());
                notifications_target_edit($_GET['id'], $receiver_id);
            }
            break;

        case 'target_email_confirm':
            $receiver_id = api_get_uint('receiver');

            try {
                $target = $api->notification_target->show($_GET['id']);
                $api->notification_target($target->id)->confirm_email_verification([
                    'token' => api_get('token'),
                ]);

                notify_user(_('E-mail address verified'), '');
                redirect(notifications_target_url($target->id, $target->user_id, $receiver_id));
            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to verify e-mail address'), $e->getResponse());
                notifications_target_edit($_GET['id'], $receiver_id);
            }
            break;

        case 'target_sms_send':
            csrf_check();
            $receiver_id = api_get_uint('receiver');

            try {
                $target = $api->notification_target->show($_GET['id']);
                $api->notification_target($target->id)->send_sms_verification_code();

                notify_user(_('Verification SMS sent'), '');
                redirect(notifications_target_url($target->id, $target->user_id, $receiver_id));
            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to send verification SMS'), $e->getResponse());
                notifications_target_edit($_GET['id'], $receiver_id);
            }
            break;

        case 'target_sms_confirm':
            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();
                $receiver_id = api_get_uint('receiver');

                try {
                    $target = $api->notification_target->show($_GET['id']);
                    $api->notification_target($target->id)->confirm_sms_verification_code([
                        'code' => api_post('code'),
                    ]);

                    notify_user(_('Phone number verified'), '');
                    redirect(notifications_target_url($target->id, $target->user_id, $receiver_id));
                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Failed to verify phone number'), $e->getResponse());
                    notifications_target_edit($_GET['id'], $receiver_id);
                }
            } else {
                notifications_target_edit($_GET['id'], api_get_uint('receiver'));
            }
            break;

        case 'target_delete':
            csrf_check();

            try {
                $target = $api->notification_target->show($_GET['id']);
                $api->notification_target->delete($target->id);

                notify_user(_('Target deleted'), '');
                redirect('?page=notifications&action=targets' . notifications_user_qs($target->user_id));
            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to delete target'), $e->getResponse());
                notifications_targets(api_get_uint('user'));
            }
            break;

        case 'receiver_target_link':
            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();

                try {
                    $receiver = $api->notification_receiver->show($_GET['receiver']);
                    $receiver->target->create(notifications_receiver_target_params(true));

                    notify_user(_('Target linked'), '');
                    redirect(notifications_receiver_url($receiver->id, $receiver->user_id));
                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Failed to link target'), $e->getResponse());
                    notifications_receiver_edit($_GET['receiver']);
                }
            } else {
                notifications_receiver_edit($_GET['receiver']);
            }
            break;

        case 'receiver_target_delete':
            csrf_check();

            try {
                $receiver = $api->notification_receiver->show($_GET['receiver']);
                $receiver->target->delete($_GET['id']);

                notify_user(_('Target unlinked'), '');
                redirect(notifications_receiver_url($receiver->id, $receiver->user_id));
            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to unlink target'), $e->getResponse());
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

        case 'limits':
            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();

                if (!isAdmin()) {
                    notify_user(_('Access denied'), _('Only administrators can update delivery limits.'));
                    redirect('?page=notifications&action=limits');
                }

                $user_id = notifications_target_user_id();
                $user = $api->user->show($user_id);

                try {
                    foreach (notifications_rate_limits_for_user($user) as $limit) {
                        $name = notifications_rate_limit_post_name($limit);
                        if (!isset($_POST[$name])) {
                            continue;
                        }

                        $limit_count = (int) $_POST[$name];
                        if ($limit_count < 1) {
                            throw new \InvalidArgumentException(_('Limits must be positive integers.'));
                        }

                        if ($limit_count !== (int) $limit->limit_count) {
                            $api->user($user_id)->notification_rate_limit($limit->id)->update([
                                'limit_count' => $limit_count,
                            ]);
                        }
                    }

                    notify_user(_('Delivery limits updated'), '');
                    redirect('?page=notifications&action=limits' . notifications_user_qs($user_id));
                } catch (\InvalidArgumentException $e) {
                    $xtpl->perex(_('Failed to update delivery limits'), h($e->getMessage()));
                    notifications_rate_limits($user_id);
                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Failed to update delivery limits'), $e->getResponse());
                    notifications_rate_limits($user_id);
                }
            } else {
                notifications_rate_limits(api_get_uint('user'));
            }
            break;

        case 'test':
            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();
                $params = [
                    'event_type' => api_post('event_type'),
                    'subject' => api_post('subject'),
                    'summary' => api_post('summary'),
                    'payload_json' => api_post('payload_json'),
                ];

                if (isAdmin()) {
                    $params['user'] = notifications_target_user_id();
                    $params['subject_scope'] = api_post('subject_scope');
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
