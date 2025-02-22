<?php

use Endroid\QrCode\QrCode;
use Endroid\QrCode\Writer\PngWriter;

function environment_configs($user_id)
{
    global $xtpl, $api;

    $cfgs = $api->user($user_id)->environment_config->list([
        'meta' => ['includes' => 'environment'],
    ]);

    $xtpl->title(_('User') . ' <a href="?page=adminm&action=edit&id=' . $user_id . '">#' . $user_id . '</a>: ' . _('Environment configs'));

    $xtpl->table_add_category(_('Environment'));
    $xtpl->table_add_category(_('Create VPS'));
    $xtpl->table_add_category(_('Destroy VPS'));
    $xtpl->table_add_category(_('VPS count'));
    $xtpl->table_add_category(_('VPS lifetime'));

    if (isAdmin()) {
        $xtpl->table_add_category(_('Default'));
        $xtpl->table_add_category('');
    }

    foreach ($cfgs as $c) {
        $vps_count = $api->vps->list([
            'limit' => 0,
            'environment' => $c->environment_id,
            'user' => $user_id,
            'meta' => ['count' => true],
        ]);

        $xtpl->table_td($c->environment->label);
        $xtpl->table_td(boolean_icon($c->can_create_vps));
        $xtpl->table_td(boolean_icon($c->can_destroy_vps));
        $xtpl->table_td(
            $vps_count->getTotalCount() . ' / ' . $c->max_vps_count,
            false,
            true
        );
        $xtpl->table_td(format_duration($c->vps_lifetime), false, true);

        if (isAdmin()) {
            $xtpl->table_td(boolean_icon($c->default));
            $xtpl->table_td('<a href="?page=adminm&section=members&action=env_cfg_edit&id=' . $user_id . '&cfg=' . $c->id . '"><img src="template/icons/m_edit.png"  title="' . _("Edit") . '"></a>');
        }

        $xtpl->table_tr();
    }

    $xtpl->table_out();

    $xtpl->sbar_add('<br><img src="template/icons/m_edit.png"  title="' . _("Back to user details") . '" />' . _('Back to user details'), "?page=adminm&section=members&action=edit&id=$user_id");
}

function env_cfg_edit_form($user_id, $cfg_id)
{
    global $xtpl, $api;

    $cfg = $api->user($user_id)->environment_config->find($cfg_id, [
        'meta' => ['includes' => 'environment'],
    ]);

    $input = $cfg->update->getParameters('input');

    $xtpl->title(_('User') . ' <a href="?page=adminm&action=edit&id=' . $user_id . '">#' . $user_id . '</a>: ' . _('Environment config for') . ' ' . $cfg->environment->label);

    $xtpl->table_title(_('Customize settings'));
    $xtpl->form_create("?page=adminm&action=env_cfg_edit&id=$user_id&cfg=$cfg_id");

    $xtpl->table_td(_('Environment'));
    $xtpl->table_td($cfg->environment->label);
    $xtpl->table_tr();

    $xtpl->table_td(_('Default settings'));
    $xtpl->table_td(boolean_icon($cfg->default));
    $xtpl->table_tr();

    foreach (['can_create_vps', 'can_destroy_vps', 'vps_lifetime', 'max_vps_count'] as $param) {
        api_param_to_form($param, $input->{$param}, post_val($param, $cfg->{$param}));
    }

    $xtpl->form_out(_('Customize'));

    if ($cfg->default) {
        return;
    }

    $xtpl->table_title(_('Reset to default settings'));
    $xtpl->form_create("?page=adminm&action=env_cfg_reset&id=$user_id&cfg=$cfg_id");

    $xtpl->table_td(_('Environment'));
    $xtpl->table_td($cfg->environment->label);
    $xtpl->table_tr();

    $xtpl->form_out(_('Reset'));

    $xtpl->sbar_add('<br><img src="template/icons/m_edit.png"  title="' . _("Back to environment configs") . '" />' . _('Back to user details'), "?page=adminm&section=members&action=env_cfg&id=$user_id");
}

function list_user_sessions($user_id)
{
    global $xtpl, $api;

    $u = $api->user->find($user_id);

    $input = $api->user_session->index->getParameters('input');
    $pagination = new \Pagination\System(null, $api->user_session->index);

    $xtpl->title(_('Session log of') . ' <a href="?page=adminm&action=edit&id=' . $u->id . '">#' . $u->id . '</a> ' . $u->login);
    $xtpl->table_title(_('Filters'));
    $xtpl->form_create('', 'get', 'user-session-filter', false);

    $xtpl->form_set_hidden_fields([
        'page' => 'adminm',
        'action' => 'user_sessions',
        'id' => $user_id,
        'list' => '1',
    ]);

    $xtpl->form_add_input(_("Limit") . ':', 'text', '40', 'limit', get_val('limit', '25'), '');
    $xtpl->form_add_input(_("From ID") . ':', 'text', '40', 'from_id', get_val('from_id'), '');
    $xtpl->form_add_input(_("Exact ID") . ':', 'text', '40', 'session_id', get_val('session_id', ''), '');
    api_param_to_form('auth_type', $input->auth_type, get_val('auth_type'), null, true);
    api_param_to_form('state', $input->state, get_val('state'), null, true);
    $xtpl->form_add_input(_("IP Address") . ':', 'text', '40', 'ip_addr', get_val('ip_addr', ''), '');
    $xtpl->form_add_input(_("User agent") . ':', 'text', '40', 'user_agent', get_val('user_agent', ''), '');
    $xtpl->form_add_input(_("Client version") . ':', 'text', '40', 'client_version', get_val('client_version', ''), '');
    $xtpl->form_add_input(_("Token") . ':', 'text', '40', 'token_fragment', get_val('token_fragment', ''), '');

    if (isAdmin()) {
        $xtpl->form_add_input(_("Admin ID") . ':', 'text', '40', 'admin', get_val('admin', ''), '');
    }

    $xtpl->form_add_checkbox(_('Detailed output') . ':', 'details', '1', isset($_GET['details']));

    $xtpl->form_out(_('Show'));

    if (!$_GET['list']) {
        return;
    }

    $params = [
        'limit' => get_val('limit', 25),
        'user' => $user_id,
    ];

    if (($_GET['from_id'] ?? 0) > 0) {
        $params['from_id'] = $_GET['from_id'];
    }

    $conds = [
        'auth_type',
        'state',
        'ip_addr',
        'user_agent',
        'client_version',
        'token_fragment',
        'admin',
    ];

    foreach ($conds as $c) {
        if ($_GET[$c]) {
            $params[$c] = $_GET[$c];
        }
    }

    $includes = [];

    if (isAdmin()) {
        $params['meta'] = ['includes' => 'admin'];
    }

    if ($_GET['session_id']) {
        $sessions = [ $api->user_session->show($_GET['session_id']) ];
    } else {
        $sessions = $api->user_session->list($params);
        $pagination->setResourceList($sessions);
    }

    $xtpl->table_add_category(_("Label"));
    $xtpl->table_add_category(_("Created at"));
    $xtpl->table_add_category(_("Closed at"));
    $xtpl->table_add_category(_("IP address"));
    $xtpl->table_add_category(_("Auth type"));
    $xtpl->table_add_category(_("Token"));

    if (isAdmin()) {
        $xtpl->table_add_category(_("Admin"));
    }

    $xtpl->table_add_category('');
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');

    $return_url = urlencode($_SERVER['REQUEST_URI']);

    foreach ($sessions as $s) {
        $xtpl->table_td(h($s->label));
        $xtpl->table_td(tolocaltz($s->created_at));
        $xtpl->table_td($s->closed_at ? tolocaltz($s->closed_at) : '---');
        $xtpl->table_td(h($s->client_ip_addr ? $s->client_ip_addr : $s->api_ip_addr));
        $xtpl->table_td($s->auth_type);
        $xtpl->table_td(
            $s->token_fragment
            ? substr($s->token_fragment, 0, 8) . '...'
            : '---'
        );

        if (isAdmin()) {
            $xtpl->table_td(
                $s->admin_id
                ? '<a href="?page=adminm&action=edit&id=' . $s->admin_id . '">' . $s->admin->login . '</a>'
                : '---'
            );
        }

        $color = false;

        if (!$s->closed_at && str_starts_with(getAuthenticationToken(), $s->token_fragment)) {
            $color = '#33CC00';
        } elseif (!$s->closed_at) {
            $color = '#66FF33';
        }

        $xtpl->table_td('<a href="?page=transactions&user_session=' . $s->id . '">Log</a>');
        $xtpl->table_td('<a href="?page=adminm&action=user_session_edit&id=' . $_GET['id'] . '&user_session=' . $s->id . '&return=' . $return_url . '"><img src="template/icons/m_edit.png"  title="' . _("Edit") . '" /></a>');

        if (!$s->closed_at) {
            $xtpl->table_td('<a href="?page=adminm&action=user_session_close&id=' . $_GET['id'] . '&user_session=' . $s->id . '&t=' . csrf_token() . '&return=' . $return_url . '"><img src="template/icons/m_delete.png"  title="' . _("Close") . '" /></a>');
        } else {
            $xtpl->table_td('');
        }

        $xtpl->table_tr($color);

        if (!$_GET['details']) {
            continue;
        }

        $xtpl->table_td(
            '<dl>' .
            '<dt>Request count:</dt><dd>' . $s->request_count . '</dd>' .
            '<dt>Last request at:</dt><dd>' . ($s->last_request_at ? tolocaltz($s->last_request_at) : '---') . '</dd>' .
            '<dt>API IP address:</dt><dd>' . h($s->api_ip_addr) . '</dd>' .
            '<dt>API IP PTR:</dt><dd>' . h($s->api_ip_ptr) . '</dd>' .
            '<dt>Client IP address:</dt><dd>' . h($s->client_ip_addr) . '</dd>' .
            '<dt>Client IP PTR:</dt><dd>' . h($s->client_ip_ptr) . '</dd>' .
            '<dt>User agent:</dt><dd>' . h($s->user_agent) . '</dd>' .
            '<dt>Client version:</dt><dd>' . h($s->client_version) . '</dd>' .
            '<dt>Token:</dt><dd>' . ($s->token_fragment ? $s->token_fragment . '...' : '---') . '</dd>' .
            '<dt>Token lifetime:</dt><dd>' . $s->token_lifetime . '</dd>' .
            '<dt>Token interval:</dt><dd>' . $s->token_interval . '</dd>' .
            '<dt>Scope:</dt><dd>' . h($s->scope) . '</dd>' .
            '<dl>',
            false,
            false,
            '10'
        );

        $xtpl->table_tr();
    }

    if (!$_GET['session_id']) {
        $xtpl->table_pagination($pagination);
    }

    $xtpl->table_out();

    $xtpl->sbar_add('<br><img src="template/icons/m_edit.png"  title="' . _("Back to user details") . '" />' . _('Back to user details'), "?page=adminm&action=edit&id=$user_id");
}

function user_session_edit_form($id)
{
    global $api, $xtpl;

    $s = $api->user_session->show($id);

    $xtpl->table_title(_('Edit user session') . ' #' . $id);
    $xtpl->form_create('?page=adminm&section=members&action=user_session_edit&id=' . $_GET['id'] . '&user_session=' . $id . '&return=' . urlencode($_GET['return']), 'post');

    $xtpl->table_td(_('Authentication type') . ':');
    $xtpl->table_td(h($s->auth_type));
    $xtpl->table_tr();

    $xtpl->table_td(_('Token') . ':');
    $xtpl->table_td($s->token_fragment ? ($s->token_fragment . '...') : '---');
    $xtpl->table_tr();

    $xtpl->form_add_input(_("Label") . ':', 'text', '30', 'label', $s->label);
    $xtpl->form_out(_('Save'));

    $xtpl->sbar_add('<br><img src="template/icons/m_edit.png"  title="' . _("Back to sessions") . '" />' . _('Back to sessions'), $_GET['return'] ?? ("?page=adminm&section=members&action=user_sessions&id={$_GET['id']}"));
}

function approval_requests_list()
{
    global $xtpl, $api;

    $limit = get_val('limit', 50);
    $pagination = new \Pagination\System(
        null,
        /**
         * This is not true, as we fetch both registration and change requests, but
         * it doesn't matter to pagination.
         */
        $api->user_request->registration->list,
        ['defaultLimit' => $limit]
    );

    $xtpl->title(_("Requests for approval"));

    $xtpl->form_create('?page=adminm&action=approval_requests', 'get');

    $xtpl->form_set_hidden_fields([
        'page' => 'adminm',
        'action' => 'approval_requests',
    ]);

    $xtpl->form_add_input(_("Limit") . ':', 'text', '30', 'limit', $limit);
    $xtpl->form_add_select(_("Type") . ':', 'type', [
        "all" => _("all"),
        "registration" => _("registration"),
        "change" => _("change"),
    ], $_GET["type"] ?? 'all');
    $xtpl->form_add_select(_("State") . ':', 'state', [
        "all" => _("all"),
        "awaiting" => _("awaiting"),
        "pending_correction" => _("pending correction"),
        "approved" => _("approved"),
        "denied" => _("denied"),
        "ignored" => _("ignored"),
    ], $_GET["state"] ?? "awaiting");

    $xtpl->form_add_input(_("IP address") . ':', 'text', '30', 'ip_addr', get_val("ip_addr"));
    $xtpl->form_add_input(_("Client IP PTR") . ':', 'text', '30', 'client_ip_ptr', get_val("client_ip_ptr"));
    $xtpl->form_add_input(_("User ID") . ':', 'text', '30', 'user', get_val("user"));
    $xtpl->form_add_input(_("Admin ID") . ':', 'text', '30', 'admin', get_val("admin"));

    $xtpl->form_out(_("Show"));

    $xtpl->table_add_category('#');
    $xtpl->table_add_category('DATE');
    $xtpl->table_add_category('TYPE');
    $xtpl->table_add_category('STATE');
    $xtpl->table_add_category('ADMIN');
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');

    $params = ['limit' => $limit];
    $state = $_GET['state'] ?? 'awaiting';

    if ($state != 'all') {
        $params['state'] = $state;
    }

    if (($_GET['from_id'] ?? 0) > 0) {
        $params['from_id'] = $_GET['from_id'];
    }

    foreach (['ip_addr', 'client_ip_ptr', 'user', 'admin'] as $v) {
        if ($_GET[$v] ?? false) {
            $params[$v] = $_GET[$v];
        }
    }

    $types = [];

    if (($_GET['type'] ?? 'all') == 'all') {
        $types[] = 'registration';
        $types[] = 'change';
    } else {
        $types[] = $_GET['type'];
    }

    $requests = [];

    foreach ($types as $type) {
        $requests = array_merge($requests, $api->user_request->{$type}->list($params)->asArray());
    }

    usort($requests, function ($a, $b) {
        return $a->id < $b->id ? 1 : -1;
    });

    $requestsSlice = array_slice($requests, 0, $limit);
    $pagination->setResourceList($requestsSlice);

    foreach ($requestsSlice as $r) {
        $type = $r->currency ? 'registration' : 'change';
        $nextUrl = urlencode($_SERVER['REQUEST_URI']);

        $xtpl->table_td('<a href="?page=adminm&action=request_details&id=' . $r->id . '&type=' . $type . '">#' . $r->id . '</a>');
        $xtpl->table_td(tolocaltz($r->created_at));
        $xtpl->table_td($type);
        $xtpl->table_td($r->state);
        $xtpl->table_td($r->admin_id ? ('<a href="?page=adminm&action=edit&id=' . $r->admin_id . '&type=' . $type . '">' . $r->admin->login . '</a>') : '-');
        $xtpl->table_td('<a href="?page=adminm&action=request_details&id=' . $r->id . '&type=' . $type . '"><img src="template/icons/m_edit.png"  title="' . _("Details") . '" /></a>');
        $xtpl->table_td('<a href="?page=adminm&action=request_process&id=' . $r->id . '&type=' . $type . '&rule=approve&t=' . csrf_token() . '&next_url=' . $nextUrl . '">' . _("approve") . '</a>');
        $xtpl->table_td('<a href="?page=adminm&action=request_process&id=' . $r->id . '&type=' . $type . '&rule=deny&t=' . csrf_token() . '&next_url=' . $nextUrl . '">' . _("deny") . '</a>');
        $xtpl->table_td('<a href="?page=adminm&action=request_process&id=' . $r->id . '&type=' . $type . '&rule=ignore&t=' . csrf_token() . '&next_url=' . $nextUrl . '">' . _("ignore") . '</a>');

        $xtpl->table_tr();

        if ($type == 'registration') {
            $dl = [
                _('Login') => $r->login,
                _('Name') => $r->full_name,
                _('Org') => $r->org_name ? "{$r->org_name} (ID {$r->org_id})" : '',
                _('Email') => $r->email,
                _('Address') => $r->address,
                _('Birth') => $r->year_of_birth,
                _('How') => $r->how,
                _('Note') => $r->note,
                _('Distribution') => $r->os_template->label,
                _('Location') => $r->location->label,
                _('Currency') => strtoupper($r->currency),
                _('Language') => $r->language->label,
                _('IP') => $r->client_ip_addr,
                _('PTR') => $r->client_ip_ptr,
                _('Proxy') => $r->ip_proxy ? 'yes' : 'no',
                _('Abuse') => $r->ip_recent_abuse ? 'yes' : 'no',
                _('VPN') => $r->ip_vpn ? 'yes' : 'no',
                _('Tor') => $r->ip_tor ? 'yes' : 'no',
                _('IP score') => $r->ip_fraud_score,
                _('Mail suspect') => $r->mail_suspect ? 'yes' : 'no',
                _('Mail score') => $r->mail_fraud_score,
            ];
        } else {
            $dl = [
                _('User') => $r->user->login,
            ];

            $changeable = [
                'full_name' => _('Full name'),
                'email' => _('Email'),
                'address' => _('Address'),
            ];

            foreach ($changeable as $param => $label) {
                if ($r->user->{$param} == $r->{$param}) {
                    continue;
                }

                $dl[$label] = $r->{$param};
            }

            $dl[_('Reason')] = $r->change_reason;
            $dl[_('IP')] = $r->client_ip_addr;
            $dl[_('PTR')] = $r->client_ip_ptr;
        }

        $xtpl->table_td(makeDefinitionList($dl, 'inline'), false, false, $xtpl->table_max_cols);
        $xtpl->table_tr();
    }

    $xtpl->table_pagination($pagination);
    $xtpl->table_out();
}

function approval_requests_details($type, $id)
{
    global $xtpl, $api;

    $r = $api->user_request->{$type}->show($id);

    $xtpl->title(_("Request for approval details"));

    $xtpl->table_add_category(_("Request info"));
    $xtpl->table_add_category('');

    $xtpl->table_td(_("Created") . ':');
    $xtpl->table_td(tolocaltz($r->created_at));
    $xtpl->table_tr();

    $xtpl->table_td(_("Changed") . ':');
    $xtpl->table_td(tolocaltz($r->updated_at));
    $xtpl->table_tr();

    $xtpl->table_td(_("Type") . ':');
    $xtpl->table_td($type == "registration" ? _("registration") : _("change"));
    $xtpl->table_tr();

    $xtpl->table_td(_("State") . ':');
    $xtpl->table_td($r->state);
    $xtpl->table_tr();

    $xtpl->table_td(_("Applicant") . ':');
    $xtpl->table_td($r->user_id ? ('<a href="?page=adminm&action=edit&id=' . $r->user_id . '">' . $r->user->login . '</a>') : '-');
    $xtpl->table_tr();

    $xtpl->table_td(_("Admin") . ':');
    $xtpl->table_td($r->admin_id ? ('<a href="?page=adminm&action=edit&id=' . $r->admin_id . '">' . $r->admin->login . '</a>') : '-');
    $xtpl->table_tr();

    $xtpl->table_td(_("API IP Address") . ':');
    $xtpl->table_td(h($r->api_ip_addr));
    $xtpl->table_tr();

    $xtpl->table_td(_("API PTR") . ':');
    $xtpl->table_td(h($r->api_ip_ptr));
    $xtpl->table_tr();

    $xtpl->table_td(_("Client IP Address") . ':');
    $xtpl->table_td(h($r->client_ip_addr));
    $xtpl->table_tr();

    $xtpl->table_td(_("Client PTR") . ':');
    $xtpl->table_td(h($r->client_ip_ptr));
    $xtpl->table_tr();

    $xtpl->table_out();

    if ($type == 'registration') {
        $xtpl->table_add_category(_('IPQS IP'));
        $xtpl->table_add_category('');

        if (!$r->ip_checked) {
            $xtpl->table_td(_('Pending check'));
            $xtpl->table_tr();
        } else {
            $xtpl->table_td(_('Success') . ':');
            $xtpl->table_td(boolean_icon($r->ip_success));
            $xtpl->table_tr();
            $xtpl->table_td(_('Request ID') . ':');
            $xtpl->table_td(h($r->ip_request_id));
            $xtpl->table_tr();

            if ($r->ip_success) {
                $xtpl->table_td(_('Proxy') . ':');
                $xtpl->table_td(boolean_icon($r->ip_proxy));
                $xtpl->table_tr();
                $xtpl->table_td(_('Crawler') . ':');
                $xtpl->table_td(boolean_icon($r->ip_crawler));
                $xtpl->table_tr();
                $xtpl->table_td(_('VPN') . ':');
                $xtpl->table_td(boolean_icon($r->ip_vpn));
                $xtpl->table_tr();
                $xtpl->table_td(_('Tor') . ':');
                $xtpl->table_td(boolean_icon($r->ip_tor));
                $xtpl->table_tr();
                $xtpl->table_td(_('Recent abuse') . ':');
                $xtpl->table_td(boolean_icon($r->ip_recent_abuse));
                $xtpl->table_tr();
                $xtpl->table_td(_('Fraud score') . ':');
                $xtpl->table_td($r->ip_fraud_score);
                $xtpl->table_tr();

                if ($r->ip_fraud_score >= 85) {
                    $action = _("It's fishy, ignore / deny");
                } elseif ($r->ip_fraud_score >= 75) {
                    $action = _('Suspicious activity');
                } else {
                    $action = _('OK');
                }

                $xtpl->table_td(_('Judgement') . ':');
                $xtpl->table_td($action);
                $xtpl->table_tr();
            } else {
                $xtpl->table_td(_('Message') . ':');
                $xtpl->table_td(h($r->ip_message));
                $xtpl->table_tr();
                $xtpl->table_td(_('Errors') . ':');
                $xtpl->table_td(h($r->ip_errors));
                $xtpl->table_tr();
            }
        }

        $xtpl->table_out();

        $xtpl->table_add_category(_('IPQS E-mail'));
        $xtpl->table_add_category('');

        if (!$r->mail_checked) {
            $xtpl->table_td(_('Pending check'));
            $xtpl->table_tr();
        } else {
            $xtpl->table_td(_('Success') . ':');
            $xtpl->table_td(boolean_icon($r->mail_success));
            $xtpl->table_tr();
            $xtpl->table_td(_('Request ID') . ':');
            $xtpl->table_td(h($r->mail_request_id));
            $xtpl->table_tr();

            if ($r->mail_success) {
                $xtpl->table_td(_('Valid') . ':');
                $xtpl->table_td(boolean_icon($r->mail_valid));
                $xtpl->table_tr();
                $xtpl->table_td(_('Disposable') . ':');
                $xtpl->table_td(boolean_icon($r->mail_disposable));
                $xtpl->table_tr();
                $xtpl->table_td(_('Timed out') . ':');
                $xtpl->table_td(boolean_icon($r->mail_timed_out));
                $xtpl->table_tr();
                $xtpl->table_td(_('Deliverability') . ':');
                $xtpl->table_td(h($r->mail_deliverability));
                $xtpl->table_tr();
                $xtpl->table_td(_('Catch-all') . ':');
                $xtpl->table_td(boolean_icon($r->mail_catch_all));
                $xtpl->table_tr();
                $xtpl->table_td(_('Leaked') . ':');
                $xtpl->table_td(boolean_icon($r->mail_leaked));
                $xtpl->table_tr();
                $xtpl->table_td(_('Suspect') . ':');
                $xtpl->table_td(boolean_icon($r->mail_suspect));
                $xtpl->table_tr();
                $xtpl->table_td(_('DNS valid') . ':');
                $xtpl->table_td(boolean_icon($r->mail_dns_valid));
                $xtpl->table_tr();
                $xtpl->table_td(_('Honeypot') . ':');
                $xtpl->table_td(boolean_icon($r->mail_honeypot));
                $xtpl->table_tr();
                $xtpl->table_td(_('SPAM trap score') . ':');
                $xtpl->table_td(h($r->mail_spam_trap_score));
                $xtpl->table_tr();
                $xtpl->table_td(_('Recent abuse') . ':');
                $xtpl->table_td(boolean_icon($r->mail_recent_abuse));
                $xtpl->table_tr();
                $xtpl->table_td(_('Frequent complainer') . ':');
                $xtpl->table_td(boolean_icon($r->mail_frequent_complainer));
                $xtpl->table_tr();

                $smtpScores = [
                    -1 => _('Invalid email address'),
                    0 => _('Mail server exists, but is rejecting all mail'),
                    1 => _('Mail server exists, but is showing a temporary error'),
                    2 => _('Mail server exists, but accepts all email'),
                    3 => _('Mail server exists and has verified the email address'),
                ];
                $xtpl->table_td(_('SMTP score') . ':');
                $xtpl->table_td($smtpScores[$r->mail_smtp_score]);
                $xtpl->table_tr();

                $overallScores = [
                    0 => _('Invalid email address'),
                    1 => _('DNS valid, unreachable mail server'),
                    2 => _('DNS valid, temporary mail rejection error'),
                    3 => _('DNS valid, accepts all mail'),
                    4 => _('DNS valid, verified email exists'),
                ];

                $xtpl->table_td(_('Overall score') . ':');
                $xtpl->table_td($overallScores[$r->mail_overall_score]);
                $xtpl->table_tr();

                $xtpl->table_td(_('Fraud score') . ':');
                $xtpl->table_td($r->mail_fraud_score);
                $xtpl->table_tr();

                if ($r->mail_fraud_score >= 75) {
                    $action = _('Suspicious activity');
                } else {
                    $action = _('OK');
                }

                $xtpl->table_td(_('Judgement') . ':');
                $xtpl->table_td($action);
                $xtpl->table_tr();
            } else {
                $xtpl->table_td(_('Message') . ':');
                $xtpl->table_td(h($r->mail_message));
                $xtpl->table_tr();
                $xtpl->table_td(_('Errors') . ':');
                $xtpl->table_td(h($r->mail_errors));
                $xtpl->table_tr();
            }
        }

        $xtpl->table_out();
    };

    $xtpl->form_create('?page=adminm&action=request_process&id=' . $r->id . '&type=' . $type, 'post');
    $params = $r->resolve->getParameters('input');
    $request_attrs = $r->show->getParameters('output');

    if ($type == 'change') {
        $xtpl->table_td(_('Full name') . ':', false, false, '1', '2');
        $xtpl->table_td(h($r->user->full_name));
        $xtpl->table_tr();
        $xtpl->form_add_input_pure(
            'text',
            '80',
            'full_name',
            post_val('full_name', $r->full_name)
        );
        $xtpl->table_tr();

        $xtpl->table_td(_('E-mail') . ':', false, false, '1', '2');
        $xtpl->table_td(h($r->user->email));
        $xtpl->table_tr();
        $xtpl->form_add_input_pure(
            'text',
            '80',
            'email',
            post_val('email', $r->email)
        );
        $xtpl->table_tr();

        $xtpl->table_td(_('Address') . ':', false, false, '1', '2');
        $xtpl->table_td(h($r->user->address));
        $xtpl->table_tr();
        $xtpl->form_add_input_pure(
            'text',
            '80',
            'address',
            post_val('address', $r->address)
        );
        $xtpl->table_tr();

        $xtpl->table_td(_('Change reason') . ':');
        $xtpl->table_td(h($r->change_reason));
        $xtpl->table_tr();

        api_param_to_form('action', $params->action);
        api_param_to_form('reason', $params->reason);

    } else {
        foreach ($params as $name => $desc) {
            $v = null;

            if (property_exists($request_attrs, $name)) {
                switch ($request_attrs->{$name}->type) {
                    case 'Resource':
                        $v = $r->{"{$name}_id"};
                        break;

                    default:
                        $v = $r->{$name};
                }
            }

            api_param_to_form($name, $desc, $v);
        }
    }

    $xtpl->form_out(_('Close request'));
}

function user_payment_info($u)
{
    global $xtpl;

    $paid = false;
    $paid_until = null;
    $t = null;

    if ($u->paid_until) {
        $dt = new DateTime($u->paid_until);
        $dt->setTimezone(new DateTimezone(date_default_timezone_get()));

        $t = $dt->getTimestamp();
        $paid = $t > time();
        $paid_until = date('Y-m-d', $t);
    }

    if (isAdmin()) {
        $td = '<a href="?page=adminm&action=payset&id=' . $u->id . '" class="user-' . ($paid ? 'paid' : 'unpaid') . '">';
        $color = '';

        if ($paid) {
            if (($t - time()) >= 604800) {
                $td .= _("->") . ' ' . $paid_until;
                $color = '#66FF66';

            } else {
                $td .= _("->") . ' ' . $paid_until;
                $color = '#FFA500';
            }

        } else {
            $td .= '<strong>' . _("not paid!") . '</strong>';
            $color = '#B22222';

            if ($u->paid_until) {
                $td .= ' (' . ceil(($t - time()) / 86400) . 'd)';
            }
        }

        $td .= '</a>';
        $xtpl->table_td($td, $color);

        return;
    }

    if ($paid) {
        if (($t - time()) >= 604800) {
            $xtpl->table_td(_("->") . ' ' . $paid_until, '#66FF66');

        } else {
            $xtpl->table_td(_("->") . ' ' . $paid_until, '#FFA500');
        }

    } else {
        $xtpl->table_td('<b>' . _("not paid!") . '</b>', '#B22222');
    }
}

function user_payment_instructions($user_id)
{
    global $xtpl, $api;

    try {
        $u = $api->user->find($user_id);

    } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
        $xtpl->perex_format_errors(_('User not found'), $e->getResponse());
        return;
    }

    $xtpl->sbar_add('<br><img src="template/icons/m_edit.png"  title="' . _("Back to user details") . '" />' . _('Back to user details'), "?page=adminm&section=members&action=edit&id={$user_id}");

    $xtpl->title(_('Payment instructions'));
    $xtpl->table_td($u->get_payment_instructions()['instructions']);
    $xtpl->table_tr(false, 'nohover', 'nohover');
    $xtpl->table_out();
}

function user_payment_form($user_id)
{
    global $xtpl, $api;

    try {
        $u = $api->user->find($user_id);

    } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
        $xtpl->perex_format_errors(_('User not found'), $e->getResponse());
        return;
    }

    $paidUntil = strtotime($u->paid_until);

    $xtpl->title(_("User payments"));

    $xtpl->table_td(_("Login") . ':');
    $xtpl->table_td($u->login);
    $xtpl->table_tr();

    $xtpl->table_td(_("Paid until") . ':');

    if ($paidUntil) {
        $lastPaidTo = date('Y-m-d', $paidUntil);

    } else {
        $lastPaidTo = _("Never been paid");
    }

    $xtpl->table_td($lastPaidTo);
    $xtpl->table_tr();

    $xtpl->table_td(_("Monthly payment") . ':');
    $xtpl->table_td($u->monthly_payment);
    $xtpl->table_tr();

    $xtpl->table_add_category('');
    $xtpl->table_add_category('');
    $xtpl->table_out();

    $xtpl->table_title(_('Set paid until date'));
    $xtpl->form_create('?page=adminm&action=payset2&id=' . $u->id, 'post');
    $xtpl->form_add_input(
        _("Paid until") . ':',
        'text',
        '30',
        'paid_until',
        post_val('paid_until'),
        _('YYYY-MM-DD, e.g.') . ' ' . date('Y-m-d')
    );
    $xtpl->form_out(_("Save"));

    $xtpl->table_title(_('Add payment'));
    $xtpl->form_create('?page=adminm&action=payset2&id=' . $u->id, 'post');
    $xtpl->form_add_input(_("Amount") . ':', 'text', '30', 'amount', post_val('amount'));
    $xtpl->form_out(_("Save"));

    $xtpl->table_title(_('Payment log'));
    $xtpl->table_add_category("ACCEPTED AT");
    $xtpl->table_add_category("ACCOUNTED BY");
    $xtpl->table_add_category("AMOUNT");
    $xtpl->table_add_category("FROM");
    $xtpl->table_add_category("TO");
    $xtpl->table_add_category("PAYMENT");

    $payments = $api->user_payment->list([
        'user' => $u->id,
        'meta' => ['includes' => 'accounted_by'],
    ]);

    foreach ($payments as $payment) {
        $xtpl->table_td(tolocaltz($payment->created_at));
        $xtpl->table_td($payment->accounted_by_id ? $payment->accounted_by->login : '-');
        $xtpl->table_td($payment->amount, false, true);
        $xtpl->table_td(tolocaltz($payment->from_date, 'Y-m-d'));
        $xtpl->table_td(tolocaltz($payment->to_date, 'Y-m-d'));

        if ($payment->incoming_payment_id) {
            $xtpl->table_td(
                '<a href="?page=adminm&action=incoming_payment&id=' .
                $payment->incoming_payment_id . '">' .
                '#' . $payment->incoming_payment_id .
                '</a>'
            );
        } else {
            $xtpl->table_td('-');
        }

        $xtpl->table_tr();
    }

    $xtpl->table_out();
}

function user_payment_history()
{
    global $xtpl, $api;

    $params = [
        'limit' => get_val('limit', 25),
        'meta' => ['includes' => 'user,accounted_by'],
    ];

    if (($_GET['from_id'] ?? 0) > 0) {
        $params['from_id'] = $_GET['from_id'];
    }

    foreach (['accounted_by', 'user'] as $filter) {
        if ($_GET[$filter]) {
            $params[$filter] = $_GET[$filter];
        }
    }

    $payments = $api->user_payment->list($params);
    $pagination = new \Pagination\System($payments);

    $xtpl->title(_('Payment history'));

    $xtpl->form_create('?page=adminm&action=payments_history', 'get');

    $xtpl->form_set_hidden_fields([
        'page' => 'adminm',
        'action' => 'payments_history',
    ]);

    $xtpl->form_add_input(_("Limit") . ':', 'text', '40', 'limit', get_val('limit', 25), '');
    $xtpl->form_add_input(_("Admin ID") . ':', 'text', '40', 'accounted_by', get_val('accounted_by'));
    $xtpl->form_add_input(_("User ID") . ':', 'text', '40', 'user', get_val('user'));
    $xtpl->form_out(_("Show"));

    $xtpl->table_add_category("ACCEPTED AT");
    $xtpl->table_add_category("USER");
    $xtpl->table_add_category("ACCOUNTED BY");
    $xtpl->table_add_category("AMOUNT");
    $xtpl->table_add_category("FROM");
    $xtpl->table_add_category("TO");
    $xtpl->table_add_category("MONTHS");

    foreach ($payments as $p) {
        $xtpl->table_td(tolocaltz($p->created_at));
        $xtpl->table_td($p->user_id ? user_link($p->user) : '-');
        $xtpl->table_td($p->accounted_by_id ? user_link($p->accounted_by) : '-');
        $xtpl->table_td($p->amount, false, true);
        $xtpl->table_td(tolocaltz($p->from_date, 'Y-m-d'));
        $xtpl->table_td(tolocaltz($p->to_date, 'Y-m-d'));
        $xtpl->table_td(
            round((strtotime($p->to_date) - strtotime($p->from_date)) / 2629800),
            false,
            true
        );
        $xtpl->table_tr();
    }

    $xtpl->table_pagination($pagination);
    $xtpl->table_out();
}

function incoming_payments_list()
{
    global $xtpl, $api;

    $params = [
        'limit' => get_val('limit', 25),
    ];

    if (($_GET['from_id'] ?? 0) > 0) {
        $params['from_id'] = $_GET['from_id'];
    }

    if (isset($_GET['state'])) {
        $params['state'] = $_GET['state'];
    }

    $payments = $api->incoming_payment->list($params);
    $pagination = new \Pagination\System($payments);

    $xtpl->title(_('Incoming payments'));

    $xtpl->form_create('?page=adminm&action=incoming_payments', 'get');

    $xtpl->form_set_hidden_fields([
        'page' => 'adminm',
        'action' => 'incoming_payments',
    ]);

    $xtpl->form_add_input(_("Limit") . ':', 'text', '40', 'limit', get_val('limit', 25), '');
    $xtpl->form_add_input(_('From ID') . ':', 'text', '40', 'from_id', get_val('from_id'), '');

    $input = $api->incoming_payment->list->getParameters('input');

    api_param_to_form(
        'state',
        $input->state,
        get_val('state')
    );

    $xtpl->form_out(_('Show'));

    $xtpl->table_add_category("DATE");
    $xtpl->table_add_category("AMOUNT");
    $xtpl->table_add_category("STATE");
    $xtpl->table_add_category("FROM");
    $xtpl->table_add_category("MESSAGE");
    $xtpl->table_add_category("VS");
    $xtpl->table_add_category("");

    foreach ($payments as $p) {
        $xtpl->table_td(tolocaltz($p->date, 'Y-m-d'));
        $xtpl->table_td($p->amount . "&nbsp;" . $p->currency, false, true);
        $xtpl->table_td($p->state);
        $xtpl->table_td(h($p->account_name));
        $xtpl->table_td(h($p->user_message));
        $xtpl->table_td(h($p->vs));
        $xtpl->table_td(
            '<a href="?page=adminm&action=incoming_payment&id=' . $p->id . '">' .
            '<img src="template/icons/m_edit.png" title="' . _('Details') . '">' .
            '</a>'
        );

        $xtpl->table_tr();
    }

    $xtpl->table_pagination($pagination);
    $xtpl->table_out();
}

function incoming_payments_details($id)
{
    global $xtpl, $api;

    $p = $api->incoming_payment->find($id);

    $xtpl->title(_("Incoming payment") . ' #' . $p->id);
    $xtpl->form_create('?page=adminm&action=incoming_payment_state&id=' . $p->id, 'post');

    $xtpl->table_td(_('Transaction ID') . ':');
    $xtpl->table_td(h($p->transaction_id));
    $xtpl->table_tr();

    $xtpl->table_td(_('Date') . ':');
    $xtpl->table_td(tolocaltz($p->date, 'Y-m-d'));
    $xtpl->table_tr();

    $xtpl->table_td(_('Accepted at') . ':');
    $xtpl->table_td(tolocaltz($p->created_at));
    $xtpl->table_tr();

    $state_desc = $api->incoming_payment->update->getParameters('input')->state;

    api_param_to_form(
        'state',
        $state_desc,
        post_val('state', $p->state)
    );

    $xtpl->table_td(_('Type') . ':');
    $xtpl->table_td(h($p->transaction_type));
    $xtpl->table_tr();

    $xtpl->table_td(_('Amount') . ':');
    $xtpl->table_td($p->amount);
    $xtpl->table_tr();

    $xtpl->table_td(_('Currency') . ':');
    $xtpl->table_td(h($p->currency));
    $xtpl->table_tr();

    if ($p->src_amount) {
        $xtpl->table_td(_('Original amount') . ':');
        $xtpl->table_td($p->src_amount);
        $xtpl->table_tr();

        $xtpl->table_td(_('Original currency') . ':');
        $xtpl->table_td(h($p->src_currency));
        $xtpl->table_tr();
    }

    $xtpl->table_td(_('Account name') . ':');
    $xtpl->table_td(h($p->account_name));
    $xtpl->table_tr();

    $xtpl->table_td(_('User identification') . ':');
    $xtpl->table_td(h($p->user_ident));
    $xtpl->table_tr();

    $xtpl->table_td(_('User message') . ':');
    $xtpl->table_td(h($p->user_message));
    $xtpl->table_tr();

    $xtpl->table_td(_('VS') . ':');
    $xtpl->table_td(h($p->vs));
    $xtpl->table_tr();

    $xtpl->table_td(_('KS') . ':');
    $xtpl->table_td(h($p->ks));
    $xtpl->table_tr();

    $xtpl->table_td(_('SS') . ':');
    $xtpl->table_td(h($p->ss));
    $xtpl->table_tr();

    $xtpl->table_td(_('Comment') . ':');
    $xtpl->table_td(h($p->comment));
    $xtpl->table_tr();

    $xtpl->form_out(_('Set state'));

    if ($p->state != 'processed') {
        $xtpl->table_title(_('Assign payment'));
        $xtpl->form_create('?page=adminm&action=incoming_payment_assign&id=' . $p->id, 'post');
        $xtpl->form_add_input(_('User ID') . ':', 'text', '30', 'user', post_val('user'));
        $xtpl->form_out(_('Assign'));
    }
}

function mail_template_recipient_form($user_id)
{
    global $xtpl, $api;

    $u = $api->user->show($user_id);

    $xtpl->title(_('Mail template recipients'));

    $xtpl->form_create('?page=adminm&action=template_recipients&id=' . $u->id, 'post');
    $xtpl->table_add_category(_('Templates'));
    $xtpl->table_add_category(_('E-mails'));

    $xtpl->table_td(
        _('E-mails configured here override role recipients. It is a comma separated list of e-mails, may contain line breaks.'),
        false,
        false,
        2
    );
    $xtpl->table_tr();

    foreach ($u->mail_template_recipient->list() as $recp) {
        $xtpl->table_td(
            $recp->label ? $recp->label : $recp->id,
            false,
            false,
            1,
            $recp->description ? 3 : 2
        );
        $xtpl->form_add_textarea_pure(
            50,
            5,
            "to[{$recp->id}]",
            $_POST['to'][$recp->id] ? $_POST['to'][$recp->id] : str_replace(',', ",\n", $recp->to)
        );
        $xtpl->table_tr();

        $xtpl->form_add_checkbox_pure(
            "disable[{$recp->id}]",
            '1',
            isset($_POST['disable']) ? isset($_POST['disable'][$recp->id]) : !$recp->enabled,
            _("Do <strong>not</strong> send this e-mail")
        );
        $xtpl->table_tr();

        if ($recp->description) {
            $xtpl->table_td($recp->description);
            $xtpl->table_tr();
        }
    }

    $xtpl->form_out(_('Save'));
}

function sort_resource_packages($pkgs)
{
    $ret = [];
    $envs = [];

    foreach ($pkgs as $pkg) {
        $envs[$pkg->environment_id] = $pkg->environment;
    }

    usort($envs, function ($a, $b) {
        return $a->environment_id - $b->environment_id;
    });

    foreach ($envs as $env) {
        $env_pkgs = [];

        foreach ($pkgs as $pkg) {
            if ($pkg->environment_id == $env->id) {
                $env_pkgs[] = $pkg;
            }
        }

        $ret[] = [$env, $env_pkgs];
    }

    return $ret;
}

function resource_package_counts($env_pkgs)
{
    $ret = [];
    $tmp = [];

    foreach ($env_pkgs as $pkg) {
        if ($pkg->is_personal) {
            continue;
        } elseif (array_key_exists($pkg->label, $tmp)) {
            $tmp[$pkg->label] += 1;
        } else {
            $tmp[$pkg->label] = 1;
        }
    }

    foreach ($tmp as $pkg_label => $count) {
        $pkg = null;

        foreach ($env_pkgs as $p) {
            if ($p->label == $pkg_label) {
                $pkg = $p;
                break;
            }
        }

        $ret[] = [$pkg, $count];
    }

    return $ret;
}

function list_user_resource_packages($user_id)
{
    global $xtpl, $api;

    $convert = ['memory', 'swap', 'diskspace'];

    $xtpl->title(_('User') . ' <a href="?page=adminm&action=edit&id=' . $user_id . '">#' . $user_id . '</a>: ' . _('Cluster resource packages'));

    $pkgs = $api->user_cluster_resource_package->list([
        'user' => $user_id,
        'meta' => ['includes' => 'environment'],
    ]);
    $sorted_pkgs = sort_resource_packages($pkgs);

    $xtpl->table_title(_('Summary'));
    $xtpl->table_add_category(_('Environment'));
    $xtpl->table_add_category(_('Package'));
    $xtpl->table_add_category(_('Count'));

    foreach ($sorted_pkgs as $v) {
        [$env, $env_pkgs] = $v;

        $pkg_counts = resource_package_counts($env_pkgs);
        $xtpl->table_td($env->label, false, false, '1', count($pkg_counts));

        foreach ($pkg_counts as $v) {
            [$pkg, $count] = $v;
            $xtpl->table_td($pkg->label);
            $xtpl->table_td($count . "&times;");
            $xtpl->table_tr('#fff', '#fff', 'nohover');
        }
    }

    $xtpl->table_out();

    foreach ($sorted_pkgs as $v) {
        [$env, $env_pkgs] = $v;

        $xtpl->table_title(_('Environment') . ': ' . $env->label);

        foreach ($env_pkgs as $pkg) {
            $xtpl->table_td(_('Package') . ':');
            $xtpl->table_td($pkg->label);

            if (isAdmin()) {
                $xtpl->table_td('<a href="?page=adminm&action=resource_packages_edit&id=' . $user_id . '&pkg=' . $pkg->id . '"><img src="template/icons/m_edit.png"  title="' . _("Edit") . '"></a>');

                if ($pkg->is_personal) {
                    $xtpl->table_td('<a href="?page=cluster&action=resource_packages_edit&id=' . $pkg->cluster_resource_package_id . '"><img src="template/icons/tool.png"  title="' . _("Configure resources") . '"></a>');
                } else {
                    $xtpl->table_td('<a href="?page=adminm&action=resource_packages_delete&id=' . $user_id . '&pkg=' . $pkg->id . '"><img src="template/icons/delete.png"  title="' . _("Delete") . '"></a>');
                }
            }

            $xtpl->table_tr();

            $xtpl->table_td(_('Resources') . ':');

            $items = $pkg->item->list(['meta' => ['includes' => 'cluster_resource']]);
            $s = '';

            foreach ($items as $it) {
                $s .= $it->cluster_resource->label . ": ";

                if (in_array($it->cluster_resource->name, $convert)) {
                    $s .= data_size_to_humanreadable($it->value);
                } else {
                    $s .= approx_number($it->value);
                }

                $s .= "<br>\n";
            }

            $xtpl->table_td($s);
            $xtpl->table_tr();

            $xtpl->table_td(_('Since') . ':');
            $xtpl->table_td(tolocaltz($pkg->created_at));
            $xtpl->table_tr();

            if (isAdmin()) {
                $xtpl->table_td(_('Added by') . ':');
                $xtpl->table_td($pkg->added_by_id ? user_link($pkg->added_by) : '-');
                $xtpl->table_tr();

                $xtpl->table_td(_('Comment') . ':');
                $xtpl->table_td($pkg->comment);
                $xtpl->table_tr();
            }

            $xtpl->table_out();
        }
    }

    $xtpl->sbar_add('<br><img src="template/icons/m_edit.png"  title="' . _("Back to user details") . '" />' . _('Back to user details'), "?page=adminm&section=members&action=edit&id={$user_id}");

    if (isAdmin()) {
        $xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="' . _("Add package") . '" />' . _('Add package'), "?page=adminm&section=members&action=resource_packages_add&id={$user_id}");
    }
}

function user_resource_package_add_form($user_id)
{
    global $xtpl, $api;

    $user = $api->user->show($user_id);
    $desc = $api->user_cluster_resource_package->create->getParameters('input');

    $xtpl->title(_('User') . ' <a href="?page=adminm&action=edit&id=' . $user->id . '">#' . $user->id . '</a>: ' . _('Add cluster resource package'));
    $xtpl->form_create('?page=adminm&action=resource_packages_add&id=' . $user->id, 'post');

    $xtpl->table_td('User' . ':');
    $xtpl->table_td($user->id . ' ' . $user->login);
    $xtpl->table_tr();

    api_param_to_form('environment', $desc->environment);

    $xtpl->form_add_select(
        _('Package') . ':',
        'cluster_resource_package',
        resource_list_to_options($api->cluster_resource_package->list(['user' => null])),
        post_val('cluster_resource_package')
    );

    api_param_to_form('comment', $desc->comment);
    api_param_to_form('from_personal', $desc->from_personal);

    $xtpl->form_out(_('Add'));
}

function user_resource_package_edit_form($user_id, $pkg_id)
{
    global $xtpl, $api;

    $user = $api->user->show($user_id);
    $pkg = $api->user_cluster_resource_package->show($pkg_id);
    $desc = $api->user_cluster_resource_package->update->getParameters('input');

    if ($user->id != $pkg->user_id) {
        die('invalid user or package');
    }

    $xtpl->title(_('User') . ' <a href="?page=adminm&action=edit&id=' . $user->id . '">#' . $user->id . '</a>: ' . _('Edit cluster resource package'));
    $xtpl->form_create('?page=adminm&action=resource_packages_edit&id=' . $user->id . '&pkg=' . $pkg->id, 'post');

    $xtpl->table_td('User' . ':');
    $xtpl->table_td($user->id . ' ' . $user->login);
    $xtpl->table_tr();

    $xtpl->table_td('Environment' . ':');
    $xtpl->table_td($pkg->environment->label);
    $xtpl->table_tr();

    $xtpl->table_td('Package' . ':');
    $xtpl->table_td($pkg->label);
    $xtpl->table_tr();

    api_param_to_form('comment', $desc->comment, $pkg->comment);

    $xtpl->form_out(_('Save'));

    if ($pkg->is_personal) {

    }

    $xtpl->sbar_add('<br><img src="template/icons/m_edit.png"  title="' . _("Back") . '" />' . _('Back'), "?page=adminm&section=members&action=resource_packages&id={$user_id}");
    $xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="' . _("Edit resources") . '" />' . _('Edit resources'), "?page=cluster&action=resource_packages_edit&id={$pkg->cluster_resource_package_id}");
}

function user_resource_package_delete_form($user_id, $pkg_id)
{
    global $xtpl, $api;

    $user = $api->user->show($user_id);
    $pkg = $api->user_cluster_resource_package->show($pkg_id);

    if ($user->id != $pkg->user_id) {
        die('invalid user or package');
    }

    $xtpl->title(_('Remove cluster resource package'));
    $xtpl->form_create('?page=adminm&action=resource_packages_delete&id=' . $user->id . '&pkg=' . $pkg->id, 'post');

    $xtpl->table_td('User' . ':');
    $xtpl->table_td($user->id . ' ' . $user->login);
    $xtpl->table_tr();

    $xtpl->table_td('Environment' . ':');
    $xtpl->table_td($pkg->environment->label);
    $xtpl->table_tr();

    $xtpl->table_td('Package' . ':');
    $xtpl->table_td($pkg->label);
    $xtpl->table_tr();

    $xtpl->form_add_checkbox(_('Confirm') . ':', 'confirm', '1', false);

    $xtpl->form_out(_('Remove'));

    $xtpl->sbar_add('<br>' . _("Back"), '?page=adminm&action=resource_packages&id=' . $user->id);
}

function totp_devices_list_form($user)
{
    global $xtpl, $api;

    $xtpl->table_title(_("TOTP devices"));
    $xtpl->table_add_category(_('Label'));
    $xtpl->table_add_category(_('Confirmed'));
    $xtpl->table_add_category(_('Enabled'));
    $xtpl->table_add_category(_('Use count'));
    $xtpl->table_add_category(_('Created at'));
    $xtpl->table_add_category(_('Last use'));
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');

    $devices = $user->totp_device->list();

    if ($devices->count() == 0) {
        $xtpl->table_td(
            '<a href="?page=adminm&action=totp_device_add&id=' . $user->id . '">' .
            _('Add TOTP device') . '</a>',
            false,
            false,
            '7'
        );
        $xtpl->table_tr();
    }

    foreach ($devices as $dev) {
        $xtpl->table_td(h($dev->label));
        $xtpl->table_td(boolean_icon($dev->confirmed));
        $xtpl->table_td(boolean_icon($dev->enabled));
        $xtpl->table_td($dev->use_count . '&times;');
        $xtpl->table_td(tolocaltz($dev->created_at));
        $xtpl->table_td($dev->last_use_at ? tolocaltz($dev->last_use_at) : '-');

        $xtpl->table_td('<a href="?page=adminm&action=totp_device_toggle&id=' . $user->id . '&dev=' . $dev->id . '&toggle=' . ($dev->enabled ? 'disable' : 'enable') . '&t=' . csrf_token() . '">' . ($dev->enabled ? _('Disable') : _('Enable')) . '</a>');
        $xtpl->table_td('<a href="?page=adminm&action=totp_device_edit&id=' . $user->id . '&dev=' . $dev->id . '"><img src="template/icons/m_edit.png"  title="' . _("Edit") . '" /></a>');
        $xtpl->table_td('<a href="?page=adminm&action=totp_device_del&id=' . $user->id . '&dev=' . $dev->id . '"><img src="template/icons/m_delete.png"  title="' . _("Delete") . '" /></a>');

        $xtpl->table_tr();
    }

    $xtpl->table_out();

    $xtpl->sbar_add('<br><img src="template/icons/m_edit.png"  title="' . _("Add TOTP device") . '" />' . _('Add TOTP device'), "?page=adminm&action=totp_device_add&id={$user->id}");
    $xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="' . _("Back to user details") . '" />' . _('Back to user details'), "?page=adminm&action=edit&id={$user->id}");
}

function totp_device_add_form($user)
{
    global $xtpl, $api;

    $xtpl->table_title(_("Add TOTP device"));
    $xtpl->form_create('?page=adminm&action=totp_device_add&id=' . $user->id, 'post');

    $xtpl->table_td(
        _('Pick a name for your authentication device. It can be changed at any time.'),
        false,
        false,
        '2'
    );
    $xtpl->table_tr();

    $xtpl->form_add_input(_('Label') . ':', 'text', '40', 'label', post_val('label'));
    $xtpl->form_out(_('Continue'));

    $xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="' . _("Back to user details") . '" />' . _('Back to user details'), "?page=adminm&action=edit&id={$user->id}");
}

function totp_device_confirm_form($user, $dev)
{
    global $xtpl, $api;

    $xtpl->table_title(_('Confirm TOTP device setup'));

    $xtpl->form_create('?page=adminm&action=totp_device_confirm&id=' . $user->id . '&dev=' . $dev->id, 'post');

    $xtpl->table_td(
        _('Install a TOTP authenticator application like FreeOTP or Google Authenticator ' .
          'and scan the QR code below, or enter the secret key manually.'),
        false,
        false,
        '2'
    );
    $xtpl->table_tr();

    $xtpl->table_td(_('Device') . ':');
    $xtpl->table_td(h($dev->label));
    $xtpl->table_tr();

    $qrWriter = new PngWriter();
    $qrCode = QrCode::create($_SESSION['totp_setup']['provisioning_uri']);
    $qrResult = $qrWriter->write($qrCode);

    $xtpl->table_td(_('QR code') . ':');
    $xtpl->table_td(
        '<img src="' . $qrResult->getDataUri() . '">'
    );
    $xtpl->table_tr();

    $xtpl->table_td(_('Secret key') . ':');
    $xtpl->table_td(implode('&nbsp;', str_split($_SESSION['totp_setup']['secret'], 4)));
    $xtpl->table_tr();

    $xtpl->form_add_input(_('TOTP code') . ':', 'text', '30', 'code');

    $xtpl->table_td(
        _('Once enabled, this authentication device or any other configured ' .
          'device will be needed to log into your account without any ' .
          'exception. Two-factor authentication can be later turned off by ' .
          'disabling or removing all configured authentication devices.'),
        false,
        false,
        '2'
    );
    $xtpl->table_tr();

    $xtpl->form_out(_('Enable the device for two-factor authentication'));
}

function totp_device_configured_form($user, $dev, $recoveryCode)
{
    global $xtpl;

    $xtpl->perex(
        _('The TOTP device was configured'),
        _('The device can now be used for authentication.')
    );
    $xtpl->table_title(_('Recovery code'));

    $xtpl->form_create('?page=adminm&action=edit&id=' . $user->id, 'get');

    $xtpl->table_td(
        _('Two-factor authentication using TOTP is now enabled. In case you ever ' .
          'lose access to the TOTP authenticator device, you can use ' .
          'the recovery code below instead of the TOTP token to log in.') .
          '<input type="hidden" name="page" value="adminm">' .
          '<input type="hidden" name="action" value="totp_devices">' .
          '<input type="hidden" name="id" value="' . $user->id . '">',
        false,
        false,
        '2'
    );
    $xtpl->table_tr();

    $xtpl->table_td(_('Device') . ':');
    $xtpl->table_td(h($dev->label));
    $xtpl->table_tr();

    $xtpl->table_td(_('Recovery code') . ':');
    $xtpl->table_td($recoveryCode);
    $xtpl->table_tr();

    $xtpl->form_out(_('Go to TOTP device list'));
}

function totp_device_edit_form($user, $dev)
{
    global $xtpl, $api;

    $xtpl->table_title(_("Edit TOTP device"));
    $xtpl->form_create('?page=adminm&action=totp_device_edit&id=' . $user->id . '&dev=' . $dev->id, 'post');
    $xtpl->form_add_input(_('Label') . ':', 'text', '40', 'label', post_val('label', $dev->label));
    $xtpl->form_out(_('Save'));

    $xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="' . _("Back to user details") . '" />' . _('Back to user details'), "?page=adminm&action=edit&id={$user->id}");
    $xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="' . _("Back to TOTP devices") . '" />' . _('Back to TOTP devices'), "?page=adminm&action=totp_devices&id={$user->id}");
}

function totp_device_del_form($user, $dev)
{
    global $xtpl, $api;

    $xtpl->table_title(_('Confirm TOTP device deletion'));
    $xtpl->form_create('?page=adminm&action=totp_device_del&id=' . $user->id . '&dev=' . $dev->id, 'post');

    $xtpl->table_td('Device' . ':');
    $xtpl->table_td(h($dev->label));
    $xtpl->table_tr();

    $xtpl->table_td(
        _('Two-factor authentication will be turned off when the last ' .
          'authentication device is either disabled or removed.'),
        false,
        false,
        '2'
    );
    $xtpl->table_tr();

    $xtpl->form_add_checkbox(_('Confirm') . ':', 'confirm', '1', false);

    $xtpl->form_out(_('Delete'));
}

function webauthn_list($user)
{
    global $xtpl;

    $xtpl->table_title(_('Passkeys'));
    $xtpl->table_add_category(_('Label'));
    $xtpl->table_add_category(_('Enabled'));
    $xtpl->table_add_category(_('Use count'));
    $xtpl->table_add_category(_('Created at'));
    $xtpl->table_add_category(_('Last use'));
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');

    $creds = $user->webauthn_credential->list();

    foreach ($creds as $cred) {
        $xtpl->table_td(h($cred->label));
        $xtpl->table_td(boolean_icon($cred->enabled));
        $xtpl->table_td($cred->sign_count, false, true);
        $xtpl->table_td(tolocaltz($cred->created_at));
        $xtpl->table_td($cred->last_use_at ? tolocaltz($cred->last_use_at) : '-');
        $xtpl->table_td('<a href="?page=adminm&action=webauthn_toggle&id=' . $user->id . '&cred=' . $cred->id . '&toggle=' . ($cred->enabled ? 'disable' : 'enable') . '&t=' . csrf_token() . '">' . ($cred->enabled ? _('Disable') : _('Enable')) . '</a>');
        $xtpl->table_td('<a href="?page=adminm&action=webauthn_edit&id=' . $user->id . '&cred=' . $cred->id . '"><img src="template/icons/m_edit.png"  title="' . _("Edit") . '" /></a>');
        $xtpl->table_td('<a href="?page=adminm&action=webauthn_del&id=' . $user->id . '&cred=' . $cred->id . '"><img src="template/icons/m_delete.png"  title="' . _("Delete") . '" /></a>');

        $xtpl->table_tr();
    }

    if ($creds->count() == 0) {
        $xtpl->table_td(_('No passkeys configured.'), false, false, 8);
        $xtpl->table_tr();
    }

    $xtpl->table_out();

    if ($_SESSION['user']['id'] == $user->id) {
        $xtpl->table_title(_('Register a new passkey'));

        if ($_SESSION['auth_type'] == 'oauth2') {
            $xtpl->form_create(getWebAuthnNewRegistrationUrl(), 'get', 'webauthn_register', false);
            $xtpl->form_set_hidden_fields([
                'access_token' => $_SESSION['access_token']['access_token'],
                'redirect_uri' => getSelfUri() . '/?page=adminm&action=webauthn_register&id=' . $user->id,
            ]);
            $xtpl->table_td(_('You will be redirected to the authentication server.'), false, false, 2);
            $xtpl->table_tr();
            $xtpl->form_out(_('Register new passkey'));
        } else {
            $xtpl->table_td(_('Passkeys cannot be registered by administrators logged in as users.'));
            $xtpl->table_tr();
            $xtpl->table_out();
        }
    }

    $xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="' . _("Back to user details") . '" />' . _('Back to user details'), "?page=adminm&action=edit&id={$user->id}");
}

function webauthn_edit_form($user, $cred)
{
    global $xtpl;

    $xtpl->table_title(_("Edit passkey"));
    $xtpl->form_create('?page=adminm&action=webauthn_edit&id=' . $user->id . '&cred=' . $cred->id, 'post');
    $xtpl->form_add_input(_('Label') . ':', 'text', '40', 'label', post_val('label', $cred->label));
    $xtpl->form_out(_('Save'));

    $xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="' . _("Back to user details") . '" />' . _('Back to user details'), "?page=adminm&action=edit&id={$user->id}");
    $xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="' . _("Back to passkeys") . '" />' . _('Back to passkeys'), "?page=adminm&action=webauthn_list&id={$user->id}");
}

function webauthn_del_form($user, $cred)
{
    global $xtpl;

    $xtpl->table_title(_('Confirm passkey deletion'));
    $xtpl->form_create('?page=adminm&action=webauthn_del&id=' . $user->id . '&cred=' . $cred->id, 'post');

    $xtpl->table_td('Passkey' . ':');
    $xtpl->table_td(h($cred->label));
    $xtpl->table_tr();

    $xtpl->table_td(
        _('Two-factor authentication will be turned off when the last ' .
          'authentication device is either disabled or removed.'),
        false,
        false,
        '2'
    );
    $xtpl->table_tr();

    $xtpl->form_add_checkbox(_('Confirm') . ':', 'confirm', '1', false);

    $xtpl->form_out(_('Delete'));

    $xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="' . _("Back to user details") . '" />' . _('Back to user details'), "?page=adminm&action=edit&id={$user->id}");
    $xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="' . _("Back to passkeys") . '" />' . _('Back to passkeys'), "?page=adminm&action=webauthn_list&id={$user->id}");
}

function known_devices_list_form($user)
{
    global $xtpl, $api;

    $xtpl->title(_('Known login devices of') . ' <a href="?page=adminm&action=edit&id=' . $user->id . '">#' . $user->id . '</a> ' . $user->login);
    $xtpl->table_title(_('Filters'));
    $xtpl->form_create('', 'get', 'known-device-filter', false);

    $xtpl->table_td(
        _("Limit") . ':' .
        '<input type="hidden" name="page" value="adminm">' .
        '<input type="hidden" name="action" value="known_devices">' .
        '<input type="hidden" name="id" value="' . $user->id . '">'
    );
    $xtpl->form_add_input_pure('text', '40', 'limit', get_val('limit', '25'), '');
    $xtpl->table_tr();

    $xtpl->form_add_checkbox(_('Detailed output') . ':', 'details', '1', isset($_GET['details']));
    $xtpl->form_out(_('Show'));

    $xtpl->table_add_category(_('OS'));
    $xtpl->table_add_category(_('Browser'));
    $xtpl->table_add_category(_('IP address'));
    $xtpl->table_add_category(_('Reverse record'));
    $xtpl->table_add_category(_('Created at'));
    $xtpl->table_add_category(_('Last seen'));
    $xtpl->table_add_category(_('Next 2FA'));
    $xtpl->table_add_category('');

    $devices = $user->known_device->list();

    foreach ($devices as $dev) {
        $ua = new WhichBrowser\Parser($dev->user_agent);

        $xtpl->table_td(h($ua->os->toString()));
        $xtpl->table_td(h($ua->browser->toString()));
        $xtpl->table_td(h($dev->client_ip_addr));
        $xtpl->table_td(h($dev->client_ip_ptr));
        $xtpl->table_td(tolocaltz($dev->created_at));
        $xtpl->table_td(tolocaltz($dev->last_seen_at));
        $xtpl->table_td($dev->skip_multi_factor_auth_until ? tolocaltz($dev->skip_multi_factor_auth_until) : '-');
        $xtpl->table_td('<a href="?page=adminm&action=known_device_del&id=' . $user->id . '&dev=' . $dev->id . '&t=' . csrf_token() . '"><img src="template/icons/m_delete.png"  title="' . _("Delete") . '" /></a>');
        $xtpl->table_tr();

        if (!isset($_GET['details'])) {
            continue;
        }

        $xtpl->table_td(
            _('User agent') . ': ' . h($dev->user_agent),
            false,
            false,
            8
        );
        $xtpl->table_tr();
    }

    $xtpl->table_out();

    $xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="' . _("Back to user details") . '" />' . _('Back to user details'), "?page=adminm&action=edit&id={$user->id}");
}

function metrics_list_access_tokens($user_id)
{
    global $xtpl, $api;

    $xtpl->table_title(_('Metrics access tokens'));
    $xtpl->table_add_category(_('Access token'));
    $xtpl->table_add_category(_('Prefix'));
    $xtpl->table_add_category(_('Use count'));
    $xtpl->table_add_category(_('Last use'));
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');

    $tokens = $api->metrics_access_token->list(['user' => $user_id]);

    foreach ($tokens as $t) {
        $xtpl->table_td('<a href="?page=adminm&action=metrics_show&id=' . $user_id . '&token=' . $t->id . '">' . substr($t->access_token, 0, 10) . '...</a>');
        $xtpl->table_td(h($t->metric_prefix));
        $xtpl->table_td($t->use_count . '&times;');
        $xtpl->table_td($t->last_use ? tolocaltz($t->last_use) : '-');
        $xtpl->table_td('<a href="?page=adminm&action=metrics_show&id=' . $user_id . '&token=' . $t->id . '"><img src="template/icons/m_edit.png" title="' . _('Show access details') . '"></a>');
        $xtpl->table_td('<a href="?page=adminm&action=metrics_delete&id=' . $user_id . '&token=' . $t->id . '&t=' . csrf_token() . '"><img src="template/icons/m_delete.png" title="' . _('Delete access token') . '"></a>');
        $xtpl->table_tr();
    }

    $xtpl->table_td('<a href="?page=adminm&action=metrics_new&id=' . $user_id . '">' . _('New access token') . '</a>', false, true, 6);
    $xtpl->table_tr();

    $xtpl->table_out();

    $xtpl->sbar_add('<br><img src="template/icons/m_edit.png"  title="' . _("Back to user details") . '" />' . _('Back to user details'), "?page=adminm&section=members&action=edit&id=$user_id");
}

function metrics_show($user_id, $token_id)
{
    global $xtpl, $api;

    $t = $api->metrics_access_token->show($token_id);

    $xtpl->table_title(_('Metrics access token') . ' ' . substr($t->access_token, 0, 10));

    if (isAdmin()) {
        $xtpl->table_td(_('User') . ':');
        $xtpl->table_td(user_link($t->user));
        $xtpl->table_tr();
    }

    $xtpl->table_td(_('Access token') . ':');
    $xtpl->table_td('<code>' . h($t->access_token) . '</code>');
    $xtpl->table_tr();

    $xtpl->table_td(_('Metric prefix') . ':');
    $xtpl->table_td(h($t->metric_prefix));
    $xtpl->table_tr();

    $xtpl->table_td(_('Use count') . ':');
    $xtpl->table_td($t->use_count . '&times;');
    $xtpl->table_tr();

    $xtpl->table_td(_('Last use') . ':');
    $xtpl->table_td($t->last_use ? tolocaltz($t->last_use) : '-');
    $xtpl->table_tr();

    $scrapeUrl = EXT_API_URL . '/metrics?access_token=' . $t->access_token;

    $xtpl->table_td(_('Scrape URL') . ':');
    $xtpl->table_td("
		<textarea rows=\"10\" cols=\"80\" readonly>
{$scrapeUrl}
		</textarea>
	");
    $xtpl->table_tr();

    $xtpl->table_td(_('Scrape link') . ':');
    $xtpl->table_td('<a href="' . $scrapeUrl . '" target="_blank">' . _('open') . '</a>');
    $xtpl->table_tr();

    $xtpl->table_out();

    $xtpl->sbar_add('<br><img src="template/icons/m_edit.png"  title="' . _("Back to user details") . '" />' . _('Back to metrics access tokens'), "?page=adminm&action=metrics&id=$user_id");
    $xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="' . _("Back to user details") . '" />' . _('Back to user details'), "?page=adminm&section=members&action=edit&id=$user_id");

}

function metrics_new_form($user_id)
{
    global $xtpl, $api;

    $xtpl->table_title(_('Create new metrics access token'));
    $xtpl->form_create('?page=adminm&action=metrics_new&id=' . $user_id, 'post');

    $input = $api->metrics_access_token->create->getParameters('input');

    api_param_to_form('metric_prefix', $input->metric_prefix);

    $xtpl->form_out(_('Create'));

    $xtpl->sbar_add('<br><img src="template/icons/m_edit.png"  title="' . _("Back to user details") . '" />' . _('Back to metrics access tokens'), "?page=adminm&action=metrics&id=$user_id");
    $xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="' . _("Back to user details") . '" />' . _('Back to user details'), "?page=adminm&section=members&action=edit&id=$user_id");
}
