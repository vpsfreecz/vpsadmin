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

function security_advisory_save_nodes($id, $revision)
{
    global $api;

    $statuses = [];
    foreach ($api->security_advisory($id)->node_status->list() as $status) {
        $statuses[$status->node->id] = $status;
    }

    foreach (security_advisory_nodes() as $node) {
        $prefix = 'node_' . $node->id;
        $state = $_POST[$prefix . '_state'];
        $params = [
            'expected_content_revision' => $revision,
            'state' => $state,
            'vulnerable_until' => $state === 'not_affected' ? null : security_advisory_datetime_param($prefix . '_vulnerable_until'),
            'mitigated_since' => $state === 'not_affected' ? null : security_advisory_datetime_param($prefix . '_mitigated_since'),
        ];

        foreach ($api->language->list() as $lang) {
            $name = $lang->code . '_note';
            $params[$name] = $_POST[$prefix . '_' . $name] ?: null;
        }

        if (isset($statuses[$node->id])) {
            $api->security_advisory($id)->node_status->update($statuses[$node->id]->id, $params);
        } else {
            $params['node'] = $node->id;
            $api->security_advisory($id)->node_status->create($params);
        }

        $revision++;
    }

    return $revision;
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
                    $revision = security_advisory_save_cves(
                        $advisory->id,
                        $cves,
                        $advisory->content_revision
                    );
                    security_advisory_save_nodes($advisory->id, $revision);
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
                    $params = security_advisory_params();
                    $params['expected_content_revision'] = (int) $_POST['expected_content_revision'];
                    $advisory = $api->security_advisory->update($_GET['id'], $params);
                    security_advisory_save_cves(
                        $_GET['id'],
                        $cves,
                        $advisory->content_revision
                    );
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
                    security_advisory_save_nodes(
                        $_GET['id'],
                        (int) $_POST['expected_content_revision']
                    );
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
                    'expected_content_revision' => (int) $_POST['expected_content_revision'],
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

    case 'link_outage':
        if (isAdmin() && $_SERVER['REQUEST_METHOD'] === 'POST') {
            csrf_check();

            try {
                $outageId = trim($_POST['outage'] ?? '');
                if (!preg_match('/^\d+$/', $outageId)) {
                    throw new \InvalidArgumentException(_('Outage ID must be a number.'));
                }

                $linked = false;

                foreach ($api->outage_security_advisory->list([
                    'outage' => $outageId,
                    'security_advisory' => $_GET['id'],
                ]) as $link) {
                    if ((int) security_advisory_link_advisory_id($link) === (int) $_GET['id']) {
                        $linked = true;
                        break;
                    }
                }

                if (!$linked) {
                    $api->outage_security_advisory->create([
                        'outage' => $outageId,
                        'security_advisory' => $_GET['id'],
                    ]);
                }

                redirect('?page=security_advisory&action=show&id=' . $_GET['id']);
            } catch (\InvalidArgumentException $e) {
                $xtpl->perex(_('Link failed'), h($e->getMessage()));
                security_advisory_details($_GET['id']);
            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Link failed'), $e->getResponse());
                security_advisory_details($_GET['id']);
            }
        }
        break;

    case 'unlink_outage':
        if (isAdmin() && $_SERVER['REQUEST_METHOD'] === 'POST') {
            csrf_check();

            try {
                $api->outage_security_advisory->delete($_GET['link']);
                redirect('?page=security_advisory&action=show&id=' . $_GET['id']);
            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Unlink failed'), $e->getResponse());
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
