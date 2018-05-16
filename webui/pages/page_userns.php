<?php

if (isLoggedIn()) {
	switch ($_GET['action']) {
	case 'list':
		userns_submenu();
		userns_list();
		break;

	case 'show':
		userns_submenu();
		userns_show($_GET['id']);
		break;

	case 'maps':
		userns_submenu();
		userns_map_list();
		break;

	case 'map_show':
		userns_submenu();
		userns_map_show($_GET['id']);
		break;

	case 'map_edit':
		csrf_check();

		try {
			$api->user_namespace_map($_GET['id'])->update([
				'label' => $_POST['label'],
			]);

			notify_user(_("Label changed"));
			redirect('?page=userns&action=map_show&id='.$_GET['id']);

		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			$xtpl->perex_format_errors(_('Unable to change label'), $e->getResponse());

			userns_submenu();
			userns_map_show($_GET['id']);
		}

		break;

	case 'map_entries_edit':
		csrf_check();

		if (isset($_POST['add'])) {
			try {
				$api->user_namespace_map($_GET['id'])->entry->create([
					'kind' => $_POST['new_kind'],
					'ns_id' => $_POST['new_ns_id'],
					'host_id' => $_POST['new_host_id'],
					'count' => $_POST['new_count'],
				]);

				notify_user(_("Entry added"));
				redirect('?page=userns&action=map_show&id='.$_GET['id']);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Unable to add entry'), $e->getResponse());

				userns_submenu();
				userns_map_show($_GET['id']);
			}

		} elseif (isset($_POST['save'])) {
			try {
				foreach ($_POST['entry_id'] as $i => $id) {
					$api->user_namespace_map($_GET['id'])->entry($id)->update([
						'kind' => $_POST['kind'][$i],
						'ns_id' => $_POST['ns_id'][$i],
						'host_id' => $_POST['host_id'][$i],
						'count' => $_POST['count'][$i],
					]);
				}

				notify_user(_("Map updated"));
				redirect('?page=userns&action=map_show&id='.$_GET['id']);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Unable to update entry'), $e->getResponse());

				userns_submenu();
				userns_map_show($_GET['id']);
			}

		}

		break;

	case 'map_entry_del':
		csrf_check();

		try {
			$api->user_namespace_map($_GET['map'])->entry->delete($_GET['entry']);

			notify_user(_("Entry removed"));
			redirect('?page=userns&action=map_show&id='.$_GET['map']);

		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			notify_user(_('Unable to delete entry'), format_errors($e->getResponse()));
			redirect('?page=userns&action=map_show&id='.$_GET['map']);
		}

		break;

	case 'map_new':
		if ($_POST['user_namespace']) {
			csrf_check();

			try {
				$map = $api->user_namespace_map->create([
					'user_namespace' => $_POST['user_namespace'],
					'label' => $_POST['label'],
				]);

				notify_user(_("Map created"));
				redirect('?page=userns&action=map_show&id='.$map->id);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors(_('Unable to create map'), $e->getResponse());

				userns_submenu();
				userns_map_new();
			}

		} else {
				userns_submenu();
				userns_map_new();
		}

		break;

	case 'map_del':
		csrf_check();

		try {
			$api->user_namespace_map->delete($_GET['id']);

			notify_user(_("Map deleted"));
			redirect('?page=userns&action=maps');

		} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
			notify_user(_('Unable to delete map'), format_errors($e->getResponse()));
			redirect('?page=userns&action=maps');
		}

		break;

	default:
		userns_submenu();
		userns_or_map_list();
	}

	$xtpl->sbar_out(_('User namespaces'));

} else {
	$xtpl->perex(
		_("Access forbidden"),
		_("You have to log in to be able to access vpsAdmin's functions")
	);
}
