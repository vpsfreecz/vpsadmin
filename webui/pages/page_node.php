<?php

if (isLoggedIn()) {
    $xtpl->sbar_add(_('Back to status'), '?page=');
    $xtpl->sbar_add(
        _('Node details'),
        '?page=node&id=' . (int) $_GET['id']
    );
    $xtpl->sbar_add(
        _('Kernel history'),
        '?page=node&action=kernel_history&id=' . (int) $_GET['id'],
        'node.kernel-history'
    );
    $xtpl->sbar_add(
        _('System history'),
        '?page=node&action=system_history&id=' . (int) $_GET['id'],
        'node.system-history'
    );
    if (isAdmin()) {
        $xtpl->sbar_add(
            _('Kernel parameters'),
            '?page=node&action=kernel_parameters&id=' . (int) $_GET['id'],
            'node.kernel-parameters'
        );
        $xtpl->sbar_add(
            _('Sysctls'),
            '?page=node&action=sysctls&id=' . (int) $_GET['id'],
            'node.sysctls'
        );
        $xtpl->sbar_add(
            _('Software versions'),
            '?page=node&action=software_versions&id=' . (int) $_GET['id'],
            'node.software-versions'
        );
    }
    $xtpl->sbar_out(_('Node'));

    switch ($_GET['action'] ?? 'show') {
        case 'kernel_history':
            node_kernel_history_table($_GET['id']);
            break;

        case 'system_history':
            node_system_history_table($_GET['id']);
            break;

        case 'kernel_boot_evidence':
            if (isAdmin()) {
                node_kernel_boot_evidence_table($_GET['id'], $_GET['event_id'] ?? 0);
            } else {
                node_admin_page_forbidden();
            }
            break;

        case 'kernel_parameters':
            if (isAdmin()) {
                node_kernel_parameters_table($_GET['id']);
            } else {
                node_admin_page_forbidden();
            }
            break;

        case 'sysctls':
            if (isAdmin()) {
                node_sysctls_table($_GET['id']);
            } else {
                node_admin_page_forbidden();
            }
            break;

        case 'sysctl_history':
            if (isAdmin()) {
                node_sysctl_history_table($_GET['id'], $_GET['name'] ?? '');
            } else {
                node_admin_page_forbidden();
            }
            break;

        case 'software_versions':
            if (isAdmin()) {
                node_software_versions_table($_GET['id']);
            } else {
                node_admin_page_forbidden();
            }
            break;

        default:
            node_details_table($_GET['id']);
            break;
    }

} else {
    $xtpl->perex(
        _("Access forbidden"),
        _("You have to log in to be able to access vpsadmin's functions")
    );
}
