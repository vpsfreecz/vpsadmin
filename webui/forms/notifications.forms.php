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
    $xtpl->sbar_add(_('Targets'), '?page=notifications&action=targets' . $user_qs);
    $xtpl->sbar_add(_('Limits'), '?page=notifications&action=limits' . $user_qs);
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
    if (is_array($object)) {
        return array_key_exists($name, $object) && $object[$name] !== null
            ? $object[$name]
            : $default;
    }

    if (!is_object($object)) {
        return $default;
    }

    if (method_exists($object, 'attributes')) {
        $attrs = $object->attributes();

        if (is_array($attrs) && array_key_exists($name, $attrs)) {
            return $attrs[$name] !== null ? $attrs[$name] : $default;
        }
    }

    if (property_exists($object, $name)) {
        return $object->{$name} !== null ? $object->{$name} : $default;
    }

    if (method_exists($object, '__get')) {
        $value = $object->{$name};

        return $value !== null ? $value : $default;
    }

    return $default;
}

function notifications_event_type_fields_from_type($type)
{
    $ret = [];

    foreach (notifications_event_type_field_metadata_from_type($type) as $name => $field) {
        $ret[$name] = isset($field['description']) && $field['description']
            ? $field['description']
            : $name;
    }

    return $ret;
}

function notifications_event_type_field_metadata_from_type($type)
{
    $raw_fields = notifications_prop($type, 'fields');

    if ($raw_fields === null) {
        return [];
    }

    $fields = notifications_event_type_metadata_array($raw_fields, true);

    $ret = [];

    foreach ($fields as $name => $field) {
        $field = notifications_event_type_metadata_array($field);
        if (!$field) {
            continue;
        }

        if (!isset($field['name'])) {
            $field['name'] = is_string($name) ? $name : null;
        }

        if (!$field['name']) {
            continue;
        }

        if (isset($field['operators'])) {
            $field['operators'] = array_values(notifications_event_type_metadata_array($field['operators'], true));
        }

        if (isset($field['choices'])) {
            $field['choices'] = notifications_event_type_metadata_array($field['choices'], true);
        }

        $ret[$field['name']] = $field;
    }

    return $ret;
}

function notifications_event_type_metadata_array($value, $decode_json = false)
{
    if ($decode_json && is_string($value)) {
        $decoded = json_decode($value, true);

        if (json_last_error() === JSON_ERROR_NONE) {
            $value = $decoded;
        }
    }

    if ($value instanceof Traversable) {
        $value = iterator_to_array($value);
    }

    if (is_object($value)) {
        $value = get_object_vars($value);
    }

    return is_array($value) ? $value : [];
}

function notifications_event_type_field_types_from_type($type)
{
    $ret = [];

    foreach (notifications_event_type_field_metadata_from_type($type) as $name => $field) {
        if (isset($field['type'])) {
            $ret[$name] = $field['type'];
        }
    }

    return $ret;
}

function notifications_event_type_field_operators_from_type($type)
{
    $ret = [];

    foreach (notifications_event_type_field_metadata_from_type($type) as $name => $field) {
        if (isset($field['operators']) && is_array($field['operators'])) {
            $ret[$name] = array_values($field['operators']);
        }
    }

    return $ret;
}

function notifications_api_list_to_array($list)
{
    $wrapped_keys = [
        'event_types',
        'event_routes',
        'event_route_matchers',
        'notification_receivers',
        'notification_targets',
        'notification_receiver_targets',
        'notification_receiver_actions',
        'events',
        'event_deliveries',
        'event_delivery_attempts',
        'event_route_matches',
        'notification_rate_limits',
        'receivers',
        'targets',
        'limits',
        'actions',
        'matchers',
        'deliveries',
        'attempts',
        'route_matches',
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
    if (!$event_type || $event_type === '__any__') {
        return notifications_matcher_field_select_options($fallback_fields);
    }

    foreach (notifications_event_types_cached() as $type) {
        if ($type->name !== $event_type) {
            continue;
        }

        $fields = notifications_event_type_fields_from_type($type);

        return notifications_matcher_field_select_options($fields ?: $fallback_fields);
    }

    return notifications_matcher_field_select_options($fallback_fields);
}

function notifications_matcher_field_select_options($fields)
{
    $ret = [];

    foreach ($fields as $name => $description) {
        $description = trim((string) $description);
        $ret[$name] = $description && $description !== (string) $name
            ? $name . ' - ' . $description
            : (string) $name;
    }

    return $ret;
}

function notifications_event_field_types($event_type = null)
{
    $ret = [];

    foreach (notifications_event_types_cached() as $type) {
        if ($event_type && $event_type !== '__any__' && $type->name !== $event_type) {
            continue;
        }

        $ret += notifications_event_type_field_types_from_type($type);
    }

    return $ret;
}

function notifications_event_field_metadata($event_type = null)
{
    $ret = [];

    foreach (notifications_event_types_cached() as $type) {
        if ($event_type && $event_type !== '__any__' && $type->name !== $event_type) {
            continue;
        }

        $ret += notifications_event_type_field_metadata_from_type($type);
    }

    return $ret;
}

function notifications_event_field_operators($event_type = null)
{
    $ret = [];

    foreach (notifications_event_types_cached() as $type) {
        if ($event_type && $event_type !== '__any__' && $type->name !== $event_type) {
            continue;
        }

        $ret += notifications_event_type_field_operators_from_type($type);
    }

    return $ret;
}

function notifications_event_type_labels($empty = true, $any = false)
{
    $ret = [];

    if ($empty) {
        $ret[''] = '---';
    }

    if ($any) {
        $ret['__any__'] = _('Any event type');
    }

    foreach (notifications_event_types_cached() as $type) {
        $name = notifications_prop($type, 'name');
        $ret[$name] = notifications_prop($type, 'label', $name) ?: $name;
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
        'contains' => _('contains list item'),
        'not_contains' => _('does not contain list item'),
    ];
    $ret = [];

    foreach ($operators as $operator => $label) {
        $ret[$operator] = isset($descriptions[$operator])
            ? $label . ' (' . $descriptions[$operator] . ')'
            : $label;
    }

    return $ret;
}

function notifications_matcher_operator_reference_html()
{
    $rows = [
        'string' => [
            _('text value'),
            ['==', '!=', '=~', '!~', '=*', '!*'],
            _('exact text, regular expression, or glob pattern'),
        ],
        'integer' => [
            _('whole number'),
            ['==', '!=', '>', '>=', '<', '<='],
            _('parsed as an integer, for example 123'),
        ],
        'number' => [
            _('number'),
            ['==', '!=', '>', '>=', '<', '<='],
            _('parsed as a decimal number, for example 3.14'),
        ],
        'boolean' => [
            _('true/false'),
            ['==', '!='],
            _('normalized from true/false, yes/no, on/off, or 1/0'),
        ],
        'datetime' => [
            _('date and time'),
            ['==', '!=', '>', '>=', '<', '<='],
            _('parsed as ISO 8601 time, for example 2026-07-01T12:00:00Z'),
        ],
        'string_list' => [
            _('list of text values'),
            ['contains', 'not_contains'],
            _('one text list item to look for'),
        ],
        'integer_list' => [
            _('list of whole numbers'),
            ['contains', 'not_contains'],
            _('one list item parsed as an integer'),
        ],
    ];

    $html = '<table class="table-style01">'
        . '<tr><th>' . _('Type') . '</th><th>' . _('Meaning') . '</th><th>' . _('Operators') . '</th><th>' . _('Value') . '</th></tr>';

    foreach ($rows as $type => $row) {
        [$meaning, $operators, $value] = $row;
        $html .= '<tr>'
            . '<td><code>' . h($type) . '</code></td>'
            . '<td>' . h($meaning) . '</td>'
            . '<td>' . notifications_operator_list_html($operators) . '</td>'
            . '<td>' . h($value) . '</td>'
            . '</tr>';
    }

    return $html . '</table>';
}

function notifications_operator_list_html($operators)
{
    if (!$operators || !is_array($operators)) {
        return '-';
    }

    $ret = [];

    foreach ($operators as $operator) {
        $ret[] = '<code>' . h($operator) . '</code>';
    }

    return implode(' ', $ret);
}

function notifications_matcher_operators_for_field($field, $operators, $field_operators)
{
    $allowed = $field_operators[$field] ?? array_keys($operators);
    $ret = [];

    foreach ($allowed as $operator) {
        if (isset($operators[$operator])) {
            $ret[$operator] = $operators[$operator];
        }
    }

    return $ret ?: $operators;
}

function notifications_field_example_html($field)
{
    if (!isset($field['example'])) {
        return '-';
    }

    $example = $field['example'];

    if (is_array($example) || is_object($example)) {
        $example = json_encode($example, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    } elseif (is_bool($example)) {
        $example = $example ? 'true' : 'false';
    }

    return '<code>' . h((string) $example) . '</code>';
}

function notifications_event_type_anchor($name)
{
    return 'event-type-' . preg_replace('/[^a-zA-Z0-9_-]+/', '-', $name);
}

function notifications_matcher_value_html($name, $value, $field, $field_types)
{
    if (($field_types[$field] ?? null) === 'boolean') {
        return notifications_select_html($name, [
            'true' => _('true'),
            'false' => _('false'),
        ], $value === 'false' || $value === false || $value === 0 || $value === '0' ? 'false' : 'true');
    }

    return notifications_text_input_html($name, $value, 35);
}

function notifications_matcher_value_toggle_script($field_types, $field_operators, $operator_labels)
{
    global $xtpl;

    $xtpl->assign(
        'AJAX_SCRIPT',
        ($xtpl->vars['AJAX_SCRIPT'] ?? '')
        . '<script type="text/javascript">'
        . '$(function(){'
        . 'var fieldTypes=' . json_encode($field_types, JSON_HEX_TAG | JSON_HEX_APOS | JSON_HEX_QUOT | JSON_HEX_AMP) . ';'
        . 'var fieldOperators=' . json_encode($field_operators, JSON_HEX_TAG | JSON_HEX_APOS | JSON_HEX_QUOT | JSON_HEX_AMP) . ';'
        . 'var operatorLabels=' . json_encode($operator_labels, JSON_HEX_TAG | JSON_HEX_APOS | JSON_HEX_QUOT | JSON_HEX_AMP) . ';'
        . 'var field=$("select[name=field]");'
        . 'var operator=$("select[name=operator]");'
        . 'var container=$("#notification-matcher-value");'
        . 'function booleanValue(value){'
        . 'value=String(value||"").toLowerCase();'
        . 'return $.inArray(value,["false","0","no","off"])>=0?"false":"true";'
        . '}'
        . 'function renderMatcherOperator(){'
        . 'var current=operator.val();'
        . 'var allowed=fieldOperators[field.val()]||Object.keys(operatorLabels);'
        . 'operator.empty();'
        . '$.each(allowed,function(_,op){'
        . 'if(operatorLabels[op]){operator.append($("<option>").attr("value",op).text(operatorLabels[op]));}'
        . '});'
        . 'if($.inArray(current,allowed)>=0){operator.val(current);}'
        . 'else if(allowed.length){operator.val(allowed[0]);}'
        . '}'
        . 'function renderMatcherValue(){'
        . 'var current=container.find("[name=value]").val()||"";'
        . 'var bool=fieldTypes[field.val()]==="boolean";'
        . 'var input=bool?$("<select>").attr({name:"value",id:"input"}):$("<input>").attr({type:"text",name:"value",id:"input",size:35});'
        . 'if(bool){'
        . 'current=booleanValue(current);'
        . 'input.append($("<option>").attr("value","true").text("true"));'
        . 'input.append($("<option>").attr("value","false").text("false"));'
        . 'input.val(current);'
        . '}else{'
        . 'input.val(current);'
        . '}'
        . 'container.empty().append(input);'
        . '}'
        . 'field.on("change",function(){renderMatcherOperator();renderMatcherValue();});'
        . 'renderMatcherOperator();'
        . '});'
        . '</script>'
    );
}

function notifications_label($labels, $value)
{
    return $labels[$value] ?? $value;
}

function notifications_subject_scope_options($desc = null)
{
    $labels = [
        'self' => _('Own events'),
        'visible' => _('Visible events'),
    ];
    $choices = $desc ? notifications_param_choices($desc) : array_combine(array_keys($labels), array_keys($labels));
    $ret = [];

    foreach ($choices as $value => $label) {
        $ret[$value] = $labels[$value] ?? $label;
    }

    return $ret;
}

function notifications_subject_scope_label($value)
{
    if ($value === null || $value === '') {
        return '-';
    }

    return notifications_subject_scope_options()[$value] ?? $value;
}

function notifications_test_subject_scope_options($desc = null)
{
    $labels = [
        'self' => _('Own routes'),
        'visible' => _('Admin visible routes'),
        'system' => _('Admin system routes'),
    ];
    $choices = $desc ? notifications_param_choices($desc) : array_combine(array_keys($labels), array_keys($labels));
    $ret = [];

    foreach ($choices as $value => $label) {
        $ret[$value] = $labels[$value] ?? $label;
    }

    return $ret;
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
    $subject_scope = api_post('subject_scope');
    if ($subject_scope !== null && $subject_scope !== '') {
        $params['subject_scope'] = $subject_scope;
    }

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

function notifications_delivery_method_enabled_map($user_id)
{
    global $api;

    static $cache = [];

    if (!array_key_exists($user_id, $cache)) {
        $cache[$user_id] = [];

        foreach ($api->user($user_id)->notification_delivery_method->list() as $method) {
            $cache[$user_id][$method->delivery_method] = (bool) $method->enabled;
        }
    }

    return $cache[$user_id];
}

function notifications_target_all_type_labels()
{
    global $api;

    $input = $api->notification_target->create->getParameters('input');

    return notifications_param_choices($input->action);
}

function notifications_target_type_labels($user_id)
{
    $labels = notifications_target_all_type_labels();
    if (isAdmin()) {
        return $labels;
    }

    $enabled_methods = notifications_delivery_method_enabled_map($user_id);
    $ret = [];

    foreach ($labels as $action => $label) {
        if ($enabled_methods[$action] ?? true) {
            $ret[$action] = $label;
        }
    }

    return $ret;
}

function notifications_target_type_label($action_type)
{
    $labels = notifications_target_all_type_labels();

    return $labels[$action_type] ?? $action_type;
}

function notifications_target_type_from_request($user_id)
{
    $labels = notifications_target_type_labels($user_id);
    $action_type = api_get('type');

    if ($action_type === null) {
        $action_type = api_post('action_type');
    }

    return isset($labels[$action_type]) ? $action_type : null;
}

function notifications_target_params($action_type, $create = false)
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

function notifications_receiver_target_params($create = false)
{
    $params = [];

    if ($create) {
        $params['notification_target_id'] = api_post_uint('notification_target_id');
    }

    return $params;
}

function notifications_target_params_from_row($row)
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
    $xtpl->table_add_category(_('Scope'));
    $xtpl->table_add_category(_('Receiver'));
    $xtpl->table_add_category(_('Matchers'));
    $xtpl->table_add_category(_('Hits'));
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
        $xtpl->table_td(h(notifications_subject_scope_label($route->subject_scope)));
        $xtpl->table_td(notifications_route_receiver_html($route, $receiver_labels));
        $xtpl->table_td($route->matcher_summary ? h($route->matcher_summary) : '<code>*</code>');
        $xtpl->table_td(
            '<a href="?page=notifications&action=events&user=' . $user_id
            . '&event_route_id=' . $route->id . '">' . $route->hit_count . '</a>',
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
        $xtpl->table_td(_('No routes configured.'), false, false, 13);
        $xtpl->table_tr(false, 'nodrag nodrop', 'nodrag nodrop');
    }

    $xtpl->table_td(notifications_route_add_link($user_id, null, _('Add route')), false, true, 13);
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
    $subject_scope_options = notifications_subject_scope_options($input->subject_scope);
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
    $xtpl->form_add_select(_('Scope') . ':', 'subject_scope', $subject_scope_options, post_val('subject_scope', 'self'));
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
    $xtpl->table_add_category(_('Scope'));
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
        $xtpl->table_td(h(notifications_subject_scope_label($child->subject_scope)));
        $xtpl->table_td(notifications_route_receiver_html($child, $receiver_labels));
        $xtpl->table_td($child->matcher_summary ? h($child->matcher_summary) : '<code>*</code>');
        $xtpl->table_td(boolean_icon($child->enabled));
        $xtpl->table_td(boolean_icon($child->continue));
        $xtpl->table_td(notifications_route_add_link($route->user_id, $child->id), false, true);
        $xtpl->table_td('<a href="?page=notifications&action=route_edit&id=' . $child->id . notifications_user_qs($route->user_id) . '"><img src="template/icons/vps_edit.png" title="' . _('Edit') . '"></a>');
        $xtpl->table_tr($child->enabled ? false : '#A6A6A6');
    }

    if (!$children) {
        $xtpl->table_td(_('No subroutes configured.'), false, false, 9);
        $xtpl->table_tr();
    }

    $xtpl->table_td(notifications_route_add_link($route->user_id, $route->id, _('Add subroute')), false, true, 9);
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
    $subject_scope_options = notifications_subject_scope_options($input->subject_scope);
    $operators = notifications_param_choices($matcher_input->operator);
    $field_types = notifications_event_field_types();
    $field_operators = notifications_event_field_operators();
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
    $xtpl->form_add_select(_('Scope') . ':', 'subject_scope', $subject_scope_options, post_val('subject_scope', $route->subject_scope));
    $xtpl->form_add_select(_('Receiver') . ':', 'notification_receiver_id', $receiver_options, post_val('notification_receiver_id', $route->notification_receiver_id));
    api_param_to_form('enabled', $input->enabled, post_val('enabled', $route->enabled));
    api_param_to_form('continue', $input->continue, post_val('continue', $route->continue));
    $xtpl->form_out(_('Save'));
    notifications_clear_table_form();

    $xtpl->table_title(_('Route lifecycle'));
    $xtpl->table_td(_('Single-use route'));
    $xtpl->table_td(boolean_icon(notifications_prop($route, 'single_use', false)));
    $xtpl->table_tr();
    $xtpl->table_td(_('Spent at'));
    $xtpl->table_td($route->spent_at ? tolocaltz($route->spent_at) : '-');
    $xtpl->table_tr();
    $xtpl->table_td(_('Expires at'));
    $xtpl->table_td($route->expires_at ? tolocaltz($route->expires_at) : '-');
    $xtpl->table_tr();
    $xtpl->table_td(_('Hits'));
    $xtpl->table_td(
        '<a href="?page=notifications&action=events' . notifications_user_qs($route->user_id)
        . '&event_route_id=' . $route->id . '">' . notifications_prop($route, 'hit_count', 0) . '</a>'
    );
    $xtpl->table_tr();
    $xtpl->table_out();

    notifications_route_subroutes($route);

    $xtpl->table_title(_('Matchers'));
    $xtpl->form_create('?page=notifications&action=matcher_save&route=' . $route->id . notifications_user_qs($route->user_id), 'post');
    $xtpl->table_add_category(_('Field'));
    $xtpl->table_add_category(_('Operator'));
    $xtpl->table_add_category(_('Value'));
    $xtpl->table_add_category('');

    foreach ($matchers as $matcher) {
        $prefix = 'matchers[' . $matcher->id . ']';
        $matcher_operators = notifications_matcher_operators_for_field($matcher->field, $operators, $field_operators);
        $xtpl->table_td('<code>' . h($matcher->field) . '</code>', false, true);
        $xtpl->table_td(notifications_select_html($prefix . '[operator]', $matcher_operators, $matcher->operator));
        $xtpl->table_td(notifications_matcher_value_html($prefix . '[value]', $matcher->value, $matcher->field, $field_types));
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
        $event_types = notifications_event_type_labels(true, true);

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
    $field_types = notifications_event_field_types($selected_event_type);
    $field_operators = notifications_event_field_operators($selected_event_type);
    $field = post_val('field', array_key_first($fields) ?: 'event_type');
    $field_operator_choices = notifications_matcher_operators_for_field($field, $operators, $field_operators);
    $operator = post_val('operator', array_key_first($field_operator_choices) ?: '==');
    $operator_labels = notifications_matcher_operator_descriptions($operators);
    notifications_matcher_value_toggle_script($field_types, $field_operators, $operator_labels);
    $url = '?page=notifications&action=matcher_new&route=' . $route->id
        . ($route_event_type ? '' : '&event_type=' . urlencode($selected_event_type))
        . notifications_user_qs($route->user_id);

    $xtpl->table_title(_('Add matcher'));
    $xtpl->form_create($url, 'post');

    $xtpl->table_td(_('Route') . ':');
    $xtpl->table_td('<a href="?page=notifications&action=route_edit&id=' . $route->id . notifications_user_qs($route->user_id) . '">#' . $route->id . '</a>');
    $xtpl->table_tr();

    $xtpl->table_td(_('Event type') . ':');
    $xtpl->table_td($selected_event_type === '__any__' ? h(_('Any event type')) : '<code>' . h($selected_event_type) . '</code>');
    $xtpl->table_tr();

    $xtpl->form_add_select(_('Field') . ':', 'field', $fields, $field);
    $xtpl->form_add_select(
        _('Operator') . ':',
        'operator',
        notifications_matcher_operator_descriptions($field_operator_choices),
        $operator
    );
    $xtpl->table_td(_('Value') . ':');
    $xtpl->table_td(
        '<span id="notification-matcher-value">'
        . notifications_matcher_value_html('value', post_val('value'), $field, $field_types)
        . '</span>',
        false,
        false
    );
    $xtpl->table_tr();
    $xtpl->form_out(_('Add'));

    $xtpl->table_title(_('Matcher operator reference'));
    $xtpl->table_td(notifications_matcher_operator_reference_html(), false, false);
    $xtpl->table_tr('#fff', false, 'nohover');
    $xtpl->table_out();

    $xtpl->sbar_add(_('Back to route'), '?page=notifications&action=route_edit&id=' . $route->id . notifications_user_qs($route->user_id));
    if (!$route_event_type) {
        $xtpl->sbar_add(_('Choose different event type'), '?page=notifications&action=matcher_new&route=' . $route->id . notifications_user_qs($route->user_id));
    }
    notifications_sidebar('routes', $route->user_id);
}

function notifications_receiver_targets_summary_html($receiver)
{
    if ($receiver->mute) {
        return '<code>' . _('muted') . '</code>';
    }

    $lines = [];

    foreach (notifications_api_list_to_array($receiver->target->list()) as $target) {
        $line = $target->action . ': ' . (notifications_prop($target, 'display_target') ?: $target->target_kind);
        if (!notifications_prop($target, 'target_enabled', true)) {
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

function notifications_target_url($target_id, $user_id = null, $receiver_id = null)
{
    $url = '?page=notifications&action=target_edit&id='
        . rawurlencode((string) $target_id)
        . notifications_user_qs($user_id);

    if ($receiver_id) {
        $url .= '&receiver=' . rawurlencode((string) $receiver_id);
    }

    return $url;
}

function notifications_receiver_target_url($receiver_id, $receiver_target_id, $user_id = null)
{
    return '?page=notifications&action=receiver_edit&id='
        . rawurlencode((string) $receiver_id)
        . notifications_user_qs($user_id)
        . '#receiver-target-'
        . rawurlencode((string) $receiver_target_id);
}

function notifications_target_pairing_token_url($target, $user_id = null, $receiver_id = null)
{
    $url = '?page=notifications&action=target_pairing_token&id='
        . rawurlencode((string) $target->id)
        . notifications_user_qs($user_id);

    if ($receiver_id) {
        $url .= '&receiver=' . rawurlencode((string) $receiver_id);
    }

    return $url . '&t=' . rawurlencode((string) csrf_token());
}

function notifications_sms_verification_send_url($target, $user_id = null, $receiver_id = null)
{
    $url = '?page=notifications&action=target_sms_send&id='
        . rawurlencode((string) $target->id)
        . notifications_user_qs($user_id);

    if ($receiver_id) {
        $url .= '&receiver=' . rawurlencode((string) $receiver_id);
    }

    return $url . '&t=' . rawurlencode((string) csrf_token());
}

function notifications_email_verification_send_url($target, $user_id = null, $receiver_id = null)
{
    $url = '?page=notifications&action=target_email_send&id='
        . rawurlencode((string) $target->id)
        . notifications_user_qs($user_id);

    if ($receiver_id) {
        $url .= '&receiver=' . rawurlencode((string) $receiver_id);
    }

    return $url . '&t=' . rawurlencode((string) csrf_token());
}

function notifications_sms_verification_confirm_url($target, $user_id = null, $receiver_id = null)
{
    $url = '?page=notifications&action=target_sms_confirm&id='
        . rawurlencode((string) $target->id)
        . notifications_user_qs($user_id);

    if ($receiver_id) {
        $url .= '&receiver=' . rawurlencode((string) $receiver_id);
    }

    return $url;
}

function notifications_receiver_action_url($receiver_id, $action_id, $user_id = null)
{
    return notifications_receiver_target_url($receiver_id, $action_id, $user_id);
}

function notifications_telegram_pairing_token_url($receiver, $action)
{
    return notifications_target_pairing_token_url($action, $receiver->user_id);
}

function notifications_sms_verification_send_url_legacy($receiver, $action)
{
    return notifications_sms_verification_send_url($action, $receiver->user_id);
}

function notifications_sms_verification_confirm_url_legacy($receiver, $action)
{
    return notifications_sms_verification_confirm_url($action, $receiver->user_id);
}

function notifications_receiver_target_delete_url($receiver, $target)
{
    return '?page=notifications&action=receiver_target_delete&receiver='
        . rawurlencode((string) $receiver->id)
        . '&id='
        . rawurlencode((string) $target->id)
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

function notifications_telegram_automatic_pairing_html($action)
{
    $link = notifications_telegram_pairing_link_html($action);
    if (!$link) {
        return _('Automatic pairing link is not available. Use manual pairing below.');
    }

    return $link . '<br>'
        . _('The link includes the pairing command. Press Start in Telegram to finish pairing.');
}

function notifications_telegram_pairing_instructions_html($action)
{
    $command = notifications_prop($action, 'telegram_pairing_command');
    $bot_name = notifications_prop($action, 'telegram_bot_name');
    if (!$command) {
        if ($bot_name) {
            return sprintf(
                _('Create a new pairing command and use it in a private chat with @%s.'),
                h($bot_name)
            );
        }

        return _('Create a new pairing command and use it in a private chat with the Telegram bot.');
    }

    $items = [];
    if ($bot_name) {
        $items[] = sprintf(_('Open a private chat with @%s.'), h($bot_name));
    } else {
        $items[] = _('Open a private chat with the vpsAdmin Telegram bot.');
    }
    $items[] = sprintf(_('Send %s.'), '<code>' . h($command) . '</code>');
    $items[] = _('The bot will confirm whether pairing succeeded.');

    return '<ol><li>' . implode('</li><li>', $items) . '</li></ol>';
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
    $target_id = notifications_prop($delivery, 'notification_target_id');
    if (!$target_id) {
        return '-';
    }

    $label = notifications_prop($delivery, 'notification_target_label')
        ?: notifications_prop($delivery, 'notification_receiver_action_label')
        ?: ('#' . $target_id);

    return '<a href="' . notifications_target_url($target_id, $user_id) . '">' . h($label) . '</a>';
}

function notifications_delivery_route_link($delivery, $user_id = null)
{
    $route_id = notifications_prop($delivery, 'event_route_id');
    if (!$route_id) {
        return '-';
    }

    $label = notifications_prop($delivery, 'event_route_label') ?: ('#' . $route_id);

    return '<a href="?page=notifications&action=route_edit&id=' . rawurlencode((string) $route_id)
        . notifications_user_qs($user_id) . '">' . h($label) . '</a>';
}

function notifications_delivery_transaction_chain_link($delivery)
{
    $chain_id = notifications_prop($delivery, 'delivery_transaction_chain_id');
    if (!$chain_id) {
        return '-';
    }

    $label = notifications_prop($delivery, 'delivery_transaction_chain_label') ?: ('#' . $chain_id);

    return '<a href="?page=transactions&chain=' . rawurlencode((string) $chain_id) . '">'
        . h($label) . '</a>';
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
        return ['sent', 'failed', 'canceled', 'skipped', 'aborted'];
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

function notifications_targets($user_id = null)
{
    global $xtpl, $api;

    $user_id = notifications_target_user_id($user_id);
    $user = $api->user->show($user_id);
    $targets = $api->notification_target->list(['user' => $user_id]);
    $action_labels = notifications_target_all_type_labels();

    $xtpl->title(_('Notification targets'));

    if (isAdmin()) {
        $xtpl->table_title(_('User'));
        $xtpl->form_create('?page=notifications&action=targets', 'get', 'notification-user', false);
        $xtpl->form_set_hidden_fields([
            'page' => 'notifications',
            'action' => 'targets',
        ]);
        $xtpl->form_add_input(_('User ID') . ':', 'text', '20', 'user', $user_id);
        $xtpl->form_out(_('Show'));
    }

    $xtpl->table_title(_('Targets') . ': ' . h($user->login));
    $xtpl->table_add_category(_('Action'));
    $xtpl->table_add_category(_('Label'));
    $xtpl->table_add_category(_('Target'));
    $xtpl->table_add_category(_('Enabled'));
    $xtpl->table_add_category(_('Status'));
    $xtpl->table_add_category(_('Events'));
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');

    foreach ($targets as $target) {
        $toggle_link = '?page=notifications&action=target_toggle&id=' . $target->id
            . notifications_user_qs($user_id) . '&t=' . csrf_token();
        $delete_link = '?page=notifications&action=target_delete&id=' . $target->id
            . notifications_user_qs($user_id) . '&t=' . csrf_token();

        $xtpl->table_td(h($action_labels[$target->action] ?? $target->action));
        $xtpl->table_td(h($target->label));
        $xtpl->table_td(notifications_receiver_action_target_html($target), false, true);
        $xtpl->table_td(
            '<a href="' . $toggle_link . '" title="' . ($target->enabled ? _('Disable target') : _('Enable target')) . '">'
            . boolean_icon($target->enabled) . '</a>'
        );
        $xtpl->table_td(notifications_target_status_html($target));
        $xtpl->table_td(notifications_event_log_link(_('Event log'), $user_id, [
            'notification_target_id' => $target->id,
        ]));
        $xtpl->table_td('<a href="' . notifications_target_url($target->id, $user_id) . '"><img src="template/icons/vps_edit.png" title="' . _('Edit') . '"></a>');
        $xtpl->table_td(
            '<a href="' . $delete_link . '"'
            . notifications_confirm_onclick(_('Do you really wish to delete this notification target? Receiver links using it will be removed.'))
            . '><img src="template/icons/vps_delete.png" title="' . _('Delete') . '"></a>'
        );
        $xtpl->table_tr($target->enabled ? false : '#A6A6A6');
    }

    if ($targets->count() == 0) {
        $xtpl->table_td(_('No targets configured.'), false, false, 8);
        $xtpl->table_tr();
    }

    $xtpl->table_td(
        '<a href="?page=notifications&action=target_new' . notifications_user_qs($user_id) . '">'
        . '<img src="template/icons/vps_add.png" title="' . _('Add target') . '" alt="' . _('Add target') . '"> '
        . _('Add target') . '</a>',
        false,
        true,
        8
    );
    $xtpl->table_tr();
    $xtpl->table_out();

    notifications_sidebar('targets', $user_id);
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
    $xtpl->table_add_category(_('Targets'));
    $xtpl->table_add_category(_('Enabled'));
    $xtpl->table_add_category(_('Mute'));
    $xtpl->table_add_category(_('Events'));
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');

    foreach ($receivers as $receiver) {
        $toggle_link = '?page=notifications&action=receiver_toggle&id=' . $receiver->id
            . notifications_user_qs($user_id) . '&t=' . csrf_token();
        $delete_link = '?page=notifications&action=receiver_delete&id=' . $receiver->id
            . notifications_user_qs($user_id) . '&t=' . csrf_token();

        $xtpl->table_td(h($receiver->label));
        $xtpl->table_td(notifications_receiver_targets_summary_html($receiver));
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

function notifications_receiver_action_secret_html($action)
{
    if (notifications_prop($action, 'target_enabled') === false) {
        return boolean_icon(false) . ' ' . _('target disabled');
    }

    if (notifications_prop($action, 'delivery_method_enabled') === false) {
        return boolean_icon(false) . ' ' . _('delivery method disabled');
    }

    return notifications_target_action_status_html($action);
}

function notifications_target_status_html($target)
{
    if (notifications_prop($target, 'enabled') === false) {
        return boolean_icon(false) . ' ' . _('target disabled');
    }

    if (notifications_prop($target, 'delivery_method_enabled') === false) {
        return boolean_icon(false) . ' ' . _('delivery method disabled');
    }

    return notifications_target_action_status_html($target);
}

function notifications_target_action_status_html($target)
{
    if ($target->action === 'webhook') {
        return boolean_icon($target->secret_present);
    }

    if ($target->action === 'email' && notifications_prop($target, 'target_kind') === 'custom') {
        return boolean_icon($target->verified) . ' ' . ($target->verified ? _('verified') : _('pending'));
    }

    if ($target->action === 'telegram') {
        return boolean_icon($target->verified) . ' ' . ($target->verified ? _('paired') : _('pending'));
    }

    if ($target->action === 'sms') {
        return boolean_icon($target->verified) . ' ' . ($target->verified ? _('verified') : _('pending'));
    }

    return '-';
}

function notifications_target_options($user_id, $empty = false)
{
    global $api;

    $options = $empty ? ['' => '---'] : [];

    foreach ($api->notification_target->list(['user' => $user_id]) as $target) {
        $label = $target->action . ': ' . $target->label;
        $display_target = notifications_prop($target, 'display_target');
        if ($display_target) {
            $label .= ' (' . $display_target . ')';
        }
        if (!$target->enabled) {
            $label .= ' - ' . _('disabled');
        }

        $options[$target->id] = $label;
    }

    return $options;
}

function notifications_email_target_toggle_script()
{
    global $xtpl;

    static $added = false;
    if ($added) {
        return;
    }
    $added = true;

    $xtpl->assign(
        'AJAX_SCRIPT',
        ($xtpl->vars['AJAX_SCRIPT'] ?? '')
        . '<style type="text/css">'
        . '.notification-email-custom-target-hidden{display:none;}'
        . '</style>'
        . '<script type="text/javascript">'
        . 'function notificationsToggleEmailTargetValue(){'
        . 'var isCustom=$("select[name=target_kind]").val()==="custom";'
        . 'var rows=$(".notification-email-custom-target");'
        . 'var input=rows.find("input[name=target_value]");'
        . 'input.prop("disabled",!isCustom);'
        . 'rows.stop(true,true);'
        . 'if(isCustom){rows.fadeIn(150);}else{rows.fadeOut(150);}'
        . '}'
        . '$(document).ready(function(){'
        . '$("select[name=target_kind]").on("change",notificationsToggleEmailTargetValue);'
        . 'notificationsToggleEmailTargetValue();'
        . '});'
        . '</script>'
    );
}

function notifications_email_target_custom_row_class($target_kind)
{
    $classes = 'notification-email-custom-target';
    if ($target_kind !== 'custom') {
        $classes .= ' notification-email-custom-target-hidden';
    }
    return $classes;
}

function notifications_target_form_fields($user_id, $action_type, $target = null, $receiver = null)
{
    global $xtpl, $api;

    $input = $api->notification_target->create->getParameters('input');
    $target_kinds = notifications_param_choices($input->target_kind);
    $label = $target ? $target->label : '';
    $enabled = $target ? $target->enabled : true;
    $receiver_id = $receiver ? $receiver->id : null;

    if (isAdmin()) {
        $target_user = $target && isset($target->user) ? $target->user : $api->user->show($user_id);
        $xtpl->table_td(_('User') . ':');
        $xtpl->table_td(user_link($target_user));
        $xtpl->table_tr();
    }

    if ($receiver) {
        $xtpl->table_td(_('Receiver') . ':');
        $xtpl->table_td(
            '<a href="' . notifications_receiver_url($receiver->id, $receiver->user_id) . '">'
            . h($receiver->label) . '</a>'
        );
        $xtpl->table_tr();
    }

    $xtpl->table_td(_('Action') . ':');
    $xtpl->table_td(h(notifications_target_type_label($action_type)));
    $xtpl->table_tr();

    $xtpl->form_add_input(
        _('Label') . ':',
        'text',
        '40',
        'label',
        post_val('label', $label),
        _('Optional display name for this target.')
    );

    if ($action_type === 'email') {
        notifications_email_target_toggle_script();
        $target_kind = post_val('target_kind', $target ? $target->target_kind : 'default_recipient');
        $custom_row_class = notifications_email_target_custom_row_class($target_kind);

        $xtpl->form_add_select(
            _('Recipient') . ':',
            'target_kind',
            $target_kinds,
            $target_kind,
            _('Use the account e-mail or provide one custom address.')
        );
        $xtpl->table_td(_('Custom e-mail address') . ':');
        $xtpl->table_td(
            '<input type="text" size="60" name="target_value" value="'
            . h(post_val('target_value', $target ? $target->target_value : ''))
            . '"'
            . ($target_kind === 'custom' ? '' : ' disabled')
            . ' />'
        );
        $xtpl->table_td(_('Used only when custom target is selected.'));
        $xtpl->table_tr(false, $custom_row_class, $custom_row_class);

        if ($target && $target->target_kind === 'custom') {
            $xtpl->table_td(_('Verification') . ':');
            $xtpl->table_td(
                boolean_icon($target->verified) . ' '
                . ($target->verified ? _('verified') : _('pending'))
            );
            $xtpl->table_tr(false, $custom_row_class, $custom_row_class);
        } elseif (!$target) {
            $xtpl->table_td(_('Verification') . ':');
            $xtpl->table_td(_('A verification e-mail is sent after saving a custom address target.'));
            $xtpl->table_tr(false, $custom_row_class, $custom_row_class);
        }

        if ($target && $target->target_kind === 'custom' && !$target->verified && $target->last_error) {
            $xtpl->table_td(_('Last error') . ':');
            $xtpl->table_td(h($target->last_error));
            $xtpl->table_tr(false, $custom_row_class, $custom_row_class);
        }
    } elseif ($action_type === 'webhook') {
        $xtpl->form_add_input(
            _('Webhook URL') . ':',
            'text',
            '50',
            'target_value',
            post_val('target_value', $target ? $target->target_value : ''),
            _('HTTP or HTTPS endpoint that receives the event JSON payload.')
        );

        $placeholder = $target ? _('leave empty to keep') : null;
        $xtpl->table_td(_('Secret') . ':');
        $xtpl->table_td(notifications_secret_input_html('secret', '', 40, null, $placeholder));
        $xtpl->table_td(_('Optional HMAC secret sent as X-VpsAdmin-Signature-256.'));
        $xtpl->table_tr();

        if ($target && $target->secret_present) {
            $xtpl->table_td(_('Current secret') . ':');
            $xtpl->table_td(boolean_icon(true) . ' ' . notifications_checkbox_html('clear_secret', false) . ' ' . _('clear secret'));
            $xtpl->table_tr();
        }
    } elseif ($action_type === 'telegram') {
        if ($target && $target->verified) {
            $xtpl->table_td(_('Pairing') . ':');
            $xtpl->table_td(boolean_icon(true) . ' ' . h($target->display_target));
            $xtpl->table_tr();
        } elseif ($target) {
            $xtpl->table_td(_('Automatic pairing') . ':');
            $xtpl->table_td(notifications_telegram_automatic_pairing_html($target));
            $xtpl->table_tr();

            $xtpl->table_td(_('Manual pairing') . ':');
            $xtpl->table_td(notifications_telegram_pairing_instructions_html($target));
            $xtpl->table_tr();
        } else {
            $xtpl->table_td(_('Automatic pairing') . ':');
            $xtpl->table_td(_('created after saving'));
            $xtpl->table_tr();
        }

        if ($target && !$target->verified) {
            if ($target->last_error) {
                $xtpl->table_td(_('Last error') . ':');
                $xtpl->table_td(h($target->last_error));
                $xtpl->table_tr();
            }
        }

        if ($target) {
            $pairing_url = notifications_target_pairing_token_url($target, $user_id, $receiver_id);

            if ($target->verified) {
                $confirm = _('Re-pairing creates a new pairing command and pauses Telegram delivery until pairing succeeds. Continue?');
                $link = '<a href="' . h($pairing_url) . '"' . notifications_confirm_onclick($confirm) . '>'
                    . _('Re-pair Telegram chat') . '</a>';
                $text = $link . '<br>' . _('Telegram delivery will be paused until the new chat is paired.');

                $xtpl->table_td(_('Re-pair') . ':');
                $xtpl->table_td($text);
            } else {
                $xtpl->table_td(_('Pairing command') . ':');
                $xtpl->table_td(
                    '<a href="' . h($pairing_url) . '">' . _('Generate new pairing command') . '</a>'
                );
            }
            $xtpl->table_tr();
        }
    } elseif ($action_type === 'sms') {
        $xtpl->form_add_input(
            _('Phone number') . ':',
            'text',
            '40',
            'target_value',
            post_val('target_value', $target ? $target->target_value : ''),
            _('Use international E.164 format, e.g. +420123456789.')
        );

        $xtpl->table_td(_('Verification') . ':');
        if ($target) {
            $xtpl->table_td(
                boolean_icon($target->verified) . ' '
                . ($target->verified ? _('verified') : _('pending'))
            );
        } else {
            $xtpl->table_td(_('created after saving'));
        }
        $xtpl->table_tr();

        if ($target && !$target->verified) {
            $xtpl->table_td(_('Instructions') . ':');
            $xtpl->table_td(
                _('Save the phone number, send a verification SMS, then enter the code from the message.')
            );
            $xtpl->table_tr();
        }

        if ($target && !$target->verified && $target->last_error) {
            $xtpl->table_td(_('Last error') . ':');
            $xtpl->table_td(h($target->last_error));
            $xtpl->table_tr();
        }
    }

    $xtpl->form_add_checkbox(_('Enabled') . ':', 'enabled', '1', post_val('enabled', $enabled));
}

function notifications_sms_verification_controls($target, $user_id = null, $receiver_id = null)
{
    global $xtpl;

    if ($target->action !== 'sms' || $target->verified) {
        return;
    }

    $send_url = notifications_sms_verification_send_url($target, $user_id, $receiver_id);
    $confirm_url = notifications_sms_verification_confirm_url($target, $user_id, $receiver_id);

    $xtpl->table_title(_('SMS verification'));
    $xtpl->table_td(_('Verification SMS') . ':');
    $xtpl->table_td(
        '<a href="' . h($send_url) . '"'
        . notifications_confirm_onclick(_('Send a verification SMS to this phone number?'))
        . '>' . _('Send verification SMS') . '</a>'
        . '<br>' . _('Delivery is limited by a short resend cooldown.')
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

function notifications_email_verification_controls($target, $user_id = null, $receiver_id = null)
{
    global $xtpl;

    if ($target->action !== 'email' || $target->target_kind !== 'custom' || $target->verified) {
        return;
    }

    $send_url = notifications_email_verification_send_url($target, $user_id, $receiver_id);

    $xtpl->table_title(_('E-mail verification'));
    $xtpl->table_td(_('Verification e-mail') . ':');
    $xtpl->table_td(
        '<a href="' . h($send_url) . '"'
        . notifications_confirm_onclick(_('Send a verification e-mail to this address?'))
        . '>' . _('Send verification e-mail') . '</a>'
        . '<br>' . _('Open the link from the message to verify this target.')
    );
    $xtpl->table_tr();
    $xtpl->table_out();
}

function notifications_target_new($user_id = null, $action_type = null, $receiver_id = null)
{
    global $xtpl, $api;

    $receiver = null;
    if ($receiver_id) {
        $receiver = $api->notification_receiver->show($receiver_id, ['meta' => ['includes' => 'user']]);
        $user_id = $receiver->user_id;
    } else {
        $user_id = notifications_target_user_id($user_id);
    }

    $labels = notifications_target_type_labels($user_id);
    $action_type = $action_type ?: notifications_target_type_from_request($user_id);
    if ($action_type !== null && !isset($labels[$action_type])) {
        $action_type = null;
    }

    if ($action_type === null) {
        if (count($labels) == 0) {
            $xtpl->title(_('Add notification target'));
            $xtpl->perex(_('No delivery methods enabled'), _('No event delivery methods are enabled for this user.'));
            if ($receiver) {
                $xtpl->sbar_add(_('Back to receiver'), notifications_receiver_url($receiver->id, $receiver->user_id));
            } else {
                $xtpl->sbar_add(_('Back to targets'), '?page=notifications&action=targets' . notifications_user_qs($user_id));
            }
            notifications_sidebar('targets', $user_id);
            return;
        }

        $selected = api_get('type') ?: 'email';

        $xtpl->title(_('Add notification target'));
        $xtpl->table_title(_('Select target type'));
        $xtpl->form_create('?page=notifications', 'get', 'notification-target-type', false);
        $hidden = [
            'page' => 'notifications',
            'action' => 'target_new',
        ];
        if (isAdmin()) {
            $hidden['user'] = $user_id;
        }
        if ($receiver) {
            $hidden['receiver'] = $receiver->id;
        }
        $xtpl->form_set_hidden_fields($hidden);
        $xtpl->form_add_select(
            _('Target type') . ':',
            'type',
            $labels,
            isset($labels[$selected]) ? $selected : 'email',
            _('Choose how matching events will be delivered.')
        );
        $xtpl->form_out(_('Continue'));

        if ($receiver) {
            $xtpl->sbar_add(_('Back to receiver'), notifications_receiver_url($receiver->id, $receiver->user_id));
        } else {
            $xtpl->sbar_add(_('Back to targets'), '?page=notifications&action=targets' . notifications_user_qs($user_id));
        }
        notifications_sidebar('targets', $user_id);
        return;
    }

    $xtpl->title(_('Add notification target'));
    $xtpl->table_title(_('Add target'));
    $xtpl->form_create(
        '?page=notifications&action=target_new&type=' . urlencode($action_type)
        . ($receiver ? '&receiver=' . rawurlencode((string) $receiver->id) : '')
        . notifications_user_qs($user_id),
        'post'
    );
    $xtpl->form_set_hidden_fields([
        'action_type' => $action_type,
    ]);
    notifications_target_form_fields($user_id, $action_type, null, $receiver);
    $xtpl->form_out(_('Add'));

    if ($receiver) {
        $xtpl->sbar_add(_('Back to receiver'), notifications_receiver_url($receiver->id, $receiver->user_id));
    } else {
        $xtpl->sbar_add(_('Back to targets'), '?page=notifications&action=targets' . notifications_user_qs($user_id));
    }
    notifications_sidebar('targets', $user_id);
}

function notifications_target_context_receiver($target, $receiver_id)
{
    global $api;

    if (!$receiver_id) {
        return null;
    }

    try {
        $receiver = $api->notification_receiver->show($receiver_id, ['meta' => ['includes' => 'user']]);
    } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
        return null;
    }

    return (int) $receiver->user_id === (int) $target->user_id ? $receiver : null;
}

function notifications_target_edit($target_id, $receiver_id = null)
{
    global $xtpl, $api;

    $target = $api->notification_target->show($target_id, ['meta' => ['includes' => 'user']]);
    $user_id = $target->user_id;
    $receiver = notifications_target_context_receiver($target, $receiver_id);

    $xtpl->title(_('Notification target') . ' #' . $target->id);
    $xtpl->table_title(_('Update target'));
    $xtpl->form_create(
        notifications_target_url($target->id, $user_id, $receiver ? $receiver->id : null),
        'post'
    );
    $xtpl->form_set_hidden_fields([
        'action_type' => $target->action,
    ]);
    notifications_target_form_fields($user_id, $target->action, $target, $receiver);
    $xtpl->form_out(_('Save'));

    notifications_email_verification_controls($target, $user_id, $receiver ? $receiver->id : null);
    notifications_sms_verification_controls($target, $user_id, $receiver ? $receiver->id : null);

    if ($receiver) {
        $xtpl->sbar_add(_('Back to receiver'), notifications_receiver_url($receiver->id, $receiver->user_id));
        notifications_sidebar('receivers', $user_id);
    } else {
        $xtpl->sbar_add(_('Back to targets'), '?page=notifications&action=targets' . notifications_user_qs($user_id));
        notifications_sidebar('targets', $user_id);
    }
}

function notifications_receiver_edit($receiver_id)
{
    global $xtpl, $api;

    $receiver = $api->notification_receiver->show($receiver_id, ['meta' => ['includes' => 'user']]);
    $input = $api->notification_receiver->update->getParameters('input');
    $target_labels = notifications_target_all_type_labels();

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

    $xtpl->table_title(_('Targets'));
    $xtpl->table_add_category(_('Action'));
    $xtpl->table_add_category(_('Label'));
    $xtpl->table_add_category(_('Target'));
    $xtpl->table_add_category(_('Target enabled'));
    $xtpl->table_add_category(_('Status'));
    $xtpl->table_add_category(_('Events'));
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');

    $receiver_targets = notifications_api_list_to_array($receiver->target->list());

    foreach ($receiver_targets as $target) {
        $xtpl->table_td(h($target_labels[$target->action] ?? $target->action));
        $xtpl->table_td(h($target->label));
        $xtpl->table_td(notifications_receiver_action_target_html($target), false, true);
        $xtpl->table_td(boolean_icon(notifications_prop($target, 'target_enabled', true)));
        $xtpl->table_td(notifications_receiver_action_secret_html($target));
        $xtpl->table_td(notifications_event_log_link(_('Event log'), $receiver->user_id, [
            'notification_receiver_id' => $receiver->id,
            'notification_target_id' => notifications_prop($target, 'notification_target_id'),
            'notification_receiver_target_id' => $target->id,
        ]));
        $xtpl->table_td(
            '<a href="' . notifications_target_url(notifications_prop($target, 'notification_target_id'), $receiver->user_id, $receiver->id)
            . '"><img src="template/icons/vps_edit.png" title="' . _('Edit target') . '"></a>'
        );
        $xtpl->table_td(
            '<a href="' . notifications_receiver_target_delete_url($receiver, $target) . '"'
            . notifications_confirm_onclick(_('Do you really wish to unlink this notification target from the receiver?'))
            . '><img src="template/icons/vps_delete.png" title="' . _('Delete') . '"></a>'
        );
        $xtpl->table_tr();
    }

    if (count($receiver_targets) == 0) {
        $xtpl->table_td(_('No targets linked.'), false, false, 8);
        $xtpl->table_tr();
    }

    $xtpl->table_td(
        '<a href="?page=notifications&action=target_new&receiver=' . $receiver->id
        . notifications_user_qs($receiver->user_id) . '"><img src="template/icons/vps_add.png" title="' . _('Add target') . '" alt="' . _('Add target') . '"> '
        . _('Create and link target') . '</a>',
        false,
        true,
        8
    );
    $xtpl->table_tr();
    $xtpl->table_out();

    $target_options = notifications_target_options($receiver->user_id, true);
    if (count($target_options) > 1) {
        $xtpl->table_title(_('Link existing target'));
        $xtpl->form_create(
            '?page=notifications&action=receiver_target_link&receiver=' . $receiver->id
            . notifications_user_qs($receiver->user_id),
            'post'
        );
        $xtpl->form_add_select(
            _('Notification target') . ':',
            'notification_target_id',
            $target_options,
            post_val('notification_target_id', ''),
            _('Select an existing reusable target.')
        );
        $xtpl->form_out(_('Link target'));
    }

    $xtpl->sbar_add(_('Back to receivers'), '?page=notifications&action=receivers' . notifications_user_qs($receiver->user_id));
    notifications_sidebar('receivers', $receiver->user_id);
}

function notifications_time_or_dash($value)
{
    return $value ? tolocaltz($value) : '-';
}

function notifications_rate_limit_post_name($limit)
{
    return 'notification_rate_limit_' . preg_replace('/[^a-zA-Z0-9_]/', '_', $limit->id);
}

function notifications_rate_limits_for_user($user)
{
    global $api;

    return notifications_api_list_to_array($api->user($user->id)->notification_rate_limit->list());
}

function notifications_rate_limit_source_label($limit)
{
    if (($limit->source ?? '') === 'override') {
        return _('custom');
    }

    return _('default');
}

function notifications_rate_limits($user_id = null)
{
    global $xtpl, $api;

    $user_id = notifications_target_user_id($user_id);
    $user = $api->user->show($user_id);
    $limits = notifications_rate_limits_for_user($user);

    $xtpl->title(_('Notification delivery limits'));

    if (isAdmin()) {
        $xtpl->table_title(_('User'));
        $xtpl->form_create('?page=notifications&action=limits', 'get', 'notification-user', false);
        $xtpl->form_set_hidden_fields([
            'page' => 'notifications',
            'action' => 'limits',
        ]);
        $xtpl->form_add_input(_('User ID') . ':', 'text', '20', 'user', $user_id);
        $xtpl->form_out(_('Show'));
    }

    $xtpl->table_title(_('Limits') . ': ' . h($user->login));
    $xtpl->table_add_category(_('Method'));
    $xtpl->table_add_category(_('Window'));
    $xtpl->table_add_category(_('Limit'));
    $xtpl->table_add_category(_('Used'));
    $xtpl->table_add_category(_('Remaining'));
    $xtpl->table_add_category(_('Resets at'));
    $xtpl->table_add_category(_('Source'));

    if (isAdmin()) {
        $xtpl->form_create('?page=notifications&action=limits&user=' . $user->id, 'post');
    }

    foreach ($limits as $limit) {
        $xtpl->table_td(h($limit->label ?? $limit->delivery_method));
        $xtpl->table_td(h($limit->period_label ?? $limit->period));
        if (isAdmin()) {
            $xtpl->table_td(
                '<input type="number" min="1" step="1" size="8" name="'
                . h(notifications_rate_limit_post_name($limit))
                . '" value="' . h((string) $limit->limit_count) . '">'
            );
        } else {
            $xtpl->table_td(h((string) $limit->limit_count));
        }
        $xtpl->table_td(h((string) ($limit->used_count ?? 0)));
        $xtpl->table_td(h((string) ($limit->remaining_count ?? 0)));
        $xtpl->table_td(notifications_time_or_dash($limit->resets_at ?? null));
        $xtpl->table_td(h(notifications_rate_limit_source_label($limit)));
        $xtpl->table_tr();
    }

    if (!$limits) {
        $xtpl->table_td(_('No delivery limits are configured.'), false, false, '7');
        $xtpl->table_tr();
    }

    if (isAdmin()) {
        $xtpl->form_out(_('Save'));
    } else {
        $xtpl->table_out();
    }

    notifications_sidebar('limits', $user_id);
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

    foreach (['event_route_id', 'notification_receiver_id', 'notification_target_id', 'notification_receiver_target_id'] as $name) {
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
    $xtpl->form_add_input(_('Target ID') . ':', 'text', '20', 'notification_target_id', get_val('notification_target_id'));
    $xtpl->form_add_input(_('Receiver target ID') . ':', 'text', '20', 'notification_receiver_target_id', get_val('notification_receiver_target_id'));
    $xtpl->table_td(_('Event type') . ':');
    $xtpl->table_td(
        notifications_select_html(
            'event_type',
            notifications_event_type_labels(true),
            get_val('event_type')
        )
    );
    $xtpl->table_tr();

    $action_label = isset($input->action->label) && $input->action->label ? $input->action->label : _('Action');
    $xtpl->table_td($action_label . ':');
    $xtpl->table_td(
        notifications_select_html(
            'delivery_action',
            notifications_param_choices($input->action, true),
            get_val('delivery_action')
        )
    );
    $xtpl->table_tr();

    $xtpl->table_td(_('State') . ':');
    $xtpl->table_td(
        notifications_select_html(
            'delivery_state',
            notifications_delivery_state_choices($state_group, true),
            get_val('delivery_state')
        )
    );
    $xtpl->table_tr();
    $xtpl->form_out(_('Show'));

    $xtpl->table_add_category(_('Delivery'));
    $xtpl->table_add_category(_('Event'));
    $xtpl->table_add_category(_('User'));
    $xtpl->table_add_category(_('VPS'));
    $xtpl->table_add_category(_('Receiver'));
    $xtpl->table_add_category(_('Target'));
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
        if ($value !== null && $value !== '') {
            $params[$name] = $value;
        }
    }

    $delivery_action = api_get('delivery_action');
    if ($delivery_action !== null && $delivery_action !== '') {
        $params['action'] = $delivery_action;
    }

    foreach (['notification_receiver_id', 'notification_target_id', 'notification_receiver_target_id'] as $name) {
        $id = api_get_uint($name);
        if ($id !== null && $id > 0) {
            $params[$name] = $id;
        }
    }

    $route_id = api_get_uint('event_route_id');
    if ($route_id !== null && $route_id > 0) {
        $params['event_route_id'] = $route_id;
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
    $xtpl->form_add_input(_('Route ID') . ':', 'text', '20', 'event_route_id', get_val('event_route_id'));
    $xtpl->form_add_input(_('Receiver ID') . ':', 'text', '20', 'notification_receiver_id', get_val('notification_receiver_id'));
    $xtpl->form_add_input(_('Target ID') . ':', 'text', '20', 'notification_target_id', get_val('notification_target_id'));
    $xtpl->form_add_input(_('Receiver target ID') . ':', 'text', '20', 'notification_receiver_target_id', get_val('notification_receiver_target_id'));

    if (isAdmin()) {
        $xtpl->form_add_input(_('User ID') . ':', 'text', '20', 'user', get_val('user'));
    }

    $xtpl->table_td(_('Event type') . ':');
    $xtpl->table_td(
        notifications_select_html(
            'event_type',
            notifications_event_type_labels(true),
            get_val('event_type')
        )
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
        )
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

function notifications_event_route_matches($event)
{
    global $xtpl;

    $matches = notifications_api_list_to_array($event->route_match->list());

    $xtpl->table_title(_('Matched routes'));
    $xtpl->table_add_category(_('Route'));
    $xtpl->table_add_category(_('User'));
    $xtpl->table_add_category(_('Relation'));

    foreach ($matches as $match) {
        $route_label = notifications_prop($match, 'event_route_label') ?: ('#' . $match->event_route_id);
        $route_user_qs = notifications_user_qs(notifications_prop($match, 'route_owner_id'));
        $owner = notifications_prop($match, 'route_owner_login') ?: ('#' . notifications_prop($match, 'route_owner_id'));

        $xtpl->table_td(
            '<a href="?page=notifications&action=route_edit&id=' . $match->event_route_id . $route_user_qs . '">'
            . h($route_label) . '</a>'
        );
        $xtpl->table_td(h($owner));
        $xtpl->table_td(h(notifications_prop($match, 'subject_relation')));
        $xtpl->table_tr();
    }

    if (!$matches) {
        $xtpl->table_td(_('No routes matched.'), false, false, 3);
        $xtpl->table_tr();
    }

    $xtpl->table_out();
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

    $xtpl->table_td(_('Summary') . ':');
    $xtpl->table_td(h($event->summary));
    $xtpl->table_tr();

    $xtpl->table_td(_('Payload') . ':');
    $xtpl->table_td(notifications_json_pre_html($event->payload_json));
    $xtpl->table_tr();
    $xtpl->table_out();

    notifications_event_route_matches($event);

    $xtpl->table_title(_('Deliveries'));
    $xtpl->table_add_category(_('Action'));
    $xtpl->table_add_category(_('Receiver'));
    $xtpl->table_add_category(_('Notification target'));
    $xtpl->table_add_category(_('Target'));
    $xtpl->table_add_category(_('State'));
    $xtpl->table_add_category(_('Route'));
    $xtpl->table_add_category(_('Attempts'));
    $xtpl->table_add_category(_('Released'));

    $deliveries = notifications_api_list_to_array($event->delivery->list());

    foreach ($deliveries as $delivery) {
        $target = notifications_prop($delivery, 'notification_target_display_target')
            ?: notifications_prop($delivery, 'target_label')
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
        $xtpl->table_td(notifications_delivery_route_link($delivery, $event->user_id));
        $xtpl->table_td(notifications_prop($delivery, 'attempt_count', 0), false, true);
        $xtpl->table_td(notifications_time_or_dash(notifications_prop($delivery, 'released_at')));
        $result = [];
        $last_attempt = notifications_prop($delivery, 'last_attempt_at');
        $next_attempt = notifications_prop($delivery, 'next_attempt_at');
        if ($last_attempt) {
            $result[] = h(_('Last attempt') . ': ' . tolocaltz($last_attempt));
        }
        if ($next_attempt) {
            $result[] = h(_('Next retry') . ': ' . tolocaltz($next_attempt));
        }
        if ($provider_message_id) {
            $result[] = h('Message-ID ' . $provider_message_id);
        }
        $response_status_label = notifications_response_status_label($delivery->action, $response_status);
        if ($response_status_label) {
            $result[] = h($response_status_label);
        }
        if ($error_summary) {
            $result[] = h($error_summary);
        }
        if (notifications_prop($delivery, 'delivery_transaction_chain_id')) {
            $result[] = h(_('Transaction chain') . ': ') . notifications_delivery_transaction_chain_link($delivery);
        }
        $xtpl->table_tr();

        if ($result) {
            $xtpl->table_td(_('Result') . ':', false, false, 2);
            $xtpl->table_td(implode(', ', $result), false, false, 6);
            $xtpl->table_tr();
        }

        $xtpl->table_td(_('Delivery attempts') . ':', false, false, 2);
        $xtpl->table_td(notifications_delivery_attempts_html($event, $delivery), false, true, 6);
        $xtpl->table_tr();

        if ($response_body) {
            $xtpl->table_td(_('Response') . ':', false, false, 2);
            $xtpl->table_td('<pre>' . h(notifications_short_value($response_body, 1024)) . '</pre>', false, false, 6);
            $xtpl->table_tr();
        }
    }

    if (count($deliveries) == 0) {
        $xtpl->table_td(_('No deliveries recorded.'), false, false, 8);
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
    $target = notifications_prop($delivery, 'notification_target_display_target')
        ?: notifications_prop($delivery, 'target_label')
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

    $xtpl->table_td(_('Notification target') . ':');
    $xtpl->table_td(notifications_delivery_receiver_action_link($delivery, $event->user_id));
    $xtpl->table_tr();

    $xtpl->table_td(_('Route') . ':');
    $xtpl->table_td(notifications_delivery_route_link($delivery, $event->user_id));
    $xtpl->table_tr();

    $xtpl->table_td(_('Transaction chain') . ':');
    $xtpl->table_td(notifications_delivery_transaction_chain_link($delivery));
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
    notifications_event_types_hash_script();
    $groups = [];

    foreach (notifications_event_types_cached() as $type) {
        $groups[notifications_prop($type, 'category') ?: _('Other')][] = $type;
    }

    ksort($groups);
    $html = '<div class="notification-event-types">';

    foreach ($groups as $category => $types) {
        usort($types, function ($a, $b) {
            return strcmp(notifications_prop($a, 'name', ''), notifications_prop($b, 'name', ''));
        });

        $html .= '<details class="notification-event-type-category">'
            . '<summary><span class="notification-event-type-category-title">'
            . h($category) . '</span> <span class="notification-event-type-category-count">'
            . h(sprintf(_('%d events'), count($types))) . '</span></summary>'
            . '<div class="notification-event-type-list">';

        foreach ($types as $type) {
            $name = notifications_prop($type, 'name');
            $anchor = notifications_event_type_anchor($name);
            $fields = notifications_event_type_field_metadata_from_type($type);
            $severity_description = notifications_prop($type, 'severity_description');
            $template = notifications_prop($type, 'template');
            $label = notifications_prop($type, 'label', $name);
            $severity = notifications_prop($type, 'severity');

            $html .= '<section id="' . h($anchor) . '" class="notification-event-type">'
                . '<h3><code>' . h($name) . '</code></h3>'
                . '<p class="notification-event-type-label">' . h($label) . '</p>'
                . '<div class="notification-event-type-meta">'
                . '<p><strong>' . _('Severity') . ':</strong> <code>' . h($severity) . '</code>'
                . ($severity_description ? '<br><small>' . h($severity_description) . '</small>' : '')
                . '</p>'
                . '<p><strong>' . _('Default routed') . ':</strong> '
                . (notifications_prop($type, 'default_routed', true) ? h(_('yes')) : h(_('no'))) . '</p>';

            if (isAdmin() && $template) {
                $html .= '<p><strong>' . _('Template') . ':</strong> <code>' . h($template) . '</code></p>';
            }

            $html .= '</div>'
                . '<table class="table-style01 notification-event-type-fields">'
                . '<tr><th>' . _('Field') . '</th><th>' . _('Type') . '</th><th>' . _('Example') . '</th><th>' . _('Meaning') . '</th></tr>';

            foreach ($fields as $name => $field) {
                $html .= '<tr>'
                    . '<td><code>' . h($name) . '</code></td>'
                    . '<td><code>' . h($field['type'] ?? '') . '</code></td>'
                    . '<td>' . notifications_field_example_html($field) . '</td>'
                    . '<td>' . h($field['description'] ?? $name) . '</td>'
                    . '</tr>';
            }

            if (!$fields) {
                $html .= '<tr><td colspan="4">' . _('No matchable fields were reported by the API.') . '</td></tr>';
            }

            $html .= '</table></section>';
        }

        $html .= '</div></details>';
    }

    $html .= '</div>';

    $xtpl->content_add_fragment($html);

    notifications_sidebar('event_types', $user_id);
    notifications_event_types_sidebar($groups, $user_id);
}

function notifications_event_types_hash_script()
{
    global $xtpl;

    $xtpl->assign(
        'AJAX_SCRIPT',
        ($xtpl->vars['AJAX_SCRIPT'] ?? '')
        . '<script type="text/javascript">'
        . '$(function(){'
        . 'function openEventTypeHash(){'
        . 'var hash=window.location.hash;'
        . 'if(!hash||hash.indexOf("#event-type-")!==0){return;}'
        . 'var target=$(hash);'
        . 'if(!target.length){return;}'
        . 'target.closest("details.notification-event-type-category").prop("open",true);'
        . 'if(target[0].scrollIntoView){target[0].scrollIntoView();}'
        . '}'
        . 'openEventTypeHash();'
        . '$(window).on("hashchange",openEventTypeHash);'
        . '$(".notification-event-type-sidebar a").on("click",function(){'
        . 'setTimeout(openEventTypeHash,0);'
        . '});'
        . '});'
        . '</script>'
    );
}

function notifications_event_types_sidebar($groups, $user_id = null)
{
    global $xtpl;

    $user_qs = notifications_user_qs($user_id);
    $html = '<div class="notification-event-type-sidebar">'
        . '<h3>' . _('Event types') . '</h3>';

    foreach ($groups as $category => $types) {
        usort($types, function ($a, $b) {
            return strcmp(notifications_prop($a, 'name', ''), notifications_prop($b, 'name', ''));
        });

        $html .= '<h4>' . h($category) . '</h4><ul>';

        foreach ($types as $type) {
            $name = notifications_prop($type, 'name');
            $url = '?page=notifications&action=event_types'
                . $user_qs
                . '#' . notifications_event_type_anchor($name);
            $html .= '<li><a href="' . h($url) . '">' . h($name) . '</a></li>';
        }

        $html .= '</ul>';
    }

    $html .= '</div>';
    $xtpl->sbar_add_fragment($html);
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
        $xtpl->form_add_select(
            _('Subject scope') . ':',
            'subject_scope',
            notifications_test_subject_scope_options($input->subject_scope),
            post_val('subject_scope', 'self')
        );
    }

    $xtpl->form_add_select(
        _('Event type') . ':',
        'event_type',
        notifications_event_type_labels(true),
        post_val('event_type', 'user.test_notification')
    );
    api_param_to_form('subject', $input->subject, post_val('subject', _('Test notification')));
    api_param_to_form('summary', $input->summary, post_val('summary', _('This event was created from notification settings.')));
    $xtpl->form_add_textarea(_('Payload') . ':', 70, 8, 'payload_json', post_val('payload_json', "{\n  \"note\": \"testing notification routing\"\n}"));
    $xtpl->form_out(_('Create event'));

    notifications_sidebar('test', $user_id);
}
