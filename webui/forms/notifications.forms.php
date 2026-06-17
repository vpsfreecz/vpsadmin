<?php

function notifications_target_user_id($user_id = null)
{
    if (!isAdmin()) {
        return $_SESSION['user']['id'] ?? null;
    }

    if ($user_id !== null && $user_id > 0) {
        return $user_id;
    }

    $user_id = api_get_uint('user');
    if ($user_id !== null && $user_id > 0) {
        return $user_id;
    }

    $user_id = api_post_uint('user');
    if ($user_id !== null && $user_id > 0) {
        return $user_id;
    }

    return $_SESSION['user']['id'] ?? null;
}

function notifications_user_qs($user_id = null)
{
    $user_id = notifications_target_user_id($user_id);

    return isAdmin() && $user_id ? '&user=' . $user_id : '';
}

function notifications_sidebar($current, $user_id = null)
{
    global $xtpl;

    $user_qs = notifications_user_qs($user_id);

    if ($current !== 'routes') {
        $xtpl->sbar_add(_('Routes'), '?page=notifications&action=routes' . $user_qs);
    }

    if ($current !== 'receivers') {
        $xtpl->sbar_add(_('Receivers'), '?page=notifications&action=receivers' . $user_qs);
    }

    if ($current !== 'event_types') {
        $xtpl->sbar_add(_('Event types'), '?page=notifications&action=event_types' . $user_qs);
    }

    if ($current !== 'events') {
        $xtpl->sbar_add(_('Event log'), '?page=notifications&action=events' . $user_qs);
    }

    if ($current !== 'test') {
        $xtpl->sbar_add(_('Test event'), '?page=notifications&action=test' . $user_qs);
    }
}

function notifications_param_choices($desc, $empty = false)
{
    $ret = [];

    if ($empty) {
        $ret[''] = '---';
    }

    if (
        !isset($desc->validators)
        || !isset($desc->validators->include)
        || !isset($desc->validators->include->values)
    ) {
        return $ret;
    }

    $choices = $desc->validators->include->values;

    if (is_object($choices)) {
        $choices = get_object_vars($choices);
    }

    if (!is_array($choices)) {
        return $ret;
    }

    if (is_assoc($choices)) {
        return $ret + $choices;
    }

    foreach ($choices as $choice) {
        $ret[$choice] = $choice;
    }

    return $ret;
}

function notifications_event_types_cached()
{
    global $api;

    static $types = null;

    if ($types === null) {
        $types = notifications_api_list_to_array($api->event_type->list());
    }

    return $types;
}

function notifications_prop($object, $name, $default = null)
{
    return $object->{$name} ?? $default;
}

function notifications_event_type_fields_from_type($type)
{
    if (!isset($type->fields) || $type->fields === null) {
        return [];
    }

    if (is_object($type->fields)) {
        return get_object_vars($type->fields);
    }

    if (is_array($type->fields)) {
        return $type->fields;
    }

    return [];
}

function notifications_api_list_to_array($list)
{
    if (is_array($list)) {
        return $list;
    }

    if ($list instanceof Traversable) {
        return iterator_to_array($list);
    }

    if (is_object($list) && method_exists($list, 'asArray')) {
        return $list->asArray();
    }

    if (!is_object($list) || !method_exists($list, 'getResponse')) {
        return [];
    }

    $response = $list->getResponse();

    if (is_array($response)) {
        return $response;
    }

    if ($response instanceof Traversable) {
        return iterator_to_array($response);
    }

    if (is_object($response)) {
        return array_values(get_object_vars($response));
    }

    return [];
}

function notifications_event_type_fields($event_type, $fallback_fields)
{
    if (!$event_type) {
        return $fallback_fields;
    }

    foreach (notifications_event_types_cached() as $type) {
        if ($type->name !== $event_type) {
            continue;
        }

        $fields = notifications_event_type_fields_from_type($type);

        return $fields ?: $fallback_fields;
    }

    return $fallback_fields;
}

function notifications_route_matcher_fields($route, $all_fields, $matchers)
{
    $fields = notifications_event_type_fields($route->event_type, $all_fields);

    foreach ($matchers as $matcher) {
        if (isset($fields[$matcher->field])) {
            continue;
        }

        $fields[$matcher->field] = $all_fields[$matcher->field] ?? $matcher->field;
    }

    return $fields;
}

function notifications_label($labels, $value)
{
    return $labels[$value] ?? $value;
}

function notifications_short_value($value, $len = 48)
{
    $value = (string) $value;

    if (mb_strlen($value) <= $len) {
        return $value;
    }

    return mb_substr($value, 0, $len) . '...';
}

function notifications_select_html($name, $options, $selected_value, $form_id = null)
{
    $form_attr = $form_id ? ' form="' . h($form_id) . '"' : '';
    $ret = '<select name="' . h($name) . '" id="input"' . $form_attr . '>';

    foreach ($options as $value => $label) {
        $selected = ((string) $value === (string) $selected_value) ? ' selected' : '';
        $ret .= '<option value="' . h($value) . '"' . $selected . '>' . h($label) . '</option>';
    }

    return $ret . '</select>';
}

function notifications_text_input_html($name, $value, $size = 30, $form_id = null)
{
    $form_attr = $form_id ? ' form="' . h($form_id) . '"' : '';

    return '<input type="text" name="' . h($name) . '" id="input" size="' . (int) $size . '" value="' . h($value) . '"' . $form_attr . '>';
}

function notifications_password_input_html($name, $value, $size = 30, $form_id = null, $placeholder = null)
{
    $form_attr = $form_id ? ' form="' . h($form_id) . '"' : '';
    $placeholder_attr = $placeholder !== null ? ' placeholder="' . h($placeholder) . '"' : '';

    return '<input type="password" name="' . h($name) . '" id="input" size="' . (int) $size . '" value="' . h($value) . '"' . $form_attr . $placeholder_attr . '>';
}

function notifications_checkbox_html($name, $checked, $form_id = null)
{
    $form_attr = $form_id ? ' form="' . h($form_id) . '"' : '';

    return '<input type="checkbox" name="' . h($name) . '" id="input" value="1"' . ($checked ? ' checked' : '') . $form_attr . '>';
}

function notifications_submit_html($label, $form_id = null, $name = null)
{
    $form_attr = $form_id ? ' form="' . h($form_id) . '"' : '';
    $name_attr = $name ? ' name="' . h($name) . '"' : '';

    return '<input type="submit" value="' . h($label) . '" class="button"' . $form_attr . $name_attr . '>';
}

function notifications_clear_table_form()
{
    global $xtpl;

    $xtpl->table_begin('');
    $xtpl->table_end('');
    $xtpl->form_csrf('common', false);
    $xtpl->form_set_hidden_fields([]);
}

function notifications_drag_handle_html()
{
    return '<span class="notification-drag-handle" title="' . _('Drag to reorder') . '">&#x2630;</span>';
}

function notifications_confirm_onclick($message)
{
    return ' onclick="return confirm(' . h(json_encode($message)) . ');"';
}

function notifications_route_new_url($user_id, $parent_id = null)
{
    $url = '?page=notifications&action=route_new' . notifications_user_qs($user_id);

    if ($parent_id !== null) {
        $url .= '&parent=' . (int) $parent_id;
    }

    return $url;
}

function notifications_route_add_link($user_id, $parent_id = null, $label = null)
{
    $title = $parent_id === null ? _('Add route') : _('Add subroute');
    $html = '<a href="' . notifications_route_new_url($user_id, $parent_id) . '">'
        . '<img src="template/icons/vps_add.png" title="' . h($title) . '" alt="' . h($title) . '">';

    if ($label !== null) {
        $html .= ' ' . h($label);
    }

    return $html . '</a>';
}

function notifications_route_label_text($route)
{
    return $route->label ?: $route->display_label;
}

function notifications_route_labels($routes)
{
    $ret = [];

    foreach ($routes as $route) {
        $ret[$route->id] = notifications_route_label_text($route);
    }

    return $ret;
}

function notifications_route_tree_label_html($route, $depth, $route_labels = [])
{
    $label = h(notifications_route_label_text($route));

    if ($depth <= 0) {
        return $label;
    }

    $indent = min((int) $depth, 8) * 12;
    $parent = null;

    if ($route->parent_id !== null && isset($route_labels[$route->parent_id])) {
        $parent = $route_labels[$route->parent_id];
    }

    $hint = $parent === null ? _('Subroute') : sprintf(_('Parent: %s'), $parent);

    return '<span style="display:block;margin-left:' . $indent . 'px;">'
        . '<span style="display:block;color:#666;font-size:90%;">' . h($hint) . '</span>'
        . '<span>' . $label . '</span>'
        . '</span>';
}

function notifications_route_parent_key($route)
{
    return $route->parent_id === null ? 'root' : (string) $route->parent_id;
}

function notifications_route_row_id($route)
{
    return 'route_' . $route->id . '_p_' . notifications_route_parent_key($route);
}

function notifications_route_move_links($route, $user_id, $is_first, $is_last)
{
    $base = '?page=notifications&action=route_move&id=' . $route->id
        . notifications_user_qs($user_id) . '&t=' . csrf_token();

    $up = $is_first
        ? '<span title="' . _('Already first') . '">&uarr;</span>'
        : '<a href="' . $base . '&direction=up" title="' . _('Move up') . '">&uarr;</a>';
    $down = $is_last
        ? '<span title="' . _('Already last') . '">&darr;</span>'
        : '<a href="' . $base . '&direction=down" title="' . _('Move down') . '">&darr;</a>';

    return $up . ' ' . $down;
}

function notifications_include_reorder_script($table_id, $row_prefix, $action)
{
    global $xtpl;

    $selector = json_encode('#' . $table_id);
    $prefix = json_encode($row_prefix . '_');
    $action = json_encode($action);
    $token = json_encode(csrf_token());

    $xtpl->assign(
        'AJAX_SCRIPT',
        ($xtpl->vars['AJAX_SCRIPT'] ?? '')
        . '<script type="text/javascript">
$(function () {
    var table = $(' . $selector . ');
    if (!table.length || !$.fn.tableDnD) {
        return;
    }

    function routeInfo(row) {
        var id = row.id || $(row).attr("id") || "";
        var match = id.match(/^route_(\d+)_p_(root|\d+)$/);

        if (!match) {
            return null;
        }

        return {
            id: match[1],
            parent: match[2]
        };
    }

    table.tableDnD({
        dragHandle: ".notification-drag-handle",
        onAllowDrop: function (draggedRow, targetRow) {
            var dragged = routeInfo(draggedRow);
            var target = routeInfo(targetRow);

            return dragged && target && dragged.parent === target.parent;
        },
        onDrop: function (tbl, droppedRow) {
            var ids = [];
            var dropped = routeInfo(droppedRow);
            var prefix = ' . $prefix . ';

            if (!dropped) {
                window.location.reload();
                return;
            }

            $("#" + tbl.id + " tr[id^=\"" + prefix + "\"]").each(function () {
                var info = routeInfo(this);

                if (info && info.parent === dropped.parent) {
                    ids.push(info.id);
                }
            });
            $.ajax({
                type: "POST",
                url: ' . $action . ',
                dataType: "json",
                data: {
                    csrf_token: ' . $token . ',
                    parent_id: dropped.parent === "root" ? "" : dropped.parent,
                    ids: ids
                },
                error: function () {
                    window.location.reload();
                },
                success: function (response) {
                    if (!response || !response.status) {
                        window.location.reload();
                    }
                }
            });
        }
    });
});
</script>'
    );
}

function notifications_is_ajax()
{
    return strtolower($_SERVER['HTTP_X_REQUESTED_WITH'] ?? '') === 'xmlhttprequest';
}

function notifications_ajax_response($status, $message = null)
{
    header('Content-Type: application/json');
    echo json_encode([
        'status' => $status,
        'message' => $message,
    ]);
    exit;
}

function notifications_posted_ids()
{
    $ids = $_POST['ids'] ?? [];

    if (!is_array($ids)) {
        return [];
    }

    $ret = [];

    foreach ($ids as $id) {
        if (is_string($id) && ctype_digit($id)) {
            $ret[] = (int) $id;
        }
    }

    return $ret;
}

function notifications_nullable_id($name)
{
    $id = api_post_uint($name);

    return $id !== null && $id > 0 ? $id : null;
}

function notifications_route_params($create = false)
{
    $params = [
        'parent_id' => notifications_nullable_id('parent_id'),
        'notification_receiver_id' => notifications_nullable_id('notification_receiver_id'),
        'label' => api_post('label'),
        'enabled' => isset($_POST['enabled']),
        'event_type' => api_post('event_type'),
        'event_type_pattern' => api_post('event_type_pattern'),
        'continue' => isset($_POST['continue']),
    ];

    if ($params['event_type'] === '') {
        $params['event_type'] = null;
    }

    if ($params['event_type_pattern'] === '') {
        $params['event_type_pattern'] = null;
    }

    if ($create && isAdmin()) {
        $params['user'] = notifications_target_user_id();
    }

    $position = api_post_uint('position');
    if ($position !== null) {
        $params['position'] = $position;
    }

    return $params;
}

function notifications_receiver_params($create = false)
{
    $params = [
        'label' => api_post('label'),
        'description' => api_post('description'),
        'enabled' => isset($_POST['enabled']),
        'mute' => isset($_POST['mute']),
    ];

    if ($create && isAdmin()) {
        $params['user'] = notifications_target_user_id();
    }

    return $params;
}

function notifications_receiver_action_type_labels($receiver)
{
    $input = $receiver->action->create->getParameters('input');

    return notifications_param_choices($input->action);
}

function notifications_receiver_action_type_label($receiver, $action_type)
{
    $labels = notifications_receiver_action_type_labels($receiver);

    return $labels[$action_type] ?? $action_type;
}

function notifications_receiver_action_type_from_request($receiver)
{
    $labels = notifications_receiver_action_type_labels($receiver);
    $action_type = api_get('type');

    if ($action_type === null) {
        $action_type = api_post('action_type');
    }

    return isset($labels[$action_type]) ? $action_type : null;
}

function notifications_receiver_action_params($action_type, $create = false)
{
    $params = [
        'label' => api_post('label'),
        'enabled' => isset($_POST['enabled']),
    ];

    if ($create) {
        $params['action'] = $action_type;
    }

    if ($action_type === 'email') {
        $target_kind = api_post('target_kind', 'default_recipient');

        $params['target_kind'] = $target_kind;
        $params['target_value'] = $target_kind === 'default_recipient' ? null : api_post('target_value');
        $params['template_name'] = api_post('template_name');
    } elseif ($action_type === 'webhook') {
        $params['target_kind'] = 'custom';
        $params['target_value'] = api_post('target_value');
        $params['template_name'] = null;
    } else {
        $params['target_kind'] = api_post('target_kind');
        $params['target_value'] = api_post('target_value');
        $params['template_name'] = api_post('template_name');
    }

    $secret = isset($_POST['secret']) ? trim((string) $_POST['secret']) : '';
    if ($secret !== '') {
        $params['secret'] = $secret;
    } elseif (isset($_POST['clear_secret'])) {
        $params['secret'] = '';
    }

    return $params;
}

function notifications_receiver_action_params_from_row($row)
{
    $target_kind = trim((string) ($row['target_kind'] ?? 'default_recipient'));
    $params = [
        'action' => trim((string) ($row['action'] ?? '')),
        'label' => trim((string) ($row['label'] ?? '')),
        'target_kind' => $target_kind,
        'target_value' => trim((string) ($row['target_value'] ?? '')),
        'template_name' => trim((string) ($row['template_name'] ?? '')),
        'enabled' => isset($row['enabled']),
    ];

    if ($target_kind === 'default_recipient') {
        $params['target_value'] = null;
    }

    $secret = trim((string) ($row['secret'] ?? ''));
    if ($secret !== '') {
        $params['secret'] = $secret;
    }

    return $params;
}

function notifications_matcher_new_params()
{
    return [
        'field' => api_post('new_field'),
        'operator' => api_post('new_operator'),
        'value' => api_post('new_value'),
    ];
}

function notifications_matcher_params_from_row($row)
{
    return [
        'field' => trim((string) ($row['field'] ?? '')),
        'operator' => trim((string) ($row['operator'] ?? '')),
        'value' => trim((string) ($row['value'] ?? '')),
    ];
}

function notifications_route_type_html($route, $event_type_labels)
{
    if ($route->event_type) {
        return h(notifications_label($event_type_labels, $route->event_type));
    }

    if ($route->event_type_pattern) {
        return '<code>' . h($route->event_type_pattern) . '</code>';
    }

    return '<code>*</code>';
}

function notifications_route_receiver_html($route, $receivers)
{
    if (!$route->notification_receiver_id) {
        return '-';
    }

    return h($receivers[$route->notification_receiver_id] ?? ('#' . $route->notification_receiver_id));
}

function notifications_receiver_options($user_id, $empty = true)
{
    global $api;

    $ret = $empty ? ['' => '---'] : [];

    foreach ($api->notification_receiver->list(['user' => $user_id]) as $receiver) {
        $label = $receiver->label;
        if ($receiver->mute) {
            $label .= ' (' . _('muted') . ')';
        }

        $ret[$receiver->id] = $receiver->id . ': ' . $label;
    }

    return $ret;
}

function notifications_receiver_labels($user_id)
{
    $labels = [];

    foreach (notifications_receiver_options($user_id, false) as $id => $label) {
        $labels[$id] = $label;
    }

    return $labels;
}

function notifications_route_options($user_id, $empty = true, $exclude_id = null)
{
    global $api;

    $ret = $empty ? ['' => '---'] : [];
    $routes = notifications_api_list_to_array($api->event_route->list(['user' => $user_id]));

    foreach (notifications_ordered_routes($routes) as $row) {
        [$route, $depth] = $row;

        if ($exclude_id !== null && (int) $route->id === (int) $exclude_id) {
            continue;
        }

        $prefix = str_repeat('-- ', $depth);
        $ret[$route->id] = $route->id . ': ' . $prefix . ($route->label ?: $route->matcher_summary);
    }

    return $ret;
}

function notifications_ordered_routes($routes, $parent_id = null, $depth = 0, &$seen = [])
{
    $children = [];

    foreach ($routes as $route) {
        $pid = $route->parent_id === null ? null : (int) $route->parent_id;
        if ($pid === $parent_id) {
            $children[] = $route;
        }
    }

    usort($children, function ($a, $b) {
        if ($a->position == $b->position) {
            return $a->id <=> $b->id;
        }

        return $a->position <=> $b->position;
    });

    $ret = [];

    foreach ($children as $route) {
        if (isset($seen[$route->id])) {
            continue;
        }

        $seen[$route->id] = true;
        $ret[] = [$route, $depth];
        $ret = array_merge($ret, notifications_ordered_routes($routes, (int) $route->id, $depth + 1, $seen));
    }

    if ($parent_id === null) {
        foreach ($routes as $route) {
            if (!isset($seen[$route->id])) {
                $seen[$route->id] = true;
                $ret[] = [$route, 0];
            }
        }
    }

    return $ret;
}

function notifications_sibling_positions($routes)
{
    $groups = [];
    $ret = [];

    foreach ($routes as $route) {
        $key = $route->parent_id === null ? 'root' : (string) $route->parent_id;
        $groups[$key][] = $route;
    }

    foreach ($groups as $group) {
        usort($group, function ($a, $b) {
            if ($a->position == $b->position) {
                return $a->id <=> $b->id;
            }

            return $a->position <=> $b->position;
        });

        $last = count($group) - 1;
        foreach ($group as $idx => $route) {
            $ret[$route->id] = [$idx === 0, $idx === $last];
        }
    }

    return $ret;
}

function notifications_route_reorder($user_id, $parent_id, $ids)
{
    global $api;

    $routes = notifications_api_list_to_array($api->event_route->list(['user' => $user_id]));
    $current = [];

    foreach ($routes as $route) {
        $pid = $route->parent_id === null ? null : (int) $route->parent_id;

        if ($pid === $parent_id) {
            $current[] = (int) $route->id;
        }
    }

    sort($current);
    $posted = $ids;
    sort($posted);

    if ($posted !== $current) {
        return false;
    }

    foreach ($ids as $idx => $id) {
        $api->event_route->update($id, ['position' => $idx + 1]);
    }

    return true;
}

function notifications_route_move($id, $direction)
{
    global $api;

    $route = $api->event_route->show($id);
    $routes = notifications_api_list_to_array($api->event_route->list(['user' => $route->user_id]));
    $siblings = [];

    foreach ($routes as $candidate) {
        if ((string) $candidate->parent_id === (string) $route->parent_id) {
            $siblings[] = $candidate;
        }
    }

    usort($siblings, function ($a, $b) {
        if ($a->position == $b->position) {
            return $a->id <=> $b->id;
        }

        return $a->position <=> $b->position;
    });

    $idx = null;
    foreach ($siblings as $i => $candidate) {
        if ((int) $candidate->id === (int) $route->id) {
            $idx = $i;
            break;
        }
    }

    if ($idx === null) {
        return $route->user_id;
    }

    $swap = $direction === 'up' ? $idx - 1 : $idx + 1;

    if (!isset($siblings[$swap])) {
        return $route->user_id;
    }

    $api->event_route->update($siblings[$idx]->id, ['position' => $siblings[$swap]->position]);
    $api->event_route->update($siblings[$swap]->id, ['position' => $siblings[$idx]->position]);

    return $route->user_id;
}

function notifications_routes_list($user_id = null)
{
    global $xtpl, $api;

    $user_id = notifications_target_user_id($user_id);
    $user = $api->user->show($user_id);
    $routes = notifications_api_list_to_array($api->event_route->list(['user' => $user_id]));
    $input = $api->event_route->create->getParameters('input');
    $event_type_labels = notifications_param_choices($input->event_type);
    $receiver_labels = notifications_receiver_labels($user_id);
    $route_labels = notifications_route_labels($routes);
    $sibling_positions = notifications_sibling_positions($routes);

    $xtpl->title(_('Notification routes'));

    if (isAdmin()) {
        $xtpl->table_title(_('User'));
        $xtpl->form_create('?page=notifications&action=routes', 'get', 'notification-user', false);
        $xtpl->form_set_hidden_fields([
            'page' => 'notifications',
            'action' => 'routes',
        ]);
        $xtpl->form_add_input(_('User ID') . ':', 'text', '20', 'user', $user_id);
        $xtpl->form_out(_('Show'));
    }

    $xtpl->table_title(_('Routes') . ': ' . h($user->login));
    $xtpl->table_add_category('');
    $xtpl->table_add_category(_('Label'));
    $xtpl->table_add_category(_('Events'));
    $xtpl->table_add_category(_('Receiver'));
    $xtpl->table_add_category(_('Matchers'));
    $xtpl->table_add_category(_('Hit count'));
    $xtpl->table_add_category(_('Enabled'));
    $xtpl->table_add_category(_('Continue'));
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');

    foreach (notifications_ordered_routes($routes) as $row) {
        [$route, $depth] = $row;
        $row_color = $route->enabled ? false : '#A6A6A6';
        [$is_first, $is_last] = $sibling_positions[$route->id] ?? [true, true];
        $enabled_link = '?page=notifications&action=route_toggle&id=' . $route->id
            . notifications_user_qs($user_id) . '&t=' . csrf_token();
        $delete_link = '?page=notifications&action=route_delete&id=' . $route->id
            . notifications_user_qs($user_id) . '&t=' . csrf_token();
        $label = notifications_route_tree_label_html($route, $depth, $route_labels);

        $xtpl->table_td(notifications_drag_handle_html(), false, true);
        $xtpl->table_td($label, false, true);
        $xtpl->table_td(notifications_route_type_html($route, $event_type_labels));
        $xtpl->table_td(notifications_route_receiver_html($route, $receiver_labels));
        $xtpl->table_td($route->matcher_summary ? h($route->matcher_summary) : '<code>*</code>');
        $xtpl->table_td(
            '<a href="?page=notifications&action=events&user=' . $user_id
            . '&matched_event_route_id=' . $route->id . '">' . $route->hit_count . '</a>',
            false,
            true
        );
        $xtpl->table_td(
            '<a href="' . $enabled_link . '" title="' . ($route->enabled ? _('Disable route') : _('Enable route')) . '">'
            . boolean_icon($route->enabled) . '</a>'
        );
        $xtpl->table_td(boolean_icon($route->continue));
        $xtpl->table_td(notifications_route_move_links($route, $user_id, $is_first, $is_last));
        $xtpl->table_td(notifications_route_add_link($user_id, $route->id), false, true);
        $xtpl->table_td('<a href="?page=notifications&action=route_edit&id=' . $route->id . notifications_user_qs($user_id) . '"><img src="template/icons/vps_edit.png" title="' . _('Edit') . '"></a>');
        $xtpl->table_td(
            '<a href="' . $delete_link . '"' . notifications_confirm_onclick(_('Do you really wish to delete this notification route?')) . '>'
            . '<img src="template/icons/vps_delete.png" title="' . _('Delete') . '"></a>'
        );
        $xtpl->table_tr($row_color, false, false, notifications_route_row_id($route));
    }

    if (!$routes) {
        $xtpl->table_td(_('No routes configured.'), false, false, 12);
        $xtpl->table_tr(false, 'nodrag nodrop', 'nodrag nodrop');
    }

    $xtpl->table_td(notifications_route_add_link($user_id, null, _('Add route')), false, true, 12);
    $xtpl->table_tr(false, 'nodrag nodrop', 'nodrag nodrop');

    $xtpl->table_out('notification-routes-table');

    notifications_include_reorder_script(
        'notification-routes-table',
        'route',
        '?page=notifications&action=route_reorder' . notifications_user_qs($user_id)
    );

    notifications_sidebar('routes', $user_id);
}

function notifications_route_new($user_id = null, $parent_id = null)
{
    global $xtpl, $api;

    $user_id = notifications_target_user_id($user_id);
    $user = $api->user->show($user_id);
    $input = $api->event_route->create->getParameters('input');
    $event_types = notifications_param_choices($input->event_type, true);
    $receiver_options = notifications_receiver_options($user_id);
    $route_options = notifications_route_options($user_id);

    if ($parent_id === null) {
        $parent_id = api_get_uint('parent');
    }

    $xtpl->title(_('Add notification route'));
    $xtpl->table_title(_('Add route'));
    $xtpl->form_create(notifications_route_new_url($user_id, $parent_id), 'post');

    $xtpl->table_td(_('User') . ':');
    $xtpl->table_td(isAdmin() ? user_link($user) : h($user->login));
    $xtpl->table_tr();

    api_param_to_form('label', $input->label, post_val('label'));
    $xtpl->form_add_select(_('Parent route') . ':', 'parent_id', $route_options, post_val('parent_id', $parent_id ?: ''));
    $xtpl->form_add_select(_('Event type') . ':', 'event_type', $event_types, post_val('event_type', ''));
    $xtpl->form_add_input(_('Event type pattern') . ':', 'text', '40', 'event_type_pattern', post_val('event_type_pattern'));
    $xtpl->form_add_select(_('Receiver') . ':', 'notification_receiver_id', $receiver_options, post_val('notification_receiver_id', ''));
    $xtpl->form_add_checkbox(_('Enabled') . ':', 'enabled', '1', post_val('enabled', true));
    $xtpl->form_add_checkbox(_('Continue') . ':', 'continue', '1', post_val('continue', false));
    $xtpl->form_out(_('Add'));

    $xtpl->sbar_add(_('Back to routes'), '?page=notifications&action=routes' . notifications_user_qs($user_id));
    notifications_sidebar('routes', $user_id);
}

function notifications_route_subroutes($route)
{
    global $xtpl, $api;

    $routes = notifications_api_list_to_array($api->event_route->list(['user' => $route->user_id]));
    $children = notifications_ordered_routes($routes, (int) $route->id);
    $input = $api->event_route->create->getParameters('input');
    $event_type_labels = notifications_param_choices($input->event_type);
    $receiver_labels = notifications_receiver_labels($route->user_id);
    $route_labels = notifications_route_labels($routes);

    $xtpl->table_title(_('Subroutes'));
    $xtpl->table_add_category(_('Label'));
    $xtpl->table_add_category(_('Events'));
    $xtpl->table_add_category(_('Receiver'));
    $xtpl->table_add_category(_('Matchers'));
    $xtpl->table_add_category(_('Enabled'));
    $xtpl->table_add_category(_('Continue'));
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');

    foreach ($children as $row) {
        [$child, $depth] = $row;

        $xtpl->table_td(notifications_route_tree_label_html($child, $depth, $route_labels), false, true);
        $xtpl->table_td(notifications_route_type_html($child, $event_type_labels));
        $xtpl->table_td(notifications_route_receiver_html($child, $receiver_labels));
        $xtpl->table_td($child->matcher_summary ? h($child->matcher_summary) : '<code>*</code>');
        $xtpl->table_td(boolean_icon($child->enabled));
        $xtpl->table_td(boolean_icon($child->continue));
        $xtpl->table_td(notifications_route_add_link($route->user_id, $child->id), false, true);
        $xtpl->table_td('<a href="?page=notifications&action=route_edit&id=' . $child->id . notifications_user_qs($route->user_id) . '"><img src="template/icons/vps_edit.png" title="' . _('Edit') . '"></a>');
        $xtpl->table_tr($child->enabled ? false : '#A6A6A6');
    }

    if (!$children) {
        $xtpl->table_td(_('No subroutes configured.'), false, false, 8);
        $xtpl->table_tr();
    }

    $xtpl->table_td(notifications_route_add_link($route->user_id, $route->id, _('Add subroute')), false, true, 8);
    $xtpl->table_tr(false, 'nodrag nodrop', 'nodrag nodrop');
    $xtpl->table_out();
}

function notifications_route_edit($route_id)
{
    global $xtpl, $api;

    $route = $api->event_route->show($route_id, ['meta' => ['includes' => 'user']]);
    $input = $api->event_route->update->getParameters('input');
    $matcher_input = $route->matcher->create->getParameters('input');
    $event_types = notifications_param_choices($input->event_type, true);
    $all_fields = notifications_param_choices($matcher_input->field);
    $operators = notifications_param_choices($matcher_input->operator);
    $receiver_options = notifications_receiver_options($route->user_id);
    $route_options = notifications_route_options($route->user_id, true, $route->id);
    $matchers = notifications_api_list_to_array($route->matcher->list());
    $fields = notifications_route_matcher_fields($route, $all_fields, $matchers);
    $default_field = array_key_first($fields) ?: 'event_type';
    $default_operator = array_key_first($operators) ?: '==';

    $xtpl->title(_('Notification route') . ' #' . $route->id);

    $xtpl->table_title(_('Update route'));
    $xtpl->form_create('?page=notifications&action=route_edit&id=' . $route->id . notifications_user_qs($route->user_id), 'post');

    $xtpl->table_td(_('User') . ':');
    $xtpl->table_td(isAdmin() ? user_link($route->user) : h($route->user->login));
    $xtpl->table_tr();

    api_param_to_form('label', $input->label, post_val('label', $route->label));
    $xtpl->form_add_select(_('Parent route') . ':', 'parent_id', $route_options, post_val('parent_id', $route->parent_id));
    $xtpl->form_add_select(_('Event type') . ':', 'event_type', $event_types, post_val('event_type', $route->event_type));
    api_param_to_form('event_type_pattern', $input->event_type_pattern, post_val('event_type_pattern', $route->event_type_pattern));
    $xtpl->form_add_select(_('Receiver') . ':', 'notification_receiver_id', $receiver_options, post_val('notification_receiver_id', $route->notification_receiver_id));
    api_param_to_form('enabled', $input->enabled, post_val('enabled', $route->enabled));
    api_param_to_form('continue', $input->continue, post_val('continue', $route->continue));
    $xtpl->form_out(_('Save'));
    notifications_clear_table_form();

    notifications_route_subroutes($route);

    $xtpl->table_title(_('Matchers'));
    $xtpl->form_create('?page=notifications&action=matcher_save&route=' . $route->id . notifications_user_qs($route->user_id), 'post');
    $xtpl->table_add_category(_('Field'));
    $xtpl->table_add_category(_('Operator'));
    $xtpl->table_add_category(_('Value'));
    $xtpl->table_add_category('');

    foreach ($matchers as $matcher) {
        $prefix = 'matchers[' . $matcher->id . ']';
        $xtpl->table_td(notifications_select_html($prefix . '[field]', $fields, $matcher->field));
        $xtpl->table_td(notifications_select_html($prefix . '[operator]', $operators, $matcher->operator));
        $xtpl->table_td(notifications_text_input_html($prefix . '[value]', $matcher->value, 35));
        $xtpl->table_td(
            '<a href="?page=notifications&action=matcher_delete&route=' . $route->id . '&id=' . $matcher->id
            . notifications_user_qs($route->user_id) . '&t=' . csrf_token() . '"><img src="template/icons/vps_delete.png" title="' . _('Delete') . '"></a>'
        );
        $xtpl->table_tr();
    }

    if (count($matchers) == 0) {
        $xtpl->table_td(_('No matchers configured.'), false, false, 4);
        $xtpl->table_tr();
    } else {
        $xtpl->table_td(_('New matcher') . ':', false, false, 2);
        $xtpl->table_td(notifications_submit_html(_('Save changes'), null, 'save_matchers'));
        $xtpl->table_td('');
        $xtpl->table_tr();
    }

    $xtpl->table_td(notifications_select_html('new_field', $fields, post_val('new_field', $default_field)));
    $xtpl->table_td(notifications_select_html('new_operator', $operators, post_val('new_operator', $default_operator)));
    $xtpl->table_td(notifications_text_input_html('new_value', post_val('new_value'), 35));
    $xtpl->table_td(notifications_submit_html(_('Add'), null, 'add_matcher'));
    $xtpl->table_tr();
    $xtpl->form_out_raw();

    notifications_fields_table($route->event_type);

    $xtpl->sbar_add(_('Back to routes'), '?page=notifications&action=routes' . notifications_user_qs($route->user_id));
    notifications_sidebar('routes', $route->user_id);
}

function notifications_receiver_actions_summary_html($receiver)
{
    if ($receiver->mute) {
        return '<code>' . _('muted') . '</code>';
    }

    $lines = [];

    foreach (notifications_api_list_to_array($receiver->action->list()) as $action) {
        $line = $action->action . ': ' . (notifications_prop($action, 'display_target') ?: $action->target_kind);
        if (!$action->enabled) {
            $line .= ' (' . _('disabled') . ')';
        }
        $lines[] = '<code>' . h($line) . '</code>';
    }

    return $lines ? implode('<br>', $lines) : '-';
}

function notifications_receivers($user_id = null)
{
    global $xtpl, $api;

    $user_id = notifications_target_user_id($user_id);
    $user = $api->user->show($user_id);
    $receivers = $api->notification_receiver->list(['user' => $user_id]);
    $input = $api->notification_receiver->create->getParameters('input');

    $xtpl->title(_('Notification receivers'));

    if (isAdmin()) {
        $xtpl->table_title(_('User'));
        $xtpl->form_create('?page=notifications&action=receivers', 'get', 'notification-user', false);
        $xtpl->form_set_hidden_fields([
            'page' => 'notifications',
            'action' => 'receivers',
        ]);
        $xtpl->form_add_input(_('User ID') . ':', 'text', '20', 'user', $user_id);
        $xtpl->form_out(_('Show'));
    }

    $xtpl->table_title(_('Receivers') . ': ' . h($user->login));
    $xtpl->table_add_category(_('Label'));
    $xtpl->table_add_category(_('Actions'));
    $xtpl->table_add_category(_('Enabled'));
    $xtpl->table_add_category(_('Mute'));
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');

    foreach ($receivers as $receiver) {
        $toggle_link = '?page=notifications&action=receiver_toggle&id=' . $receiver->id
            . notifications_user_qs($user_id) . '&t=' . csrf_token();
        $delete_link = '?page=notifications&action=receiver_delete&id=' . $receiver->id
            . notifications_user_qs($user_id) . '&t=' . csrf_token();

        $xtpl->table_td(h($receiver->label));
        $xtpl->table_td(notifications_receiver_actions_summary_html($receiver));
        $xtpl->table_td(
            '<a href="' . $toggle_link . '" title="' . ($receiver->enabled ? _('Disable receiver') : _('Enable receiver')) . '">'
            . boolean_icon($receiver->enabled) . '</a>'
        );
        $xtpl->table_td(boolean_icon($receiver->mute));
        $xtpl->table_td('<a href="?page=notifications&action=receiver_edit&id=' . $receiver->id . notifications_user_qs($user_id) . '"><img src="template/icons/vps_edit.png" title="' . _('Edit') . '"></a>');
        $xtpl->table_td(
            '<a href="' . $delete_link . '"' . notifications_confirm_onclick(_('Do you really wish to delete this notification receiver?')) . '>'
            . '<img src="template/icons/vps_delete.png" title="' . _('Delete') . '"></a>'
        );
        $xtpl->table_td('');
        $xtpl->table_tr($receiver->enabled ? false : '#A6A6A6');
    }

    if ($receivers->count() == 0) {
        $xtpl->table_td(_('No receivers configured.'), false, false, 7);
        $xtpl->table_tr();
    }

    $xtpl->table_out();

    $xtpl->table_title(_('Add receiver'));
    $xtpl->form_create('?page=notifications&action=receiver_new' . notifications_user_qs($user_id), 'post');
    api_param_to_form('label', $input->label, post_val('label'));
    api_param_to_form('description', $input->description, post_val('description'));
    $xtpl->form_add_checkbox(_('Enabled') . ':', 'enabled', '1', post_val('enabled', true));
    $xtpl->form_add_checkbox(_('Mute') . ':', 'mute', '1', post_val('mute', false));
    $xtpl->form_out(_('Add'));

    notifications_sidebar('receivers', $user_id);
}

function notifications_receiver_action_target_html($action)
{
    $target = notifications_prop($action, 'display_target')
        ?: notifications_prop($action, 'target_value')
        ?: notifications_prop($action, 'target_kind');

    return $target ? h($target) : '-';
}

function notifications_receiver_action_template_html($action)
{
    if ($action->action !== 'email') {
        return '-';
    }

    return $action->template_name ? '<code>' . h($action->template_name) . '</code>' : _('default');
}

function notifications_receiver_action_secret_html($action)
{
    if ($action->action !== 'webhook') {
        return '-';
    }

    return boolean_icon($action->secret_present);
}

function notifications_receiver_action_form_fields($receiver, $action_type, $action = null)
{
    global $xtpl;

    $input = $receiver->action->create->getParameters('input');
    $target_kinds = notifications_param_choices($input->target_kind);
    $label = $action ? $action->label : '';
    $enabled = $action ? $action->enabled : true;

    $xtpl->table_td(_('Receiver') . ':');
    $xtpl->table_td('<a href="?page=notifications&action=receiver_edit&id=' . $receiver->id . notifications_user_qs($receiver->user_id) . '">' . h($receiver->label) . '</a>');
    $xtpl->table_tr();

    $xtpl->table_td(_('Action') . ':');
    $xtpl->table_td(h(notifications_receiver_action_type_label($receiver, $action_type)));
    $xtpl->table_tr();

    $xtpl->form_add_input(
        _('Label') . ':',
        'text',
        '40',
        'label',
        post_val('label', $label),
        _('Optional display name for this action.')
    );

    if ($action_type === 'email') {
        $target_kind = post_val('target_kind', $action ? $action->target_kind : 'default_recipient');

        $xtpl->form_add_select(
            _('Recipient') . ':',
            'target_kind',
            $target_kinds,
            $target_kind,
            _('Use the account e-mail or provide custom comma-separated addresses.')
        );
        $xtpl->form_add_input(
            _('Custom e-mail addresses') . ':',
            'text',
            '60',
            'target_value',
            post_val('target_value', $action ? $action->target_value : ''),
            _('Used only when custom target is selected.')
        );
        $xtpl->form_add_input(
            _('Template') . ':',
            'text',
            '40',
            'template_name',
            post_val('template_name', $action ? $action->template_name : ''),
            _('Leave empty to use the event default e-mail template.')
        );
    } elseif ($action_type === 'webhook') {
        $xtpl->form_add_input(
            _('Webhook URL') . ':',
            'text',
            '80',
            'target_value',
            post_val('target_value', $action ? $action->target_value : ''),
            _('HTTP or HTTPS endpoint that receives the event JSON payload.')
        );

        $placeholder = $action ? _('leave empty to keep') : null;
        $xtpl->table_td(_('Secret') . ':');
        $xtpl->table_td(notifications_password_input_html('secret', '', 40, null, $placeholder));
        $xtpl->table_td(_('Optional HMAC secret sent as X-VpsAdmin-Signature-256.'));
        $xtpl->table_tr();

        if ($action && $action->secret_present) {
            $xtpl->table_td(_('Current secret') . ':');
            $xtpl->table_td(boolean_icon(true) . ' ' . notifications_checkbox_html('clear_secret', false) . ' ' . _('clear secret'), false, true);
            $xtpl->table_tr();
        }
    }

    $xtpl->form_add_checkbox(_('Enabled') . ':', 'enabled', '1', post_val('enabled', $enabled));
}

function notifications_receiver_action_new($receiver_id, $action_type = null)
{
    global $xtpl, $api;

    $receiver = $api->notification_receiver->show($receiver_id, ['meta' => ['includes' => 'user']]);
    $labels = notifications_receiver_action_type_labels($receiver);
    $action_type = $action_type ?: notifications_receiver_action_type_from_request($receiver);
    if ($action_type !== null && !isset($labels[$action_type])) {
        $action_type = null;
    }

    if ($action_type === null) {
        $selected = api_get('type') ?: 'email';

        $xtpl->title(_('Add receiver action'));
        $xtpl->table_title(_('Select action type'));
        $xtpl->form_create('?page=notifications', 'get', 'notification-action-type', false);
        $hidden = [
            'page' => 'notifications',
            'action' => 'receiver_action_new',
            'receiver' => $receiver->id,
        ];
        if (isAdmin()) {
            $hidden['user'] = $receiver->user_id;
        }
        $xtpl->form_set_hidden_fields($hidden);
        $xtpl->form_add_select(
            _('Action type') . ':',
            'type',
            $labels,
            isset($labels[$selected]) ? $selected : 'email',
            _('Choose how this receiver will deliver matching events.')
        );
        $xtpl->form_out(_('Continue'));

        $xtpl->sbar_add(_('Back to receiver'), '?page=notifications&action=receiver_edit&id=' . $receiver->id . notifications_user_qs($receiver->user_id));
        notifications_sidebar('receivers', $receiver->user_id);
        return;
    }

    $xtpl->title(_('Add receiver action'));
    $xtpl->table_title(_('Add action'));
    $xtpl->form_create(
        '?page=notifications&action=receiver_action_new&receiver=' . $receiver->id
        . '&type=' . urlencode($action_type) . notifications_user_qs($receiver->user_id),
        'post'
    );
    $xtpl->form_set_hidden_fields([
        'action_type' => $action_type,
    ]);
    notifications_receiver_action_form_fields($receiver, $action_type);
    $xtpl->form_out(_('Add'));

    $xtpl->sbar_add(_('Back to receiver'), '?page=notifications&action=receiver_edit&id=' . $receiver->id . notifications_user_qs($receiver->user_id));
    notifications_sidebar('receivers', $receiver->user_id);
}

function notifications_receiver_action_edit($receiver_id, $action_id)
{
    global $xtpl, $api;

    $receiver = $api->notification_receiver->show($receiver_id, ['meta' => ['includes' => 'user']]);
    $action = $receiver->action->show($action_id);

    $xtpl->title(_('Receiver action') . ' #' . $action->id);
    $xtpl->table_title(_('Update action'));
    $xtpl->form_create(
        '?page=notifications&action=receiver_action_edit&receiver=' . $receiver->id
        . '&id=' . $action->id . notifications_user_qs($receiver->user_id),
        'post'
    );
    $xtpl->form_set_hidden_fields([
        'action_type' => $action->action,
    ]);
    notifications_receiver_action_form_fields($receiver, $action->action, $action);
    $xtpl->form_out(_('Save'));

    $xtpl->sbar_add(_('Back to receiver'), '?page=notifications&action=receiver_edit&id=' . $receiver->id . notifications_user_qs($receiver->user_id));
    notifications_sidebar('receivers', $receiver->user_id);
}

function notifications_receiver_edit($receiver_id)
{
    global $xtpl, $api;

    $receiver = $api->notification_receiver->show($receiver_id, ['meta' => ['includes' => 'user']]);
    $input = $api->notification_receiver->update->getParameters('input');
    $action_labels = notifications_receiver_action_type_labels($receiver);

    $xtpl->title(_('Notification receiver') . ' #' . $receiver->id);
    $xtpl->table_title(_('Update receiver'));
    $xtpl->form_create('?page=notifications&action=receiver_edit&id=' . $receiver->id . notifications_user_qs($receiver->user_id), 'post');

    $xtpl->table_td(_('User') . ':');
    $xtpl->table_td(isAdmin() ? user_link($receiver->user) : h($receiver->user->login));
    $xtpl->table_tr();

    api_param_to_form('label', $input->label, post_val('label', $receiver->label));
    api_param_to_form('description', $input->description, post_val('description', $receiver->description));
    api_param_to_form('enabled', $input->enabled, post_val('enabled', $receiver->enabled));
    api_param_to_form('mute', $input->mute, post_val('mute', $receiver->mute));
    $xtpl->form_out(_('Save'));
    notifications_clear_table_form();

    $xtpl->table_title(_('Actions'));
    $xtpl->table_add_category(_('Action'));
    $xtpl->table_add_category(_('Label'));
    $xtpl->table_add_category(_('Target'));
    $xtpl->table_add_category(_('Template'));
    $xtpl->table_add_category(_('Enabled'));
    $xtpl->table_add_category(_('Webhook secret'));
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');

    $receiver_actions = notifications_api_list_to_array($receiver->action->list());

    foreach ($receiver_actions as $action) {
        $xtpl->table_td(h($action_labels[$action->action] ?? $action->action));
        $xtpl->table_td(h($action->label));
        $xtpl->table_td(notifications_receiver_action_target_html($action), false, true);
        $xtpl->table_td(notifications_receiver_action_template_html($action), false, true);
        $xtpl->table_td(boolean_icon($action->enabled));
        $xtpl->table_td(notifications_receiver_action_secret_html($action));
        $xtpl->table_td(
            '<a href="?page=notifications&action=receiver_action_edit&receiver=' . $receiver->id . '&id=' . $action->id
            . notifications_user_qs($receiver->user_id) . '"><img src="template/icons/vps_edit.png" title="' . _('Edit') . '"></a>'
        );
        $xtpl->table_td(
            '<a href="?page=notifications&action=receiver_action_delete&receiver=' . $receiver->id . '&id=' . $action->id
            . notifications_user_qs($receiver->user_id) . '&t=' . csrf_token() . '"><img src="template/icons/vps_delete.png" title="' . _('Delete') . '"></a>'
        );
        $xtpl->table_tr();
    }

    if (count($receiver_actions) == 0) {
        $xtpl->table_td(_('No actions configured.'), false, false, 8);
        $xtpl->table_tr();
    }

    $xtpl->table_td(
        '<a href="?page=notifications&action=receiver_action_new&receiver=' . $receiver->id
        . notifications_user_qs($receiver->user_id) . '"><img src="template/icons/vps_add.png" title="' . _('Add action') . '" alt="' . _('Add action') . '"> '
        . _('Add action') . '</a>',
        false,
        true,
        8
    );
    $xtpl->table_tr();
    $xtpl->table_out();

    $xtpl->sbar_add(_('Back to receivers'), '?page=notifications&action=receivers' . notifications_user_qs($receiver->user_id));
    notifications_sidebar('receivers', $receiver->user_id);
}

function notifications_time_or_dash($value)
{
    return $value ? tolocaltz($value) : '-';
}

function notifications_delivery_attempts_html($event, $delivery)
{
    $lines = [];

    foreach (notifications_api_list_to_array($event->delivery($delivery->id)->attempt->list()) as $attempt) {
        $line = '#' . $attempt->attempt_number
            . ' ' . $attempt->state
            . ' ' . notifications_time_or_dash($attempt->started_at)
            . ' - ' . notifications_time_or_dash($attempt->finished_at);

        $provider_message_id = notifications_prop($attempt, 'provider_message_id');
        $response_status = notifications_prop($attempt, 'response_status');
        $error_summary = notifications_prop($attempt, 'error_summary');
        $response_body = notifications_prop($attempt, 'response_body');

        if ($provider_message_id) {
            $line .= ' ' . _('message') . ' ' . $provider_message_id;
        }

        if ($response_status) {
            $line .= ' HTTP ' . $response_status;
        }

        if ($error_summary) {
            $line .= ' ' . $error_summary;
        }

        $lines[] = '<code>' . h($line) . '</code>';

        if ($response_body) {
            $lines[] = '<pre>' . h(notifications_short_value($response_body, 1024)) . '</pre>';
        }
    }

    return $lines ? implode('<br>', $lines) : '-';
}

function notifications_events()
{
    global $xtpl, $api;

    $params = [
        'limit' => api_get_uint('limit', 25),
        'meta' => ['includes' => 'user,vps'],
    ];

    foreach (['event_type', 'category', 'severity', 'routing_state'] as $name) {
        $value = api_get($name);
        if ($value !== null) {
            $params[$name] = $value;
        }
    }

    $delivery_action = api_get('delivery_action');
    if ($delivery_action !== null) {
        $params['action'] = $delivery_action;
    }

    $route_id = api_get_uint('matched_event_route_id');
    if ($route_id !== null && $route_id > 0) {
        $params['matched_event_route_id'] = $route_id;
    }

    $user_id = api_get_uint('user');
    if ($user_id !== null && $user_id > 0) {
        $params['user'] = $user_id;
    }

    $from_id = api_get_uint('from_id');
    if ($from_id !== null && $from_id > 0) {
        $params['from_id'] = $from_id;
    }

    $events = $api->event->list($params);
    $pagination = new \Pagination\System($events);
    $input = $api->event->list->getParameters('input');

    $xtpl->title(_('Event log'));
    $xtpl->table_title(_('Filters'));
    $xtpl->form_create('', 'get', 'notification-events', false);
    $xtpl->form_set_hidden_fields([
        'page' => 'notifications',
        'action' => 'events',
    ]);

    $xtpl->form_add_input(_('Limit') . ':', 'text', '20', 'limit', get_val('limit', '25'));
    $xtpl->form_add_input(_('From ID') . ':', 'text', '20', 'from_id', get_val('from_id'));
    $xtpl->form_add_input(_('Route ID') . ':', 'text', '20', 'matched_event_route_id', get_val('matched_event_route_id'));

    if (isAdmin()) {
        $xtpl->form_add_input(_('User ID') . ':', 'text', '20', 'user', get_val('user'));
    }

    api_param_to_form('event_type', $input->event_type, get_val('event_type'), null, true);
    api_param_to_form('category', $input->category, get_val('category'));
    api_param_to_form('severity', $input->severity, get_val('severity'), null, true);
    api_param_to_form('routing_state', $input->routing_state, get_val('routing_state'), null, true);
    $action_label = isset($input->action->label) && $input->action->label ? $input->action->label : _('Action');
    $xtpl->table_td($action_label . ':');
    $xtpl->table_td(
        notifications_select_html(
            'delivery_action',
            notifications_param_choices($input->action, true),
            get_val('delivery_action')
        ),
        false,
        true
    );
    $xtpl->table_tr();
    $xtpl->form_out(_('Show'));

    $xtpl->table_add_category(_('Time'));
    $xtpl->table_add_category(_('Type'));

    if (isAdmin()) {
        $xtpl->table_add_category(_('User'));
    }

    $xtpl->table_add_category(_('VPS'));
    $xtpl->table_add_category(_('Subject'));
    $xtpl->table_add_category(_('Severity'));
    $xtpl->table_add_category(_('State'));
    $xtpl->table_add_category(_('Deliveries'));
    $xtpl->table_add_category('');

    foreach ($events as $event) {
        $deliveries = notifications_api_list_to_array($event->delivery->list());
        $action_labels = [];

        foreach ($deliveries as $delivery) {
            $label = $delivery->action . ':' . $delivery->state;
            $response_status = notifications_prop($delivery, 'response_status');
            if ($response_status) {
                $label .= ':' . $response_status;
            }
            $action_labels[] = '<code>' . h($label) . '</code>';
        }

        $xtpl->table_td(tolocaltz($event->created_at));
        $xtpl->table_td(h($event->event_type));

        if (isAdmin()) {
            $xtpl->table_td($event->user_id ? user_link($event->user) : '-');
        }

        $xtpl->table_td($event->vps_id ? vps_link($event->vps) : '-');
        $xtpl->table_td(h($event->subject));
        $xtpl->table_td(h($event->severity));
        $xtpl->table_td(h($event->routing_state));
        $xtpl->table_td($action_labels ? implode(' ', $action_labels) : '-');
        $xtpl->table_td('<a href="?page=notifications&action=event_show&id=' . $event->id . '"><img src="template/icons/vps_edit.png" title="' . _('Details') . '"></a>');
        $xtpl->table_tr();
    }

    $xtpl->table_pagination($pagination);
    $xtpl->table_out();

    notifications_sidebar('events', notifications_target_user_id());
}

function notifications_event_show($event_id)
{
    global $xtpl, $api;

    $event = $api->event->show($event_id, ['meta' => ['includes' => 'user,vps']]);

    $xtpl->title(_('Event') . ' #' . $event->id . ': ' . h($event->subject));

    $xtpl->table_td(_('Time') . ':');
    $xtpl->table_td(tolocaltz($event->created_at));
    $xtpl->table_tr();

    $xtpl->table_td(_('Event type') . ':');
    $xtpl->table_td(h($event->event_type));
    $xtpl->table_tr();

    if (isAdmin()) {
        $xtpl->table_td(_('User') . ':');
        $xtpl->table_td($event->user_id ? user_link($event->user) : '-');
        $xtpl->table_tr();
    }

    $xtpl->table_td(_('VPS') . ':');
    $xtpl->table_td($event->vps_id ? vps_link($event->vps) : '-');
    $xtpl->table_tr();

    $xtpl->table_td(_('Severity') . ':');
    $xtpl->table_td(h($event->severity));
    $xtpl->table_tr();

    $xtpl->table_td(_('Routing state') . ':');
    $xtpl->table_td(h($event->routing_state));
    $xtpl->table_tr();

    $xtpl->table_td(_('Matched route') . ':');
    $xtpl->table_td($event->matched_event_route_id ? '<a href="?page=notifications&action=route_edit&id=' . $event->matched_event_route_id . notifications_user_qs($event->user_id) . '">' . $event->matched_event_route_id . '</a>' : '-');
    $xtpl->table_tr();

    $xtpl->table_td(_('Summary') . ':');
    $xtpl->table_td(h($event->summary));
    $xtpl->table_tr();

    $xtpl->table_td(_('Parameters') . ':');
    $xtpl->table_td('<pre>' . h($event->parameters_json) . '</pre>');
    $xtpl->table_tr();
    $xtpl->table_out();

    $xtpl->table_title(_('Deliveries'));
    $xtpl->table_add_category(_('Action'));
    $xtpl->table_add_category(_('Receiver'));
    $xtpl->table_add_category(_('Target'));
    $xtpl->table_add_category(_('State'));
    $xtpl->table_add_category(_('Route'));
    $xtpl->table_add_category(_('Attempts'));
    $xtpl->table_add_category(_('Released'));
    $xtpl->table_add_category(_('Last attempt'));
    $xtpl->table_add_category(_('Next retry'));
    $xtpl->table_add_category(_('Result'));

    $deliveries = notifications_api_list_to_array($event->delivery->list());

    foreach ($deliveries as $delivery) {
        $target = notifications_prop($delivery, 'target_label')
            ?: notifications_prop($delivery, 'target_value')
            ?: notifications_prop($delivery, 'target_kind');
        $provider_message_id = notifications_prop($delivery, 'provider_message_id');
        $response_status = notifications_prop($delivery, 'response_status');
        $error_summary = notifications_prop($delivery, 'error_summary');
        $response_body = notifications_prop($delivery, 'response_body');

        $xtpl->table_td(h($delivery->action));
        $xtpl->table_td($delivery->notification_receiver_id ? h('#' . $delivery->notification_receiver_id) : '-');
        $xtpl->table_td($target ? h($target) : '-');
        $xtpl->table_td(h($delivery->state));
        $xtpl->table_td($delivery->event_route_id ? '<a href="?page=notifications&action=route_edit&id=' . $delivery->event_route_id . notifications_user_qs($event->user_id) . '">' . $delivery->event_route_id . '</a>' : '-');
        $xtpl->table_td(notifications_prop($delivery, 'attempt_count', 0), false, true);
        $xtpl->table_td(notifications_time_or_dash(notifications_prop($delivery, 'released_at')));
        $xtpl->table_td(notifications_time_or_dash(notifications_prop($delivery, 'last_attempt_at')));
        $xtpl->table_td(notifications_time_or_dash(notifications_prop($delivery, 'next_attempt_at')));
        $result = [];
        if ($provider_message_id) {
            $result[] = _('message') . ' ' . $provider_message_id;
        }
        if ($response_status) {
            $result[] = 'HTTP ' . $response_status;
        }
        if ($error_summary) {
            $result[] = $error_summary;
        }
        $xtpl->table_td($result ? h(implode(', ', $result)) : '-');
        $xtpl->table_tr();

        $xtpl->table_td(_('Delivery attempts') . ':', false, false, 2);
        $xtpl->table_td(notifications_delivery_attempts_html($event, $delivery), false, true, 8);
        $xtpl->table_tr();

        if ($response_body) {
            $xtpl->table_td(_('Response') . ':', false, false, 2);
            $xtpl->table_td('<pre>' . h(notifications_short_value($response_body, 1024)) . '</pre>', false, false, 8);
            $xtpl->table_tr();
        }
    }

    if (count($deliveries) == 0) {
        $xtpl->table_td(_('No deliveries recorded.'), false, false, 10);
        $xtpl->table_tr();
    }

    $xtpl->table_out();

    $xtpl->sbar_add(_('Back to event log'), '?page=notifications&action=events');
    notifications_sidebar('events', $event->user_id);
}

function notifications_fields_table($event_type = null)
{
    global $xtpl;

    $types = notifications_event_types_cached();

    foreach ($types as $type) {
        if ($event_type && $type->name !== $event_type) {
            continue;
        }

        $fields = notifications_event_type_fields_from_type($type);

        $xtpl->table_title(_('Matchable fields') . ': ' . h($type->label));
        $xtpl->table_add_category(_('Field'));
        $xtpl->table_add_category(_('Label'));

        foreach ($fields as $field => $label) {
            $xtpl->table_td('<code>' . h($field) . '</code>');
            $xtpl->table_td(h($label));
            $xtpl->table_tr();
        }

        $xtpl->table_out();
    }
}

function notifications_event_types($user_id = null)
{
    global $xtpl;

    $xtpl->title(_('Event types'));
    $xtpl->table_title(_('Event types'));
    $xtpl->table_add_category(_('Name'));
    $xtpl->table_add_category(_('Category'));
    $xtpl->table_add_category(_('Severity'));
    $xtpl->table_add_category(_('Matchable fields'));

    foreach (notifications_event_types_cached() as $type) {
        $fields = notifications_event_type_fields_from_type($type);
        $lines = [];

        foreach ($fields as $name => $label) {
            $lines[] = '<code>' . h($name) . '</code> ' . h($label);
        }

        $xtpl->table_td('<code>' . h($type->name) . '</code><br>' . h($type->label), false, true);
        $xtpl->table_td(h($type->category));
        $xtpl->table_td(h($type->severity));
        $xtpl->table_td($lines ? implode('<br>', $lines) : '-');
        $xtpl->table_tr();
    }

    $xtpl->table_out();

    notifications_sidebar('event_types', $user_id);
}

function notifications_test_event($user_id = null)
{
    global $xtpl, $api;

    $user_id = notifications_target_user_id($user_id);
    $input = $api->event->test->getParameters('input');

    $xtpl->title(_('Test notification event'));
    $xtpl->table_title(_('Create test event'));
    $xtpl->form_create('?page=notifications&action=test' . notifications_user_qs($user_id), 'post');

    if (isAdmin()) {
        $xtpl->form_add_input(_('User ID') . ':', 'text', '20', 'user', $user_id);
    }

    api_param_to_form('event_type', $input->event_type, post_val('event_type', 'user.test_notification'), null, true);
    api_param_to_form('subject', $input->subject, post_val('subject', _('Test notification')));
    api_param_to_form('summary', $input->summary, post_val('summary', _('This event was created from notification settings.')));
    $xtpl->form_add_textarea(_('Parameters') . ':', 70, 8, 'parameters_json', post_val('parameters_json', "{\n  \"note\": \"testing notification routing\"\n}"));
    $xtpl->form_out(_('Create event'));

    notifications_sidebar('test', $user_id);
}
