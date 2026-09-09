<?php

if (!isLoggedIn()) {
    $xtpl->perex(_('IP release request'), _('Sign in to view your IP release request.'));
    return;
}

$action = $_GET['action'] ?? 'list';
$id = (int) ($_GET['id'] ?? 0);
$mutations = ['create', 'update', 'close', 'notify', 'release', 'keep', 'exempt'];
$adminActions = ['new', 'show', 'create', 'update', 'close', 'notify', 'release', 'exempt'];
if (in_array($action, $adminActions, true) && !isAdmin()) {
    $xtpl->perex(_('Access denied'), _('This action is available only to administrators.'));
    return;
}

try {
    if (in_array($action, $mutations, true)) {
        if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
            $xtpl->perex(_('Invalid request'), _('Submit this action using its form.'));
            return;
        }
        csrf_check();
        if (in_array($action, ['create', 'keep'], true) && ($_POST['selection_complete'] ?? null) !== '1') {
            throw new InvalidArgumentException(_('The address selection was incomplete. Reload the form and try again.'));
        }
        $campaign = in_array($action, ['create', 'update', 'close', 'notify', 'release'], true)
            ? $api->ip_release_campaign($id) : null;
        switch ($action) {
            case 'create':
            case 'update':
                $deadline = DateTime::createFromFormat('!Y-m-d H:i', $_POST['deadline'] ?? '');
                if (!$deadline || $deadline->format('Y-m-d H:i') !== ($_POST['deadline'] ?? '')) {
                    throw new InvalidArgumentException(_('Enter the deadline as YYYY-MM-DD HH:MM.'));
                }
                $params = [
                    'label' => trim($_POST['label'] ?? ''),
                    'deadline' => $deadline->format('c'),
                    'allow_keep' => isset($_POST['allow_keep']),
                ];
                if ($action === 'create') {
                    $params['addresses'] = array_map('intval', $_POST['addresses'] ?? []);
                    $created = $api->ip_release_campaign->create($params);
                    $id = $created->id;
                } else {
                    $campaign->update($params);
                }
                break;
            case 'close':
                $campaign->close();
                break;
            case 'notify':
                $campaign->notify(['event' => $_POST['event'] ?? 'requested']);
                break;
            case 'release':
                $campaign->release();
                break;
            case 'keep':
                $api->ip_release_request($id)->keep([
                    'addresses' => array_map('intval', $_POST['addresses'] ?? []),
                    'reason' => $_POST['reason'] ?? '',
                ]);
                break;
            case 'exempt':
                $api->ip_release_request($id)->address((int) ($_POST['address'] ?? 0))->exempt([
                    'reason' => isset($_POST['remove']) ? null : ($_POST['reason'] ?? ''),
                ]);
                break;
        }
        notify_user(_('IP release request updated'), '');
        redirect(ip_release_url(in_array($action, ['keep', 'exempt'], true) ? 'request' : 'show', $id));
    }

    switch ($action) {
        case 'new':
            ip_release_new();
            break;
        case 'show':
            ip_release_show($id);
            break;
        case 'notices':
            ip_release_notice_history($api->ip_release_request->show($id));
            break;
        case 'request':
            ip_release_request_details($api->ip_release_request->show($id));
            break;
        default:
            ip_release_list();
    }
} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
    $xtpl->perex_format_errors(_('Action failed'), $e->getResponse());
} catch (\Exception $e) {
    $xtpl->perex(_('Invalid request'), h($e->getMessage()));
}
