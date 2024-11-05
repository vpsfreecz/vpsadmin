<?php

$DATASET_PROPERTIES = ['compression', 'recordsize', 'atime', 'relatime', 'sync'];
$DATASET_UNITS_TR = ["m" => 1, "g" => 1024, "t" => 1024 * 1024];

function is_mount_dst_valid($dst)
{
    $dst = trim($dst);

    if(!preg_match("/^[a-zA-Z0-9\_\-\/\.]+$/", $dst) || preg_match("/\.\./", $dst)) {
        return false;
    }

    if (strpos($dst, "/") !== 0) {
        $dst = "/" . $dst;
    }

    return $dst;
}

function is_ds_valid($p)
{
    $p = trim($p);

    if(preg_match("/^\//", $p)) {
        return false;
    }

    if(!preg_match("/^[a-zA-Z0-9\/\-\:\.\_]+$/", $p)) {
        return false;
    }

    if(preg_match("/\/\//", $p)) {
        return false;
    }

    return $p;
}

function dataset_list($role, $parent = null, $user = null, $dataset = null, $limit = null, $from_id = null, $opts = [])
{
    global $xtpl, $api;

    $params = $api->dataset->list->getParameters('output');
    $ignore = ['id', 'name', 'parent', 'user'];
    $include = [];

    if ($role == 'primary') {
        $include[] = 'used';
        $include[] = 'compressratio';
    } else {
        $include[] = 'referenced';
        $include[] = 'refcompressratio';
    }

    $include[] = 'avail';

    if ($role == 'primary') {
        $include[] = 'quota';
    } else {
        $include[] = 'refquota';
    }

    $colspan = ((isAdmin() || USERNS_PUBLIC) ? 7 : 6) + count($include);

    $xtpl->table_title($opts['title'] ?? _('Datasets'));

    if (isAdmin()) {
        $xtpl->table_add_category('#');
    }

    $xtpl->table_add_category(_('Dataset'));

    foreach ($include as $name) {
        $xtpl->table_add_category($params->{$name}->label);
    }

    if ($role == 'hypervisor') {
        $xtpl->table_add_category(_('Mount'));
    }

    if ($role == 'primary' && isExportPublic()) {
        $xtpl->table_add_category(_('Export'));
    }

    $xtpl->table_add_category('');
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');

    $listParams = [
        'role' => $role,
        'dataset' => $parent,
    ];

    if ($user) {
        $listParams['user'] = $user;
    }

    if ($dataset) {
        $listParams['dataset'] = $dataset;
    }

    if ($limit) {
        $listParams['limit'] = $limit;
    }

    if ($from_id) {
        $listParams['from_id'] = $from_id;
    }

    $datasets = $api->dataset->list($listParams);
    $return = urlencode($_SERVER['REQUEST_URI']);

    foreach ($datasets as $ds) {
        if (isAdmin()) {
            $xtpl->table_td(
                '<a href="?page=nas&action=list&dataset=' . $ds->id . '">' . $ds->id . '</a>'
            );
        }

        $xtpl->table_td($ds->name);

        foreach ($include as $name) {
            $desc = $params->{$name};
            $showValue = '';

            if ($name == 'refquota' && $ds->dataset_expansion_id) {
                $showValue .= '<img src="template/icons/warning.png" title="' . _('Dataset temporarily expanded') . '"> ';
            }

            if ($name == 'compressratio' || $name == 'refcompressratio') {
                $showValue .= compressRatioWithUsedSpace($ds, $name);
            } elseif ($desc->type == 'Integer') {
                $showValue .= data_size_to_humanreadable($ds->{$name});
            } else {
                $showValue .= $ds->{$name};
            }

            $xtpl->table_td($showValue);
        }

        if ($role == 'hypervisor') {
            $xtpl->table_td('<a href="?page=dataset&action=mount&dataset=' . $ds->id . '&vps=' . $_GET['veid'] . '&return=' . $return . '">' . _('Mount') . '</a>');
        }

        if ($role == 'primary' && isExportPublic()) {
            if ($ds->export_id) {
                $xtpl->table_td('<a href="?page=export&action=edit&export=' . $ds->export_id . '">' . _('exported') . '</a>');
            } else {
                $xtpl->table_td('<a href="?page=export&action=create&dataset=' . $ds->id . '">' . _('Export') . '</a>');
            }
        }

        $xtpl->table_td('<a href="?page=dataset&action=new&role=' . $role . '&parent=' . $ds->id . '&return=' . $return . '"><img src="template/icons/vps_add.png" title="' . _("Create a subdataset") . '"></a>');
        $xtpl->table_td('<a href="?page=dataset&action=edit&role=' . $role . '&id=' . $ds->id . '&return=' . $return . '"><img src="template/icons/edit.png" title="' . _("Edit") . '"></a>');
        $xtpl->table_td('<a href="?page=dataset&action=destroy&id=' . $ds->id . '&return=' . $return . '"><img src="template/icons/delete.png" title="' . _("Delete") . '"></a>');

        $xtpl->table_tr();
    }

    $xtpl->table_td(
        '<a href="?page=dataset&action=new&role=' . $role . '&parent=' . $parent . '&return=' . $return . '">' . _('Create a new dataset') . '</a>',
        false,
        true, // right
        $colspan // colspan
    );
    $xtpl->table_tr();

    $xtpl->table_out();

    if ($opts['submenu'] ?? null !== false) {
        $xtpl->sbar_add(_('Create dataset'), '?page=dataset&action=new&role=' . $role . '&parent=' . $parent . '&return=' . urlencode($_SERVER['REQUEST_URI']));
    }
}

function dataset_create_form()
{
    global $xtpl, $api, $DATASET_PROPERTIES;

    include_dataset_scripts();

    $params = $api->dataset->create->getParameters('input');
    $quota_name = $_GET['role'] == 'hypervisor' ? 'refquota' : 'quota';

    if ($_GET['parent']) {
        $ds = $api->dataset->find($_GET['parent']);
        $xtpl->table_title(_('Create a new subdataset in') . ' ' . $ds->name);

    } else {
        $xtpl->table_title(_('Create a new dataset'));
    }

    $xtpl->form_create('?page=dataset&action=new&role=' . $_GET['role'] . '&parent=' . $_GET['parent'], 'post');

    if ($_GET['parent']) {
        $ds = $api->dataset->find($_GET['parent']);

        $xtpl->table_td($params->dataset->label);
        $xtpl->table_td($ds->name);
        $xtpl->table_tr();

    } else {
        $xtpl->form_add_select(
            $params->dataset->label,
            'dataset',
            resource_list_to_options($api->dataset->list(['role' => $_GET['role']]), 'id', 'name'),
            $_POST['dataset'],
            $params->dataset->description
        );
    }

    $xtpl->form_add_input(
        _('Name'),
        'text',
        '30',
        'name',
        $_POST['name'],
        _('Do not prefix with VPS ID. Allowed characters: a-z A-Z 0-9 _ : .<br>'
        . 'Use / as a separator to create subdatasets. Max length 254 chars.')
    );
    $xtpl->form_add_checkbox(_("Auto mount"), 'automount', '1', true, $params->automount->description);

    // Quota
    $quota = $params->{$quota_name};

    if (!$_POST[$quota_name]) {
        $v = data_size_unitize(
            ($_POST[$quota_name] ? $_POST[$quota_name] : $quota->default) * 1024 * 1024
        );
    }

    $xtpl->table_td(
        $quota->label . ' ' .
        '<input type="hidden" name="return" value="' . ($_GET['return'] ? $_GET['return'] : $_POST['return']) . '">'
    );
    $xtpl->form_add_input_pure('text', '30', $quota_name, $_POST[$quota_name] ? $_POST[$quota_name] : $v[0], $quota->description);
    $xtpl->form_add_select_pure('quota_unit', ["g" => "GiB", "t" => "TiB"], $_POST[$quota_name] ? $_POST['quota_unit'] : $v[1]);
    $xtpl->table_tr();

    // Remaining dataset properties
    foreach ($DATASET_PROPERTIES as $name) {
        if ($name != 'quota' && $name != 'refquota') {
            $inherit = $params->{$name}->label . '<br>'
            . '<input type="checkbox" name="inherit_' . $name . '" value="1" checked> '
            . _('Inherit');
        } else {
            $inherit = $params->{$name}->label;
        }

        $xtpl->table_td($inherit);
        api_param_to_form_pure($name, $params->{$name});
        $xtpl->table_td($params->{$name}->description);

        $xtpl->table_tr(false, 'advanced-property');
    }

    $xtpl->form_out(_('Save'), null, '<span class="advanced-property-toggle"></span>');

    $xtpl->sbar_add(_("Back"), $_GET['return'] ? $_GET['return'] : $_POST['return']);
    $xtpl->sbar_out(_('Dataset'));
}

function dataset_edit_form()
{
    global $xtpl, $api, $DATASET_PROPERTIES;

    include_dataset_scripts();

    $ds = $api->dataset->find($_GET['id']);

    $params = $api->dataset->update->getParameters('input');
    $quota_name = $_GET['role'] == 'hypervisor' ? 'refquota' : 'quota';

    $xtpl->table_title(_('Edit dataset') . ' ' . $ds->name);
    $xtpl->form_create('?page=dataset&action=edit&role=' . $_GET['role'] . '&id=' . $ds->id, 'post');

    if (isAdmin()) {
        $xtpl->table_td(_('Used space') . ':');
        $xtpl->table_td(usedSpaceWithCompression($ds, 'used'));
        $xtpl->table_tr();

        $xtpl->table_td(_('Referenced space') . ':');
        $xtpl->table_td(usedSpaceWithCompression($ds, 'referenced'));
        $xtpl->table_tr();
    } else {
        $xtpl->table_td(_('Used space') . ':');
        $xtpl->table_td(usedSpaceWithCompression($ds, 'used'));
        $xtpl->table_tr();
    }

    // Quota
    $quota = $params->{$quota_name};

    if (!$_POST[$quota_name]) {
        $v = data_size_unitize($ds->{$quota_name} * 1024 * 1024);
    }

    $xtpl->table_td(
        $quota->label . ' ' .
        '<input type="hidden" name="return" value="' . ($_GET['return'] ? $_GET['return'] : $_POST['return']) . '">'
    );
    $xtpl->form_add_input_pure('text', '30', $quota_name, $_POST[$quota_name] ? $_POST[$quota_name] : $v[0], $quota->description);
    $xtpl->form_add_select_pure('quota_unit', ["g" => "GiB", "t" => "TiB"], $_POST[$quota_name] ? $_POST['quota_unit'] : $v[1]);
    $xtpl->table_tr();

    if (isAdmin()) {
        api_param_to_form('admin_override', $params->admin_override);
        api_param_to_form('admin_lock_type', $params->admin_lock_type);
    }

    // Remaining dataset properties
    foreach ($DATASET_PROPERTIES as $name) {
        if ($name != 'quota' && $name != 'refquota') {
            $inherit = $params->{$name}->label . '<br>'
            . '<input type="checkbox" name="inherit_' . $name . '" value="1" ' . ($ds->{$name} == $params->{$name}->default ? 'checked' : 'disabled') . '> '
            . _('Inherit');
        } else {
            $inherit = $params->{$name}->label;
        }

        $xtpl->table_td($inherit);
        api_param_to_form_pure($name, $params->{$name}, $ds->{$name});
        $xtpl->table_td($params->{$name}->description);

        $xtpl->table_tr(false, 'advanced-property');
    }

    $xtpl->form_out(_('Save'), null, '<span class="advanced-property-toggle"></span>');

    if ($ds->dataset_expansion_id) {
        $exp = $ds->dataset_expansion;

        $xtpl->table_title(_('Temporary dataset expansion'));

        if (isAdmin()) {
            $xtpl->form_create('?page=dataset&action=edit_expansion&role=' . $_GET['role'] . '&id=' . $ds->id . '&expansion=' . $exp->id, 'post');

            $xtpl->form_set_hidden_fields([
                'return' => $_GET['return'] ?? $_POST['return'],
            ]);
        }

        $xtpl->table_td(_('Expanded at') . ':');
        $xtpl->table_td(tolocaltz($exp->created_at));
        $xtpl->table_tr();

        $xtpl->table_td(_('Original refquota') . ':');
        $xtpl->table_td(data_size_to_humanreadable($exp->original_refquota));
        $xtpl->table_tr();

        $xtpl->table_td(_('Added space') . ':');
        $xtpl->table_td(data_size_to_humanreadable($exp->added_space));
        $xtpl->table_tr();

        $xtpl->table_td(_('Number of days over refquota') . ':');
        $xtpl->table_td(round($exp->over_refquota_seconds / 60 / 60 / 24, 1));
        $xtpl->table_tr();

        if (isAdmin()) {
            $updateInput = $exp->update->getParameters('input');

            $xtpl->form_add_number(_('Max days over refquota') . ':', 'max_over_refquota_days', post_val('max_over_refquota_days', round($exp->max_over_refquota_seconds / 60 / 60 / 24)));
            api_param_to_form('enable_notifications', $updateInput->enable_notifications, $exp->enable_notifications);
            api_param_to_form('enable_shrink', $updateInput->enable_shrink, $exp->enable_shrink);
            api_param_to_form('stop_vps', $updateInput->stop_vps, $exp->stop_vps);

            $xtpl->form_out(_('Save'));
        } else {
            $xtpl->table_td(_('Max number of days over refquota') . ':');
            $xtpl->table_td(round($exp->max_over_refquota_seconds / 60 / 60 / 24));
            $xtpl->table_tr();

            $xtpl->table_out();
        }

        $xtpl->table_add_category(_('Date'));
        $xtpl->table_add_category(_('Original refquota'));
        $xtpl->table_add_category(_('New refquota'));
        $xtpl->table_add_category(_('Added space'));

        if (isAdmin()) {
            $xtpl->table_add_category(_('Added by'));
        }

        foreach ($exp->history->list() as $hist) {
            $xtpl->table_td(tolocaltz($hist->created_at));
            $xtpl->table_td(data_size_to_humanreadable($hist->original_refquota));
            $xtpl->table_td(data_size_to_humanreadable($hist->new_refquota));
            $xtpl->table_td(data_size_to_humanreadable($hist->added_space));

            if (isAdmin()) {
                $xtpl->table_td($hist->admin_id ? user_link($hist->admin) : 'nodectld');
            }

            $xtpl->table_tr();
        }

        $xtpl->table_out();

        if (isAdmin()) {
            $xtpl->form_create('?page=dataset&action=expand_add_space&role=' . $_GET['role'] . '&id=' . $ds->id . '&expansion=' . $exp->id, 'post');

            $xtpl->form_set_hidden_fields([
                'return' => $_GET['return'] ?? $_POST['return'],
            ]);

            $xtpl->table_td(_('Add space') . ':');
            $xtpl->form_add_number_pure('added_space', post_val('added_space', '20'));
            $xtpl->form_add_select_pure('unit', ["m" => "MiB", "g" => "GiB", "t" => "TiB"], post_val('unit', 'g'));
            $xtpl->table_tr();

            $xtpl->form_out(_('Add space'));
        }

    } elseif (isAdmin() && $_GET['role'] == 'hypervisor') {
        $xtpl->table_title(_('Temporarily expand dataset'));

        $xtpl->form_create('?page=dataset&action=add_expansion&role=' . $_GET['role'] . '&id=' . $ds->id, 'post');

        $xtpl->form_set_hidden_fields([
            'return' => $_GET['return'] ?? $_POST['return'],
        ]);

        $newInput = $api->dataset_expansion->create->getParameters('input');

        $xtpl->table_td(_('Add space') . ':');
        $xtpl->form_add_number_pure('added_space', post_val('added_space', '20'));
        $xtpl->form_add_select_pure('unit', ["m" => "MiB", "g" => "GiB", "t" => "TiB"], post_val('unit', 'g'));
        $xtpl->table_tr();

        $xtpl->form_add_number(_('Max number of days over refquota') . ':', 'max_over_refquota_days', post_val('max_over_refquota_days', 30));
        api_param_to_form('enable_notifications', $newInput->enable_notifications, true);
        api_param_to_form('enable_shrink', $newInput->enable_shrink, true);
        api_param_to_form('stop_vps', $newInput->stop_vps, true);

        $xtpl->form_out(_('Expand'));

        $xtpl->table_title(_('Register existing expansion'));

        $xtpl->form_create('?page=dataset&action=register_expansion&role=' . $_GET['role'] . '&id=' . $ds->id, 'post');

        $xtpl->form_set_hidden_fields([
            'return' => $_GET['return'] ?? $_POST['return'],
        ]);

        $addInput = $api->dataset_expansion->register_expanded->getParameters('input');

        $xtpl->table_td(_('Original refquota') . ':');
        $xtpl->form_add_number_pure('original_refquota', post_val('original_refquota', '120'));
        $xtpl->form_add_select_pure('unit', ["m" => "MiB", "g" => "GiB", "t" => "TiB"], post_val('unit', 'g'));
        $xtpl->table_tr();

        $xtpl->form_add_number(_('Max number of days over refquota') . ':', 'max_over_refquota_days', post_val('max_over_refquota_days', 30));
        api_param_to_form('enable_notifications', $addInput->enable_notifications, true);
        api_param_to_form('enable_shrink', $addInput->enable_shrink, true);
        api_param_to_form('stop_vps', $addInput->stop_vps, true);

        $xtpl->form_out(_('Register'));
    }

    $xtpl->table_title(_('Backup plans'));

    $plans = $ds->plan->list();

    $xtpl->form_create('?page=dataset&action=plan_add&role=' . $_GET['role'] . '&id=' . $ds->id, 'post');
    $xtpl->table_add_category(_('Label'));
    $xtpl->table_add_category(_('Description'));
    $xtpl->table_add_category('');

    foreach ($plans as $plan) {
        $xtpl->table_td($plan->environment_dataset_plan->label);
        $xtpl->table_td($plan->environment_dataset_plan->dataset_plan->description);
        $xtpl->table_td('<a href="?page=dataset&action=plan_delete&id=' . $ds->id . '&plan=' . $plan->id . '&return=' . urlencode($_GET['return'] ? $_GET['return'] : $_POST['return']) . '&t=' . csrf_token() . '"><img src="template/icons/delete.png" title="' . _("Delete") . '"></a>');
        $xtpl->table_tr();
    }

    $xtpl->table_td(
        _('Add backup plan') . ':' . ' ' .
        '<input type="hidden" name="return" value="' . ($_GET['return'] ? $_GET['return'] : $_POST['return']) . '">'
    );
    $xtpl->form_add_select_pure('environment_dataset_plan', resource_list_to_options($ds->environment->dataset_plan->list()));
    $xtpl->table_td('');
    $xtpl->table_tr();

    $xtpl->form_out(_('Add'));

    $xtpl->sbar_add(_("Back"), $_GET['return'] ? $_GET['return'] : $_POST['return']);
    $xtpl->sbar_out(_('Dataset'));
}

function dataset_snapshot_list($datasets, $vps = null)
{
    global $xtpl, $api;

    $return_url = urlencode($_SERVER['REQUEST_URI']);

    foreach ($datasets as $ds) {
        $snapshots = $ds->snapshot->list(['meta' => ['includes' => 'mount']]);

        if (!$snapshots->count() && ($_GET['noempty'] ?? false)) {
            continue;
        }

        if ($vps && $ds->id == $vps->dataset_id) {
            $xtpl->table_title(_('VPS') . ' #' . $vps->id . ' ' . $vps->hostname);
        } else {
            $xtpl->table_title($ds->name);
        }

        $xtpl->table_add_category('<span title="' . _('History identifier') . '">[H]</span>');
        $xtpl->table_add_category(_('Date and time'));
        $xtpl->table_add_category(_('Label'));
        $xtpl->table_add_category(_('Restore'));
        $xtpl->table_add_category(_('Download'));

        if (isExportPublic()) {
            $xtpl->table_add_category(_('Export'));
        }

        if (!$vps) {
            $xtpl->table_add_category('');
        }

        $xtpl->form_create('?page=backup&action=restore&dataset=' . $ds->id . '&vps_id=' . ($vps ? $vps->id : '') . '&return=' . $return_url, 'post');

        $histories = [];
        foreach ($snapshots as $snap) {
            $histories[] = $snap->history_id;
        }
        $colors = colorize(array_unique($histories));

        foreach ($snapshots as $snap) {
            $xtpl->table_td($snap->history_id, '#' . $colors[ $snap->history_id ], true);
            $xtpl->table_td(tolocaltz($snap->created_at, 'Y-m-d H:i'));
            $xtpl->table_td($snap->label ? h($snap->label) : '-');
            $xtpl->form_add_radio_pure("restore_snapshot", $snap->id);
            $xtpl->table_td('[<a href="?page=backup&action=download&dataset=' . $ds->id . '&snapshot=' . $snap->id . '&return=' . $return_url . '">' . _("Download") . '</a>]');

            if (isExportPublic()) {
                if ($snap->export_id) {
                    $xtpl->table_td('[<a href="?page=export&action=edit&export=' . $snap->export_id . '">' . _('exported, can be mounted') . '</a>]');
                } else {
                    $xtpl->table_td('[<a href="?page=export&action=create&dataset=' . $ds->id . '&snapshot=' . $snap->id . '">' . _('Export to mount') . '</a>]');
                }
            }

            if (!$vps) {
                $xtpl->table_td('<a href="?page=backup&action=snapshot_destroy&dataset=' . $ds->id . '&snapshot=' . $snap->id . '&return=' . $return_url . '"><img src="template/icons/delete.png" title="' . _("Delete") . '"></a>');
            }

            $xtpl->table_tr();
        }

        $xtpl->table_td('<a href="?page=backup&action=snapshot&dataset=' . $ds->id . '&return=' . $return_url . '">' . _('Make a new snapshot') . '</a>', false, false, '2');
        $xtpl->table_td($xtpl->html_submit(_("Restore"), "restore"));
        $xtpl->table_tr();

        $xtpl->form_out_raw('ds-' . $ds->id);
    }
}

function mount_list($vps)
{
    global $xtpl, $api;

    $xtpl->table_title(_('Mounts'));

    $xtpl->table_add_category(_('Dataset'));
    $xtpl->table_add_category(_('Mountpoint'));
    $xtpl->table_add_category(_('On mount fail'));
    $xtpl->table_add_category(_('State'));
    $xtpl->table_add_category(_('Expiration'));
    $xtpl->table_add_category(_('Action'));
    $xtpl->table_add_category('');
    $xtpl->table_add_category('');

    $mounts = $vps->mount->list();
    $return = urlencode($_SERVER['REQUEST_URI']);

    foreach ($mounts as $m) {
        $xtpl->table_td($m->dataset->name);
        $xtpl->table_td(h($m->mountpoint));

        $xtpl->table_td(translate_mount_on_start_fail($m->on_start_fail));

        $state = '';

        switch ($m->current_state) {
            case 'created':
                $state = _('About to be mounted');
                break;

            case 'mounted':
                $state = _('Mounted');
                break;

            case 'unmounted':
                $state = _('Unmounted');
                break;

            case 'skipped':
                $state = _('Skipped');
                break;

            case 'delayed':
                $state = _('Trying to mount');
                break;

            case 'waiting':
                $state = _('Waiting for mount');
                break;

            default:
                $state = $m->current_state;
        }

        $xtpl->table_td($state);

        $xtpl->table_td($m->expiration_date ? tolocaltz($m->expiration_date, 'Y-m-d H:i') : '---');
        if ($m->master_enabled) {
            $xtpl->table_td(
                '<a href="?page=dataset&action=mount_toggle&vps=' . $vps->id . '&id=' . $m->id . '&do=' . ($m->enabled ? 0 : 1) . '&return=' . $return . '&t=' . csrf_token() . '">' .
                ($m->enabled ? _('Disable') : _('Enable')) .
                '</a>'
            );

        } else {
            $xtpl->table_td(_('Disabled by admin'));
        }

        $xtpl->table_td('<a href="?page=dataset&action=mount_edit&vps=' . $vps->id . '&id=' . $m->id . '&return=' . $return . '"><img src="template/icons/edit.png" title="' . _("Edit") . '"></a>');
        $xtpl->table_td('<a href="?page=dataset&action=mount_destroy&vps=' . $vps->id . '&id=' . $m->id . '&return=' . $return . '"><img src="template/icons/delete.png" title="' . _("Delete") . '"></a>');

        $color = false;

        if (!$m->enabled || !$m->master_enabled) {
            $color = '#A6A6A6';
        } elseif ($m->current_state != 'created' && $m->current_state != 'mounted') {
            $color = '#FFCCCC';
        }

        $xtpl->table_tr($color);
    }

    $xtpl->table_td(
        _('Mount a dataset from the list above.'),
        false,
        true, // right
        9 // colspan
    );
    $xtpl->table_tr();

    $xtpl->table_out();
}

function mount_create_form()
{
    global $xtpl, $api;

    $xtpl->table_title(_('Mount dataset'));
    $xtpl->form_create('?page=dataset&action=mount&vps=' . $_GET['vps'] . '&dataset=' . $_GET['dataset'], 'post');

    $params = $api->vps->mount->create->getParameters('input');

    $vps = $api->vps->find($_GET['vps']);

    $xtpl->table_td(_('Mount to VPS'));
    $xtpl->table_td($vps->id . ' <input type="hidden" name="vps" value="' . $vps->id . '">');
    $xtpl->table_tr();

    $ds = $api->dataset->find($_GET['dataset']);

    $xtpl->table_td(_('Mount dataset'));
    $xtpl->table_td($ds->name . ' <input type="hidden" name="dataset" value="' . $ds->id . '">');
    $xtpl->table_tr();

    $xtpl->table_td($params->mountpoint->label . ' <input type="hidden" name="return" value="' . ($_GET['return'] ? $_GET['return'] : $_POST['return']) . '">');
    api_param_to_form_pure('mountpoint', $params->mountpoint, '');
    $xtpl->table_tr();

    $xtpl->table_td($params->mode->label);
    api_param_to_form_pure('mode', $params->mode);
    $xtpl->table_tr();

    $xtpl->table_td($params->on_start_fail->label);
    api_param_to_form_pure(
        'on_start_fail',
        $params->on_start_fail,
        post_val('on_start_fail', 'mount_later'),
        'translate_mount_on_start_fail'
    );
    $xtpl->table_td($params->on_start_fail->description);
    $xtpl->table_tr();

    $xtpl->form_out(_('Save'));

    $xtpl->sbar_add(_("Back"), $_GET['return'] ? $_GET['return'] : $_POST['return']);
    $xtpl->sbar_out(_('Mount'));
}

function mount_edit_form($vps_id, $mnt_id)
{
    global $xtpl, $api;

    $vps = $api->vps->find($vps_id);
    $m = $vps->mount->find($mnt_id);
    $params = $api->vps->mount->create->getParameters('input');

    $xtpl->table_title(_('Edit mount of VPS') . ' ' . vps_link($vps) . ' at ' . $m->mountpoint);

    $xtpl->form_create('?page=dataset&action=mount_edit&vps=' . $vps_id . '&id=' . $mnt_id, 'post');

    $xtpl->table_td($params->on_start_fail->label . ' <input type="hidden" name="return" value="' . ($_GET['return'] ? $_GET['return'] : $_POST['return']) . '">');

    api_param_to_form_pure(
        'on_start_fail',
        $params->on_start_fail,
        post_val('on_start_fail', $m->on_start_fail),
        'translate_mount_on_start_fail'
    );
    $xtpl->table_td($params->on_start_fail->description);
    $xtpl->table_tr();

    $xtpl->form_out(_('Save'));

    $xtpl->sbar_add(_("Back"), $_GET['return'] ? $_GET['return'] : $_POST['return']);
    $xtpl->sbar_out(_('Mount'));
}

function translate_mount_on_start_fail($v)
{
    $start_fail_choices = [
        'skip' => _('Skip'),
        'mount_later' => _('Mount later'),
        'fail_start' => _('Fail VPS start'),
        'wait_for_mount' => _('Wait until mounted'),
    ];

    return $start_fail_choices[$v];
}

function include_dataset_scripts()
{
    global $xtpl;

    $xtpl->assign(
        'AJAX_SCRIPT',
        $xtpl->vars['AJAX_SCRIPT'] .
        '<script type="text/javascript" src="js/dataset.js"></script>'
    );
}
