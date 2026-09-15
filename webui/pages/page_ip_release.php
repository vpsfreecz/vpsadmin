<?php

if (!isLoggedIn()) {
    $xtpl->perex(_('IP release request'), _('Sign in to view your IP release request.'));
    return;
}

$action = $_GET['action'] ?? 'list';
$id = (int) ($_GET['id'] ?? 0);
$mutations = ['create', 'update', 'close', 'notify', 'release', 'keep', 'exempt', 'selection'];
$confirmations = ['close', 'notify', 'release'];
$adminActions = ['new', 'show', 'edit', 'create', 'update', 'close', 'notify', 'release', 'exempt', 'campaign_notices', 'selection'];
if (in_array($action, $adminActions, true) && !isAdmin()) {
    $xtpl->perex(_('Access denied'), _('This action is available only to administrators.'));
    ip_release_sbar();
    return;
}

$views = ['create' => 'new', 'update' => 'edit', 'keep' => 'request', 'exempt' => 'show', 'selection' => 'new'];
$view = $views[$action] ?? $action;
try {
    if (in_array($action, $mutations, true) && $_SERVER['REQUEST_METHOD'] === 'POST') {
        csrf_check();
        foreach (['deadline', 'reason', 'event'] as $field) {
            if (isset($_POST[$field]) && !is_string($_POST[$field])) {
                unset($_POST[$field]);
                throw new InvalidArgumentException(_('Invalid form value.'));
            }
        }
        if (in_array($action, ['create', 'keep', 'exempt', 'selection'], true)) {
            if (($_POST['selection_complete'] ?? null) !== '1') {
                throw new InvalidArgumentException(_('The address selection was incomplete. Reload the form and try again.'));
            }
            $selection = $_POST['addresses'] ?? [];
            if (!is_array($selection)) {
                throw new InvalidArgumentException(_('Invalid address selection.'));
            }
            if (in_array($action, ['create', 'selection'], true)) {
                $preview = &ip_release_preview();
                $operation = $_POST['selection_action'] ?? 'page';
                if (!is_string($operation) || !in_array($operation, ['all', 'none', 'page'], true)) {
                    throw new InvalidArgumentException(_('Invalid address selection.'));
                }
                IpReleaseSelection::update($preview, (int) $_SESSION['user']['id'], api_get_uint('preview_page', 0), $selection, $operation);
                $preview['settings'] = ['deadline' => $_POST['deadline'] ?? ''];
                if (isset($_POST['allow_keep'])) {
                    $preview['settings']['allow_keep'] = '1';
                }
                if ($action === 'selection') {
                    $next = $_POST['next_page'] ?? (string) api_get_uint('preview_page', 0);
                    if (!is_string($next) || !ctype_digit($next)) {
                        throw new InvalidArgumentException(_('Invalid address selection.'));
                    }
                    redirect(ip_release_url('new') . '&selection=' . rawurlencode($_GET['selection']) . '&preview_page=' . (int) $next);
                    return;
                }
                $selection = array_map('strval', array_keys($preview['selected']));
            }
            if (!$selection) {
                throw new InvalidArgumentException(_('Select at least one address.'));
            }
            foreach ($selection as $selected) {
                if (!is_string($selected) || !ctype_digit($selected) || (int) $selected <= 0) {
                    unset($_POST['addresses']);
                    throw new InvalidArgumentException(_('Invalid address selection.'));
                }
            }
            $selection = array_map('intval', $selection);
        }
        $campaign = $action === 'keep' ? null : $api->ip_release_campaign($id);
        switch ($action) {
            case 'create':
            case 'update':
                $deadline = DateTime::createFromFormat('!Y-m-d H:i', $_POST['deadline'] ?? '');
                if (!$deadline || $deadline->format('Y-m-d H:i') !== ($_POST['deadline'] ?? '')) {
                    throw new InvalidArgumentException(_('Enter the deadline as YYYY-MM-DD HH:MM.'));
                }
                $params = [
                    'deadline' => $deadline->format('c'),
                    'allow_keep' => isset($_POST['allow_keep']),
                ];
                if ($action === 'create') {
                    $params['addresses'] = $selection;
                    $created = $api->ip_release_campaign->create($params);
                    $id = $created->id;
                    unset($_SESSION['ip_release_previews'][$_GET['selection']]);
                    $message = _('IP release campaign created');
                } else {
                    $campaign->update($params);
                    $message = _('Campaign settings updated');
                }
                break;
            case 'close':
                $campaign->close();
                $message = _('Campaign closed without starting a release');
                break;
            case 'notify':
                $campaign->notify(['event' => $_POST['event'] ?? 'requested']);
                $message = _('Notice action completed');
                break;
            case 'release':
                $campaign->release();
                $message = _('Release attempted; see the result for each address');
                break;
            case 'keep':
                $api->ip_release_request($id)->keep(['addresses' => $selection, 'reason' => $_POST['reason'] ?? '']);
                $message = _('Reason saved for the selected IPs');
                break;
            case 'exempt':
                $params = ['addresses' => $selection, 'remove' => isset($_POST['remove'])];
                if (!$params['remove']) {
                    $params['reason'] = $_POST['reason'] ?? '';
                }
                $campaign->exempt($params);
                $message = isset($_POST['remove']) ? _('Exemptions removed from the selected IPs') : _('Exemptions saved for the selected IPs');
                break;
        }
        notify_user($message, '');
        redirect(ip_release_url($action === 'keep' ? 'request' : 'show', $id));
    } elseif (in_array($action, $mutations, true) && !in_array($action, $confirmations, true)) {
        throw new InvalidArgumentException(_('Submit this action using its form.'));
    }
} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
    $xtpl->perex_format_errors(_('Action failed'), $e->getResponse());
} catch (\Exception $e) {
    $xtpl->perex(_('Invalid request'), h($e->getMessage()));
}

$campaign = null;
$request = null;
try {
    if (in_array($view, ['show', 'edit', 'close', 'notify', 'release', 'campaign_notices'], true)) {
        $campaign = $api->ip_release_campaign->show($id);
    } elseif (in_array($view, ['request', 'notices'], true)) {
        $request = $api->ip_release_request->show($id);
        if (isAdmin()) {
            $campaign = $api->ip_release_campaign->show($request->ip_release_campaign_id);
        }
    }
    if ($campaign && $campaign->closed_at && in_array($view, ['edit', 'close', 'notify', 'release'], true)) {
        $xtpl->perex(_('Campaign closed'), _('This campaign is closed. Its history remains available.'));
        $view = 'show';
    }
    switch ($view) {
        case 'new':
            ip_release_new();
            break;
        case 'show':
            ip_release_show($campaign);
            break;
        case 'edit':
            ip_release_edit($campaign);
            break;
        case 'close':
        case 'notify':
        case 'release':
            ip_release_action_form($campaign, $view);
            break;
        case 'campaign_notices':
            ip_release_notice_history($campaign, true);
            break;
        case 'notices':
            ip_release_notice_history($request);
            break;
        case 'request':
            ip_release_request_details($request, $campaign);
            break;
        default:
            ip_release_list();
    }
} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
    $xtpl->perex_format_errors(_('Action failed'), $e->getResponse());
} catch (\Exception $e) {
    $xtpl->perex(_('Invalid request'), h($e->getMessage()));
}
ip_release_sbar($campaign, $request);
