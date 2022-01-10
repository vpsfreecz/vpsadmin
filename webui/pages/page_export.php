<?php

if (isLoggedIn()) {
	switch ($_GET['action'] ?? null) {
	case 'export_dataset':
		if ($_SERVER['REQUEST_METHOD'] === 'POST') {
			try {
				$ds = $api->dataset->show($_POST['dataset']);
				redirect('?page=export&action=create&dataset='.$ds->id);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Dataset not found'), $e->getResponse());
				export_dataset_form();
			}
		} else {
			export_dataset_form();
		}
		break;

	case 'create':
		if ($_SERVER['REQUEST_METHOD'] === 'POST') {
			csrf_check();

			try {
				$ex = $api->export->create([
					'dataset' => $_GET['snapshot'] ? null : $_GET['dataset'],
					'snapshot' => get_val('snapshot', null),
					'all_vps' => isset($_POST['all_vps']),
					'rw' => isset($_POST['rw']),
					'sync' => isset($_POST['sync']),
					'subtree_check' => isset($_POST['subtree_check']),
					'root_squash' => isset($_POST['root_squash']),
					'threads' => post_val('threads', null),
					'enabled' => isset($_POST['enabled']),
				]);

				notify_user(_('Export created'), '');
				redirect('?page=export&action=edit&export='.$ex->id);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Export creation failed'), $e->getResponse());
				export_create_form($_GET['dataset'], $_GET['snapshot']);
			}
		} else {
			export_create_form($_GET['dataset'], $_GET['snapshot']);
		}
		break;

	case 'edit':
		if ($_SERVER['REQUEST_METHOD'] === 'POST') {
			csrf_check();

			try {
				$api->export->update($_GET['export'], [
					'all_vps' => isset($_POST['all_vps']),
					'rw' => isset($_POST['rw']),
					'sync' => isset($_POST['sync']),
					'subtree_check' => isset($_POST['subtree_check']),
					'root_squash' => isset($_POST['root_squash']),
					'threads' => post_val('threads', null),
				]);

				notify_user(_('Export settings updated'), '');
				redirect('?page=export&action=edit&export='.$_GET['export']);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Edit export failed'), $e->getResponse());
				export_edit_form($_GET['export']);
			}
		} else {
			export_edit_form($_GET['export']);
		}
		break;

	case 'destroy':
		if ($_SERVER['REQUEST_METHOD'] === 'POST' && $_POST['confirm']) {
			csrf_check();

			try {
				$api->export->destroy($_GET['export']);

				notify_user(_('Export deleted'), '');
				redirect('?page=export');

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Edit deletion failed'), $e->getResponse());
				export_destroy_form($_GET['export']);
			}
		} else {
			export_destroy_form($_GET['export']);
		}
		break;

	case 'enable':
		if ($_SERVER['REQUEST_METHOD'] === 'POST') {
			csrf_check();

			try {
				$api->export->update($_GET['export'], [
					'enabled' => true,
				]);

				notify_user(
					_('Export activated'),
					_('The NFS server will start momentarily.')
				);
				redirect('?page=export&action=edit&export='.$_GET['export']);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Server start failed'), $e->getResponse());
				export_edit_form($_GET['export']);
			}
		} else {
			export_edit_form($_GET['export']);
		}
		break;

	case 'disable':
		if ($_SERVER['REQUEST_METHOD'] === 'POST') {
			csrf_check();

			try {
				$api->export->update($_GET['export'], [
					'enabled' => false,
				]);

				notify_user(
					_('Export deactivated'),
					_('The NFS server will stop momentarily.')
				);
				redirect('?page=export&action=edit&export='.$_GET['export']);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Server stop failed'), $e->getResponse());
				export_edit_form($_GET['export']);
			}
		} else {
			export_edit_form($_GET['export']);
		}
		break;

	case 'add_host':
		if ($_SERVER['REQUEST_METHOD'] === 'POST') {
			csrf_check();

			try {
				$api->export($_GET['export'])->host->create([
					'ip_address' => $_POST['ip_address'],
					'rw' => isset($_POST['rw']),
					'sync' => isset($_POST['sync']),
					'subtree_check' => isset($_POST['subtree_check']),
					'root_squash' => isset($_POST['root_squash']),
				]);

				notify_user(
					_('Host added'),
					_('The changes will take effect momentarily.')
				);
				redirect('?page=export&action=edit&export='.$_GET['export']);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Edit host failed'), $e->getResponse());
				export_host_add_form($_GET['export']);
			}
		} else {
			export_host_add_form($_GET['export']);
		}
		break;

	case 'edit_host':
		if ($_SERVER['REQUEST_METHOD'] === 'POST') {
			csrf_check();

			try {
				$api->export($_GET['export'])->host->update($_GET['host'], [
					'rw' => isset($_POST['rw']),
					'sync' => isset($_POST['sync']),
					'subtree_check' => isset($_POST['subtree_check']),
					'root_squash' => isset($_POST['root_squash']),
				]);

				notify_user(
					_('Host settings updated'),
					_('The changes will take effect momentarily.')
				);
				redirect('?page=export&action=edit&export='.$_GET['export']);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Edit host failed'), $e->getResponse());
				export_host_edit_form($_GET['export'], $_GET['host']);
			}
		} else {
			export_host_edit_form($_GET['export'], $_GET['host']);
		}
		break;

	case 'del_host':
		csrf_check();

		try {
			$api->export($_GET['export'])->host($_GET['host'])->delete();

			notify_user(
				_('Host removed'),
				_('The changes will take effect momentarily.')
			);
			redirect('?page=export&action=edit&export='.$_GET['export']);

		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			$xtpl->perex_format_errors(_('Host removal failed'), $e->getResponse());
			export_edit_form($_GET['export']);
		}

		break;

	case 'list':
	default:
		export_list();
	}

	$xtpl->sbar_out(_('NFS Exports'));

} else {
	$xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
}
