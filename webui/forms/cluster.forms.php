<?php

function cluster_header()
{
    global $xtpl, $api;

    $return_url = urlencode($_SERVER['REQUEST_URI']);

    $xtpl->sbar_add(_("VPS overview"), '?page=cluster&action=vps');
    $xtpl->sbar_add(_("System config"), '?page=cluster&action=sysconfig');
    $xtpl->sbar_add(_("Register new node"), '?page=cluster&action=newnode');
    $xtpl->sbar_add(_("Manage OS templates"), '?page=cluster&action=templates');
    $xtpl->sbar_add(_("Manage networks"), '?page=cluster&action=networks');
    $xtpl->sbar_add(_("Manage routable addresses"), '?page=cluster&action=ip_addresses');
    $xtpl->sbar_add(_("Manage host addresses"), '?page=cluster&action=host_ip_addresses');
    $xtpl->sbar_add(_("Manage DNS servers"), '?page=cluster&action=dns');
    $xtpl->sbar_add(_("Manage environments"), '?page=cluster&action=environments');
    $xtpl->sbar_add(_("Manage locations"), '?page=cluster&action=locations');
    $xtpl->sbar_add(_("Manage resource packages"), '?page=cluster&action=resource_packages');
    $xtpl->sbar_add(_("OOM reports"), '?page=oom_reports&action=list');
    $xtpl->sbar_add(_("Incident reports"), '?page=incidents&action=list&return=' . $return_url);

    if ($api->outage) {
        $xtpl->sbar_add(_("Outage list"), '?page=outage&action=list');
    }

    if ($api->monitored_event) {
        $xtpl->sbar_add(_("Monitoring"), '?page=monitoring&action=list');
    }

    if ($api->news_log) {
        $xtpl->sbar_add(_("Event log"), '?page=cluster&action=eventlog');
    }

    if ($api->help_box) {
        $xtpl->sbar_add(_("Help boxes"), '?page=cluster&action=helpboxes');
    }

    $xtpl->table_title(_("Summary"));

    $stats = $api->cluster->full_stats();

    $xtpl->table_td(_("Nodes") . ':');
    $xtpl->table_td($stats["nodes_online"] . ' ' . _("online") . ' / ' . $stats["node_count"] . ' ' . _("total"), $stats["nodes_online"] < $stats["node_count"] ? '#FFA500' : '#66FF66');
    $xtpl->table_tr();

    $xtpl->table_td(_("VPS") . ':');
    $xtpl->table_td($stats["vps_running"] . ' ' . _("running") . ' / ' . $stats["vps_stopped"] . ' ' . _("stopped") . ' / ' . $stats["vps_suspended"] . ' ' . _("suspended") . ' / ' .
                    $stats["vps_deleted"] . ' ' . _("deleted") . ' / ' . $stats["vps_count"] . ' ' . _("total"));
    $xtpl->table_tr();

    $xtpl->table_td(_("Members") . ':');
    $xtpl->table_td($stats["user_active"] . ' ' . _("active") . ' / ' . $stats["user_suspended"] . ' ' . _("suspended")
                    . ' / ' . $stats["user_deleted"] . ' ' . _("deleted") . ' / ' . $stats["user_count"] . ' ' . _("total"));
    $xtpl->table_tr();

    $xtpl->table_td(_("IPv4 addresses") . ':');
    $xtpl->table_td($stats["ipv4_used"] . ' ' . _("used") . ' / ' . $stats["ipv4_count"] . ' ' . _("total"));
    $xtpl->table_tr();

    $xtpl->table_out();
}

function node_overview()
{
    global $xtpl, $api;

    $xtpl->table_title(_("Node list"));
    $xtpl->table_add_category('');
    $xtpl->table_add_category('#');
    $xtpl->table_add_category(_("Name"));
    $xtpl->table_add_category(_("VPS"));
    $xtpl->table_add_category(_("Up"));
    $xtpl->table_add_category(_("Load"));
    $xtpl->table_add_category(_("%iowait"));
    $xtpl->table_add_category(_("%idle"));
    $xtpl->table_add_category(_("Free mem"));
    $xtpl->table_add_category(_("ARC"));
    $xtpl->table_add_category(_("%hit"));
    $xtpl->table_add_category(_("Version"));
    $xtpl->table_add_category(_("Kernel"));
    $xtpl->table_add_category('<img title="' . _("Toggle maintenance on node.") . '" alt="' . _("Toggle maintenance on node.") . '" src="template/icons/maintenance_mode.png">');

    foreach ($api->node->overview_list() as $node) {
        // Availability icon
        $icons = "";
        $maintenance_toggle = $node->maintenance_lock == 'lock' ? 0 : 1;
        $t = null;

        if ($node->last_report) {
            $t = new DateTime($node->last_report);
            $t->setTimezone(new DateTimeZone(date_default_timezone_get()));
        }

        if (!$node->last_report || (time() - $t->getTimestamp()) > 150) {
            $icons .= '<img title="' . _("The server is not responding") . '" src="template/icons/error.png"/>';

        } else {
            $icons .= '<img title="' . _("The server is online") . '" src="template/icons/server_online.png"/>';
        }

        $icons = '<a href="?page=cluster&action=' . ($maintenance_toggle ? 'maintenance_lock' : 'set_maintenance_lock') . '&type=node&obj_id=' . $node->id . '&lock=' . $maintenance_toggle . '">' . $icons . '</a>';

        $xtpl->table_td($icons, false, true);

        // Node ID, Name, IP, load
        $xtpl->table_td($node->id);
        $xtpl->table_td($node->domain_name);
        $xtpl->table_td($node->vps_running, false, true);
        $xtpl->table_td(sprintf('%.1f', $node->uptime / 60.0 / 60 / 24), false, true);
        $xtpl->table_td($node->loadavg, false, true);

        // CPU
        $xtpl->table_td(sprintf('%.2f', $node->cpu_iowait), false, true);
        $xtpl->table_td(sprintf('%.2f', $node->cpu_idle), false, true);

        // Memory
        $xtpl->table_td(
            sprintf('%.2f', ($node->total_memory - $node->used_memory) / 1024),
            false,
            true
        );

        // ARC
        $xtpl->table_td(sprintf('%.2f', $node->arc_size / 1024.0), false, true);
        $xtpl->table_td(sprintf('%.2f', $node->arc_hitpercent), false, true);

        // Daemon version
        $xtpl->table_td($node->version, false, true);

        // Kernel
        $xtpl->table_td(kernel_version($node->kernel));

        $xtpl->table_td(maintenance_lock_icon('node', $node));

        $xtpl->table_tr();
    }

    $xtpl->table_out('cluster_node_list');


}

function node_vps_overview()
{
    global $xtpl, $api;

    $xtpl->table_title(_("Node list"));
    $xtpl->table_add_category('');
    $xtpl->table_add_category('#');
    $xtpl->table_add_category(_("Name"));
    $xtpl->table_add_category(_("Up"));
    $xtpl->table_add_category(_("Down"));
    $xtpl->table_add_category(_("Del"));
    $xtpl->table_add_category(_("Sum"));
    $xtpl->table_add_category(_("Free"));
    $xtpl->table_add_category(_("Max"));
    $xtpl->table_add_category(' ');

    foreach ($api->node->overview_list() as $node) {
        // Availability icon
        $icons = "";
        $maintenance_toggle = $node->maintenance_lock == 'lock' ? 0 : 1;

        $t = new DateTime($node->last_report);
        $t->setTimezone(new DateTimeZone(date_default_timezone_get()));

        if (!$node->last_report || (time() - $t->getTimestamp()) > 150) {
            $icons .= '<img title="' . _("The server is not responding") . '" src="template/icons/error.png"/>';

        } else {
            $icons .= '<img title="' . _("The server is online") . '" src="template/icons/server_online.png"/>';
        }

        $icons = '<a href="?page=cluster&action=' . ($maintenance_toggle ? 'maintenance_lock' : 'set_maintenance_lock') . '&type=node&obj_id=' . $node->id . '&lock=' . $maintenance_toggle . '">' . $icons . '</a>';

        $xtpl->table_td($icons, false, true);

        // Node ID, Name, IP, load
        $xtpl->table_td($node->id);
        $xtpl->table_td($node->domain_name);

        // Up, down, del, sum
        $xtpl->table_td($node->vps_running, false, true);
        $xtpl->table_td($node->vps_stopped, false, true);
        $xtpl->table_td($node->vps_deleted, false, true);
        $xtpl->table_td($node->vps_total, false, true);

        // Free, max
        $xtpl->table_td($node->vps_free, false, true);
        $xtpl->table_td($node->vps_max, false, true);

        $xtpl->table_td('<a href="?page=cluster&action=node_edit&node_id=' . $node->id . '"><img src="template/icons/edit.png" title="' . _("Edit") . '"></a>');


        $xtpl->table_tr();
    }

    $xtpl->table_out('cluster_node_list');
}

function networks_list()
{
    global $xtpl, $api;

    $xtpl->title(_('Networks'));

    $xtpl->table_add_category(_('Network'));
    $xtpl->table_add_category(_('Location'));
    $xtpl->table_add_category(_('Label'));
    $xtpl->table_add_category(_('Type'));
    $xtpl->table_add_category(_('Managed'));
    $xtpl->table_add_category(_('Size'));
    $xtpl->table_add_category(_('Used'));
    $xtpl->table_add_category(_('Assigned'));
    $xtpl->table_add_category(_('Owned'));
    $xtpl->table_add_category(_('Free'));
    $xtpl->table_add_category(_('IPs'));
    $xtpl->table_add_category(_('Locations'));

    $networks = $api->network->list();

    foreach ($networks as $n) {
        $xtpl->table_td($n->address . '/' . $n->prefix);
        $xtpl->table_td($n->primary_location_id ? $n->primary_location->label : '-');
        $xtpl->table_td($n->label);
        $xtpl->table_td([
            'public_access' => 'Pub',
            'private_access' => 'Priv',
        ][$n->role]);
        $xtpl->table_td(boolean_icon($n->managed));
        $xtpl->table_td(approx_number($n->size), false, true);
        $xtpl->table_td($n->used, false, true);
        $xtpl->table_td($n->assigned, false, true);
        $xtpl->table_td($n->owned, false, true);
        $xtpl->table_td(
            (approx_number($n->used - $n->taken)) .
            ' (' . (approx_number($n->size - $n->taken)) . ')',
            false,
            true
        );
        $xtpl->table_td(
            ip_list_link(
                'cluster',
                '<img
				src="template/icons/vps_ip_list.png"
				title="' . _('List IP addresses in this network') . '">',
                ['network' => $n->id]
            )
        );
        $xtpl->table_td(
            '<a href="?page=cluster&action=network_locations&network=' . $n->id . '">' .
            '<img
				src="template/icons/vps_ip_list.png"
				title="' . _('List locations this network is available in') . '">' .
            '</a>'
        );
        $xtpl->table_tr();
    }

    $xtpl->table_out();
}

function ip_list_link($page, $text, $conds)
{
    $str_conds = [];

    foreach ($conds as $k => $v) {
        $str_conds[] = "$k=$v";
    }

    $ret = '<a href="?page=' . $page . '&action=ip_addresses&list=1&' . implode('&', $str_conds) . '">';
    $ret .= $text;
    $ret .= '</a>';

    return $ret;
}

function network_locations_list($netId)
{
    global $xtpl, $api;

    $net = $api->network->show($netId);

    $xtpl->title(_('Network locations') . ': ' . $net->address . '/' . $net->prefix);
    $xtpl->sbar_add(
        _("Add location"),
        '?page=cluster&action=location_network_add_loctonet&network=' . $net->id
    );

    $xtpl->table_add_category(_('Label'));
    $xtpl->table_add_category(_('Primary'));
    $xtpl->table_add_category(_('Priority'));
    $xtpl->table_add_category(_('Autopick'));
    $xtpl->table_add_category(_('Userpick'));
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');

    $locnets = $api->location_network->list([
        'network' => $netId,
        'meta' => ['includes' => 'location'],
    ]);

    foreach ($locnets as $locnet) {
        $xtpl->table_td($locnet->location->label);
        $xtpl->table_td(boolean_icon($locnet->primary));
        $xtpl->table_td($locnet->priority, false, true);
        $xtpl->table_td(boolean_icon($locnet->autopick));
        $xtpl->table_td(boolean_icon($locnet->userpick));
        $xtpl->table_td('<a href="?page=cluster&action=location_network_edit&id=' . $locnet->id . '" title="' . _("Edit") . '"><img src="template/icons/edit.png" title="' . _("Edit") . '"></a>');
        $xtpl->table_td('<a href="?page=cluster&action=location_network_del&id=' . $locnet->id . '&t=' . csrf_token() . '&return=' . $return_url . '" title="' . _("Delete") . '"><img src="template/icons/delete.png" title="' . _("Delete") . '"></a>');
        $xtpl->table_tr();
    }

    $xtpl->table_out();
}

function location_networks_list($locId)
{
    global $xtpl, $api;

    $loc = $api->location->show($locId);

    $xtpl->title(_('Location networks') . ': ' . $loc->label);
    $xtpl->sbar_add(
        _("Add network"),
        '?page=cluster&action=location_network_add_nettoloc&location=' . $loc->id
    );

    $xtpl->table_add_category(_('Address'));
    $xtpl->table_add_category(_('Label'));
    $xtpl->table_add_category(_('Primary'));
    $xtpl->table_add_category(_('Priority'));
    $xtpl->table_add_category(_('Autopick'));
    $xtpl->table_add_category(_('Userpick'));
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');

    $locnets = $api->location_network->list([
        'location' => $locId,
        'meta' => ['includes' => 'network'],
    ]);

    $return_url = urlencode($_SERVER['REQUEST_URI']);

    foreach ($locnets as $locnet) {
        $xtpl->table_td($locnet->network->address . '/' . $locnet->network->prefix);
        $xtpl->table_td($locnet->network->label);
        $xtpl->table_td(boolean_icon($locnet->primary));
        $xtpl->table_td($locnet->priority, false, true);
        $xtpl->table_td(boolean_icon($locnet->autopick));
        $xtpl->table_td(boolean_icon($locnet->userpick));
        $xtpl->table_td('<a href="?page=cluster&action=location_network_edit&id=' . $locnet->id . '" title="' . _("Edit") . '"><img src="template/icons/edit.png" title="' . _("Edit") . '"></a>');
        $xtpl->table_td('<a href="?page=cluster&action=location_network_del&id=' . $locnet->id . '&t=' . csrf_token() . '&return=' . $return_url . '" title="' . _("Delete") . '"><img src="template/icons/delete.png" title="' . _("Delete") . '"></a>');
        $xtpl->table_tr();
    }

    $xtpl->table_out();
}

function location_network_add_nettoloc_form($locId)
{
    global $xtpl, $api;

    $loc = $api->location->show($locId);

    $xtpl->title(_('Add network to location'));

    $xtpl->form_create(
        '?page=cluster&action=location_network_add_nettoloc&location=' . $loc->id,
        'post'
    );

    $input = $api->location_network->create->getParameters('input');

    $xtpl->table_td(_('Location') . ':');
    $xtpl->table_td($loc->label);
    $xtpl->table_tr();

    api_param_to_form('network', $input->network);
    api_param_to_form('primary', $input->primary);
    api_param_to_form('priority', $input->priority);
    api_param_to_form('autopick', $input->autopick);
    api_param_to_form('userpick', $input->userpick);
    $xtpl->form_out(_('Add'));
}

function location_network_add_loctonet_form($netId)
{
    global $xtpl, $api;

    $net = $api->network->show($netId);

    $xtpl->title(_('Add location to network'));

    $xtpl->form_create(
        '?page=cluster&action=location_network_add_loctonet&network=' . $net->id,
        'post'
    );

    $input = $api->location_network->create->getParameters('input');

    $xtpl->table_td(_('Network') . ':');
    $xtpl->table_td($net->address . '/' . $net->prefix);
    $xtpl->table_tr();

    api_param_to_form('location', $input->location);
    api_param_to_form('primary', $input->primary);
    api_param_to_form('priority', $input->priority);
    api_param_to_form('autopick', $input->autopick);
    api_param_to_form('userpick', $input->userpick);
    $xtpl->form_out(_('Add'));
}

function location_network_edit_form($locnetId)
{
    global $xtpl, $api;

    $locnet = $api->location_network->show($locnetId, [
        'meta' => ['includes' => 'location,network'],
    ]);

    $xtpl->sbar_add(
        _("Back to network locations"),
        '?page=cluster&action=network_locations&network=' . $locnet->network_id
    );

    $xtpl->sbar_add(
        _("Back to location networks"),
        '?page=cluster&action=location_networks&location=' . $locnet->location_id
    );

    $xtpl->title(
        _('Location network') . ': ' . $locnet->location->label . ' @ ' .
        $locnet->network->address . '/' . $locnet->network->prefix
    );

    $xtpl->form_create('?page=cluster&action=location_network_edit&id=' . $locnet->id, 'post');
    api_update_form($locnet);
    $xtpl->form_out(_('Save'));
}

function ip_add_form($ip_addresses = '')
{
    global $xtpl, $api;

    if (!$ip_addresses && $_POST['ip_addresses']) {
        $ip_addresses = $_POST['ip_addresses'];
    }

    $xtpl->table_title(_("Add IP addresses"));
    $xtpl->sbar_add(_("Back"), '?page=cluster&action=ip_addresses');

    $xtpl->form_create('?page=cluster&action=ipaddr_add2', 'post');
    $xtpl->form_add_textarea(_("IP addresses") . ':', 40, 10, 'ip_addresses', $ip_addresses);
    $xtpl->form_add_select(
        _("Network") . ':',
        'network',
        resource_list_to_options(
            $api->network->list(),
            'id',
            'label',
            true,
            'network_label'
        ),
        $_POST['network']
    );
    $xtpl->form_add_select(
        _("User") . ':',
        'user',
        resource_list_to_options($api->user->list(), 'id', 'login'),
        $_POST['user']
    );

    $xtpl->form_out(_("Add"));
}

function ip_edit_form($id)
{
    global $xtpl, $api;

    $ip = $api->ip_address->show($id, ['meta' => ['includes' => 'network']]);

    $xtpl->table_title($ip->addr . '/' . $ip->network->prefix);
    $xtpl->sbar_add(
        _("Back"),
        $_GET['return'] ? $_GET['return'] : '?page=cluster&action=ip_addresses'
    );

    $xtpl->form_create(
        '?page=cluster&action=ipaddr_edit_user&id=' . $ip->id . '&return=' . urlencode($_GET['return']),
        'post'
    );

    $xtpl->table_add_category(_('Owner'));
    $xtpl->table_add_category('');

    $xtpl->form_add_input(_('User ID') . ':', 'text', '30', 'user', post_val('user', $ip->user_id));
    $xtpl->form_add_select(
        _('Environment') . ':',
        'environment',
        resource_list_to_options($api->environment->list()),
        post_val('environment')
    );

    $xtpl->form_out(_("Set owner"));
}

function dns_delete_form()
{
    global $xtpl, $api;

    $ns = $api->dns_resolver->find($_GET['id']);

    $xtpl->table_title(_("Delete DNS resolver") . ' ' . $ns->label . ' (' . $ns->ip_addr . ')');
    $xtpl->form_create('?page=cluster&action=dns_delete&id=' . $_GET['id'], 'post');

    api_params_to_form($api->dns_resolver->delete, 'input');

    $xtpl->form_out(_("Delete"));
}

function os_template_edit_form()
{
    global $xtpl, $api;

    $t = $api->os_template->find($_GET['id']);

    $xtpl->title2(_("Edit template") . ' ' . $t->label);

    $xtpl->table_add_category('');
    $xtpl->table_add_category('');

    $xtpl->form_create('?page=cluster&action=templates_edit&id=' . $t->id, 'post');
    api_update_form($t);
    $xtpl->form_out(_("Save changes"));

    $xtpl->sbar_add(_("Back"), '?page=cluster&action=templates');
}

function os_template_add_form()
{
    global $xtpl, $api;

    $xtpl->title2(_("Register new template"));
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');

    $xtpl->form_create('?page=cluster&action=template_register', 'post');
    api_create_form($api->os_template);
    $xtpl->form_out(_("Register"));

    $xtpl->sbar_add(_("Back"), '?page=cluster&action=templates');
}

function node_create_form()
{
    global $xtpl, $api;

    $xtpl->title2(_("Register new server into cluster"));
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');
    $xtpl->form_create('?page=cluster&action=newnode_save', 'post');

    api_create_form($api->node);

    $xtpl->form_out(_("Register"));
}

function node_update_form($id)
{
    global $xtpl, $api;

    $node = $api->node->show($id);

    $xtpl->title2(_("Edit node"));
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');
    $xtpl->form_create('?page=cluster&action=node_edit_save&node_id=' . $node->id, 'post');

    api_update_form($node);

    $xtpl->form_out(_("Save"));
}

function system_config_form()
{
    global $xtpl, $api;

    $xtpl->title2(_("System config"));
    $xtpl->form_create('?page=cluster&action=sysconfig_save', 'post');

    $options = $api->system_config->index();
    $last_cat = null;

    foreach ($options as $opt) {
        if ($last_cat === null || $last_cat != $opt->category) {
            $xtpl->table_td($opt->category, '#5EAFFF; color:#FFF; font-weight:bold;', false, 2);
            $xtpl->table_tr();
            $last_cat = $opt->category;
        }

        $xtpl->table_td(
            ($opt->label ? $opt->label : $opt->name) . ':',
            false,
            false,
            '1',
            $opt->description ? '2' : '1'
        );

        $name = $opt->category . ':' . $opt->name;
        $value = $_POST[$name] ?? $opt->value;

        switch ($opt->type) {
            case 'String':
                $xtpl->form_add_input_pure('text', '70', $name, $value);
                break;

            case 'Text':
            case 'Custom':
            case 'Hash':
            case 'Array':
                $xtpl->form_add_textarea_pure('70', '15', $name, $value);
                break;

            case 'Integer':
            case 'Float':
                $xtpl->form_add_number_pure($name, $value);
                break;

            case 'Boolean':
                $xtpl->form_add_checkbox_pure($name, '1', $value ? true : false);
                break;
        }

        $xtpl->table_tr();

        if ($opt->description) {
            $xtpl->table_td($opt->description);
            $xtpl->table_tr();
        }
    }

    $xtpl->form_out(_("Save changes"));
}

function news_list_and_create_form()
{
    global $xtpl, $api;

    $xtpl->table_title(_("News Log"));
    $xtpl->table_add_category('Add entry');
    $xtpl->table_add_category('');
    $xtpl->form_create('?page=cluster&action=log_add', 'post');
    $xtpl->form_add_input(_("Date and time") . ':', 'text', '30', 'published_at', post_val('published_at', strftime("%Y-%m-%d %H:%M")));
    $xtpl->form_add_textarea(_("Message") . ':', 80, 5, 'message', post_val('message'));
    $xtpl->form_out(_("Add"));

    $xtpl->table_add_category(_('Date and time'));
    $xtpl->table_add_category(_('Message'));
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');

    foreach ($api->news_log->list() as $news) {
        $xtpl->table_td(tolocaltz($news->published_at, "Y-m-d H:i"));
        $xtpl->table_td($news->message);
        $xtpl->table_td('<a href="?page=cluster&action=log_edit&id=' . $news->id . '" title="' . _("Edit") . '"><img src="template/icons/edit.png" title="' . _("Edit") . '"></a>');
        $xtpl->table_td('<a href="?page=cluster&action=log_del&id=' . $news->id . '&t=' . csrf_token() . '" title="' . _("Delete") . '"><img src="template/icons/delete.png" title="' . _("Delete") . '"></a>');
        $xtpl->table_tr();
    }

    $xtpl->table_out();
}

function news_edit_form($id)
{
    global $xtpl, $api;

    $news = $api->news_log->show($_GET['id']);

    $xtpl->form_create('?page=cluster&action=log_edit_save&id=' . $news->id, 'post');
    $xtpl->form_add_input(_("Date and time") . ':', 'text', '30', 'published_at', post_val('published_at', tolocaltz($news->published_at, 'Y-m-d H:i')));
    $xtpl->form_add_textarea(_("Message") . ':', 80, 5, 'message', $news->message);
    $xtpl->form_out(_("Update"));
}

function helpbox_list_and_create_form()
{
    global $xtpl, $api;

    $xtpl->table_title(_("Help boxes"));

    $xtpl->table_add_category('');
    $xtpl->table_add_category('');
    $xtpl->form_create('?page=cluster&action=helpboxes_add', 'post');
    $xtpl->form_add_input(_("Page") . ':', 'text', '30', 'page', post_val('page', $_GET["help_page"]));
    $xtpl->form_add_input(_("Action") . ':', 'text', '30', 'action', post_val('action', $_GET["help_action"]));
    $xtpl->form_add_select(_("Language") . ':', 'language', resource_list_to_options($api->language->list()), post_val('language'));
    $xtpl->form_add_textarea(_("Content") . ':', 80, 15, 'content', post_val('content'));
    $xtpl->form_out(_("Add"));

    $xtpl->table_add_category(_("Page"));
    $xtpl->table_add_category(_("Action"));
    $xtpl->table_add_category(_("Language"));
    $xtpl->table_add_category(_("Content"));
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');

    $boxes = $api->help_box->list([
        'meta' => ['includes' => 'language'],
    ]);

    foreach ($boxes as $box) {
        $xtpl->table_td($box->page);
        $xtpl->table_td($box->action);
        $xtpl->table_td($box->language_id ? $box->language->label : _('All'));
        $xtpl->table_td($box->content);
        $xtpl->table_td('<a href="?page=cluster&action=helpboxes_edit&id=' . $box->id . '" title="' . _("Edit") . '"><img src="template/icons/edit.png" title="' . _("Edit") . '"></a>');
        $xtpl->table_td('<a href="?page=cluster&action=helpboxes_del&id=' . $box->id . '&t=' . csrf_token() . '" title="' . _("Delete") . '"><img src="template/icons/delete.png" title="' . _("Delete") . '"></a>');
        $xtpl->table_tr();
    }

    $xtpl->table_out();
}

function helpbox_edit_form($id)
{
    global $xtpl, $api;

    $box = $api->help_box->show($id);

    $xtpl->form_create('?page=cluster&action=helpboxes_edit_save&id=' . $box->id, 'post');
    $xtpl->form_add_input(_("Page") . ':', 'text', '30', 'page', post_val('page', $box->page));
    $xtpl->form_add_input(_("Action") . ':', 'text', '30', 'action', post_val('action', $box->action));
    $xtpl->form_add_select(_("Language") . ':', 'language', resource_list_to_options($api->language->list()), post_val('language', $box->language_id));
    $xtpl->form_add_textarea(_("Content") . ':', 80, 15, 'content', post_val('content', $box->content));
    $xtpl->form_out(_("Update"));
}

function resource_packages_list()
{
    global $xtpl, $api;

    $xtpl->title(_('Cluster resource packages'));
    $xtpl->table_add_category(_('Package'));
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');

    $pkgs = $api->cluster_resource_package->list(['user' => null]);

    foreach ($pkgs as $pkg) {
        $xtpl->table_td($pkg->label);
        $xtpl->table_td('<a href="?page=cluster&action=resource_packages_edit&id=' . $pkg->id . '" title="' . _("Edit") . '"><img src="template/icons/edit.png" title="' . _("Edit") . '"></a>');
        $xtpl->table_td('<a href="?page=cluster&action=resource_packages_delete&id=' . $pkg->id . '&t=' . csrf_token() . '" title="' . _("Delete") . '"><img src="template/icons/delete.png" title="' . _("Delete") . '"></a>');
        $xtpl->table_tr();
    }

    $xtpl->table_out();

    $xtpl->sbar_add(_("Back"), '?page=cluster');
    $xtpl->sbar_add(_("New package"), '?page=cluster&action=resource_packages_new');
}

function resource_packages_create_form()
{
    global $xtpl, $api;

    $xtpl->title(_('Create a new cluster resource package'));
    $xtpl->form_create('?page=cluster&action=resource_packages_new');
    api_param_to_form(
        'label',
        $api->cluster_resource_package->create->getParameters('input')->label
    );
    $xtpl->form_out(_('Create'));

    $xtpl->sbar_add(_("Back"), '?page=cluster&action=resource_packages');
}

function resource_packages_edit_form($pkg_id)
{
    global $xtpl, $api;

    $pkg = $api->cluster_resource_package->show($pkg_id);

    $xtpl->title(_('Edit cluster resource package'));
    $xtpl->form_create('?page=cluster&action=resource_packages_edit&id=' . $pkg->id, 'post');

    if ($pkg->user_id) {
        $xtpl->table_td(_('User') . ':');
        $xtpl->table_td(user_link($pkg->user));
        $xtpl->table_tr();

        $xtpl->table_td(_('Environment') . ':');
        $xtpl->table_td($pkg->environment->label);
        $xtpl->table_tr();
    }

    api_param_to_form(
        'label',
        $api->cluster_resource_package->create->getParameters('input')->label,
        $pkg->label
    );
    $xtpl->form_out(_('Update'));

    $xtpl->table_title(_('Cluster resources'));
    $xtpl->table_add_category(_("Resource"));
    $xtpl->table_add_category(_("Value"));
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');

    $items = $pkg->item->list(['meta' => ['includes' => 'cluster_resource']]);

    foreach ($items as $it) {
        $xtpl->table_td($it->cluster_resource->label);
        $xtpl->table_td($it->value);
        $xtpl->table_td('<a href="?page=cluster&action=resource_packages_item_edit&id=' . $pkg->id . '&item=' . $it->id . '"><img src="template/icons/m_edit.png"  title="' . _("Edit") . '"></a>');
        $xtpl->table_td('<a href="?page=cluster&action=resource_packages_item_delete&id=' . $pkg->id . '&item=' . $it->id . '"><img src="template/icons/delete.png"  title="' . _("Delete") . '"></a>');
        $xtpl->table_tr();
    }

    $desc = $pkg->item->create->getParameters('input');

    $xtpl->table_out();

    $xtpl->table_title(_('Add resource'));
    $xtpl->form_create('?page=cluster&action=resource_packages_item_add&id=' . $pkg->id, 'post');
    api_param_to_form('cluster_resource', $desc->cluster_resource);
    api_param_to_form('value', $desc->value);
    $xtpl->form_out(_('Add'));

    if ($pkg->user_id) {
        $xtpl->sbar_add(_("Back"), '?page=adminm&action=resource_packages&id=' . $pkg->user_id);
    } else {
        $xtpl->sbar_add(_("Back"), '?page=cluster&action=resource_packages');
    }
}

function resource_packages_delete_form($pkg_id)
{
    global $xtpl, $api;

    $pkg = $api->cluster_resource_package->show($pkg_id);

    $xtpl->title(_('Remove cluster resource package'));
    $xtpl->form_create('?page=cluster&action=resource_packages_delete&id=' . $pkg_id, 'post');

    $xtpl->table_td(_('Package') . ':');
    $xtpl->table_td($pkg->label);
    $xtpl->table_tr();

    $xtpl->table_td(
        _('<b>Warning:</b> The package will also be immediately removed from ' .
        'all users that are using it.'),
        false,
        false,
        '2'
    );
    $xtpl->table_tr();

    $xtpl->form_add_checkbox(_('Confirm') . ':', 'confirm', '1', false);

    $xtpl->form_out(_('Remove'));

    $xtpl->sbar_add(_("Back"), '?page=cluster&action=resource_packages');
}

function resource_packages_item_edit_form($pkg_id, $item_id)
{
    global $xtpl, $api;

    $pkg = $api->cluster_resource_package->show($pkg_id);
    $it = $pkg->item->show($item_id);

    $xtpl->title(_('Edit cluster resource package item'));
    $xtpl->form_create('?page=cluster&action=resource_packages_item_edit&id=' . $pkg_id . '&item=' . $item_id, 'post');

    $xtpl->table_td(_('Package') . ':');
    $xtpl->table_td($pkg->label);
    $xtpl->table_tr();

    $xtpl->table_td(_('Resource') . ':');
    $xtpl->table_td($it->cluster_resource->label);
    $xtpl->table_tr();

    $xtpl->table_td(_('Value') . ':');
    $xtpl->form_add_number_pure(
        'value',
        $it->value,
        0,
        0,
        $it->cluster_resource->stepsize,
        unit_for_cluster_resource($it->cluster_resource->name)
    );
    $xtpl->table_tr();

    $xtpl->form_out(_('Save'));

    $xtpl->sbar_add(_("Back"), '?page=cluster&action=resource_packages_edit&id=' . $pkg_id);
}

function resource_packages_item_delete_form($pkg_id, $item_id)
{
    global $xtpl, $api;

    $pkg = $api->cluster_resource_package->show($pkg_id);
    $it = $pkg->item->show($item_id);

    $xtpl->title(_('Remove cluster resource package item'));
    $xtpl->form_create('?page=cluster&action=resource_packages_item_delete&id=' . $pkg_id . '&item=' . $item_id, 'post');

    $xtpl->table_td(_('Package') . ':');
    $xtpl->table_td($pkg->label);
    $xtpl->table_tr();

    $xtpl->table_td(_('Resource') . ':');
    $xtpl->table_td($it->cluster_resource->label);
    $xtpl->table_tr();

    $xtpl->table_td(_('Value') . ':');
    $xtpl->table_td($it->value);
    $xtpl->table_tr();

    $xtpl->table_td(
        _('<b>Warning:</b> The resource will also be immediately removed from ' .
        'all users having this package.'),
        false,
        false,
        '2'
    );
    $xtpl->table_tr();

    $xtpl->form_add_checkbox(_('Confirm') . ':', 'confirm', '1', false);

    $xtpl->form_out(_('Remove'));

    $xtpl->sbar_add(_("Back"), '?page=cluster&action=resource_packages_edit&id=' . $pkg_id);
}
