<?php

function security_advisory_params()
{
    global $api;

    $params = [
        'name' => $_POST['name'],
        'published_at' => security_advisory_datetime_param('published_at'),
    ];

    foreach ($api->language->list() as $lang) {
        foreach (['summary', 'description', 'response'] as $field) {
            $key = $lang->code . '_' . $field;
            $params[$key] = $_POST[$key] ?? '';
        }
    }

    return $params;
}

function security_advisory_save_nodes($id)
{
    global $api;

    $statuses = [];
    foreach ($api->security_advisory($id)->node_status->list() as $status) {
        $statuses[$status->node_id] = $status;
    }

    foreach (security_advisory_nodes() as $node) {
        $prefix = 'node_' . $node->id;
        $state = $_POST[$prefix . '_state'];
        $params = [
            'state' => $state,
            'vulnerable_until' => $state === 'not_affected' ? null : security_advisory_datetime_param($prefix . '_vulnerable_until'),
            'mitigated_since' => $state === 'not_affected' ? null : security_advisory_datetime_param($prefix . '_mitigated_since'),
            'note' => $_POST[$prefix . '_note'] ?: null,
        ];

        if (isset($statuses[$node->id])) {
            $api->security_advisory($id)->node_status->update($statuses[$node->id]->id, $params);
        } else {
            $params['node'] = $node->id;
            $api->security_advisory($id)->node_status->create($params);
        }
    }
}

function security_advisory_datetime_param($name)
{
    $value = trim($_POST[$name] ?? '');
    if ($value === '') {
        return null;
    }

    if (preg_match('/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}(:\d{2})?$/', $value)) {
        $ts = strtotime($value);
        if ($ts !== false) {
            return date('c', $ts);
        }
    }

    return $value;
}

function security_advisory_update_params($id)
{
    $params = [
        'security_advisory' => $id,
        'send_mail' => isset($_POST['send_mail']),
        'published_at' => security_advisory_datetime_param('published_at'),
    ];

    if (!empty($_POST['state'])) {
        $params['state'] = $_POST['state'];
    }

    return array_merge($params, security_advisory_update_text_params());
}

function security_advisory_update_text_params()
{
    global $api;

    $params = [];

    foreach ($api->language->list() as $lang) {
        foreach (['summary', 'message'] as $field) {
            $key = $lang->code . '_' . $field;
            $params[$key] = $_POST[$key] ?? '';
        }
    }

    return $params;
}

switch ($_GET['action'] ?? 'list') {
    case 'new':
        if (isAdmin()) {
            security_advisory_sbar();

            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();

                try {
                    $cves = security_advisory_parse_cves($_POST['cves'] ?? '');
                    $advisory = $api->security_advisory->create(security_advisory_params());
                    security_advisory_save_cves($advisory->id, $cves);
                    security_advisory_save_nodes($advisory->id);
                    redirect('?page=security_advisory&action=show&id=' . $advisory->id);
                } catch (\InvalidArgumentException $e) {
                    $xtpl->perex(_('Create failed'), h($e->getMessage()));
                    security_advisory_form();
                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Create failed'), $e->getResponse());
                    security_advisory_form();
                }
            } else {
                security_advisory_form();
            }
        }
        break;

    case 'edit':
        if (isAdmin()) {
            security_advisory_sbar($_GET['id']);

            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();

                try {
                    $cves = security_advisory_parse_cves($_POST['cves'] ?? '');
                    $api->security_advisory->update($_GET['id'], security_advisory_params());
                    security_advisory_save_cves($_GET['id'], $cves);
                    redirect('?page=security_advisory&action=show&id=' . $_GET['id']);
                } catch (\InvalidArgumentException $e) {
                    $xtpl->perex(_('Update failed'), h($e->getMessage()));
                    security_advisory_form($_GET['id']);
                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Update failed'), $e->getResponse());
                    security_advisory_form($_GET['id']);
                }
            } else {
                security_advisory_form($_GET['id']);
            }
        }
        break;

    case 'nodes':
        if (isAdmin()) {
            security_advisory_sbar($_GET['id']);

            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();

                try {
                    security_advisory_save_nodes($_GET['id']);
                    redirect('?page=security_advisory&action=show&id=' . $_GET['id']);
                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Update failed'), $e->getResponse());
                    security_advisory_node_form($_GET['id']);
                }
            } else {
                security_advisory_node_form($_GET['id']);
            }
        }
        break;

    case 'publish':
        if (isAdmin() && $_SERVER['REQUEST_METHOD'] === 'POST') {
            csrf_check();

            try {
                $api->security_advisory->publish($_GET['id'], [
                    'send_mail' => isset($_POST['send_mail']),
                    'published_at' => security_advisory_datetime_param('published_at'),
                ]);
                redirect('?page=security_advisory&action=show&id=' . $_GET['id']);
            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Publish failed'), $e->getResponse());
                security_advisory_details($_GET['id']);
            }
        }
        break;

    case 'rebuild':
        if (isAdmin()) {
            csrf_check();
            $api->security_advisory->rebuild_affected_vps($_GET['id']);
            redirect('?page=security_advisory&action=show&id=' . $_GET['id']);
        }
        break;

    case 'update':
        if (isAdmin()) {
            security_advisory_sbar($_GET['id']);

            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();

                try {
                    $api->security_advisory_update->create(security_advisory_update_params($_GET['id']));
                    redirect('?page=security_advisory&action=show&id=' . $_GET['id']);
                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Update failed'), $e->getResponse());
                    security_advisory_update_form($_GET['id']);
                }
            } else {
                security_advisory_update_form($_GET['id']);
            }
        }
        break;

    case 'edit_update':
        if (isAdmin()) {
            security_advisory_sbar($_GET['id']);

            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();

                try {
                    $api->security_advisory_update->update($_GET['update'], security_advisory_update_text_params());
                    notify_user(_('Update saved'), _('The security advisory update was successfully saved.'));
                    redirect('?page=security_advisory&action=show&id=' . $_GET['id']);
                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Save failed'), $e->getResponse());
                    security_advisory_update_form($_GET['id'], $_GET['update']);
                }
            } else {
                security_advisory_update_form($_GET['id'], $_GET['update']);
            }
        }
        break;

    case 'delete_update':
        if (isAdmin() && $_SERVER['REQUEST_METHOD'] === 'POST') {
            csrf_check();

            try {
                $api->security_advisory_update->delete($_GET['update']);
                notify_user(_('Update deleted'), _('The security advisory update was successfully deleted.'));
                redirect('?page=security_advisory&action=show&id=' . $_GET['id']);
            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Delete failed'), $e->getResponse());
                security_advisory_details($_GET['id']);
            }
        }
        break;

    case 'users':
        if (isAdmin()) {
            security_advisory_sbar($_GET['id']);
            security_advisory_affected_users($_GET['id']);
        }
        break;

    case 'vps':
        security_advisory_sbar($_GET['id']);
        security_advisory_affected_vps($_GET['id']);
        break;

    case 'show':
        security_advisory_details($_GET['id']);
        break;

    case 'list':
    default:
        security_advisory_sbar();
        security_advisory_list();
        break;
}

$xtpl->sbar_out(_('Security advisories'));
