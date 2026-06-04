<?php

function security_advisory_link($advisory)
{
    return '<a href="?page=security_advisory&action=show&id=' . $advisory->id . '">'
        . _('Security advisory') . ' #' . $advisory->id
        . '</a>';
}

function security_advisory_cve_links($cves)
{
    $ret = [];

    if (is_string($cves)) {
        $items = [];
        foreach (preg_split('/[,\s]+/', $cves) as $cve) {
            $cve = trim($cve);
            if ($cve === '') {
                continue;
            }
            $items[] = (object) [
                'cve_id' => strtoupper($cve),
                'url' => 'https://www.cve.org/CVERecord?id=' . strtoupper($cve),
            ];
        }
    } else {
        $items = $cves;
    }

    foreach ($items as $cve) {
        $cveId = is_object($cve) ? $cve->cve_id : $cve['cve_id'];
        $url = is_object($cve) ? $cve->url : $cve['url'];

        if (!$cveId) {
            continue;
        }

        $ret[] = '<a href="' . h($url) . '" target="_blank">'
            . h($cveId)
            . '</a>';
    }

    return implode(', ', $ret);
}

function security_advisory_parse_cves($value)
{
    $ret = [];

    foreach (preg_split('/[,\s]+/', $value) as $cve) {
        $cve = strtoupper(trim($cve));
        if ($cve === '') {
            continue;
        }

        if (!preg_match('/^CVE-\d{4}-\d{4,}$/', $cve)) {
            throw new \InvalidArgumentException(sprintf(_('Invalid CVE identifier: %s'), $cve));
        }

        $ret[$cve] = $cve;
    }

    if (count($ret) === 0) {
        throw new \InvalidArgumentException(_('At least one CVE must be entered.'));
    }

    return array_values($ret);
}

function security_advisory_cve_rows($advisory, $refresh = false)
{
    global $api;
    static $cache = [];

    $id = is_object($advisory) ? $advisory->id : $advisory;

    if ($refresh || !isset($cache[$id])) {
        $cache[$id] = $api->security_advisory_cve->list([
            'security_advisory' => $id,
        ])->asArray();
    }

    return $cache[$id];
}

function security_advisory_cve_ids($advisory)
{
    return array_map(function ($cve) {
        return $cve->cve_id;
    }, security_advisory_cve_rows($advisory));
}

function security_advisory_cve_text($advisory)
{
    return implode(', ', security_advisory_cve_ids($advisory));
}

function security_advisory_option_label($advisory)
{
    $label = '#' . $advisory->id . ' ' . security_advisory_cve_text($advisory);

    if ($advisory->name) {
        $label .= ' - ' . $advisory->name;
    }

    return $label;
}

function security_advisory_save_cves($id, $desired = null)
{
    global $api;

    if ($desired === null) {
        $desired = security_advisory_parse_cves($_POST['cves'] ?? '');
    }

    $desired = array_flip($desired);
    $existing = [];

    foreach (security_advisory_cve_rows($id, true) as $cve) {
        if (isset($desired[$cve->cve_id])) {
            $existing[$cve->cve_id] = true;
        } else {
            $api->security_advisory_cve->delete($cve->id);
        }
    }

    foreach (array_keys($desired) as $cveId) {
        if (!isset($existing[$cveId])) {
            $api->security_advisory_cve->create([
                'security_advisory' => $id,
                'cve_id' => $cveId,
            ]);
        }
    }

    security_advisory_cve_rows($id, true);
}

function security_advisory_state_label($state)
{
    switch ($state) {
        case 'draft':
            return _('draft');
        case 'published':
            return _('published');
        case 'retracted':
            return _('retracted');
        default:
            return h($state);
    }
}

function security_advisory_node_state_label($state)
{
    switch ($state) {
        case 'unknown':
            return _('unknown');
        case 'not_affected':
            return _('not affected');
        case 'vulnerable':
            return _('vulnerable');
        case 'mitigated':
            return _('mitigated');
        default:
            return h($state);
    }
}

function security_advisory_time($value)
{
    return $value ? tolocaltz($value, 'Y-m-d H:i:s T') : '-';
}

function security_advisory_datetime_form_value($value = null)
{
    return $value ? tolocaltz($value, 'Y-m-d H:i') : date('Y-m-d H:i');
}

function security_advisory_current_language_code()
{
    global $lang;

    if (!isset($lang)) {
        return 'en';
    }

    $locale = $lang->get_current_lang();
    if (preg_match('/^([a-z]{2})/', $locale, $matches)) {
        return $matches[1];
    }

    return 'en';
}

function security_advisory_display_languages($langs)
{
    $ret = [];
    foreach ($langs as $l) {
        $ret[] = $l;
    }

    if (!isLoggedIn()) {
        return $ret;
    }

    $current = security_advisory_current_language_code();
    foreach ($ret as $l) {
        if ($l->code === $current) {
            return [$l];
        }
    }

    foreach ($ret as $l) {
        if ($l->code === 'en') {
            return [$l];
        }
    }

    return array_slice($ret, 0, 1);
}

function security_advisory_localized_text($object, $field)
{
    $codes = isLoggedIn() ? [security_advisory_current_language_code(), 'en'] : ['en'];

    foreach (array_unique($codes) as $code) {
        $name = $code . '_' . $field;
        $value = $object->{$name};
        if ($value !== null && $value !== '') {
            return $value;
        }
    }

    return '';
}

function security_advisory_node_role_label($type)
{
    switch ($type) {
        case 'node':
            return _('hypervisor');
        case 'storage':
            return _('storage');
        default:
            return h($type);
    }
}

function security_advisory_node_state_options()
{
    return [
        'unknown' => _('unknown'),
        'not_affected' => _('not affected'),
        'vulnerable' => _('vulnerable'),
        'mitigated' => _('mitigated'),
    ];
}

function security_advisory_nodes()
{
    global $api;

    $nodes = [];
    foreach (['node', 'storage'] as $type) {
        foreach ($api->node->list(['state' => 'active', 'type' => $type]) as $node) {
            $nodes[] = $node;
        }
    }

    usort($nodes, function ($a, $b) {
        return $a->id <=> $b->id;
    });

    return $nodes;
}

function security_advisory_sbar($id = null)
{
    global $xtpl;

    if (isAdmin()) {
        $xtpl->sbar_add(_('New security advisory'), '?page=security_advisory&action=new');
    }

    if ($id !== null) {
        $xtpl->sbar_add(_('Security advisory details'), '?page=security_advisory&action=show&id=' . $id);
    }

    $xtpl->sbar_add(_('Security advisories'), '?page=security_advisory&action=list');
}

function security_advisory_param_description($params, $name, $fallback = '')
{
    if (
        $params
        && isset($params->{$name})
        && isset($params->{$name}->description)
        && $params->{$name}->description
    ) {
        return $params->{$name}->description;
    }

    return $fallback;
}

function security_advisory_join_descriptions($descriptions)
{
    $ret = [];

    foreach ($descriptions as $desc) {
        if ($desc !== null && $desc !== '') {
            $ret[] = $desc;
        }
    }

    return implode(' ', $ret);
}

function security_advisory_form_input($label, $name, $value, $placeholder, $hint, $size = 60)
{
    global $xtpl;

    $xtpl->table_td($label);
    $xtpl->table_td(
        '<input type="text" size="' . $size . '" name="' . h($name) . '" value="' . h((string) $value) . '" placeholder="' . h($placeholder) . '" />'
    );
    $xtpl->table_td($hint);
    $xtpl->table_tr();
}

function security_advisory_form_textarea($label, $name, $value, $placeholder, $hint)
{
    global $xtpl;

    $xtpl->table_td($label);
    $xtpl->table_td(
        '<textarea name="' . h($name) . '" cols="60" rows="8" placeholder="' . h($placeholder) . '">'
        . htmlspecialchars((string) $value, ENT_NOQUOTES | ENT_SUBSTITUTE | ENT_HTML5, 'UTF-8', false)
        . '</textarea>'
    );
    $xtpl->table_td($hint);
    $xtpl->table_tr();
}

function security_advisory_form($id = null)
{
    global $xtpl, $api;

    $advisory = $id ? $api->security_advisory->show($id) : null;
    $langs = $api->language->list();
    $input = ($id ? $api->security_advisory->update : $api->security_advisory->create)
        ->getParameters('input');
    $cveInput = $api->security_advisory_cve->create->getParameters('input');

    $xtpl->title($id ? _('Edit security advisory') : _('New security advisory'));
    $xtpl->form_create(
        $id
            ? '?page=security_advisory&action=edit&id=' . $id
            : '?page=security_advisory&action=new',
        'post'
    );

    security_advisory_form_input(
        _('Published at') . ':',
        'published_at',
        post_val('published_at', security_advisory_datetime_form_value($advisory ? $advisory->published_at : null)),
        security_advisory_datetime_form_value(),
        security_advisory_param_description(
            $input,
            'published_at',
            _('Date and time shown as the advisory publication time.')
        ),
        30
    );
    security_advisory_form_input(
        _('CVEs') . ':',
        'cves',
        post_val('cves', $advisory ? security_advisory_cve_text($advisory) : ''),
        'CVE-2026-12345, CVE-2026-23456',
        security_advisory_join_descriptions([
            security_advisory_param_description(
                $cveInput,
                'cve_id',
                _('CVE identifier in CVE-YYYY-NNNN format.')
            ),
            _('Separate multiple CVEs with commas.'),
        ])
    );
    security_advisory_form_input(
        _('Name') . ':',
        'name',
        post_val('name', $advisory ? $advisory->name : ''),
        'Dirty Pipe',
        security_advisory_param_description(
            $input,
            'name',
            _('Optional well-known vulnerability name.')
        )
    );

    foreach ($langs as $lang) {
        $name = $lang->code . '_summary';
        security_advisory_form_input(
            $lang->label . ' ' . _('summary') . ':',
            $name,
            post_val($name, $advisory ? $advisory->{$name} : ''),
            _('A kernel bug could affect containers on selected nodes.'),
            security_advisory_param_description(
                $input,
                $name,
                _('One-sentence summary shown in advisory lists and emails.')
            )
        );

        $name = $lang->code . '_description';
        security_advisory_form_textarea(
            $lang->label . ' ' . _('description') . ':',
            $name,
            post_val($name, $advisory ? $advisory->{$name} : ''),
            _('Describe the vulnerability, affected kernel versions, and required conditions.'),
            security_advisory_param_description(
                $input,
                $name,
                _('User-facing explanation of the issue.')
            )
        );

        $name = $lang->code . '_response';
        security_advisory_form_textarea(
            $lang->label . ' ' . _('response') . ':',
            $name,
            post_val($name, $advisory ? $advisory->{$name} : ''),
            _('Describe the mitigation, rollout time, and whether users need to take action.'),
            security_advisory_param_description(
                $input,
                $name,
                _('What administrators did in response.')
            )
        );
    }

    if (!$id) {
        security_advisory_node_fields(null, true);
    }

    $xtpl->form_out($id ? _('Save') : _('Create draft'));
}

function security_advisory_list($recent = false)
{
    global $xtpl, $api;

    $params = [
        'order' => 'newest',
        'meta' => [
            'includes' => 'created_by,published_by',
        ],
    ];

    if ($recent) {
        $params['recent_since'] = date('c', time() - 60 * 60 * 24 * 30);
        $params['limit'] = 5;
        $params['state'] = 'published';
    }

    if (!$recent) {
        $state = api_get('state');
        if ($state !== null && $state !== '') {
            $params['state'] = $state;
        }

        $cve = api_get('cve');
        if ($cve !== null && $cve !== '') {
            $params['cve'] = $cve;
        }

        if (isLoggedIn()) {
            $affected = api_get('affected');
            if ($affected === 'yes') {
                $params['affected'] = true;
            } elseif ($affected === 'no') {
                $params['affected'] = false;
            }

            $vps = api_get_uint('vps');
            if ($vps !== null && $vps > 0) {
                $params['vps'] = $vps;
            }
        }
    }

    $advisories = $api->security_advisory->list($params);

    if ($recent && $advisories->count() == 0) {
        return;
    }

    $xtpl->table_title($recent ? _('Recent security advisories') : _('Security advisories'));
    $xtpl->table_add_category(_('Published'));
    if (!$recent) {
        $xtpl->table_add_category(_('State'));
    }
    $xtpl->table_add_category(_('CVEs'));
    $xtpl->table_add_category(_('Name'));
    if (!$recent) {
        $xtpl->table_add_category(_('Nodes'));
    }
    $xtpl->table_add_category(_('Summary'));

    if (isAdmin()) {
        $xtpl->table_add_category(_('Users'));
        $xtpl->table_add_category(_('VPS'));
    } elseif (isLoggedIn()) {
        $xtpl->table_add_category(_('Affects me?'));
    }

    $xtpl->table_add_category('');

    foreach ($advisories as $advisory) {
        $xtpl->table_td(security_advisory_time($advisory->published_at));
        if (!$recent) {
            $xtpl->table_td(security_advisory_state_label($advisory->state));
        }
        $xtpl->table_td(security_advisory_cve_links(security_advisory_cve_rows($advisory)));
        $xtpl->table_td(h($advisory->name ?: '-'));
        if (!$recent) {
            $xtpl->table_td($advisory->affected_node_count, false, true);
        }
        $xtpl->table_td(h(security_advisory_localized_text($advisory, 'summary')));

        if (isAdmin()) {
            $xtpl->table_td(
                '<a href="?page=security_advisory&action=users&id=' . $advisory->id . '">'
                . $advisory->affected_user_count
                . '</a>',
                false,
                true
            );
            $xtpl->table_td(
                '<a href="?page=security_advisory&action=vps&id=' . $advisory->id . '">'
                . $advisory->affected_vps_count
                . '</a>',
                false,
                true
            );
        } elseif (isLoggedIn()) {
            $xtpl->table_td(boolean_icon($advisory->affected));
        }

        $xtpl->table_td('<a href="?page=security_advisory&action=show&id=' . $advisory->id . '"><img src="template/icons/m_edit.png" title="' . _('Details') . '"></a>');
        $xtpl->table_tr();
    }

    if ($advisories->count() == 0) {
        $cols = 5 + (isAdmin() ? 2 : (isLoggedIn() ? 1 : 0));
        if (!$recent) {
            $cols += 2;
        }
        $xtpl->table_td(_('No security advisories found.'), false, false, $cols);
        $xtpl->table_tr();
    }

    $xtpl->table_out();
}

function security_advisory_details($id)
{
    global $xtpl, $api;

    $advisory = $api->security_advisory->show($id);
    $langs = security_advisory_display_languages($api->language->list());

    if (isAdmin()) {
        $xtpl->sbar_add(_('Edit advisory'), '?page=security_advisory&action=edit&id=' . $id);
        $xtpl->sbar_add(_('Node statuses'), '?page=security_advisory&action=nodes&id=' . $id);
        $xtpl->sbar_add(_('Post update'), '?page=security_advisory&action=update&id=' . $id);
        $xtpl->sbar_add(_('Affected users'), '?page=security_advisory&action=users&id=' . $id);
        $xtpl->sbar_add(_('Affected VPS'), '?page=security_advisory&action=vps&id=' . $id);
        $xtpl->sbar_add(_('New security advisory'), '?page=security_advisory&action=new');
    }

    $xtpl->sbar_add(_('Security advisories'), '?page=security_advisory&action=list');
    $xtpl->title(_('Security advisory') . ' #' . $id);

    if (isAdmin()) {
        $xtpl->table_title(_('Affected resources'));
        $xtpl->table_td(_('Affected users') . ':');
        $xtpl->table_td(
            '<a href="?page=security_advisory&action=users&id=' . $advisory->id . '">'
            . $advisory->affected_user_count
            . '</a>',
            false,
            true
        );
        $xtpl->table_tr();
        $xtpl->table_td(_('Affected VPS') . ':');
        $xtpl->table_td(
            '<a href="?page=security_advisory&action=vps&id=' . $advisory->id . '">'
            . $advisory->affected_vps_count
            . '</a>',
            false,
            true
        );
        $xtpl->table_tr();
        $xtpl->table_out();
    } elseif (isLoggedIn()) {
        $vpses = $api->vps_security_advisory->list([
            'security_advisory' => $id,
            'meta' => ['includes' => 'vps,node'],
        ]);

        $xtpl->table_title(_('Your affected VPS'));
        if ($vpses->count()) {
            $xtpl->table_add_category(_('VPS'));
            $xtpl->table_add_category(_('Node'));
            $xtpl->table_add_category(_('Vulnerable until'));
            $xtpl->table_add_category(_('Mitigated since'));

            foreach ($vpses as $row) {
                $xtpl->table_td(vps_link($row->vps) . ' - ' . h($row->vps->hostname));
                $xtpl->table_td(h($row->node->domain_name));
                $xtpl->table_td(security_advisory_time($row->vulnerable_until));
                $xtpl->table_td(security_advisory_time($row->mitigated_since));
                $xtpl->table_tr();
            }
        } else {
            $xtpl->table_td('<strong>' . _('Your VPS were not affected by this advisory.') . '</strong>');
            $xtpl->table_tr();
        }
        $xtpl->table_out();
    }

    $xtpl->table_title(_('Information'));
    $xtpl->table_td(_('State') . ':');
    $xtpl->table_td(security_advisory_state_label($advisory->state));
    $xtpl->table_tr();
    $xtpl->table_td(_('Published at') . ':');
    $xtpl->table_td(security_advisory_time($advisory->published_at));
    $xtpl->table_tr();
    $xtpl->table_td(_('CVEs') . ':');
    $xtpl->table_td(security_advisory_cve_links(security_advisory_cve_rows($advisory)));
    $xtpl->table_tr();
    $xtpl->table_td(_('Name') . ':');
    $xtpl->table_td(h($advisory->name ?: '-'));
    $xtpl->table_tr();

    foreach (['summary', 'description', 'response'] as $field) {
        $rowCount = max(1, count($langs));
        $firstRow = true;

        foreach ($langs as $lang) {
            $name = $lang->code . '_' . $field;
            $value = $field === 'description' || $field === 'response'
                ? nl2br(h($advisory->{$name}))
                : h($advisory->{$name});

            if ($firstRow) {
                $xtpl->table_td(_(ucfirst($field)) . ':', false, false, 1, $rowCount, 'top');
                $firstRow = false;
            }

            $xtpl->table_td(isLoggedIn() ? $value : '<strong>' . h($lang->label) . '</strong>: ' . $value);
            $xtpl->table_tr();
        }
    }
    $xtpl->table_out();

    security_advisory_node_status_table($id);
    security_advisory_outage_table($id);
    security_advisory_updates_table($id);

    if (isAdmin() && $advisory->state == 'draft') {
        $publishInput = $api->security_advisory->publish->getParameters('input');

        $xtpl->table_title(_('Publish advisory'));
        $xtpl->form_create('?page=security_advisory&action=publish&id=' . $id, 'post');
        $xtpl->form_add_input(
            _('Published at') . ':',
            'text',
            30,
            'published_at',
            post_val('published_at', security_advisory_datetime_form_value($advisory->published_at)),
            security_advisory_param_description($publishInput, 'published_at')
        );
        $xtpl->form_add_checkbox(
            _('Send mails to affected users') . ':',
            'send_mail',
            '1',
            false,
            security_advisory_param_description($publishInput, 'send_mail')
        );
        $xtpl->form_out(_('Publish'));
    }
}

function security_advisory_node_status_table($id)
{
    global $xtpl, $api;

    $statuses = $api->security_advisory($id)->node_status->list([
        'meta' => ['includes' => 'node'],
    ]);

    $xtpl->table_title(_('Node status'));
    $xtpl->table_add_category(_('Node'));
    $xtpl->table_add_category(_('State'));
    $xtpl->table_add_category(_('Vulnerable until'));
    $xtpl->table_add_category(_('Mitigated since'));
    $xtpl->table_add_category(_('Note'));

    foreach ($statuses as $status) {
        $xtpl->table_td(h($status->node_name));
        $xtpl->table_td(security_advisory_node_state_label($status->state));
        $xtpl->table_td(security_advisory_time($status->vulnerable_until));
        $xtpl->table_td(security_advisory_time($status->mitigated_since));
        $xtpl->table_td(nl2br(h($status->note)));
        $xtpl->table_tr();
    }

    if ($statuses->count() == 0) {
        $xtpl->table_td(_('No node statuses recorded.'), false, false, 5);
        $xtpl->table_tr();
    }

    $xtpl->table_out();
}

function security_advisory_outage_table($id)
{
    global $xtpl, $api;

    if (!$api->outage) {
        return;
    }

    $outages = $api->outage->list(['security_advisory' => $id]);

    if ($outages->count() == 0) {
        return;
    }

    $xtpl->table_title(_('Related outages'));
    $xtpl->table_add_category(_('Date'));
    $xtpl->table_add_category(_('Summary'));
    $xtpl->table_add_category('');

    foreach ($outages as $outage) {
        $xtpl->table_td(security_advisory_time($outage->begins_at));
        $xtpl->table_td(h(security_advisory_localized_text($outage, 'summary')));
        $xtpl->table_td('<a href="?page=outage&action=show&id=' . $outage->id . '">' . _('Show') . '</a>');
        $xtpl->table_tr();
    }

    $xtpl->table_out();
}

function security_advisory_updates_table($id)
{
    global $xtpl, $api;

    $updates = $api->security_advisory_update->list([
        'security_advisory' => $id,
        'meta' => ['includes' => 'reported_by'],
    ]);

    $xtpl->table_title(_('Updates'));
    $xtpl->table_add_category(_('Date'));
    $xtpl->table_add_category(_('Summary'));
    $xtpl->table_add_category(_('Reported by'));
    if (isAdmin()) {
        $xtpl->table_add_category('');
    }

    foreach ($updates as $update) {
        $xtpl->table_td(security_advisory_time($update->created_at));
        $xtpl->table_td(h(security_advisory_localized_text($update, 'summary')));
        $xtpl->table_td(h($update->reporter_name));
        if (isAdmin()) {
            $actions = '<a href="?page=security_advisory&action=edit_update&id=' . $id . '&update=' . $update->id . '">'
                . '<img src="template/icons/m_edit.png" title="' . _('Edit') . '" alt="' . _('Edit') . '">'
                . '</a> '
                . '<form action="?page=security_advisory&action=delete_update&id=' . $id . '&update=' . $update->id . '" method="post" style="display:inline">'
                . '<input type="hidden" name="csrf_token" value="' . h(csrf_token()) . '">'
                . '<input type="image" src="template/icons/vps_delete.png" title="' . _('Delete') . '" alt="' . _('Delete') . '"'
                . ' onclick="return confirm(\'' . h(addslashes(_('Do you really wish to delete this update?'))) . '\');">'
                . '</form>';
            $xtpl->table_td($actions);
        }
        $xtpl->table_tr();

        $message = security_advisory_localized_text($update, 'message');
        if ($message !== '') {
            $xtpl->table_td(nl2br(h($message)), false, false, isAdmin() ? 4 : 3);
            $xtpl->table_tr();
        }
    }

    if ($updates->count() == 0) {
        $xtpl->table_td(_('No updates posted.'), false, false, isAdmin() ? 4 : 3);
        $xtpl->table_tr();
    }

    $xtpl->table_out();
}

function security_advisory_node_form($id)
{
    global $xtpl, $api;

    $advisory = $api->security_advisory->show($id);

    $xtpl->title(_('Security advisory') . ' #' . $advisory->id . ' - ' . _('node statuses'));
    $xtpl->form_create('?page=security_advisory&action=nodes&id=' . $id, 'post');
    security_advisory_node_fields($id);
    $xtpl->form_out(_('Save node statuses'));
}

function security_advisory_node_select_html($name, $selected, $class, $field)
{
    $html = '<select'
        . ($name !== '' ? ' name="' . h($name) . '"' : '')
        . ' class="' . h($class) . '" data-field="' . h($field) . '">';

    foreach (security_advisory_node_state_options() as $value => $label) {
        $html .= '<option value="' . h($value) . '"'
            . ($selected === $value ? ' selected="selected"' : '')
            . '>'
            . h($label)
            . '</option>';
    }

    return $html . '</select>';
}

function security_advisory_node_input_html($name, $value, $field, $size, $placeholder)
{
    return '<input type="text" size="' . $size . '" name="' . h($name)
        . '" value="' . h((string) $value) . '" placeholder="' . h($placeholder)
        . '" class="security-advisory-node-field" data-field="' . h($field) . '" />';
}

function security_advisory_node_bulk_input_html($field, $size, $placeholder, $value = '')
{
    return '<input type="text" size="' . $size . '" placeholder="' . h($placeholder)
        . '" value="' . h((string) $value)
        . '" class="security-advisory-node-bulk" data-field="' . h($field) . '" />';
}

function security_advisory_node_script_html()
{
    return '<script type="text/javascript">
        function securityAdvisoryRefreshNodeRequirements() {
            var rows = document.querySelectorAll("tr.security-advisory-node-row");
            for (var i = 0; i < rows.length; i++) {
                var state = rows[i].querySelector("[data-field=state]");
                var required = state && state.value === "mitigated";
                var dates = rows[i].querySelectorAll("[data-field=vulnerable_until], [data-field=mitigated_since]");
                for (var j = 0; j < dates.length; j++) {
                    if (required) {
                        dates[j].required = true;
                        dates[j].setAttribute("required", "required");
                    } else {
                        dates[j].required = false;
                        dates[j].removeAttribute("required");
                    }
                }
            }
        }

        function securityAdvisoryApplyNodeDefaults() {
            var bulk = document.querySelectorAll(".security-advisory-node-bulk");
            for (var i = 0; i < bulk.length; i++) {
                var field = bulk[i].getAttribute("data-field");
                var inputs = document.querySelectorAll(".security-advisory-node-field[data-field=\"" + field + "\"]");
                for (var j = 0; j < inputs.length; j++) {
                    inputs[j].value = bulk[i].value;
                }
            }
            securityAdvisoryRefreshNodeRequirements();
        }

        document.addEventListener("DOMContentLoaded", function () {
            var states = document.querySelectorAll(".security-advisory-node-field[data-field=state]");
            for (var i = 0; i < states.length; i++) {
                states[i].addEventListener("change", securityAdvisoryRefreshNodeRequirements);
            }
            var forms = document.querySelectorAll("form");
            for (var j = 0; j < forms.length; j++) {
                forms[j].addEventListener("submit", securityAdvisoryRefreshNodeRequirements);
            }
            securityAdvisoryRefreshNodeRequirements();
        });
        </script>';
}

function security_advisory_node_script_row()
{
    global $xtpl;

    $xtpl->table_td(security_advisory_node_script_html(), false, false, 5);
    $xtpl->table_tr(false, 'security-advisory-node-script');
}

function security_advisory_node_table_cell_html($content, $style = '')
{
    return '<td' . ($style !== '' ? ' style="' . h($style) . '"' : '') . '>' . $content . '</td>';
}

function security_advisory_node_header_html()
{
    $style = 'background:#5EAFFF; color:#FFF; font-weight:bold; text-align:center;';
    $html = '<tr>';

    foreach ([_('Node'), _('State'), _('Vulnerable until'), _('Mitigated since'), _('Note')] as $label) {
        $html .= security_advisory_node_table_cell_html(h($label), $style);
    }

    return $html . '</tr>';
}

function security_advisory_node_bulk_row_html()
{
    $defaultTime = security_advisory_datetime_form_value();

    return '<tr class="security-advisory-node-bulk-row">'
        . security_advisory_node_table_cell_html(
            '<strong>' . h(_('All nodes')) . '</strong><br>'
            . '<input type="button" value="' . h(_('Apply')) . '" onclick="securityAdvisoryApplyNodeDefaults();" style="margin-top:3px;" />'
        )
        . security_advisory_node_table_cell_html(security_advisory_node_select_html('', 'mitigated', 'security-advisory-node-bulk', 'state'))
        . security_advisory_node_table_cell_html(security_advisory_node_bulk_input_html('vulnerable_until', 15, $defaultTime, $defaultTime))
        . security_advisory_node_table_cell_html(security_advisory_node_bulk_input_html('mitigated_since', 15, $defaultTime, $defaultTime))
        . security_advisory_node_table_cell_html(security_advisory_node_bulk_input_html('note', 18, _('Kernel updated')))
        . '</tr>';
}

function security_advisory_node_row_html($node, $status)
{
    $prefix = 'node_' . $node->id;
    $defaultTime = security_advisory_datetime_form_value();
    $vulnerableUntil = $status && $status->vulnerable_until
        ? security_advisory_datetime_form_value($status->vulnerable_until)
        : $defaultTime;
    $mitigatedSince = $status && $status->mitigated_since
        ? security_advisory_datetime_form_value($status->mitigated_since)
        : $defaultTime;

    return '<tr class="security-advisory-node-row">'
        . security_advisory_node_table_cell_html(h($node->domain_name) . '<br><small>' . security_advisory_node_role_label($node->type) . '</small>')
        . security_advisory_node_table_cell_html(security_advisory_node_select_html(
            $prefix . '_state',
            post_val($prefix . '_state', $status ? $status->state : 'unknown'),
            'security-advisory-node-field',
            'state'
        ))
        . security_advisory_node_table_cell_html(security_advisory_node_input_html(
            $prefix . '_vulnerable_until',
            post_val($prefix . '_vulnerable_until', $vulnerableUntil),
            'vulnerable_until',
            15,
            $defaultTime
        ))
        . security_advisory_node_table_cell_html(security_advisory_node_input_html(
            $prefix . '_mitigated_since',
            post_val($prefix . '_mitigated_since', $mitigatedSince),
            'mitigated_since',
            15,
            $defaultTime
        ))
        . security_advisory_node_table_cell_html(security_advisory_node_input_html(
            $prefix . '_note',
            post_val($prefix . '_note', $status ? $status->note : ''),
            'note',
            18,
            _('Kernel updated')
        ))
        . '</tr>';
}

function security_advisory_node_embedded_table_html($nodes, $statuses)
{
    $html = '<table class="table-style01 security-advisory-node-table" style="margin:0; width:auto; max-width:100%;">';
    $html .= security_advisory_node_header_html();
    $html .= security_advisory_node_bulk_row_html();

    foreach ($nodes as $node) {
        $html .= security_advisory_node_row_html($node, $statuses[$node->id] ?? null);
    }

    return $html . '</table>' . security_advisory_node_script_html();
}

function security_advisory_node_fields($id = null, $embedded = false)
{
    global $xtpl, $api;

    $nodes = security_advisory_nodes();
    $statuses = [];

    if ($id !== null) {
        foreach ($api->security_advisory($id)->node_status->list() as $status) {
            $statuses[$status->node_id] = $status;
        }
    }

    if ($embedded) {
        $xtpl->table_td('<strong>' . _('Node status') . '</strong>', false, false, 3);
        $xtpl->table_tr();
        $xtpl->table_td(security_advisory_node_embedded_table_html($nodes, $statuses), false, false, 3);
        $xtpl->table_tr();
        return;
    }

    $xtpl->table_title(_('Node status'));
    $xtpl->table_add_category(_('Node'));
    $xtpl->table_add_category(_('State'));
    $xtpl->table_add_category(_('Vulnerable until'));
    $xtpl->table_add_category(_('Mitigated since'));
    $xtpl->table_add_category(_('Note'));

    $xtpl->table_td(
        '<strong>' . h(_('All nodes')) . '</strong><br>'
        . '<input type="button" value="' . h(_('Apply')) . '" onclick="securityAdvisoryApplyNodeDefaults();" style="margin-top:3px;" />'
    );
    $xtpl->table_td(security_advisory_node_select_html('', 'mitigated', 'security-advisory-node-bulk', 'state'));
    $defaultTime = security_advisory_datetime_form_value();
    $xtpl->table_td(security_advisory_node_bulk_input_html('vulnerable_until', 15, $defaultTime, $defaultTime));
    $xtpl->table_td(security_advisory_node_bulk_input_html('mitigated_since', 15, $defaultTime, $defaultTime));
    $xtpl->table_td(security_advisory_node_bulk_input_html('note', 18, _('Kernel updated')));
    $xtpl->table_tr(false, 'security-advisory-node-bulk-row');

    foreach ($nodes as $node) {
        $status = $statuses[$node->id] ?? null;
        $prefix = 'node_' . $node->id;
        $vulnerableUntil = $status && $status->vulnerable_until
            ? security_advisory_datetime_form_value($status->vulnerable_until)
            : $defaultTime;
        $mitigatedSince = $status && $status->mitigated_since
            ? security_advisory_datetime_form_value($status->mitigated_since)
            : $defaultTime;
        $xtpl->table_td(h($node->domain_name) . '<br><small>' . security_advisory_node_role_label($node->type) . '</small>');
        $xtpl->table_td(security_advisory_node_select_html(
            $prefix . '_state',
            post_val($prefix . '_state', $status ? $status->state : 'unknown'),
            'security-advisory-node-field',
            'state'
        ));
        $xtpl->table_td(security_advisory_node_input_html(
            $prefix . '_vulnerable_until',
            post_val($prefix . '_vulnerable_until', $vulnerableUntil),
            'vulnerable_until',
            15,
            $defaultTime
        ));
        $xtpl->table_td(security_advisory_node_input_html(
            $prefix . '_mitigated_since',
            post_val($prefix . '_mitigated_since', $mitigatedSince),
            'mitigated_since',
            15,
            $defaultTime
        ));
        $xtpl->table_td(security_advisory_node_input_html(
            $prefix . '_note',
            post_val($prefix . '_note', $status ? $status->note : ''),
            'note',
            18,
            _('Kernel updated')
        ));
        $xtpl->table_tr(false, 'security-advisory-node-row');
    }

    security_advisory_node_script_row();
}

function security_advisory_update_form($id, $updateId = null)
{
    global $xtpl, $api;

    $advisory = $api->security_advisory->show($id);
    $update = $updateId ? $api->security_advisory_update->show($updateId) : null;
    $langs = $api->language->list();
    $input = ($update ? $api->security_advisory_update->update : $api->security_advisory_update->create)
        ->getParameters('input');

    $xtpl->title($update ? _('Edit security advisory update') : _('Post security advisory update'));
    $xtpl->form_create(
        $update
            ? '?page=security_advisory&action=edit_update&id=' . $id . '&update=' . $updateId
            : '?page=security_advisory&action=update&id=' . $id,
        'post'
    );

    if (!$update) {
        security_advisory_form_input(
            _('Published at') . ':',
            'published_at',
            post_val('published_at', security_advisory_datetime_form_value($advisory->published_at)),
            security_advisory_datetime_form_value(),
            security_advisory_param_description($input, 'published_at'),
            30
        );
        $xtpl->form_add_select(_('State') . ':', 'state', [
            '' => _('no change'),
            'retracted' => _('retracted'),
        ], post_val('state'), security_advisory_param_description($input, 'state'));
    }

    foreach ($langs as $lang) {
        $name = $lang->code . '_summary';
        security_advisory_form_input(
            $lang->label . ' ' . _('summary') . ':',
            $name,
            post_val($name, $update ? $update->{$name} : ''),
            _('Short summary of this update.'),
            security_advisory_param_description($input, $name)
        );

        $name = $lang->code . '_message';
        security_advisory_form_textarea(
            $lang->label . ' ' . _('message') . ':',
            $name,
            post_val($name, $update ? $update->{$name} : ''),
            _('Optional details about this update.'),
            security_advisory_param_description($input, $name)
        );
    }

    if (!$update) {
        $xtpl->form_add_checkbox(
            _('Send mails to affected users') . ':',
            'send_mail',
            '1',
            false,
            security_advisory_param_description($input, 'send_mail')
        );
    }
    $xtpl->form_out($update ? _('Save') : _('Post update'));
}

function security_advisory_affected_users($id)
{
    global $xtpl, $api;

    $users = $api->user_security_advisory->list([
        'security_advisory' => $id,
        'meta' => ['includes' => 'user'],
    ]);

    $xtpl->title(_('Security advisory') . ' #' . $id);
    $xtpl->table_title(_('Affected users'));
    $xtpl->table_add_category(_('Login'));
    $xtpl->table_add_category(_('Name'));
    $xtpl->table_add_category(_('VPS count'));

    foreach ($users as $row) {
        $xtpl->table_td(user_link($row->user));
        $xtpl->table_td(h($row->user->full_name));
        $xtpl->table_td('<a href="?page=security_advisory&action=vps&id=' . $id . '&user=' . $row->user_id . '">' . $row->vps_count . '</a>');
        $xtpl->table_tr();
    }

    $xtpl->table_out();
}

function security_advisory_affected_vps($id)
{
    global $xtpl, $api;

    $params = [
        'security_advisory' => $id,
        'meta' => ['includes' => isAdmin() ? 'vps,user,node' : 'vps,node'],
    ];

    $userId = api_get_uint('user');
    if ($userId !== null && $userId > 0) {
        $params['user'] = $userId;
    }

    $vpses = $api->vps_security_advisory->list($params);

    $xtpl->title(_('Security advisory') . ' #' . $id);
    $xtpl->table_title(_('Affected VPS'));
    $xtpl->table_add_category(_('VPS'));
    if (isAdmin()) {
        $xtpl->table_add_category(_('User'));
    }
    $xtpl->table_add_category(_('Node'));
    $xtpl->table_add_category(_('Vulnerable until'));
    $xtpl->table_add_category(_('Mitigated since'));

    foreach ($vpses as $row) {
        $xtpl->table_td(vps_link($row->vps) . ' - ' . h($row->vps->hostname));
        if (isAdmin()) {
            $xtpl->table_td(user_link($row->user));
        }
        $xtpl->table_td(h($row->node->domain_name));
        $xtpl->table_td(security_advisory_time($row->vulnerable_until));
        $xtpl->table_td(security_advisory_time($row->mitigated_since));
        $xtpl->table_tr();
    }

    $xtpl->table_out();
}
