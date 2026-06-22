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

    $xtpl->sbar_add(_('Event log'), '?page=notifications&action=events' . $user_qs);
    if (isAdmin()) {
        $xtpl->sbar_add(_('Delivery queue'), '?page=notifications&action=delivery_queue');
        $xtpl->sbar_add(_('Delivery log'), '?page=notifications&action=delivery_log');
    }
    $xtpl->sbar_add(_('Routes'), '?page=notifications&action=routes' . $user_qs);
    $xtpl->sbar_add(_('Receivers'), '?page=notifications&action=receivers' . $user_qs);
    $xtpl->sbar_add(_('Event types'), '?page=notifications&action=event_types' . $user_qs);
    $xtpl->sbar_add(_('Test event'), '?page=notifications&action=test' . $user_qs);
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
    $wrapped_keys = [
        'event_types',
        'event_routes',
        'event_route_matchers',
        'notification_receivers',
        'notification_receiver_actions',
        'events',
        'event_deliveries',
        'event_delivery_attempts',
        'receivers',
        'actions',
        'matchers',
        'deliveries',
        'attempts',
    ];

    foreach ($wrapped_keys as $key) {
        if (is_array($list) && array_key_exists($key, $list)) {
            return notifications_api_list_to_array($list[$key]);
        }

        if (is_object($list) && property_exists($list, $key)) {
            return notifications_api_list_to_array($list->{$key});
        }
    }

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

    foreach ($wrapped_keys as $key) {
        if (is_array($response) && array_key_exists($key, $response)) {
            return notifications_api_list_to_array($response[$key]);
        }

        if (is_object($response) && property_exists($response, $key)) {
            return notifications_api_list_to_array($response->{$key});
        }
    }

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

function notifications_event_type_labels($empty = true)
{
    $ret = [];

    if ($empty) {
        $ret[''] = '---';
    }

    foreach (notifications_event_types_cached() as $type) {
        $ret[$type->name] = isset($type->label) && $type->label ? $type->label : $type->name;
    }

    return $ret;
}

function notifications_matcher_operator_descriptions($operators)
{
    $descriptions = [
        '==' => _('equals'),
        '!=' => _('does not equal'),
        '=~' => _('matches regular expression'),
        '!~' => _('does not match regular expression'),
        '=*' => _('matches glob'),
        '!*' => _('does not match glob'),
        '>' => _('greater than'),
        '>=' => _('greater than or equal'),
        '<' => _('less than'),
        '<=' => _('less than or equal'),
    ];
    $ret = [];

    foreach ($operators as $operator => $label) {
        $ret[$operator] = isset($descriptions[$operator])
            ? $label . ' (' . $descriptions[$operator] . ')'
            : $label;
    }

    return $ret;
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

function notifications_event_log_url($user_id = null, $params = [])
{
    $url = '?page=notifications&action=events' . notifications_user_qs($user_id);

    foreach ($params as $name => $value) {
        if ($value === null || $value === '') {
            continue;
        }

        $url .= '&' . rawurlencode($name) . '=' . rawurlencode((string) $value);
    }

    return $url;
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

function notifications_secret_input_html($name, $value, $size = 30, $form_id = null, $placeholder = null)
{
    $form_attr = $form_id ? ' form="' . h($form_id) . '"' : '';
    $placeholder_attr = $placeholder !== null ? ' placeholder="' . h($placeholder) . '"' : '';

    return '<input type="text" name="' . h($name) . '" id="input" size="' . (int) $size . '" value="' . h($value) . '"' . $form_attr . $placeholder_attr . '>';
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
        . '<style type="text/css">
#' . h($table_id) . ' .notification-drag-handle {
    cursor: move;
    display: inline-block;
    padding: 0 4px;
    user-select: none;
}
#' . h($table_id) . ' tr.notification-route-dragged td {
    opacity: 0.75;
}
body.notification-route-dragging,
body.notification-route-dragging * {
    cursor: move !important;
}
</style>
<script type="text/javascript">
$(function () {
    var table = $(' . $selector . ');
    var prefix = ' . $prefix . ';
    var action = ' . $action . ';
    var token = ' . $token . ';
    var drag = null;

    if (!table.length) {
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

    function routeRows() {
        return table.find("tr[id^=\"" + prefix + "\"]").filter(function () {
            return !!routeInfo(this);
        });
    }

    function routeRowMap() {
        var map = {};

        routeRows().each(function () {
            var info = routeInfo(this);
            map[info.id] = this;
        });

        return map;
    }

    function isDescendantOf(row, ancestorId, map) {
        var info = routeInfo(row);
        var parent = info ? info.parent : null;

        while (parent && parent !== "root") {
            if (parent === ancestorId) {
                return true;
            }

            if (!map[parent]) {
                return false;
            }

            parent = routeInfo(map[parent]).parent;
        }

        return false;
    }

    function subtreeRows(row, map) {
        var info = routeInfo(row);
        var rows = [];

        if (!info) {
            return rows;
        }

        routeRows().each(function () {
            if (this === row || isDescendantOf(this, info.id, map)) {
                rows.push(this);
            }
        });

        return rows;
    }

    function containsRow(rows, row) {
        return $.inArray(row, rows) !== -1;
    }

    function siblingIds(parent) {
        var ids = [];

        routeRows().each(function () {
            var info = routeInfo(this);

            if (info && info.parent === parent) {
                ids.push(info.id);
            }
        });

        return ids;
    }

    function sameIds(a, b) {
        if (a.length !== b.length) {
            return false;
        }

        for (var i = 0; i < a.length; i++) {
            if (a[i] !== b[i]) {
                return false;
            }
        }

        return true;
    }

    function destinationFor(clientY, parent, draggedRows, map) {
        var destination = null;

        routeRows().each(function () {
            var info = routeInfo(this);

            if (!info || info.parent !== parent || containsRow(draggedRows, this)) {
                return;
            }

            var block = subtreeRows(this, map);
            var first = block[0];
            var last = block[block.length - 1];
            var firstRect = first.getBoundingClientRect();
            var lastRect = last.getBoundingClientRect();
            var middle = firstRect.top + ((lastRect.bottom - firstRect.top) / 2);

            if (clientY < middle) {
                destination = {
                    rows: block,
                    before: true
                };
                return false;
            }

            destination = {
                rows: block,
                before: false
            };
        });

        return destination;
    }

    function moveBlock(draggedRows, destination) {
        var rows = $(draggedRows).detach();

        if (destination.before) {
            $(destination.rows[0]).before(rows);
        } else {
            $(destination.rows[destination.rows.length - 1]).after(rows);
        }
    }

    function beginDrag() {
        drag.active = true;
        $("body").addClass("notification-route-dragging");
        $(subtreeRows(drag.row, routeRowMap())).addClass("notification-route-dragged");
    }

    function postOrder(parent, ids) {
        $.ajax({
            type: "POST",
            url: action,
            dataType: "json",
            data: {
                csrf_token: token,
                parent_id: parent === "root" ? "" : parent,
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

    function dragMove(ev) {
        if (!drag) {
            return;
        }

        if (!drag.active && Math.abs(ev.pageY - drag.startY) < 3) {
            return false;
        }

        if (!drag.active) {
            beginDrag();
        }

        var map = routeRowMap();
        var draggedRows = subtreeRows(drag.row, map);
        var before = siblingIds(drag.parent);
        var destination = destinationFor(ev.clientY, drag.parent, draggedRows, map);

        if (destination) {
            moveBlock(draggedRows, destination);
            $(subtreeRows(drag.row, routeRowMap())).addClass("notification-route-dragged");
            drag.changed = drag.changed || !sameIds(before, siblingIds(drag.parent));
        }

        return false;
    }

    function dragEnd() {
        var finished = drag;

        $(document).off(".notificationRoutes");
        $("body").removeClass("notification-route-dragging");
        table.find("tr.notification-route-dragged").removeClass("notification-route-dragged");
        drag = null;

        if (!finished || !finished.changed) {
            return false;
        }

        var ids = siblingIds(finished.parent);

        if (!sameIds(finished.originalIds, ids)) {
            postOrder(finished.parent, ids);
        }

        return false;
    }

    table.find("tr[id^=\"" + prefix + "\"]").css("cursor", "");
    table.on("mousedown", ".notification-drag-handle", function (ev) {
        if (ev.which && ev.which !== 1) {
            return;
        }

        var row = $(this).closest("tr")[0];
        var info = routeInfo(row);

        if (!info) {
            return;
        }

        drag = {
            row: row,
            parent: info.parent,
            startY: ev.pageY,
            originalIds: siblingIds(info.parent),
            active: false,
            changed: false
        };

        $(document)
            .on("mousemove.notificationRoutes", dragMove)
            .on("mouseup.notificationRoutes", dragEnd);

        ev.preventDefault();
        ev.stopPropagation();
        return false;
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
    } elseif ($action_type === 'telegram') {
        if ($create) {
            $params['target_kind'] = 'custom';
            $params['target_value'] = null;
        }
    } elseif ($action_type === 'sms') {
        $params['target_kind'] = 'custom';
        $params['target_value'] = api_post('target_value');
    } elseif ($action_type === 'webhook') {
        $params['target_kind'] = 'custom';
        $params['target_value'] = api_post('target_value');
    } else {
        $params['target_kind'] = api_post('target_kind');
        $params['target_value'] = api_post('target_value');
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
        'field' => api_post('field'),
        'operator' => api_post('operator'),
        'value' => api_post('value'),
    ];
}

function notifications_matcher_params_from_row($row)
{
    return [
        'operator' => trim((string) ($row['operator'] ?? '')),
        'value' => trim((string) ($row['value'] ?? '')),
    ];
}

function notifications_route_type_html($route, $event_type_labels)
{
    if (notifications_prop($route, 'default_route', false)) {
        return h(_('Default event types'));
    }

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
    $event_type_labels = notifications_event_type_labels(false);
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
    $event_types = notifications_event_type_labels(true);
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
    $event_type_labels = notifications_event_type_labels(false);
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
    $event_types = notifications_event_type_labels(true);
    $operators = notifications_param_choices($matcher_input->operator);
    $receiver_options = notifications_receiver_options($route->user_id);
    $route_options = notifications_route_options($route->user_id, true, $route->id);
    $matchers = notifications_api_list_to_array($route->matcher->list());

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

    if (
        notifications_prop($route, 'default_route', false)
        || notifications_prop($route, 'single_use', false)
        || notifications_prop($route, 'spent_at')
        || notifications_prop($route, 'expires_at')
    ) {
        $xtpl->table_title(_('Route lifecycle'));
        $xtpl->table_td(_('Default route'));
        $xtpl->table_td(boolean_icon(notifications_prop($route, 'default_route', false)));
        $xtpl->table_tr();
        $xtpl->table_td(_('Single-use route'));
        $xtpl->table_td(boolean_icon(notifications_prop($route, 'single_use', false)));
        $xtpl->table_tr();
        $xtpl->table_td(_('Spent at'));
        $xtpl->table_td($route->spent_at ? tolocaltz($route->spent_at) : '-');
        $xtpl->table_tr();
        $xtpl->table_td(_('Expires at'));
        $xtpl->table_td($route->expires_at ? tolocaltz($route->expires_at) : '-');
        $xtpl->table_tr();
        $xtpl->table_out();
    }

    notifications_route_subroutes($route);

    $xtpl->table_title(_('Matchers'));
    $xtpl->form_create('?page=notifications&action=matcher_save&route=' . $route->id . notifications_user_qs($route->user_id), 'post');
    $xtpl->table_add_category(_('Field'));
    $xtpl->table_add_category(_('Operator'));
    $xtpl->table_add_category(_('Value'));
    $xtpl->table_add_category('');

    foreach ($matchers as $matcher) {
        $prefix = 'matchers[' . $matcher->id . ']';
        $xtpl->table_td('<code>' . h($matcher->field) . '</code>', false, true);
        $xtpl->table_td(notifications_select_html($prefix . '[operator]', $operators, $matcher->operator));
        $xtpl->table_td(notifications_text_input_html($prefix . '[value]', $matcher->value, 35));
        $xtpl->table_td(
            '<a href="?page=notifications&action=matcher_delete&route=' . $route->id . '&id=' . $matcher->id
            . notifications_user_qs($route->user_id) . '&t=' . csrf_token() . '"><img src="template/icons/vps_delete.png" title="' . _('Delete') . '"></a>'
        );
        $xtpl->table_tr();
    }

    $add_link = '<a href="?page=notifications&action=matcher_new&route=' . $route->id
        . notifications_user_qs($route->user_id) . '">'
        . '<img src="template/icons/vps_add.png" title="' . _('Add matcher') . '" alt="' . _('Add matcher') . '"> '
        . _('Add matcher') . '</a>';

    if (count($matchers) == 0) {
        $xtpl->table_td(_('No matchers configured.'), false, false, 4);
        $xtpl->table_tr();
    } else {
        $xtpl->table_td('');
        $xtpl->table_td('');
        $xtpl->table_td(notifications_submit_html(_('Save changes'), null, 'save_matchers'));
        $xtpl->table_td('');
        $xtpl->table_tr();
    }

    $xtpl->table_td($add_link, false, true, 4);
    $xtpl->table_tr();
    $xtpl->form_out_raw();

    $xtpl->sbar_add(_('Back to routes'), '?page=notifications&action=routes' . notifications_user_qs($route->user_id));
    notifications_sidebar('routes', $route->user_id);
}

function notifications_matcher_new($route_id, $event_type = null)
{
    global $xtpl, $api;

    $route = $api->event_route->show($route_id, ['meta' => ['includes' => 'user']]);
    $matcher_input = $route->matcher->create->getParameters('input');
    $all_fields = notifications_param_choices($matcher_input->field);
    $operators = notifications_param_choices($matcher_input->operator);
    $route_event_type = $route->event_type ?: null;
    $selected_event_type = $route_event_type ?: $event_type;

    $xtpl->title(_('Add matcher') . ': ' . _('Notification route') . ' #' . $route->id);

    if (!$selected_event_type) {
        $event_types = notifications_event_type_labels();

        $xtpl->table_title(_('Select event type'));
        $xtpl->form_create('?page=notifications', 'get', 'notification-matcher-event-type', false);
        $hidden = [
            'page' => 'notifications',
            'action' => 'matcher_new',
            'route' => $route->id,
        ];
        if (isAdmin()) {
            $hidden['user'] = $route->user_id;
        }
        $xtpl->form_set_hidden_fields($hidden);
        $xtpl->form_add_select(
            _('Event type') . ':',
            'event_type',
            $event_types,
            get_val('event_type', $event_type),
            _('Choose the event type whose fields should be offered.')
        );
        $xtpl->form_out(_('Continue'));

        $xtpl->sbar_add(_('Back to route'), '?page=notifications&action=route_edit&id=' . $route->id . notifications_user_qs($route->user_id));
        notifications_sidebar('routes', $route->user_id);
        return;
    }

    $fields = notifications_event_type_fields($selected_event_type, $all_fields);
    $field = post_val('field', array_key_first($fields) ?: 'event_type');
    $operator = post_val('operator', array_key_first($operators) ?: '==');
    $url = '?page=notifications&action=matcher_new&route=' . $route->id
        . ($route_event_type ? '' : '&event_type=' . urlencode($selected_event_type))
        . notifications_user_qs($route->user_id);

    $xtpl->table_title(_('Add matcher'));
    $xtpl->form_create($url, 'post');

    $xtpl->table_td(_('Route') . ':');
    $xtpl->table_td('<a href="?page=notifications&action=route_edit&id=' . $route->id . notifications_user_qs($route->user_id) . '">#' . $route->id . '</a>');
    $xtpl->table_tr();

    $xtpl->table_td(_('Event type') . ':');
    $xtpl->table_td('<code>' . h($selected_event_type) . '</code>');
    $xtpl->table_tr();

    $xtpl->form_add_select(_('Field') . ':', 'field', $fields, $field);
    $xtpl->form_add_select(
        _('Operator') . ':',
        'operator',
        notifications_matcher_operator_descriptions($operators),
        $operator
    );
    $xtpl->form_add_input(_('Value') . ':', 'text', '35', 'value', post_val('value'));
    $xtpl->form_out(_('Add'));

    $xtpl->sbar_add(_('Back to route'), '?page=notifications&action=route_edit&id=' . $route->id . notifications_user_qs($route->user_id));
    if (!$route_event_type) {
        $xtpl->sbar_add(_('Choose different event type'), '?page=notifications&action=matcher_new&route=' . $route->id . notifications_user_qs($route->user_id));
    }
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

function notifications_event_log_link($label, $user_id, $params)
{
    return '<a href="' . notifications_event_log_url($user_id, $params) . '">' . h($label) . '</a>';
}

function notifications_delivery_url($event_id, $delivery_id)
{
    return '?page=notifications&action=delivery_show&event='
        . rawurlencode((string) $event_id)
        . '&id='
        . rawurlencode((string) $delivery_id);
}

function notifications_delivery_link($event_id, $delivery_id, $label)
{
    return '<a href="' . notifications_delivery_url($event_id, $delivery_id) . '">' . h($label) . '</a>';
}

function notifications_event_url($event_id)
{
    return '?page=notifications&action=event_show&id=' . rawurlencode((string) $event_id);
}

function notifications_event_link($event_id, $label)
{
    return '<a href="' . notifications_event_url($event_id) . '">' . h($label) . '</a>';
}

function notifications_delivery_retry_form_html($event_id, $delivery_id)
{
    return '<form action="?page=notifications&action=delivery_retry&event='
        . rawurlencode((string) $event_id)
        . '&id='
        . rawurlencode((string) $delivery_id)
        . '" method="post" style="display:inline" autocomplete="off">'
        . '<input type="hidden" name="csrf_token" value="' . h(csrf_token()) . '">'
        . '<input type="submit" value="' . h(_('Retry delivery')) . '">'
        . '</form>';
}

function notifications_receiver_url($receiver_id, $user_id = null)
{
    return '?page=notifications&action=receiver_edit&id='
        . rawurlencode((string) $receiver_id)
        . notifications_user_qs($user_id);
}

function notifications_receiver_action_url($receiver_id, $action_id, $user_id = null)
{
    return '?page=notifications&action=receiver_action_edit&receiver='
        . rawurlencode((string) $receiver_id)
        . '&id='
        . rawurlencode((string) $action_id)
        . notifications_user_qs($user_id);
}

function notifications_telegram_pairing_token_url($receiver, $action)
{
    return '?page=notifications&action=receiver_action_pairing_token&receiver='
        . rawurlencode((string) $receiver->id)
        . '&id='
        . rawurlencode((string) $action->id)
        . notifications_user_qs($receiver->user_id)
        . '&t='
        . rawurlencode((string) csrf_token());
}

function notifications_telegram_pairing_link_html($action)
{
    $pairing_url = notifications_prop($action, 'telegram_pairing_url');
    if (!$pairing_url) {
        return null;
    }

    return '<a href="' . h($pairing_url) . '" target="_blank" rel="noopener">'
        . _('Open Telegram bot') . '</a>';
}

function notifications_telegram_pairing_instructions_html($action)
{
    $command = notifications_prop($action, 'telegram_pairing_command');
    if (!$command) {
        return _('Create a new pairing command and use it in a private chat with the Telegram bot.');
    }

    $items = [];
    $link = notifications_telegram_pairing_link_html($action);

    if ($link) {
        $items[] = sprintf(_('Open %s and press Start.'), $link);
    } else {
        $items[] = _('Open a private chat with the vpsAdmin Telegram bot.');
    }

    $items[] = sprintf(_('Send %s.'), '<code>' . h($command) . '</code>');
    $items[] = _('The bot will confirm whether pairing succeeded.');

    return '<ol><li>' . implode('</li><li>', $items) . '</li></ol>';
}

function notifications_sms_verification_send_url($receiver, $action)
{
    return '?page=notifications&action=receiver_action_sms_send&receiver='
        . rawurlencode((string) $receiver->id)
        . '&id='
        . rawurlencode((string) $action->id)
        . notifications_user_qs($receiver->user_id)
        . '&t='
        . rawurlencode((string) csrf_token());
}

function notifications_sms_verification_confirm_url($receiver, $action)
{
    return '?page=notifications&action=receiver_action_sms_confirm&receiver='
        . rawurlencode((string) $receiver->id)
        . '&id='
        . rawurlencode((string) $action->id)
        . notifications_user_qs($receiver->user_id);
}

function notifications_delivery_receiver_link($delivery, $user_id = null)
{
    $receiver_id = notifications_prop($delivery, 'notification_receiver_id');
    if (!$receiver_id) {
        return '-';
    }

    $label = notifications_prop($delivery, 'notification_receiver_label') ?: ('#' . $receiver_id);

    return '<a href="' . notifications_receiver_url($receiver_id, $user_id) . '">' . h($label) . '</a>';
}

function notifications_delivery_receiver_action_link($delivery, $user_id = null)
{
    $receiver_id = notifications_prop($delivery, 'notification_receiver_id');
    $action_id = notifications_prop($delivery, 'notification_receiver_action_id');
    if (!$action_id) {
        return '-';
    }

    $label = notifications_prop($delivery, 'notification_receiver_action_label') ?: ('#' . $action_id);
    if (!$receiver_id) {
        return h($label);
    }

    return '<a href="' . notifications_receiver_action_url($receiver_id, $action_id, $user_id) . '">' . h($label) . '</a>';
}

function notifications_delivery_user_link($delivery)
{
    $user_id = notifications_prop($delivery, 'event_user_id');
    if (!$user_id) {
        return '-';
    }

    $label = notifications_prop($delivery, 'event_user_login') ?: ('#' . $user_id);

    return '<a href="?page=adminm&action=edit&id=' . rawurlencode((string) $user_id) . '">' . h($label) . '</a>';
}

function notifications_delivery_vps_link($delivery)
{
    $vps_id = notifications_prop($delivery, 'event_vps_id');
    if (!$vps_id) {
        return '-';
    }

    $label = '#' . $vps_id;
    $hostname = notifications_prop($delivery, 'event_vps_hostname');
    if ($hostname) {
        $label .= ' ' . $hostname;
    }

    return '<a href="?page=adminvps&action=info&veid=' . rawurlencode((string) $vps_id) . '">' . h($label) . '</a>';
}

function notifications_delivery_state_group_states($state_group)
{
    if ($state_group === 'queue') {
        return ['prepared', 'released', 'sending'];
    } elseif ($state_group === 'log') {
        return ['sent', 'failed', 'canceled', 'skipped'];
    }

    return [];
}

function notifications_delivery_state_choices($state_group, $empty = false)
{
    $ret = $empty ? ['' => '---'] : [];

    foreach (notifications_delivery_state_group_states($state_group) as $state) {
        $ret[$state] = $state;
    }

    return $ret;
}

function notifications_delivery_state_label($delivery)
{
    $state = notifications_prop($delivery, 'state');

    if ($state === 'prepared') {
        return _('prepared (waiting for transaction release)');
    } elseif ($state === 'released') {
        $next_attempt_at = notifications_prop($delivery, 'next_attempt_at');

        return $next_attempt_at ? _('released (scheduled)') : _('released');
    } elseif ($state === 'sending') {
        return _('sending');
    }

    return $state ?: '-';
}

function notifications_delivery_result_label($delivery)
{
    $state = notifications_prop($delivery, 'state');
    if ($state === 'prepared') {
        return _('Waiting for transaction release');
    } elseif ($state === 'released') {
        return _('Waiting for dispatcher');
    } elseif ($state === 'sending') {
        return _('Delivery attempt is running');
    }

    $result = [];
    $provider_message_id = notifications_prop($delivery, 'provider_message_id');
    if ($provider_message_id) {
        $result[] = 'Message-ID ' . $provider_message_id;
    }

    $response_status_label = notifications_response_status_label(
        notifications_prop($delivery, 'action'),
        notifications_prop($delivery, 'response_status')
    );
    if ($response_status_label) {
        $result[] = $response_status_label;
    }

    $error_summary = notifications_prop($delivery, 'error_summary');
    if ($error_summary) {
        $result[] = $error_summary;
    }

    return $result ? implode(', ', $result) : '-';
}

function notifications_json_pretty($value)
{
    if ($value === null || $value === '') {
        return null;
    }

    $decoded = json_decode((string) $value, true);
    if (json_last_error() !== JSON_ERROR_NONE) {
        return (string) $value;
    }

    return json_encode(
        $decoded,
        JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE
    );
}

function notifications_pre_html($value)
{
    if ($value === null || $value === '') {
        return '-';
    }

    return '<pre style="white-space: pre-wrap; overflow-wrap: anywhere; max-width: 100%; overflow-x: auto;">' . h($value) . '</pre>';
}

function notifications_json_pre_html($value)
{
    return notifications_pre_html(notifications_json_pretty($value));
}

function notifications_decode_json_object($value)
{
    if ($value === null || $value === '') {
        return [];
    }

    $decoded = json_decode((string) $value, true);
    if (json_last_error() !== JSON_ERROR_NONE || !is_array($decoded)) {
        return [];
    }

    return $decoded;
}

function notifications_headers_html($value)
{
    $headers = notifications_decode_json_object($value);
    if (!$headers) {
        return '-';
    }

    ksort($headers);

    $html = '<table class="table-style01">'
        . '<tr><th>' . _('Header') . '</th><th>' . _('Value') . '</th></tr>';

    foreach ($headers as $name => $values) {
        $values = is_array($values) ? $values : [$values];
        $html .= '<tr><td><code>' . h($name) . '</code></td><td>'
            . implode('<br>', array_map('h', $values))
            . '</td></tr>';
    }

    return $html . '</table>';
}

function notifications_html_preview($html)
{
    if ($html === null || $html === '') {
        return '-';
    }

    return '<div class="notification-delivery-html-preview">'
        . '<div class="notification-delivery-html-frame">'
        . '<iframe sandbox="" title="' . h(_('HTML preview')) . '" srcdoc="' . h($html) . '"></iframe>'
        . '</div>'
        . '</div>';
}

function notifications_html_source_details($html)
{
    if ($html === null || $html === '') {
        return '-';
    }

    return '<details class="notification-delivery-html-source">'
        . '<summary>' . h(_('HTML source')) . '</summary>'
        . notifications_pre_html($html)
        . '</details>';
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
    $xtpl->table_add_category(_('Events'));
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
        $xtpl->table_td(notifications_event_log_link(_('Event log'), $user_id, [
            'notification_receiver_id' => $receiver->id,
        ]));
        $xtpl->table_td('<a href="?page=notifications&action=receiver_edit&id=' . $receiver->id . notifications_user_qs($user_id) . '"><img src="template/icons/vps_edit.png" title="' . _('Edit') . '"></a>');
        $xtpl->table_td(
            '<a href="' . $delete_link . '"' . notifications_confirm_onclick(_('Do you really wish to delete this notification receiver?')) . '>'
            . '<img src="template/icons/vps_delete.png" title="' . _('Delete') . '"></a>'
        );
        $xtpl->table_td('');
        $xtpl->table_tr($receiver->enabled ? false : '#A6A6A6');
    }

    if ($receivers->count() == 0) {
        $xtpl->table_td(_('No receivers configured.'), false, false, 8);
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

function notifications_receiver_action_secret_html($action)
{
    if ($action->action === 'webhook') {
        return boolean_icon($action->secret_present);
    }

    if ($action->action === 'telegram') {
        return boolean_icon($action->verified) . ' ' . ($action->verified ? _('paired') : _('pending'));
    }

    if ($action->action === 'sms') {
        return boolean_icon($action->verified) . ' ' . ($action->verified ? _('verified') : _('pending'));
    }

    return '-';
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
    } elseif ($action_type === 'webhook') {
        $xtpl->form_add_input(
            _('Webhook URL') . ':',
            'text',
            '50',
            'target_value',
            post_val('target_value', $action ? $action->target_value : ''),
            _('HTTP or HTTPS endpoint that receives the event JSON payload.')
        );

        $placeholder = $action ? _('leave empty to keep') : null;
        $xtpl->table_td(_('Secret') . ':');
        $xtpl->table_td(notifications_secret_input_html('secret', '', 40, null, $placeholder));
        $xtpl->table_td(_('Optional HMAC secret sent as X-VpsAdmin-Signature-256.'));
        $xtpl->table_tr();

        if ($action && $action->secret_present) {
            $xtpl->table_td(_('Current secret') . ':');
            $xtpl->table_td(boolean_icon(true) . ' ' . notifications_checkbox_html('clear_secret', false) . ' ' . _('clear secret'), false, true);
            $xtpl->table_tr();
        }
    } elseif ($action_type === 'telegram') {
        $xtpl->table_td(_('Pairing') . ':');
        if ($action) {
            if ($action->verified) {
                $xtpl->table_td(boolean_icon(true) . ' ' . h($action->display_target));
            } else {
                $cmd = notifications_prop($action, 'telegram_pairing_command') ?: '-';
                $pairing_link = notifications_telegram_pairing_link_html($action);
                $pairing_html = '<code>' . h($cmd) . '</code>';

                if ($pairing_link) {
                    $pairing_html = $pairing_link . '<br>' . $pairing_html;
                }

                $xtpl->table_td($pairing_html, false, true);
            }
        } else {
            $xtpl->table_td(_('created after saving'));
        }
        $xtpl->table_tr();

        if ($action && !$action->verified) {
            $xtpl->table_td(_('Instructions') . ':');
            $xtpl->table_td(notifications_telegram_pairing_instructions_html($action), false, true);
            $xtpl->table_tr();
        }

        if ($action && !$action->verified && $action->last_error) {
            $xtpl->table_td(_('Last error') . ':');
            $xtpl->table_td(h($action->last_error));
            $xtpl->table_tr();
        }

        if ($action) {
            $pairing_url = notifications_telegram_pairing_token_url($receiver, $action);

            if ($action->verified) {
                $confirm = _('Re-pairing creates a new pairing command and pauses Telegram delivery until pairing succeeds. Continue?');
                $link = '<a href="' . h($pairing_url) . '"' . notifications_confirm_onclick($confirm) . '>'
                    . _('Re-pair Telegram chat') . '</a>';
                $text = $link . '<br>' . _('Telegram delivery will be paused until the new chat is paired.');

                $xtpl->table_td(_('Re-pair') . ':');
                $xtpl->table_td($text, false, true);
            } else {
                $xtpl->table_td(_('Pairing command') . ':');
                $xtpl->table_td(
                    '<a href="' . h($pairing_url) . '">' . _('Generate new pairing command') . '</a>',
                    false,
                    true
                );
            }
            $xtpl->table_tr();
        }
    } elseif ($action_type === 'sms') {
        $xtpl->form_add_input(
            _('Phone number') . ':',
            'text',
            '30',
            'target_value',
            post_val('target_value', $action ? $action->target_value : ''),
            _('Use international E.164 format, e.g. +420123456789.')
        );

        $xtpl->table_td(_('Verification') . ':');
        if ($action) {
            $xtpl->table_td(
                boolean_icon($action->verified) . ' '
                . ($action->verified ? _('verified') : _('pending'))
            );
        } else {
            $xtpl->table_td(_('created after saving'));
        }
        $xtpl->table_tr();

        if ($action && !$action->verified) {
            $xtpl->table_td(_('Instructions') . ':');
            $xtpl->table_td(
                _('Save the phone number, send a verification SMS, then enter the code from the message.'),
                false,
                true
            );
            $xtpl->table_tr();
        }

        if ($action && !$action->verified && $action->last_error) {
            $xtpl->table_td(_('Last error') . ':');
            $xtpl->table_td(h($action->last_error));
            $xtpl->table_tr();
        }
    }

    $xtpl->form_add_checkbox(_('Enabled') . ':', 'enabled', '1', post_val('enabled', $enabled));
}

function notifications_sms_verification_controls($receiver, $action)
{
    global $xtpl;

    if ($action->action !== 'sms' || $action->verified) {
        return;
    }

    $send_url = notifications_sms_verification_send_url($receiver, $action);
    $confirm_url = notifications_sms_verification_confirm_url($receiver, $action);

    $xtpl->table_title(_('SMS verification'));
    $xtpl->table_td(_('Verification SMS') . ':');
    $xtpl->table_td(
        '<a href="' . h($send_url) . '"'
        . notifications_confirm_onclick(_('Send a verification SMS to this phone number?'))
        . '>' . _('Send verification SMS') . '</a>'
        . '<br>' . _('Delivery is limited by a short resend cooldown.'),
        false,
        true
    );
    $xtpl->table_tr();
    $xtpl->table_out();

    $xtpl->form_create($confirm_url, 'post');
    $xtpl->form_add_input(
        _('Verification code') . ':',
        'text',
        '20',
        'code',
        post_val('code'),
        _('Enter the 6-digit code from the SMS.')
    );
    $xtpl->form_out(_('Confirm code'));
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

    notifications_sms_verification_controls($receiver, $action);

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
    $xtpl->table_add_category(_('Enabled'));
    $xtpl->table_add_category(_('Status'));
    $xtpl->table_add_category(_('Events'));
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');

    $receiver_actions = notifications_api_list_to_array($receiver->action->list());

    foreach ($receiver_actions as $action) {
        $xtpl->table_td(h($action_labels[$action->action] ?? $action->action));
        $xtpl->table_td(h($action->label));
        $xtpl->table_td(notifications_receiver_action_target_html($action), false, true);
        $xtpl->table_td(boolean_icon($action->enabled));
        $xtpl->table_td(notifications_receiver_action_secret_html($action));
        $xtpl->table_td(notifications_event_log_link(_('Event log'), $receiver->user_id, [
            'notification_receiver_id' => $receiver->id,
            'notification_receiver_action_id' => $action->id,
        ]));
        $xtpl->table_td(
            '<a href="?page=notifications&action=receiver_action_edit&receiver=' . $receiver->id . '&id=' . $action->id
            . notifications_user_qs($receiver->user_id) . '"><img src="template/icons/vps_edit.png" title="' . _('Edit') . '"></a>'
        );
        $xtpl->table_td(
            '<a href="?page=notifications&action=receiver_action_delete&receiver=' . $receiver->id . '&id=' . $action->id
            . notifications_user_qs($receiver->user_id) . '&t=' . csrf_token() . '"'
            . notifications_confirm_onclick(_('Do you really wish to delete this notification receiver action?'))
            . '><img src="template/icons/vps_delete.png" title="' . _('Delete') . '"></a>'
        );
        $xtpl->table_tr();
    }

    if (count($receiver_actions) == 0) {
        $xtpl->table_td(_('No actions configured.'), false, false, 9);
        $xtpl->table_tr();
    }

    $xtpl->table_td(
        '<a href="?page=notifications&action=receiver_action_new&receiver=' . $receiver->id
        . notifications_user_qs($receiver->user_id) . '"><img src="template/icons/vps_add.png" title="' . _('Add action') . '" alt="' . _('Add action') . '"> '
        . _('Add action') . '</a>',
        false,
        true,
        9
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

function notifications_response_status_label($action, $status)
{
    if (!$status) {
        return null;
    }

    if ($action === 'email') {
        return 'SMTP ' . $status;
    } elseif ($action === 'telegram') {
        return 'Telegram API ' . $status;
    }

    return 'HTTP ' . $status;
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
            $line .= ' Message-ID ' . $provider_message_id;
        }

        $response_status_label = notifications_response_status_label($delivery->action, $response_status);
        if ($response_status_label) {
            $line .= ' ' . $response_status_label;
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

function notifications_deliveries_admin($state_group)
{
    global $xtpl, $api;

    if (!isAdmin()) {
        $xtpl->perex(_('Access forbidden'), _('Only administrators can view notification delivery queues.'));
        notifications_sidebar('events');
        return;
    }

    $action = $state_group === 'log' ? 'delivery_log' : 'delivery_queue';
    $title = $state_group === 'log' ? _('Delivery log') : _('Delivery queue');
    $params = [
        'limit' => api_get_uint('limit', 25),
        'state_group' => $state_group,
    ];

    $delivery_action = api_get('delivery_action');
    if ($delivery_action !== null) {
        $params['action'] = $delivery_action;
    }

    $delivery_state = api_get('delivery_state');
    if ($delivery_state !== null) {
        $params['state'] = $delivery_state;
    }

    $event_type = api_get('event_type');
    if ($event_type !== null) {
        $params['event_type'] = $event_type;
    }

    foreach (['event_route_id', 'notification_receiver_id', 'notification_receiver_action_id'] as $name) {
        $id = api_get_uint($name);
        if ($id !== null && $id > 0) {
            $params[$name] = $id;
        }
    }

    $user_id = api_get_uint('user');
    if ($user_id !== null && $user_id > 0) {
        $params['user'] = $user_id;
    }

    $deliveries = $api->event_delivery->list($params);
    $pagination = new \Pagination\System($deliveries);
    $input = $api->event_delivery->list->getParameters('input');

    $xtpl->title($title);
    $xtpl->table_title(_('Filters'));
    $xtpl->form_create('', 'get', 'notification-deliveries', false);
    $xtpl->form_set_hidden_fields([
        'page' => 'notifications',
        'action' => $action,
    ]);

    $xtpl->form_add_input(_('Limit') . ':', 'text', '20', 'limit', get_val('limit', '25'));
    $xtpl->form_add_input(_('User ID') . ':', 'text', '20', 'user', get_val('user'));
    $xtpl->form_add_input(_('Route ID') . ':', 'text', '20', 'event_route_id', get_val('event_route_id'));
    $xtpl->form_add_input(_('Receiver ID') . ':', 'text', '20', 'notification_receiver_id', get_val('notification_receiver_id'));
    $xtpl->form_add_input(_('Action ID') . ':', 'text', '20', 'notification_receiver_action_id', get_val('notification_receiver_action_id'));
    $xtpl->table_td(_('Event type') . ':');
    $xtpl->table_td(
        notifications_select_html(
            'event_type',
            notifications_event_type_labels(true),
            get_val('event_type')
        ),
        false,
        true
    );
    $xtpl->table_tr();

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

    $xtpl->table_td(_('State') . ':');
    $xtpl->table_td(
        notifications_select_html(
            'delivery_state',
            notifications_delivery_state_choices($state_group, true),
            get_val('delivery_state')
        ),
        false,
        true
    );
    $xtpl->table_tr();
    $xtpl->form_out(_('Show'));

    $xtpl->table_add_category(_('Delivery'));
    $xtpl->table_add_category(_('Event'));
    $xtpl->table_add_category(_('User'));
    $xtpl->table_add_category(_('VPS'));
    $xtpl->table_add_category(_('Receiver'));
    $xtpl->table_add_category(_('Receiver action'));
    $xtpl->table_add_category(_('State'));
    $xtpl->table_add_category(_('Attempts'));
    $xtpl->table_add_category(_('Released'));
    $xtpl->table_add_category(_('Last attempt'));
    $xtpl->table_add_category(_('Next retry'));
    $xtpl->table_add_category('');

    foreach ($deliveries as $delivery) {
        $event_label = '#' . $delivery->event_id;
        $event_type = notifications_prop($delivery, 'event_type');
        if ($event_type) {
            $event_label .= ' ' . $event_type;
        }
        $event_subject = notifications_prop($delivery, 'event_subject');

        $xtpl->table_td(notifications_delivery_link(
            $delivery->event_id,
            $delivery->id,
            '#' . $delivery->id . ' ' . $delivery->action
        ));
        $xtpl->table_td(
            notifications_event_link($delivery->event_id, $event_label)
            . ($event_subject ? '<br>' . h(notifications_short_value($event_subject, 120)) : ''),
            false,
            true
        );
        $xtpl->table_td(notifications_delivery_user_link($delivery), false, true);
        $xtpl->table_td(notifications_delivery_vps_link($delivery), false, true);
        $xtpl->table_td(notifications_delivery_receiver_link($delivery, notifications_prop($delivery, 'event_user_id')));
        $xtpl->table_td(notifications_delivery_receiver_action_link($delivery, notifications_prop($delivery, 'event_user_id')));
        $xtpl->table_td(h(notifications_delivery_state_label($delivery)));
        $xtpl->table_td(notifications_prop($delivery, 'attempt_count', 0), false, true);
        $xtpl->table_td(notifications_time_or_dash(notifications_prop($delivery, 'released_at')));
        $xtpl->table_td(notifications_time_or_dash(notifications_prop($delivery, 'last_attempt_at')));
        $xtpl->table_td(notifications_time_or_dash(notifications_prop($delivery, 'next_attempt_at')));
        $xtpl->table_td('<a href="' . notifications_delivery_url($delivery->event_id, $delivery->id) . '"><img src="template/icons/vps_edit.png" title="' . _('Details') . '"></a>');
        $xtpl->table_tr();
    }

    if ($deliveries->count() == 0) {
        $xtpl->table_td(_('No deliveries found.'), false, false, 12);
        $xtpl->table_tr();
    }

    $xtpl->table_pagination($pagination);
    $xtpl->table_out();

    notifications_sidebar($action);
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

    foreach (['notification_receiver_id', 'notification_receiver_action_id'] as $name) {
        $id = api_get_uint($name);
        if ($id !== null && $id > 0) {
            $params[$name] = $id;
        }
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
    $xtpl->form_add_input(_('Receiver ID') . ':', 'text', '20', 'notification_receiver_id', get_val('notification_receiver_id'));
    $xtpl->form_add_input(_('Action ID') . ':', 'text', '20', 'notification_receiver_action_id', get_val('notification_receiver_action_id'));

    if (isAdmin()) {
        $xtpl->form_add_input(_('User ID') . ':', 'text', '20', 'user', get_val('user'));
    }

    $xtpl->table_td(_('Event type') . ':');
    $xtpl->table_td(
        notifications_select_html(
            'event_type',
            notifications_event_type_labels(true),
            get_val('event_type')
        ),
        false,
        true
    );
    $xtpl->table_tr();
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
            $action_labels[] = '<a href="' . notifications_delivery_url($event->id, $delivery->id) . '"><code>' . h($label) . '</code></a>';
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
    $xtpl->table_td(notifications_json_pre_html($event->parameters_json));
    $xtpl->table_tr();
    $xtpl->table_out();

    $xtpl->table_title(_('Deliveries'));
    $xtpl->table_add_category(_('Action'));
    $xtpl->table_add_category(_('Receiver'));
    $xtpl->table_add_category(_('Receiver action'));
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

        $xtpl->table_td(notifications_delivery_link($event->id, $delivery->id, $delivery->action));
        $xtpl->table_td(notifications_delivery_receiver_link($delivery, $event->user_id));
        $xtpl->table_td(notifications_delivery_receiver_action_link($delivery, $event->user_id));
        $xtpl->table_td($target ? h($target) : '-');
        $xtpl->table_td(h($delivery->state));
        $xtpl->table_td($delivery->event_route_id ? '<a href="?page=notifications&action=route_edit&id=' . $delivery->event_route_id . notifications_user_qs($event->user_id) . '">' . $delivery->event_route_id . '</a>' : '-');
        $xtpl->table_td(notifications_prop($delivery, 'attempt_count', 0), false, true);
        $xtpl->table_td(notifications_time_or_dash(notifications_prop($delivery, 'released_at')));
        $xtpl->table_td(notifications_time_or_dash(notifications_prop($delivery, 'last_attempt_at')));
        $xtpl->table_td(notifications_time_or_dash(notifications_prop($delivery, 'next_attempt_at')));
        $result = [];
        if ($provider_message_id) {
            $result[] = 'Message-ID ' . $provider_message_id;
        }
        $response_status_label = notifications_response_status_label($delivery->action, $response_status);
        if ($response_status_label) {
            $result[] = $response_status_label;
        }
        if ($error_summary) {
            $result[] = $error_summary;
        }
        $xtpl->table_td($result ? h(implode(', ', $result)) : '-');
        $xtpl->table_tr();

        $xtpl->table_td(_('Delivery attempts') . ':', false, false, 2);
        $xtpl->table_td(notifications_delivery_attempts_html($event, $delivery), false, true, 9);
        $xtpl->table_tr();

        if ($response_body) {
            $xtpl->table_td(_('Response') . ':', false, false, 2);
            $xtpl->table_td('<pre>' . h(notifications_short_value($response_body, 1024)) . '</pre>', false, false, 9);
            $xtpl->table_tr();
        }
    }

    if (count($deliveries) == 0) {
        $xtpl->table_td(_('No deliveries recorded.'), false, false, 11);
        $xtpl->table_tr();
    }

    $xtpl->table_out();

    $xtpl->sbar_add(_('Back to event log'), '?page=notifications&action=events');
    notifications_sidebar('events', $event->user_id);
}

function notifications_delivery_show($event_id, $delivery_id)
{
    global $xtpl, $api;

    $event = $api->event->show($event_id, ['meta' => ['includes' => 'user,vps']]);
    $delivery = $event->delivery($delivery_id)->show();
    $target = notifications_prop($delivery, 'target_label')
        ?: notifications_prop($delivery, 'target_value')
        ?: notifications_prop($delivery, 'target_kind');

    $xtpl->title(
        _('Event delivery') . ' #' . $delivery->id . ': '
        . h($delivery->action) . ' / ' . h($delivery->state)
    );

    $xtpl->table_title(_('Delivery'));

    $xtpl->table_td(_('Event') . ':');
    $xtpl->table_td(
        '<a href="?page=notifications&action=event_show&id=' . $event->id . '">'
        . '#' . $event->id . ' ' . h($event->subject) . '</a>'
    );
    $xtpl->table_tr();

    $xtpl->table_td(_('Action') . ':');
    $xtpl->table_td(h($delivery->action));
    $xtpl->table_tr();

    $template_name = notifications_prop($delivery, 'template_name');
    if (isAdmin() && $delivery->action === 'email' && $template_name) {
        $xtpl->table_td(_('Template') . ':');
        $xtpl->table_td('<code>' . h($template_name) . '</code>');
        $xtpl->table_tr();
    }

    $xtpl->table_td(_('State') . ':');
    $xtpl->table_td(h($delivery->state));
    $xtpl->table_tr();

    $xtpl->table_td(_('Target') . ':');
    $xtpl->table_td($target ? h($target) : '-');
    $xtpl->table_tr();

    $xtpl->table_td(_('Receiver') . ':');
    $xtpl->table_td(notifications_delivery_receiver_link($delivery, $event->user_id));
    $xtpl->table_tr();

    $xtpl->table_td(_('Receiver action') . ':');
    $xtpl->table_td(notifications_delivery_receiver_action_link($delivery, $event->user_id));
    $xtpl->table_tr();

    $xtpl->table_td(_('Route') . ':');
    $xtpl->table_td(
        $delivery->event_route_id
            ? '<a href="?page=notifications&action=route_edit&id=' . $delivery->event_route_id
                . notifications_user_qs($event->user_id) . '">' . $delivery->event_route_id . '</a>'
            : '-'
    );
    $xtpl->table_tr();

    $xtpl->table_td(_('Released') . ':');
    $xtpl->table_td(notifications_time_or_dash(notifications_prop($delivery, 'released_at')));
    $xtpl->table_tr();

    $xtpl->table_td(_('Last attempt') . ':');
    $xtpl->table_td(notifications_time_or_dash(notifications_prop($delivery, 'last_attempt_at')));
    $xtpl->table_tr();

    $xtpl->table_td(_('Next retry') . ':');
    $xtpl->table_td(notifications_time_or_dash(notifications_prop($delivery, 'next_attempt_at')));
    $xtpl->table_tr();

    $xtpl->table_td(_('Attempts') . ':');
    $xtpl->table_td(h(notifications_prop($delivery, 'attempt_count', 0)));
    $xtpl->table_tr();

    $provider_message_id = notifications_prop($delivery, 'provider_message_id');
    if ($provider_message_id) {
        $xtpl->table_td(_('Message ID') . ':');
        $xtpl->table_td(h($provider_message_id));
        $xtpl->table_tr();
    }

    $response_status = notifications_prop($delivery, 'response_status');
    if ($response_status) {
        $xtpl->table_td(_('Response status') . ':');
        $xtpl->table_td(h(notifications_response_status_label($delivery->action, $response_status)));
        $xtpl->table_tr();
    }

    $error_summary = notifications_prop($delivery, 'error_summary');
    if ($error_summary) {
        $xtpl->table_td(_('Error') . ':');
        $xtpl->table_td(h($error_summary));
        $xtpl->table_tr();
    }

    if (notifications_prop($delivery, 'state') === 'failed') {
        $xtpl->table_td(_('Retry') . ':');
        $xtpl->table_td(notifications_delivery_retry_form_html($event->id, $delivery->id));
        $xtpl->table_tr();
    }

    $xtpl->table_out();

    if ($delivery->action === 'email') {
        notifications_delivery_email_show($delivery);
    } elseif ($delivery->action === 'telegram') {
        notifications_delivery_telegram_show($delivery);
    } elseif ($delivery->action === 'sms') {
        notifications_delivery_sms_show($delivery);
    } elseif ($delivery->action === 'webhook') {
        notifications_delivery_webhook_show($delivery);
    }

    notifications_delivery_attempts_show($event, $delivery);

    $xtpl->sbar_add(_('Back to event'), '?page=notifications&action=event_show&id=' . $event->id);
    $xtpl->sbar_add(_('Back to event log'), '?page=notifications&action=events');
    notifications_sidebar('events', $event->user_id);
}

function notifications_delivery_email_show($delivery)
{
    global $xtpl;

    $xtpl->table_title(_('E-mail'));
    $shown = false;

    foreach ([
        _('To') => 'mail_to',
        _('Cc') => 'mail_cc',
        _('From') => 'mail_from',
        _('Reply-To') => 'mail_reply_to',
        _('Return-Path') => 'mail_return_path',
        _('Message ID') => 'mail_message_id',
        _('Subject') => 'mail_subject',
    ] as $label => $field) {
        $value = notifications_prop($delivery, $field);
        if ($value === null || $value === '') {
            continue;
        }

        $xtpl->table_td($label . ':');
        $xtpl->table_td(h($value));
        $xtpl->table_tr();
        $shown = true;
    }

    $plain = notifications_prop($delivery, 'mail_text_plain');
    if ($plain) {
        $xtpl->table_td(_('Plain text') . ':');
        $xtpl->table_td(notifications_pre_html($plain));
        $xtpl->table_tr();
        $shown = true;
    }

    $html = notifications_prop($delivery, 'mail_text_html');
    if (!$shown && !$html) {
        $xtpl->table_td(_('No e-mail snapshot recorded for this delivery.'), false, false, 2);
        $xtpl->table_tr();
    }

    $xtpl->table_out();

    if ($html) {
        $xtpl->table_title(_('HTML preview'));
        $xtpl->table_td(notifications_html_preview($html), false, false, 1, 1, 'top');
        $xtpl->table_tr();
        $xtpl->table_td(notifications_html_source_details($html), false, false, 1, 1, 'top');
        $xtpl->table_tr();
        $xtpl->table_out('notification-delivery-html');
    }
}

function notifications_delivery_telegram_show($delivery)
{
    global $xtpl;

    $xtpl->table_title(_('Telegram'));

    $payload = json_decode(notifications_prop($delivery, 'payload') ?: '{}', true);
    if (!is_array($payload)) {
        $payload = [];
    }

    $xtpl->table_td(_('Chat') . ':');
    $xtpl->table_td(h($payload['chat_id'] ?? notifications_prop($delivery, 'target_value', '-')));
    $xtpl->table_tr();

    $xtpl->table_td(_('Message') . ':');
    $xtpl->table_td(notifications_pre_html($payload['text'] ?? ''));
    $xtpl->table_tr();

    $response_body = notifications_prop($delivery, 'response_body');
    if ($response_body) {
        $xtpl->table_td(_('Response') . ':');
        $xtpl->table_td(notifications_json_pre_html($response_body));
        $xtpl->table_tr();
    }

    $xtpl->table_out();
}

function notifications_delivery_sms_show($delivery)
{
    global $xtpl;

    $xtpl->table_title(_('SMS'));

    $payload = json_decode(notifications_prop($delivery, 'payload') ?: '{}', true);
    if (!is_array($payload)) {
        $payload = [];
    }

    $xtpl->table_td(_('Phone number') . ':');
    $xtpl->table_td(h($payload['to'] ?? notifications_prop($delivery, 'target_value', '-')));
    $xtpl->table_tr();

    $xtpl->table_td(_('Message') . ':');
    $xtpl->table_td(notifications_pre_html($payload['text'] ?? ''));
    $xtpl->table_tr();

    $response_body = notifications_prop($delivery, 'response_body');
    if ($response_body) {
        $xtpl->table_td(_('Gateway callback') . ':');
        $xtpl->table_td(notifications_json_pre_html($response_body));
        $xtpl->table_tr();
    }

    $xtpl->table_out();
}

function notifications_delivery_webhook_show($delivery)
{
    global $xtpl;

    $xtpl->table_title(_('Webhook'));

    $xtpl->table_td(_('Request payload') . ':');
    $xtpl->table_td(notifications_json_pre_html(notifications_prop($delivery, 'payload')));
    $xtpl->table_tr();

    $response_status = notifications_prop($delivery, 'response_status');
    if ($response_status) {
        $xtpl->table_td(_('Response status') . ':');
        $xtpl->table_td(h(notifications_response_status_label($delivery->action, $response_status)));
        $xtpl->table_tr();
    }

    $xtpl->table_td(_('Response headers') . ':');
    $xtpl->table_td(notifications_headers_html(notifications_prop($delivery, 'response_headers_json')));
    $xtpl->table_tr();

    $response_body = notifications_prop($delivery, 'response_body');
    $xtpl->table_td(_('Response body') . ':');
    $xtpl->table_td(notifications_pre_html($response_body));
    $xtpl->table_tr();

    $xtpl->table_out();
}

function notifications_delivery_attempts_show($event, $delivery)
{
    global $xtpl;

    $attempts = notifications_api_list_to_array($event->delivery($delivery->id)->attempt->list());

    $xtpl->table_title(_('Delivery attempts'));
    $xtpl->table_add_category(_('Attempt'));
    $xtpl->table_add_category(_('State'));
    $xtpl->table_add_category(_('Started'));
    $xtpl->table_add_category(_('Finished'));
    $xtpl->table_add_category(_('Result'));

    foreach ($attempts as $attempt) {
        $result = [];
        $provider_message_id = notifications_prop($attempt, 'provider_message_id');
        $response_status = notifications_prop($attempt, 'response_status');
        $error_summary = notifications_prop($attempt, 'error_summary');

        if ($provider_message_id) {
            $result[] = 'Message-ID ' . $provider_message_id;
        }

        $response_status_label = notifications_response_status_label($delivery->action, $response_status);
        if ($response_status_label) {
            $result[] = $response_status_label;
        }

        if ($error_summary) {
            $result[] = $error_summary;
        }

        $xtpl->table_td('#' . h($attempt->attempt_number), false, true);
        $xtpl->table_td(h($attempt->state));
        $xtpl->table_td(notifications_time_or_dash($attempt->started_at));
        $xtpl->table_td(notifications_time_or_dash($attempt->finished_at));
        $xtpl->table_td($result ? h(implode(', ', $result)) : '-');
        $xtpl->table_tr();

        $response_headers = notifications_prop($attempt, 'response_headers_json');
        if ($response_headers && notifications_decode_json_object($response_headers)) {
            $xtpl->table_td(_('Response headers') . ':', false, false, 2);
            $xtpl->table_td(notifications_headers_html($response_headers), false, true, 3);
            $xtpl->table_tr();
        }

        $response_body = notifications_prop($attempt, 'response_body');
        if ($response_body) {
            $xtpl->table_td(_('Response body') . ':', false, false, 2);
            $xtpl->table_td(notifications_pre_html($response_body), false, false, 3);
            $xtpl->table_tr();
        }
    }

    if (count($attempts) == 0) {
        $xtpl->table_td(_('No attempts recorded.'), false, false, 5);
        $xtpl->table_tr();
    }

    $xtpl->table_out();
}

function notifications_event_types($user_id = null)
{
    global $xtpl;

    $xtpl->title(_('Event types'));
    $groups = [];

    foreach (notifications_event_types_cached() as $type) {
        $groups[$type->category ?: _('Other')][] = $type;
    }

    ksort($groups);
    $html = '<div class="notification-event-types">';

    foreach ($groups as $category => $types) {
        $html .= '<details style="margin-bottom:1em;">'
            . '<summary><strong>' . h($category) . '</strong> (' . count($types) . ')</summary>'
            . '<table class="table-style01" style="margin-top:0.5em;">'
            . '<tr><th>' . _('Name') . '</th><th>' . _('Severity') . '</th><th>' . _('Default route') . '</th><th>' . _('Matchable fields') . '</th></tr>';

        foreach ($types as $type) {
            $fields = notifications_event_type_fields_from_type($type);
            $fields_html = '-';

            if ($fields) {
                $fields_html = '<table class="table-style01">'
                    . '<tr><th>' . _('Field') . '</th><th>' . _('Label') . '</th></tr>';

                foreach ($fields as $name => $label) {
                    $fields_html .= '<tr><td><code>' . h($name) . '</code></td><td>' . h($label) . '</td></tr>';
                }

                $fields_html .= '</table>';
            }

            $html .= '<tr>'
                . '<td><code>' . h($type->name) . '</code><br>' . h($type->label) . '</td>'
                . '<td>' . h($type->severity)
                . (notifications_prop($type, 'severity_description') ? '<br><small>' . h($type->severity_description) . '</small>' : '')
                . '</td>'
                . '<td>' . (notifications_prop($type, 'default_routed', true) ? h(_('yes')) : h(_('opt-in'))) . '</td>'
                . '<td>' . $fields_html . '</td>'
                . '</tr>';
        }

        $html .= '</table></details>';
    }

    $html .= '</div>';

    $xtpl->table_title(_('Event types'));
    $xtpl->table_td($html);
    $xtpl->table_tr();
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

    $xtpl->form_add_select(
        _('Event type') . ':',
        'event_type',
        notifications_event_type_labels(true),
        post_val('event_type', 'user.test_notification')
    );
    api_param_to_form('subject', $input->subject, post_val('subject', _('Test notification')));
    api_param_to_form('summary', $input->summary, post_val('summary', _('This event was created from notification settings.')));
    $xtpl->form_add_textarea(_('Parameters') . ':', 70, 8, 'parameters_json', post_val('parameters_json', "{\n  \"note\": \"testing notification routing\"\n}"));
    $xtpl->form_out(_('Create event'));

    notifications_sidebar('test', $user_id);
}
