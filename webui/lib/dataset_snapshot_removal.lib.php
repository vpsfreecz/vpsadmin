<?php

// Validate the complete Custom manifest before any review can be acknowledged.
// The API owns storage safety and the digest; the UI never constructs a delete set.
function dataset_snapshot_removal_validate($preview, int $dataset, array $options): array
{
    $invalid = static function () {
        throw new UnexpectedValueException(_('The snapshot inventory is incomplete or unsupported. Request a new preview.'));
    };
    $preview = json_decode(json_encode($preview, JSON_THROW_ON_ERROR), true, flags: JSON_THROW_ON_ERROR);
    if (!is_array($preview) || ($preview['manifest_version'] ?? null) !== 1
        || !is_string($preview['manifest_digest'] ?? null)
        || !preg_match('/\Av1:[a-f0-9]{64}\z/', $preview['manifest_digest'])
        || !is_array($preview['manifest'] ?? null)) {
        $invalid();
    }
    $m = $preview['manifest'];
    if (($m['root_dataset_id'] ?? null) !== $dataset || !is_array($m['options'] ?? null)
        || ($m['options']['recursive'] ?? null) !== $options['recursive']
        || ($m['options']['disable_plans'] ?? null) !== $options['disable_plans']) {
        $invalid();
    }
    $schemas = [
        'datasets' => ['id' => 'id', 'parent_id' => '?id', 'user_id' => 'id', 'name' => 'string', 'full_name' => 'string', 'current_history_id' => 'count'],
        'copies' => ['id' => 'id', 'dataset_id' => 'id', 'pool_id' => 'id', 'pool_label' => 'string', 'pool_role' => 'string', 'pool_filesystem' => 'string', 'pool_open' => 'bool', 'node_id' => 'id', 'node_name' => 'string'],
        'snapshot_locations' => ['snapshot_id' => 'id', 'snapshot_name' => 'string', 'snapshot_label' => '?string', 'created_at' => '?time', 'history_id' => 'count', 'dataset_in_pool_id' => 'id', 'snapshot_in_pool_id' => 'id', 'snapshot_in_pool_in_branch_id' => '?id', 'branch_id' => '?id', 'origin_snapshot_in_pool_in_branch_id' => '?id'],
        'trees' => ['id' => 'id', 'dataset_in_pool_id' => 'id', 'name' => 'string', 'head' => 'bool'],
        'branches' => ['id' => 'id', 'dataset_tree_id' => 'id', 'name' => 'string', 'head' => 'bool'],
        'plans' => ['id' => 'id', 'dataset_in_pool_id' => 'id', 'environment_dataset_plan_id' => 'id', 'dataset_plan_id' => 'id', 'name' => 'string', 'action' => 'string'],
    ];
    $index = [];
    foreach ($schemas as $collection => $schema) {
        if (!is_array($m[$collection] ?? null) || !array_is_list($m[$collection])) {
            $invalid();
        }
        $index[$collection] = [];
        foreach ($m[$collection] as $row) {
            if (!is_array($row)) {
                $invalid();
            }
            foreach ($schema as $key => $type) {
                if (!array_key_exists($key, $row)) {
                    $invalid();
                }
                $value = $row[$key];
                if ($type[0] === '?') {
                    if ($value === null) {
                        continue;
                    }
                    $type = substr($type, 1);
                }
                $valid = match ($type) {
                    'id' => is_int($value) && $value > 0,
                    'count' => is_int($value) && $value >= 0,
                    'bool' => is_bool($value),
                    'string' => is_string($value),
                    'time' => is_string($value) && preg_match('/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?(?:Z|\+00:00)\z/', $value),
                };
                if (!$valid) {
                    $invalid();
                }
            }
            if ($collection !== 'snapshot_locations') {
                if (isset($index[$collection][$row['id']])) {
                    $invalid();
                }
                $index[$collection][$row['id']] = $row;
            }
        }
    }
    if (!isset($index['datasets'][$dataset]) || (!$options['recursive'] && count($m['datasets']) !== 1)) {
        $invalid();
    }
    foreach ($m['copies'] as $copy) {
        if (!isset($index['datasets'][$copy['dataset_id']])
            || !in_array($copy['pool_role'], ['primary', 'hypervisor', 'backup'], true)) {
            $invalid();
        }
    }
    foreach ($m['datasets'] as $row) {
        $sources = array_filter($m['copies'], static fn($copy) => $copy['dataset_id'] === $row['id'] && $copy['pool_role'] !== 'backup');
        if (count($sources) !== 1) {
            $invalid();
        }
    }
    foreach ($m['trees'] as $tree) {
        if (!isset($index['copies'][$tree['dataset_in_pool_id']])
            || $index['copies'][$tree['dataset_in_pool_id']]['pool_role'] !== 'backup') {
            $invalid();
        }
    }
    foreach ($m['branches'] as $branch) {
        if (!isset($index['trees'][$branch['dataset_tree_id']])) {
            $invalid();
        }
    }
    $snapshots = $locations = $memberships = $snapshotCopies = [];
    foreach ($m['snapshot_locations'] as $row) {
        $copy = $index['copies'][$row['dataset_in_pool_id']] ?? null;
        if (!$copy) {
            $invalid();
        }
        $identity = [$copy['id'], $row['snapshot_id']];
        if (isset($snapshotCopies[$row['snapshot_in_pool_id']]) && $snapshotCopies[$row['snapshot_in_pool_id']] !== $identity) {
            $invalid();
        }
        $snapshotCopies[$row['snapshot_in_pool_id']] = $identity;
        if ($copy['pool_role'] === 'backup') {
            $branch = $index['branches'][$row['branch_id']] ?? null;
            if (!$branch || $row['snapshot_in_pool_in_branch_id'] === null
                || $index['trees'][$branch['dataset_tree_id']]['dataset_in_pool_id'] !== $copy['id']
                || isset($memberships[$row['snapshot_in_pool_in_branch_id']])) {
                $invalid();
            }
            $memberships[$row['snapshot_in_pool_in_branch_id']] = $row;
        } elseif ($row['branch_id'] !== null || $row['snapshot_in_pool_in_branch_id'] !== null
            || $row['origin_snapshot_in_pool_in_branch_id'] !== null) {
            $invalid();
        }
        $key = $copy['id'] . ':' . $row['snapshot_in_pool_id'] . ':' . ($row['snapshot_in_pool_in_branch_id'] ?? 0);
        if (isset($locations[$key])) {
            $invalid();
        }
        $locations[$key] = true;
        $snapshots[$row['snapshot_id']] = true;
    }
    foreach ($m['snapshot_locations'] as $row) {
        $origin = $row['origin_snapshot_in_pool_in_branch_id'];
        if ($origin !== null && (!isset($memberships[$origin])
            || $memberships[$origin]['dataset_in_pool_id'] !== $row['dataset_in_pool_id'])) {
            $invalid();
        }
    }
    foreach ($m['plans'] as $plan) {
        if (!isset($index['copies'][$plan['dataset_in_pool_id']])
            || $plan['action'] !== ($options['disable_plans'] ? 'remove' : 'retain')) {
            $invalid();
        }
    }
    $counts = ['snapshots' => count($snapshots), 'plans_to_disable' => $options['disable_plans'] ? count($m['plans']) : 0];
    foreach (array_keys($schemas) as $collection) {
        $counts[$collection] = count($m[$collection]);
    }
    foreach ($counts as $name => $count) {
        if (($m['counts'][$name] ?? null) !== $count) {
            $invalid();
        }
    }
    return $preview;
}

function dataset_snapshot_removal_available(): bool
{
    global $api;
    if (!isAdmin() || !$api->dataset->preview_snapshot_removal || !$api->dataset->remove_snapshots) {
        return false;
    }
    foreach (['preview_snapshot_removal', 'remove_snapshots'] as $name) {
        $action = $api->dataset->{$name};
        $input = $action->getParameters('input');
        if ($action->httpMethod() !== 'POST' || ($input->recursive->type ?? null) !== 'Boolean'
            || ($input->disable_plans->type ?? null) !== 'Boolean') {
            return false;
        }
    }
    $output = $api->dataset->preview_snapshot_removal->getParameters('output');
    return $api->dataset->preview_snapshot_removal->layout('output') === 'hash'
        && ($output->manifest_version->type ?? null) === 'Integer'
        && ($output->manifest_digest->type ?? null) === 'String'
        && ($output->manifest->type ?? null) === 'Custom'
        && ($api->dataset->remove_snapshots->getParameters('input')->manifest_digest->type ?? null) === 'String';
}

function dataset_snapshot_removal_url(int $dataset, string $return = ''): string
{
    return '?page=dataset&action=remove_snapshots&id=' . $dataset . '&return=' . rawurlencode(local_redirect_target($return, '?page=dataset&action=edit&role=hypervisor&id=' . $dataset));
}

function dataset_snapshot_removal_options(array $values): array
{
    $options = [];
    foreach (['recursive' => '0', 'disable_plans' => '1'] as $key => $default) {
        $value = $values[$key] ?? $default;
        if (!in_array($value, ['0', '1'], true)) {
            throw new InvalidArgumentException(_('Invalid form value.'));
        }
        $options[$key] = $value === '1';
    }
    return $options;
}

function dataset_snapshot_removal_context(): string
{
    return hash('sha256', (string) ($_SESSION['user']['id'] ?? '') . ':' . ($_SESSION['csrf_base'] ?? ''));
}

function dataset_snapshot_removal_page(): void
{
    global $api, $xtpl;
    $dataset = filter_var($_GET['id'] ?? null, FILTER_VALIDATE_INT, ['options' => ['min_range' => 1]]);
    if (!$dataset || !dataset_snapshot_removal_available()) {
        unset($_SESSION['dataset_snapshot_removal']);
        $xtpl->perex(_('Snapshot removal is unavailable'), '');
        return;
    }
    $return = local_redirect_target($_GET['return'] ?? '', '?page=dataset&action=edit&role=hypervisor&id=' . $dataset);
    $options = ['recursive' => false, 'disable_plans' => true];
    $state = $_SESSION['dataset_snapshot_removal'] ?? null;
    try {
        if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
            unset($_SESSION['dataset_snapshot_removal']);
            $state = null;
        } else {
            if (!is_string($_POST['csrf_token'] ?? null) || $_POST['csrf_token'] === '') {
                throw new CsrfTokenInvalid();
            }
            $options = dataset_snapshot_removal_options($_POST);
            $phase = isset($_POST['change_options']) ? 'options' : (isset($_POST['return_review']) ? 'back' : ($_POST['phase'] ?? ''));
            if ($phase === 'preview') {
                csrf_check('dataset_snapshot_removal:preview:' . $dataset);
                unset($_SESSION['dataset_snapshot_removal']);
                $state = null;
                $preview = $api->dataset($dataset)->preview_snapshot_removal($options)->getResponse();
                $preview = dataset_snapshot_removal_validate($preview, $dataset, $options);
                $state = ['dataset' => $dataset, 'context' => dataset_snapshot_removal_context(),
                    'options' => $options, 'preview' => $preview, 'stage' => 'review', 'nonce' => bin2hex(random_bytes(16))];
            } else {
                if (!$state || $state['dataset'] !== $dataset || $state['context'] !== dataset_snapshot_removal_context()
                    || $state['options'] !== $options || !is_string($_POST['manifest_digest'] ?? null)
                    || !hash_equals($state['preview']['manifest_digest'], $_POST['manifest_digest'])) {
                    throw new InvalidArgumentException(_('The review has changed. Request a new preview and confirm it again.'));
                }
                $scope = 'dataset_snapshot_removal:' . $state['nonce'] . ':' . $state['stage'];
                csrf_check($scope);
                if ($phase === 'options') {
                    unset($_SESSION['dataset_snapshot_removal']);
                    $state = null;
                } elseif ($phase === 'continue' && $state['stage'] === 'review' && ($_POST['acknowledge'] ?? '') === '1') {
                    $state['stage'] = 'final';
                } elseif ($phase === 'back' && $state['stage'] === 'final') {
                    $state['stage'] = 'review';
                } elseif ($phase === 'remove' && $state['stage'] === 'final' && ($_POST['confirm'] ?? '') === '1') {
                    // Consume progression before submitting, including when transport/receipt is uncertain.
                    unset($_SESSION['dataset_snapshot_removal']);
                    $state = null;
                    $result = $api->dataset($dataset)->remove_snapshots($options + ['manifest_digest' => $_POST['manifest_digest']]);
                    $receipt = $result->getApiResponse()->getMeta()->action_state_id ?? null;
                    if (!is_int($receipt) || $receipt < 1) {
                        throw new UnexpectedValueException(_('The submission outcome is unknown. Inspect the existing tasks and remaining history before trying again.'));
                    }
                    notify_user(_('Snapshot and backup history removal has been queued.'));
                    redirect($return);
                    return;
                } else {
                    throw new InvalidArgumentException(_('Confirm the reviewed inventory before continuing.'));
                }
            }
            if ($state) {
                $_SESSION['dataset_snapshot_removal'] = $state;
            }
        }
    } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
        $errors = $e->getResponse()->getErrors();
        if (in_array('stale_preview', $errors->manifest_digest ?? [], true)) {
            $xtpl->perex(_('Cannot remove snapshots'), _('The history has changed. Request a new preview and confirm it again.'));
        } else {
            $xtpl->perex_format_errors(_('Cannot remove snapshots'), $e->getResponse());
        }
        unset($_SESSION['dataset_snapshot_removal']);
        $state = null;
    } catch (\InvalidArgumentException|\UnexpectedValueException $e) {
        unset($_SESSION['dataset_snapshot_removal']);
        $state = null;
        $xtpl->perex(_('Cannot remove snapshots'), h($e->getMessage()));
    }
    $xtpl->title(_('Remove all snapshots and backup history'));
    if ($state) {
        dataset_snapshot_removal_review_form($state, $return);
    } else {
        dataset_snapshot_removal_options_form($dataset, $return, $options);
    }
    $xtpl->sbar_add(_('Back'), $return);
    $xtpl->sbar_out(_('Dataset'));
}

function dataset_snapshot_removal_options_form(int $dataset, string $return, array $options = ['recursive' => false, 'disable_plans' => true]): void
{
    global $xtpl;
    $xtpl->table_title(_('Remove all snapshots and backup history'));
    $xtpl->form_create(dataset_snapshot_removal_url($dataset, $return), 'post');
    $scope = 'dataset_snapshot_removal:preview:' . $dataset;
    csrf_token($scope, 1);
    $xtpl->form_csrf($scope);
    $xtpl->form_set_hidden_fields(['phase' => 'preview', 'recursive' => '0', 'disable_plans' => '0']);
    $xtpl->table_td('<p>' . h(_('Preview all source and backup snapshots, branches and trees that will be removed. The live dataset and its files are preserved.')) . '</p>', false, false, '2');
    $xtpl->table_tr();
    $xtpl->form_add_checkbox(_('Include subdatasets'), 'recursive', '1', $options['recursive']);
    $xtpl->form_add_checkbox(_('Remove selected datasets from backup plans'), 'disable_plans', '1', $options['disable_plans']);
    $xtpl->table_td(h(_('If plans remain enabled, scheduled snapshots and backups can recreate history after removal.')), false, false, '2');
    $xtpl->table_tr();
    $xtpl->form_out(_('Preview snapshot removal'));
}

function dataset_snapshot_removal_table(string $title, array $headers, array $rows): void
{
    global $xtpl;
    $xtpl->table_title(h($title));
    foreach ($headers as $header) {
        $xtpl->table_add_category(h($header));
    }
    foreach ($rows as $row) {
        foreach ($row as $value) {
            $xtpl->table_td(h((string) $value));
        }
        $xtpl->table_tr();
    }
    if (!$rows) {
        $xtpl->table_td(h(_('None')), false, false, (string) count($headers));
        $xtpl->table_tr();
    }
    $xtpl->table_out();
}

function dataset_snapshot_removal_review_form(array $state, string $return): void
{
    global $xtpl;
    $m = $state['preview']['manifest'];
    $counts = $m['counts'];
    dataset_snapshot_removal_table(_('Removal summary'), [_('Item'), _('Count')], [
        [_('Datasets'), $counts['datasets']], [_('Pool copies'), $counts['copies']],
        [_('Snapshots'), $counts['snapshots']], [_('Snapshot locations'), $counts['snapshot_locations']],
        [_('Dataset trees'), $counts['trees']], [_('Dataset branches'), $counts['branches']],
        [_('Backup plans to disable'), $counts['plans_to_disable']],
    ]);
    foreach ($m['datasets'] as $dataset) {
        $copies = array_filter($m['copies'], static fn($copy) => $copy['dataset_id'] === $dataset['id']);
        foreach ($copies as $copy) {
            $rows = [];
            foreach ($m['snapshot_locations'] as $row) {
                if ($row['dataset_in_pool_id'] !== $copy['id']) {
                    continue;
                }
                $branch = $row['branch_id'] === null ? null : array_values(array_filter($m['branches'], static fn($b) => $b['id'] === $row['branch_id']))[0];
                $rows[] = [$row['snapshot_name'] . ' (#' . $row['snapshot_id'] . ')',
                    $row['snapshot_label'] ?? '', $row['created_at'] ?? '', $row['history_id'],
                    $row['snapshot_in_pool_id'], $branch ? $branch['name'] . ' (#' . $branch['id'] . ')' : '-',
                    $row['snapshot_in_pool_in_branch_id'] ?? '-', $row['origin_snapshot_in_pool_in_branch_id'] ?? '-'];
            }
            $label = $dataset['full_name'] . ' (#' . $dataset['id'] . ') / ' . $copy['pool_label']
                . ' (#' . $copy['pool_id'] . ', ' . $copy['pool_role'] . ', ' . ($copy['pool_open'] ? _('Open') : _('Closed')) . ') / '
                . $copy['node_name'] . ' (#' . $copy['node_id'] . ') / ' . $copy['pool_filesystem'] . ' / #' . $copy['id'];
            dataset_snapshot_removal_table($label, [_('Snapshot'), _('Label'), _('Created at'), _('History'), _('Snapshot copy'), _('Dataset branch'), _('Branch membership'), _('Origin membership')], $rows);
            $trees = array_filter($m['trees'], static fn($tree) => $tree['dataset_in_pool_id'] === $copy['id']);
            $rows = [];
            foreach ($trees as $tree) {
                $rows[] = [$tree['name'], $tree['id'], $tree['head'] ? _('Yes') : _('No')];
            }
            dataset_snapshot_removal_table(_('Dataset trees to remove'), [_('Name'), _('ID'), _('Head')], $rows);
            $rows = [];
            foreach ($m['branches'] as $branch) {
                foreach ($trees as $tree) {
                    if ($branch['dataset_tree_id'] === $tree['id']) {
                        $rows[] = [$branch['name'], $branch['id'], $tree['name'] . ' (#' . $tree['id'] . ')', $branch['head'] ? _('Yes') : _('No')];
                    }
                }
            }
            dataset_snapshot_removal_table(_('Dataset branches to remove'), [_('Name'), _('ID'), _('Dataset tree'), _('Head')], $rows);
            $rows = [];
            foreach ($m['plans'] as $plan) {
                if ($plan['dataset_in_pool_id'] === $copy['id']) {
                    $rows[] = [$plan['name'], $plan['id'], $plan['dataset_plan_id'], $plan['environment_dataset_plan_id'], $plan['action'] === 'remove' ? _('Disable') : _('Retain')];
                }
            }
            dataset_snapshot_removal_table(_('Backup plan effects'), [_('Name'), _('Membership'), _('Plan'), _('Environment plan'), _('Action')], $rows);
        }
    }
    $final = $state['stage'] === 'final';
    $xtpl->table_title($final ? _('Final confirmation of snapshot removal') : _('Review snapshot removal'));
    $xtpl->form_create(dataset_snapshot_removal_url($state['dataset'], $return), 'post');
    $scope = 'dataset_snapshot_removal:' . $state['nonce'] . ':' . $state['stage'];
    csrf_token($scope, 1);
    $xtpl->form_csrf($scope);
    $xtpl->form_set_hidden_fields(['phase' => $final ? 'remove' : 'continue',
        'recursive' => $state['options']['recursive'] ? '1' : '0',
        'disable_plans' => $state['options']['disable_plans'] ? '1' : '0',
        'manifest_digest' => $state['preview']['manifest_digest']]);
    $xtpl->table_td(h($state['options']['recursive'] ? _('Scope: dataset and subdatasets') : _('Scope: this dataset only')), false, false, '2');
    $xtpl->table_tr();
    $xtpl->table_td(h($state['options']['disable_plans'] ? _('The selected datasets will be removed from backup plans.') : _('Backup plans remain enabled and can recreate history.')), false, false, '2');
    $xtpl->table_tr();
    $xtpl->table_td(h(_('All listed snapshots, branches and trees will be permanently deleted. The live dataset and its files are preserved. Deletion cannot be undone. If the task fails, some history may already be deleted.')), false, false, '2');
    $xtpl->table_tr();
    $name = $final ? 'confirm' : 'acknowledge';
    $label = $final ? _('Confirm permanent removal') : _('I have reviewed the complete inventory');
    $xtpl->table_td('<label for="snapshot-removal-' . $name . '">' . h($label) . '</label>');
    $xtpl->table_td('<input type="checkbox" id="snapshot-removal-' . $name . '" name="' . $name . '" value="1" required>');
    $xtpl->table_tr();
    $xtpl->table_td('<button type="submit" name="change_options" value="1" formnovalidate>' . h(_('Change options')) . '</button>', false, false, '2');
    $xtpl->table_tr();
    if ($final) {
        $xtpl->table_td('<button type="submit" name="return_review" value="1" formnovalidate>' . h(_('Back to review')) . '</button>', false, false, '2');
        $xtpl->table_tr();
    }
    $xtpl->form_out($final ? _('Remove all snapshots and backup history') : _('Continue to final confirmation'));
}
