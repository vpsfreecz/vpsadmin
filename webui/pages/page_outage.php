<?php

function outage_create () {
	global $xtpl, $api;

	try {
		$params = array(
			'begins_at' => date('c', strtotime($_POST['begins_at'])),
			'duration' => $_POST['duration'],
			'planned' => isset($_POST['planned']),
			'type' => $_POST['type'],
		);

		$texts = array();
		foreach ($api->language->list() as $lang) {
			foreach (array('summary', 'description') as $name) {
				$param = $lang->code.'_'.$name;

				if ($_POST[$param])
					$params[$param] = $_POST[$param];
			}
		}

		return $api->outage->create($params);

	} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
		$xtpl->perex_format_errors('Create failed', $e->getResponse());
		return null;
	}
}

function outage_set_entities ($outage) {
	$existing_entities = $outage->entity->list();
	$new_entities = array();

	$tr = array(
		'environments' => 'Environment',
		'locations' => 'Location',
		'nodes' => 'Node',
	);

	foreach ($tr as $post => $name) {
		foreach ($_POST[$post] as $v) {
			$new_entities[] = array($name, (int)$v);
		}
	}

	if ($_POST['cluster_wide'])
		$new_entities[] = array('Cluster', null);

	if ($_POST['entities']) {
		foreach (explode(',', $_POST['entities']) as $ent) {
			$trimmed = trim($ent);

			if ($trimmed)
				$new_entities[] = array($trimmed, null);
		}
	}

	// Create new entities
	foreach ($new_entities as $new) {
		$exists = false;

		foreach ($existing_entities as $ent) {
			if ($ent->name === $new[0] && $ent->entity_id === $new[1]) {
				$exists = true;
				break;
			}
		}

		if (!$exists) {
			$outage->entity->create(array(
				'name' => $new[0],
				'entity_id' => $new[1],
			));
		}
	}

	// Delete deselected entities
	foreach ($existing_entities as $ent) {
		$exists = false;

		foreach ($new_entities as $new) {
			if ($ent->name === $new[0] && $ent->entity_id === $new[1]) {
				$exists = true;
				break;
			}
		}

		if (!$exists) {
			$outage->entity->delete($ent->id);
		}
	}
}

function outage_set_handlers ($outage) {
	$existing = $outage->handler->list();

	// Create new handlers
	foreach ($_POST['handlers'] as $new) {
		$exists = false;

		foreach ($existing as $h) {
			if ($h->user_id === (int)$new) {
				$exists = true;
				break;
			}
		}

		if (!$exists) {
			$outage->handler->create(array('user' => $new));
		}
	}

	// Delete existing handlers
	foreach ($existing as $h) {
		$exists = false;

		foreach ($_POST['handlers'] as $new) {
			if ($h->user_id === (int)$new) {
				$exists = true;
				break;
			}
		}

		if (!$exists) {
			$outage->handler->delete($h->id);
		}
	}
}

if (isLoggedIn()) {
	switch ($_GET['action']) {
	case 'report':
		csrf_check();

		if (isAdmin()) {
			$outage = outage_create();

			if (!$outage) {
				outage_report_form();

			} else {
				try {
					outage_set_entities($outage);
					outage_set_handlers($outage);

					redirect('?page=outage&action=show&id='.$outage->id);

				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors('Create failed', $e->getResponse());
					outage_report_form();
				}
			}
		}
		break;

	case 'edit':
		if (isAdmin()) {
			if ($_SERVER['REQUEST_METHOD'] === 'POST') {
				csrf_check();

				try {
					$outage = $api->outage->show($_GET['id']);
					outage_set_entities($outage);
					outage_set_handlers($outage);
					$outage->rebuild_affected_vps();

					redirect('?page=outage&action=show&id='.$outage->id);

				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors('Save failed', $e->getResponse());
					outage_edit_form($_GET['id']);
				}

			} else
				outage_edit_form($_GET['id']);
		}
		break;

	case 'update':
		if (isAdmin()) {
			if ($_SERVER['REQUEST_METHOD'] === 'POST') {
				csrf_check();

				$outage = $api->outage->show($_GET['id']);
				$params = array(
					'send_mail' => isset($_POST['send_mail']),
				);
				$dates = array('begins_at', 'finished_at');
				$fields = array('duration', 'type', 'state');

				foreach ($dates as $d) {
					$v = strtotime($_POST[$d]);

					if ($_POST[$d] && $v != strtotime($outage->{$d}))
						$params[$d] = date('c', $v);

					elseif (!$_POST[$d] && $outage->{$d})
						$params[$d] = null;
				}

				foreach ($fields as $f) {
					if ($_POST[$f] && $_POST[$f] != $outage->{$f})
						$params[$f] = $_POST[$f];
				}

				$texts = array();
				foreach ($api->language->list() as $l) {
					foreach (array('summary', 'description') as $name) {
						$param = $l->code.'_'.$name;

						if ($_POST[$param])
							$params[$param] = $_POST[$param];
					}
				}

				try {
					$outage->update($params);

					notify_user(_('Update posted'), _('The outage update was successfully posted.'));
					redirect('?page=outage&action=show&id='.$outage->id);

				} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
					$xtpl->perex_format_errors('Update failed', $e->getResponse());
					outage_update_form($_GET['id']);
				}

			} else
				outage_update_form($_GET['id']);
		}
		break;

	case 'set_state':
		if (isAdmin() && $_SERVER['REQUEST_METHOD'] === 'POST') {
			csrf_check();

			try {
				$api->outage->update($_GET['id'], array(
					'send_mail' => isset($_POST['send_mail']),
					'state' => $_POST['state']
				));

				notify_user(_('State set'), _('The outage state was successfully set.'));
				redirect('?page=outage&action=show&id='.$_GET['id']);

			} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
				$xtpl->perex_format_errors('Update failed', $e->getResponse());
				outage_details($_GET['id']);
			}
		}
		break;

	case 'list':
		outage_list();
		break;

	case 'show':
		outage_details($_GET['id']);
		break;

	case 'users':
		outage_affected_users($_GET['id']);
		break;

	case 'vps':
		outage_affected_vps($_GET['id']);
		break;
	}

	$xtpl->sbar_out(_('Outages'));

} else {
	switch ($_GET['action']) {
	case 'list':
		outage_list();
		break;

	case 'show':
		outage_details($_GET['id']);
		break;

	default:
		$xtpl->perex(
			_("Access forbidden"),
			_("You have to log in to be able to access vpsAdmin's functions")
		);
	}
}
