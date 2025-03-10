<?php

/*
    ./lib/functions.lib.php

    vpsAdmin
    Web-admin interface for vpsAdminOS (see https://vpsadminos.org)
    Copyright (C) 2008-2009 Pavel Snajdr, snajpa@snajpa.net

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

$DATA_SIZE_UNITS = [
    "b" => "B",
    "k" => "KiB",
    "m" => "MiB",
    "g" => "GiB",
    "t" => "TiB",
];


function get_free_route_list($res, $vps, $role = null, $limit = null)
{
    global $api;

    if ($res === 'ipv4' || $res === 'ipv4_private') {
        $v = 4;
    } else {
        $v = 6;
    }

    $ret = [];
    $filters = [
        'version' => $v,
        'network_interface' => null,
        'location' => $vps->node->location_id,
        'meta' => ['includes' => 'user'],
    ];

    if ($role) {
        $filters['role'] = $role;
    }

    if ($limit) {
        $filters['limit'] = $limit;
    }

    foreach ($api->ip_address->list($filters) as $ip) {
        $note = '';

        if ($ip->user_id) {
            if ($ip->user_id == $vps->user_id) {
                $note = '(owned)';
            } else {
                $note = '(owned by ' . $ip->user->login . ')';
            }
        }

        $ret[$ip->id] = $ip->addr . '/' . $ip->prefix . " $note";
    }

    return $ret;
}

function get_free_host_addr_list($res, $vps, $netif, $role = null, $limit = null)
{
    global $api;

    if ($res === 'ipv4' || $res === 'ipv4_private') {
        $v = 4;
    } else {
        $v = 6;
    }

    $ret = [];
    $filters = [
        'version' => $v,
        'network_interface' => $netif->id,
        'assigned' => false,
        'meta' => ['includes' => 'ip_address'],
    ];

    if ($role) {
        $filters['role'] = $role;
    }

    if ($limit) {
        $filters['limit'] = $limit;
    }

    foreach ($api->host_ip_address->list($filters) as $ip) {
        $ret[$ip->id] = $ip->addr . '/' . $ip->ip_address->prefix;
    }

    return $ret;
}

function get_vps_ip_route_list($vps)
{
    global $api;

    return $api->ip_address->list(['vps' => $vps->id]);
}

function get_ip_address_id($val)
{
    global $api;

    if (is_numeric($val)) {
        return $val;
    }

    $ips = $api->ip_address->list(['addr' => $val]);

    if ($ips->count() < 1) {
        return false;
    } else {
        return $ips->first()->id;
    }
}

function ip_label($ip)
{
    switch ($ip->network->role) {
        case 'public_access':
            return 'Public IPv' . $ip->network->ip_version;
        case 'private_access':
            return 'Private IPv' . $ip->network->ip_version;
    }
}

function host_ip_label($ip)
{
    return ip_label($ip->ip_address);
}

function ip_type_label($type)
{
    return [
        'ipv4' => _('Public IPv4'),
        'ipv4_private' => _('Private IPv4'),
        'ipv6' => _('Public IPv6'),
    ][$type];
}

function available_ip_types($vps)
{
    $ret = [];

    $free_4_pub = get_free_route_list('ipv4', $vps, 'public_access', 1);
    if (!empty($free_4_pub)) {
        $ret[] = 'ipv4';
    }

    $free_4_priv = get_free_route_list('ipv4_private', $vps, 'private_access', 1);
    if (!empty($free_4_priv)) {
        $ret[] = 'ipv4_private';
    }

    if ($vps->node->location->has_ipv6) {
        $free_6 = get_free_route_list('ipv6', $vps, null, 1);

        if (!empty($free_6)) {
            $ret[] = 'ipv6';
        }
    }

    return $ret;
}

function available_ip_options($vps)
{
    $ret = [];

    foreach (available_ip_types($vps) as $t) {
        $ret[$t] = ip_type_label($t);
    }

    return $ret;
}

function ip_address_assignment_label($as)
{
    return $as->ip_addr . ' (VPS ' . $as->raw_vps_id . ', ' . tolocaltz($as->from_date) . ' - ' . ($as->to_date ? tolocaltz($as->to_date) : _('now')) . ')';
}

function list_templates($vps = null)
{
    global $api;

    $disabled = _('(IMPORTANT: This template is currently disabled, it cannot be used)');
    $tpls = $api->os_template->list();
    $choices = resource_list_to_options(
        $tpls,
        'id',
        'label',
        false,
        function ($t) use ($vps) {
            if ($vps && $t->hypervisor_type != $vps->node->hypervisor_type) {
                return null;
            }

            $ret = $t->label;

            if (isAdmin() && !$t->enabled) {
                return $ret . ' ' . _('(IMPORTANT: This template is currently disabled, it cannot be used)');
            };

            return $ret;
        }
    );

    if ($vps && !$vps->os_template->enabled && !isAdmin()) {
        $choices = [$vps->os_template_id => $vps->os_template->label . ' ' . $disabled] + $choices;
    }

    return $choices;
}

function notify_user($title, $msg = '')
{
    $_SESSION["notification"] = [
        "title" => $title,
        "msg" => $msg,
    ];
}

function show_notification()
{
    global $xtpl;

    if (!isset($_SESSION["notification"])) {
        return;
    }

    $xtpl->perex($_SESSION["notification"]["title"], $_SESSION["notification"]["msg"]);
    unset($_SESSION["notification"]);
}

function redirect($loc)
{
    header('Location: ' . preg_replace('#^/+#', '/', $loc));
    exit;
}

function format_duration($interval)
{
    $d = $interval / 86400;
    $h = floor($interval / 3600) % 24;
    $m = floor($interval / 60) % 60;
    $s = floor($interval) % 60;

    if ($d >= 1) {
        return sprintf("%d days, %02d:%02d:%02d", floor($d), $h, $m, $s);
    } else {
        return sprintf("%02d:%02d:%02d", $h, $m, $s);
    }
}

function tolocaltz($datetime, $format = "Y-m-d H:i:s")
{
    if (is_null($datetime)) {
        return '-';
    }

    $t = new DateTime($datetime);
    $t->setTimezone(new DateTimeZone(date_default_timezone_get()));
    return $t->format($format);
}

function toutc($datetime)
{
    $t = new DateTime($datetime);
    return $t->setTimezone(new DateTimeZone('UTC'));
}

function random_string($len)
{
    $str = "";
    $chars = array_merge(range(0, 9), range('a', 'z'), range('A', 'Z'));

    for ($i = 0; $i < $len; $i++) {
        $str .= $chars[array_rand($chars)];
    }

    return $str;
}

function format_data_rate($n, $suffix)
{
    $units = [
        2 << 29 => 'G',
        2 << 19 => 'M',
        2 << 9 => 'k',
    ];

    $ret = "";
    $selected = 0;

    foreach ($units as $threshold => $unit) {
        if ($n > $threshold) {
            return round(($n / $threshold), 2) . "$unit$suffix";
        }
    }

    return round($n, 2) . "$suffix";
}

function getClientIdentity()
{
    $hash = getCommitHash();

    if ($hash) {
        $short = substr($hash, 0, 8);
    } else {
        $short = VERSION;
    }

    return  "vpsadmin-webui " . $short;
}

function api_description_changed($api)
{
    $_SESSION["api_description"] = $api->getDescription();
}

function maintenance_lock_icon($type, $obj)
{
    $m_icon_on = '<img alt="' . _('Turn maintenance OFF.') . '" src="template/icons/maintenance_mode.png">';
    $m_icon_off = '<img alt="' . _('Turn maintenance ON.') . '" src="template/icons/transact_ok.png">';

    switch ($obj->maintenance_lock) {
        case 'no':
            return '<a href="?page=cluster&action=maintenance_lock&type=' . $type . '&obj_id=' . $obj->id . '&lock=1">'
                   . $m_icon_off
                   . '</a>';

        case 'lock':
            return '<a href="?page=cluster&action=set_maintenance_lock&type=' . $type . '&obj_id=' . $obj->id . '&lock=0&t=' . csrf_token() . '"
			           title="' . _('Maintenance lock reason') . ': ' . htmlspecialchars($obj->maintenance_lock_reason) . '">'
                    . $m_icon_on
                    . '</a>';

        case 'master_lock':
            return '<img alt="' . _('Under maintenance.') . '"
			             title="' . _('Under maintenance') . ': ' . htmlspecialchars($obj->maintenance_lock_reason) . '"
			             src="template/icons/maintenance_mode.png">';
    }
}

function resource_list_to_options($list, $id = 'id', $label = 'label', $empty = true, $label_callback = null)
{
    $ret = [];

    if ($empty) {
        $ret[0] = '---';
    }

    foreach ($list as $item) {
        $item_label = $label_callback ? $label_callback($item) : $item->{$label};

        if ($item_label === null) {
            continue;
        }

        $ret[ $item->{$id} ] = $item_label;
    }

    return $ret;
}

function boolean_icon($val)
{
    if ($val) {
        return '<img src="template/icons/transact_ok.png" />';
    } else {
        return '<img src="template/icons/transact_fail.png" />';
    }
}

function api_param_to_form_pure($name, $desc, $v = null, $label_callback = null, $empty = null)
{
    global $xtpl, $api;

    if ($v === null && property_exists($desc, 'default')) {
        $v = $desc->default === '_nil' ? null : $desc->default;
    }

    if (isset($_POST[$name])) {
        $v = $_POST[$name];
    }

    switch ($desc->type) {
        case 'String':
        case 'Integer':
        case 'Float':
            if ($desc->validators && property_exists($desc->validators, 'include')) {
                $desc_choices = $desc->validators->include->values;
                $assoc = is_assoc($desc_choices);
                $choices = [];

                if ($empty) {
                    $choices[''] = '---';
                }

                if ($label_callback) {
                    foreach ($desc_choices as $k => $val) {
                        $choice_label = $label_callback($val);

                        if (is_null($choice_label)) {
                            continue;
                        }

                        if ($assoc) {
                            $choices[$k] = $choice_label;
                        } else {
                            $choices[$val] = $choice_label;
                        }
                    }

                } else {
                    if ($assoc) {
                        $choices = $desc_choices;

                    } else {
                        foreach ($desc_choices as $val) {
                            $choices[$val] = $val;
                        }
                    }
                }

                $xtpl->form_add_select_pure(
                    $name,
                    $choices,
                    $v
                );

            } else {
                $xtpl->form_add_input_pure('text', '30', $name, $v);
            }
            break;

        case 'Text':
            $xtpl->form_add_textarea_pure(70, 10, $name, $v);
            break;

        case 'Boolean':
            $xtpl->form_add_checkbox_pure($name, '1', $v);
            break;

        case 'Datetime':
            $xtpl->form_add_datetime_pure($name, $v, false);
            break;

        case 'Resource':
            $xtpl->form_add_select_pure(
                $name,
                resource_list_to_options(
                    $api[ implode('.', $desc->resource) ]->index(),
                    $desc->value_id,
                    $desc->value_label,
                    $empty === null || $empty,
                    $label_callback
                ),
                ($v instanceof \HaveAPI\Client\ResourceInstance) ? $v->id : $v
            );

            // no break
        default:
            break;
    }
}

function api_param_to_form($name, $desc, $v = null, $label_callback = null, $empty = null)
{
    global $xtpl;

    $xtpl->table_td(($desc->label ? $desc->label : $name) . ':');
    api_param_to_form_pure($name, $desc, $v, $label_callback, $empty);

    if ($desc->description) {
        $xtpl->table_td($desc->description);
    }

    $xtpl->table_tr();
}

function api_params_to_form($action, $direction, $label_callbacks = null)
{
    $params = $action->getParameters($direction);

    foreach ($params as $name => $desc) {
        api_param_to_form($name, $desc, null, $label_callbacks ? $label_callbacks[$name] : null);
    }
}

function api_create_form($resource)
{
    api_params_to_form($resource->create, 'input');
}

function api_update_form($obj)
{
    $params = $obj->update->getParameters('input');

    foreach ($params as $name => $desc) {
        api_param_to_form($name, $desc, post_val($name, $obj->{$name}));
    }
}

function client_params_to_api($action, $from = null)
{
    if (!$from) {
        $from = $_POST;
    }

    $params = $action->getParameters('input');
    $ret = [];

    foreach ($params as $name => $desc) {
        if (isset($from[ $name ])) {
            if ($desc->validators->include) {
                $ret[ $name ] = $from[$name];
                continue;
            }

            switch ($desc->type) {
                case 'Integer':
                    $v = (int) $from[$name];
                    break;

                case 'Boolean':
                    $v = true;
                    break;

                case 'Resource':
                    if (!$from[$name]) {
                        continue 2;
                    }

                    // no break
                default:
                    $v = $from[ $name ];
            }

            $ret[ $name ] = $v;

        } else {
            switch ($desc->type) {
                case 'Boolean':
                    $ret[ $name ] = false;
                    break;

                default:
                    break;
            }
        }
    }

    return $ret;
}

function unit_for_cluster_resource($name)
{
    switch ($name) {
        case 'cpu':
            return _('cores');

        case 'ipv4':
        case 'ipv4_private':
        case 'ipv6':
            return _('addresses');

        default:
            return 'MiB';
    }
}

function data_size_unitize($val)
{
    $units = ["t" => 39, "g" => 29, "m" => 19, "k" => 9, "b" => 0];
    $sign = 1;

    if ($val < 0) {
        $sign = -1;
        $val = $val * -1;
    }

    if (!$val) {
        return [0, "b"];
    } elseif ($val < 1024) {
        return [$val * $sign, "b"];
    }

    foreach ($units as $u => $ex) {
        if ($val >= (2 << $ex)) {
            return [($val / (2 << $ex)) * $sign, $u];
        }
    }

    return [$val * $sign, "b"];
}

function data_size_to_humanreadable_b($val)
{
    global $DATA_SIZE_UNITS;

    if (!$val) {
        return _("none");
    }

    $res = data_size_unitize($val);
    return round($res[0], 2) . " " . $DATA_SIZE_UNITS[$res[1]];
}

function data_size_to_humanreadable_kb($val)
{
    if (!$val) {
        return _("none");
    }

    return data_size_to_humanreadable_b($val * 1024);
}

function data_size_to_humanreadable_mb($val)
{
    if (!$val) {
        return _("none");
    }

    return data_size_to_humanreadable_b($val * 1024 * 1024);
}

function data_size_to_humanreadable($val)
{
    return data_size_to_humanreadable_mb($val);
}

function number_unitize($val)
{
    $units = [
        "t" => 1000000000000,
        "g" => 1000000000,
        "m" => 1000000,
        "k" => 1000,
        "" => 0,
    ];
    $sign = 1;

    if ($val < 0) {
        $sign = -1;
        $val = $val * -1;
    }

    if (!$val) {
        return [0, ""];
    } elseif ($val < 1000) {
        return [$val * $sign, ""];
    }

    foreach ($units as $u => $ex) {
        if ($val >= $ex) {
            return [($val / $ex) * $sign, $u];
        }
    }

    return [$val * $sign, ""];
}

function format_number_with_unit($n)
{
    [$val, $unit] = number_unitize($n);

    if ($unit != 'k') {
        $unit = strtoupper($unit);
    }

    return round($val, 2) . $unit;
}

function approx_number($val)
{
    $start = 1000;
    $units = [
        "&nbsp;million",
        "&nbsp;billion",
        "&times;10<sup>12</sup>",
        "&times;10<sup>15</sup>",
        "&times;10<sup>18</sup>",
        "&times;10<sup>21</sup>",
        "&times;10<sup>24</sup>",
        "&times;10<sup>27</sup>",
        "&times;10<sup>30</sup>",
        "&times;10<sup>33</sup>",
    ];

    $i = 1;
    $n = $start;
    $data = [];
    $sign = 1;

    if ($val < 0) {
        $sign = -1;
        $val = $val * -1;
    }

    foreach ($units as $u) {
        $n *= 1000;
        $data[] = ['n' => $n, 'unit' => $u];
    }

    foreach (array_reverse($data) as $unit) {
        if ($val > $unit['n']) {
            return (round($val / $unit['n'], 2) * $sign) . $unit['unit'];
        }
    }

    return number_format($val * $sign, 0, '.', ' ');
}

function get_val($name, $default = '')
{
    if (isset($_GET[$name])) {
        return h($_GET[$name]);
    }

    if (is_string($default)) {
        return h($default);
    } else {
        return $default;
    }
}

function post_val($name, $default = '')
{
    if (isset($_POST[$name])) {
        if (is_string($_POST[$name])) {
            return h($_POST[$name]);
        } else {
            return $_POST[$name];
        }
    }

    if (is_string($default)) {
        return h($default);
    } else {
        return $default;
    }
}

function post_val_array($name, $index, $default = '')
{
    if (isset($_POST[$name]) && isset($_POST[$name][$index])) {
        return $_POST[$name][$index];
    }
    return $default;
}

function get_val_issetto($name, $value, $default = false)
{
    if (!isset($_GET[$name])) {
        return $default;
    }

    return $_GET[$name] == $value;
}

function post_val_issetto($name, $value, $default = false)
{
    if (!isset($_POST[$name])) {
        return $default;
    }

    return $_POST[$name] == $value;
}

function transaction_concern_class($klass)
{
    $tr = [
        'Vps' => 'VPS',
    ];

    if (array_key_exists($klass, $tr)) {
        return $tr[$klass];
    }

    return $klass;
}

function transaction_concern_link($klass, $row_id)
{
    switch ($klass) {
        case 'Vps':
            return '<a href="?page=adminvps&action=info&veid=' . $row_id . '">' . $row_id . '</a>';

        case 'User':
            return '<a href="?page=adminm&action=edit&id=' . $row_id . '">' . $row_id . '</a>';

        case 'UserPayment':
            return '<a href="?page=redirect&to=payset&from=payment&id=' . $row_id . '">' . $row_id . '</a>';

        case 'RegistrationRequest':
            return '<a href="?page=adminm&action=request_details&id=' . $row_id . '&type=registration">' . $row_id . '</a>';

        case 'ChangeRequest':
            return '<a href="?page=adminm&action=request_details&id=' . $row_id . '&type=change">' . $row_id . '</a>';

        case 'Outage':
            return '<a href="?page=outage&action=show&id=' . $row_id . '">' . $row_id . '</a>';

        case 'Export':
            return '<a href="?page=export&action=edit&export=' . $row_id . '">' . $row_id . '</a>';

        case 'DnsZone':
            return '<a href="?page=dns&action=zone_show&id=' . $row_id . '">' . $row_id . '</a>';

        case 'HostIpAddress':
            return '<a href="?page=redirect&to=ip_address&from=host_ip_address&id=' . $row_id . '">' . $row_id . '</a>';

        default:
            return "$row_id";
    }
}

function transaction_chain_concerns($chain, $limit = 10)
{
    if (!$chain->concerns) {
        return '---';
    }

    switch ($chain->concerns->type) {
        case 'affect':
            if (count($chain->concerns->objects) < 1) {
                return '---';
            }
            $o = $chain->concerns->objects[0];
            return transaction_concern_class($o[0]) . ' ' . transaction_concern_link($o[0], $o[1]);

        case 'transform':
            if (count($chain->concerns->objects) < 2) {
                return '---';
            }

            $src = $chain->concerns->objects[0];
            $dst = $chain->concerns->objects[1];

            return transaction_concern_class($src[0]) . ' ' . transaction_concern_link($src[0], $src[1]) . ' -> ' . transaction_concern_link($dst[0], $dst[1]);

        default:
            return _('Unknown');
    }
}

function get_all_users()
{
    global $api;

    $cnt = $api->user->list([
        'limit' => 0,
        'meta' => ['count' => true],
    ])->getTotalCount();

    return $api->user->list([
        'limit' => $cnt + 10,
    ]);
}

function vps_label($vps)
{
    return '#' . $vps->id . ' ' . $vps->hostname;
}

function user_label($user)
{
    return '#' . $user->id . ' ' . $user->login;
}

function node_link($node, $label = null)
{
    if (!$label) {
        $label = $node->domain_name;
    }

    return '<a href="?page=node&id=' . $node->id . '">' . $label . '</a>';
};

function vps_link($vps)
{
    return '<a href="?page=adminvps&action=info&veid=' . $vps->id . '">#' . $vps->id . '</a>';
}

function user_link($user)
{
    if ($user) {
        return '<a href="?page=adminm&action=edit&id=' . $user->id . '">' . $user->login . '</a>';
    }

    return '-';
}

function export_link($export)
{
    return '<a href="?page=export&action=edit&export=' . $export->id . '">#' . $export->id . '</a>';
}

function kernel_version($v)
{
    if (is_null($v)) {
        return '-';
    }

    if (preg_match("/\d+stab.+/", $v, $matches)) {
        return $matches[0];
    } elseif ($pos = strpos($v, '.el6')) {
        return substr($v, 0, $pos);
    } else {
        return $v;
    }
}

function cgroup_version($v)
{
    if (is_null($v)) {
        return '-';
    }

    switch ($v) {
        case 'cgroup_v1':
            return 'v1';
        case 'cgroup_v2':
            return 'v2';
        default:
            return "v1";
    }
}

function colorize($array)
{
    $ret = [];

    $from = 0x70;
    $to = 0xff;
    $cnt = count($array);

    if (!$cnt) {
        return $ret;
    }

    $step = (int) round(($to - $from) / pow($cnt, 1.0 / 3));
    $i = 0;

    for ($r = $from; $r < $to; $r += $step) {
        for ($g = $from; $g < $to; $g += $step) {
            for ($b = $from; $b < $to; $b += $step) {
                if (count($ret) >= $cnt) {
                    return $ret;
                }

                $ret[ $array[$i++] ] = dechex(($r << 16) + ($g << 8) + $b);
            }
        }
    }

    return $ret;
}

function lang_id_by_code($code, $langs = null)
{
    global $api;

    if (!$langs) {
        $langs = $api->language->list();
    }

    foreach ($langs as $l) {
        if ($l->code == $code) {
            return $l->id;
        }
    }

    return false;
}


function network_label($net)
{
    return $net->label ? $net->label : $net->address . '/' . $net->prefix;
}

function payments_enabled()
{
    global $api;

    return $api->user_payment ? true : false;
}

function is_assoc($arr)
{
    if ([] === $arr) {
        return false;
    }

    return array_keys($arr) !== range(0, count($arr) - 1);
}

function h($v)
{
    if (is_null($v)) {
        return '';
    }

    return htmlspecialchars($v);
}

/**
 * @return bool
 */
function isLoggedIn()
{
    return $_SESSION["logged_in"] ?? false;
}

/**
 * @return bool
 */
function isAdmin()
{
    return $_SESSION['is_admin'] ?? false;
}

function getVersionLink()
{
    $hash = getCommitHash();

    if (!$hash) {
        return VERSION;
    }

    $short = substr($hash, 0, 8);

    return '<a href="https://github.com/vpsfreecz/vpsadmin/commit/' . $hash . '" target="_blank">' . $short . '</a>';
}

function getCommitHash()
{
    $hash = null;

    if (isset($_SESSION['commit_hash'])) {
        $hash = $_SESSION['commit_hash'];

    } else {
        $hash = readCommitHash();
        $_SESSION['commit_hash'] = $hash;
    }

    return $hash;
}

function readCommitHash()
{
    $revisionFile = WWW_ROOT . '/.git-revision';

    if (file_exists($revisionFile)) {
        return trim(file_get_contents($revisionFile));
    }

    $gitDir = WWW_ROOT . '/../.git';

    if (!file_exists($gitDir)) {
        return null;
    }

    $gitHead = file_get_contents($gitDir . '/HEAD');

    if (!str_starts_with($gitHead, 'ref: ')) {
        return trim($gitHead);
    }

    $ref = trim(explode(' ', $gitHead)[1]);

    return trim(file_get_contents($gitDir . '/' . $ref));
}

function format_errors($response)
{
    $body = _('Error message: ') . $response->getMessage();
    $errors = $response->getErrors();

    $body .= '<br>';

    if (count((array) $errors) > 0) {
        $body .= '<ul>';

        foreach ($errors as $param => $err) {
            $body .= '<li>' . $param . ': ' . implode(', ', $err) . '</li>';
        }

        $body .= '</ul>';
    }

    return $body;
}

function hasTotpEnabled($user)
{
    global $api;

    return $user->totp_device->list([
        'enabled' => true,
        'limit' => 0,
        'meta' => ['count' => true],
    ])->getTotalCount() > 0;
}

function hasWebAuthnEnabled($user)
{
    global $api;

    return $user->webauthn_credential->list([
        'enabled' => true,
        'limit' => 0,
        'meta' => ['count' => true],
    ])->getTotalCount() > 0;
}

function getUserEmails($user, $mail_role_recipients, $role)
{
    foreach ($mail_role_recipients as $recp) {
        if ($recp->label === $role && $recp->to != '') {
            return explode(',', $recp->to);
        }
    }

    return [$user->email];
}

function isExportPublic()
{
    return isAdmin() || EXPORT_PUBLIC;
}

function hypervisorTypeToLabel($type)
{
    switch ($type) {
        case 'vpsadminos':
            return 'vpsAdminOS';
        default:
            return 'Unknown';
    }
}

function findBestPublicHostAddress($hostAddrs)
{
    // Public IPv4
    foreach ($hostAddrs as $ip) {
        $net = $ip->ip_address->network;

        if ($net->ip_version == 4 && $net->role == "public_access") {
            return $ip;
        }
    }

    // Public IPv6
    foreach ($hostAddrs as $ip) {
        $net = $ip->ip_address->network;

        if ($net->ip_version == 6 && $net->role == "public_access") {
            return $ip;
        }
    }

    // No public IP
    return null;
}

function showVpsDiskSpaceWarning($vps)
{
    return $vps->used_diskspace > $vps->diskspace / 100.0 * 90;
}

function vpsDiskUsagePercent($vps)
{
    return $vps->used_diskspace / $vps->diskspace * 100;
}

function showVpsDiskExpansionWarning($vps)
{
    return $vps->dataset->dataset_expansion_id ? true : false;
}

function usedSpaceWithCompression($dataset, $property)
{
    $used = $dataset->{$property};
    $ratio = $dataset->{$property == 'used' ? 'compressratio' : 'refcompressratio'};

    $ret = '';
    $ret .= data_size_to_humanreadable($used);
    $ret .= ' (';
    $ret .= data_size_to_humanreadable($used * $ratio);
    $ret .= ' ' . _('uncompressed, ratio ') . $ratio . '&times;)';

    return $ret;
}

function compressRatioWithUsedSpace($dataset, $property)
{
    $used = $dataset->{$property == 'compressratio' ? 'used' : 'referenced'};
    $ratio = $dataset->{$property};

    $ret = '';
    $ret .= $ratio . '&times;';
    $ret .= ' (';
    $ret .= data_size_to_humanreadable($used * $ratio);
    $ret .= ' ' . _('uncompressed') . ')';

    return $ret;
}

function sortMaintenanceWindowsByCloseness($windows)
{
    $ret = [];

    $curWeekday = intval(date('w'));
    $curHour = intval(date('H'));
    $curMinute = intval(date('i'));

    $nowInMins = $curHour * 60 + $curMinute;
    $reserveTime = 5;

    foreach ($windows as $w) {
        $daydiff = 0;

        if ($curWeekday == $w->weekday) {
            if ($nowInMins >= $w->opens_at && $nowInMins <= ($w->closes_at - $reserveTime)) {
                $daydiff = 0;
            } else {
                $daydiff = 7;
            }
        } elseif ($curWeekday > $w->weekday) {
            $daydiff = $w->weekday - $curWeekday + 7;
        } else {
            $daydiff = $w->weekday - $curWeekday;
        }

        $ret[$daydiff] = $w;
    }

    ksort($ret);

    return $ret;
}

function cgroupEnumTolabel($v)
{
    switch ($v) {
        case 'cgroup_any':
            return 'cgroup v1/v2';
        case 'cgroup_v1':
            return 'cgroup v1';
        case 'cgroup_v2':
            return 'cgroup v2';
        default:
            return 'unknown cgroup';
    }
}

function makeDefinitionList($array, $classes = '')
{
    $ret = '<dl class="' . $classes . '">';


    foreach ($array as $k => $v) {
        $ret .= '<dt>' . h($k) . ':</dt>';
        $ret .= '<dd>' . h((is_null($v) || $v === '') ? '-' : $v) . '</dd>';
    }

    $ret .= '</dl>';

    return $ret;
}

function truncateString(string $string, int $maxLength): string
{
    if (mb_strlen($string) <= $maxLength) {
        return $string;
    }

    return mb_substr($string, 0, $maxLength - 3) . '...';
}

function moo_inputremaining($input, $output, $chars, $uid)
{
    $out = "<script type=\"text/javascript\">\n";

    $out .= '
	$(document).ready(function (){
		$("#' . $input . '").keyup(function (o){
			var n = ' . abs($chars) . ' - $(this).val().length;
			$("#' . $output . '").text( n < 0 ? 0 : n );
		});
	});
	';

    $out .= "</script>\n";

    return $out;
}
