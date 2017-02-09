<?php

function list_object_history() {
	global $xtpl, $api;

	$xtpl->title(_('Object history'));

	if ($_GET['return_url']) {
		$xtpl->sbar_add(_('Back'), $_GET['return_url']);
		$xtpl->sbar_out(_("Object history"));
	}

	$xtpl->table_title(_('Filters'));
	$xtpl->form_create('', 'get', 'user-session-filter', false);

	$xtpl->table_td(_("Limit").':'.
		'<input type="hidden" name="page" value="history">'.
		'<input type="hidden" name="return_url" value="'.$_GET['return_url'].'">'.
		'<input type="hidden" name="list" value="1">'
	);
	$xtpl->form_add_input_pure('text', '40', 'limit', get_val('limit', '25'), '');
	$xtpl->table_tr();

	$xtpl->form_add_input(_("Offset").':', 'text', '40', 'offset', get_val('offset', '0'), '');

	if ($_SESSION['is_admin'])
		$xtpl->form_add_input(_("User").':', 'text', '40', 'user', get_val('user', ''), '');

	$xtpl->form_add_input(_("User session").':', 'text', '40', 'user_session', get_val('user_session', ''), '');
	$xtpl->form_add_input(_("Object").':', 'text', '40', 'object', get_val('object', ''), '');
	$xtpl->form_add_input(_("Object ID").':', 'text', '40', 'object_id', get_val('object_id', ''), '');
	$xtpl->form_add_input(_("Event").':', 'text', '40', 'event_type', get_val('event_type', ''), '');

	$xtpl->form_add_checkbox(_('Detailed output').':', 'details', '1', isset($_GET['details']));

	$xtpl->form_out(_('Show'));

	if (!$_GET['list'])
		return;

	$params = array(
		'limit' => get_val('limit', 25),
		'offset' => get_val('offset', 0),
	);

	$conds = array('user', 'user_session', 'object', 'object_id', 'event_type');

	foreach ($conds as $c) {
		if ($_GET[$c])
			$params[$c] = $_GET[$c];
	}

	$params['meta'] = array(
		'includes' => 'user,user_session',
		'count' => true,
	);

	$events = $api->object_history->list($params);

	$xtpl->table_add_category(_("Created at"));
	$xtpl->table_add_category(_("User"));
	$xtpl->table_add_category(_("Session"));
	$xtpl->table_add_category(_("Object"));
	$xtpl->table_add_category(_("Event"));
	$xtpl->table_add_category(_("Data"));

	foreach ($events as $e) {
		$xtpl->table_td(tolocaltz($e->created_at), false, false, 1, 1, 'top');

		if ($e->user_id) {
			$xtpl->table_td('<a href="?page=adminm&action=edit&id='.$e->user_id.'">'.$e->user->login.'</a>', false, false, 1, 1, 'top');
			$xtpl->table_td('<a href="?page=adminm&action=user_sessions&id='.$e->user_id.'&list=1&session_id='.$e->user_session_id.'&details=1">'.$e->user_session_id.'</a>', false, false, 1, 1, 'top');

		} else {
			$xtpl->table_td('---', false, false, 1, 1, 'top');
			$xtpl->table_td('---', false, false, 1, 1, 'top');
		}

		$xtpl->table_td($e->object .' '.$e->object_id, false, false, 1, 1, 'top');
		$xtpl->table_td($e->event_type, false, false, 1, 1, 'top');
		$xtpl->table_td('<pre>'.h(print_r($e->event_data, true)).'</pre>', false, false, 1, 1, 'top');
		$xtpl->table_tr();
	}

	$xtpl->table_out();

	$xtpl->table_td('Displayed events:');
	$xtpl->table_td($events->count());
	$xtpl->table_tr();
	$xtpl->table_td('Total events:');
	$xtpl->table_td($events->getTotalCount());
	$xtpl->table_tr();
	$xtpl->table_out();
}

