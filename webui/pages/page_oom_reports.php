<?php

if (isLoggedIn()) {
    switch ($_GET['action'] ?? null) {
        case 'show':
            oom_reports_show($_GET['id']);
            break;

        case 'rule_list':
            oom_reports_rules_list($_GET['vps']);
            break;

        case 'rule_new':
            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();

                try {
                    $api->oom_report_rule->create([
                        'vps' => $_GET['vps'],
                        'action' => $_POST['action'],
                        'cgroup_pattern' => $_POST['cgroup_pattern'],
                    ]);

                    notify_user(_('Rule added'), '');
                    redirect('?page=oom_reports&action=rule_list&vps=' . $_GET['vps']);

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Failed to add rule'), $e->getResponse());
                    oom_reports_rules_list($_GET['vps']);
                }
            } else {
                oom_reports_rules_list($_GET['vps']);
            }
            break;

        case 'rule_edit':
            if ($_SERVER['REQUEST_METHOD'] === 'POST') {
                csrf_check();

                try {
                    $api->oom_report_rule->update($_GET['id'], [
                        'action' => $_POST['action'],
                        'cgroup_pattern' => $_POST['cgroup_pattern'],
                    ]);

                    notify_user(_('Rule updated'), '');
                    redirect('?page=oom_reports&action=rule_list&vps=' . $_GET['vps']);

                } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                    $xtpl->perex_format_errors(_('Failed to update rule'), $e->getResponse());
                    oom_reports_rules_edit($_GET['vps'], $_GET['id']);
                }
            } else {
                oom_reports_rules_edit($_GET['vps'], $_GET['id']);
            }
            break;

        case 'rule_delete':
            csrf_check();

            try {
                $api->oom_report_rule->delete($_GET['id']);

                notify_user(_('Rule deleted'), '');
                redirect('?page=oom_reports&action=rule_list&vps=' . $_GET['vps']);
            } catch (\HaveAPI\Client\Exception\ActionFailed $e) {
                $xtpl->perex_format_errors(_('Failed to delete rule'), $e->getResponse());
                oom_reports_rules_list($_GET['vps']);
            }

            break;

        case 'list':
        default:
            oom_reports_list();
    }

    $xtpl->sbar_out(_('OOM Reports'));

} else {
    $xtpl->perex(
        _("Access forbidden"),
        _("You have to log in to be able to access vpsAdmin's functions")
    );
}
