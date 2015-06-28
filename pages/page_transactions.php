<?php
/*
	./pages/page_transactions.php

	vpsAdmin
	Web-admin interface for OpenVZ (see http://openvz.org)
	Copyright (C) 2008-2011 Pavel Snajdr, snajpa@snajpa.net
*/

function chain_class($chain) {
	switch ($chain->state) {
		case 'queued':
			return 'pending';
		
		case 'done':
			return 'ok';
		
		case 'rollbacking':
			return 'warning';
		
		case 'failed':
			return 'error';
		
		default:
			return '';
	}
}

function list_chains() {
	global $xtpl, $api;
	
	$xtpl->title(_("Transaction chains"));

	$xtpl->table_title(_('Filters'));
	$xtpl->form_create('', 'get', 'vps-filter', false);

	$xtpl->table_td(_("Limit").':'.
		'<input type="hidden" name="page" value="transactions">'
	);
	$xtpl->form_add_input_pure('text', '40', 'limit', get_val('limit', '25'), '');
	$xtpl->table_tr();

	$xtpl->form_add_input(_("Offset").':', 'text', '40', 'offset', get_val('offset', '0'), '');
	$xtpl->form_add_input(_("Exact ID").':', 'text', '40', 'chain', get_val('chain'));
	$xtpl->form_add_input(_("User ID").':', 'text', '40', 'user', get_val('user'));
	$xtpl->form_add_input(_("State").':', 'text', '40', 'state', get_val('state'), 'queued, done, rollbacking, failed');
	$xtpl->form_add_input(_("Name").':', 'text', '40', 'name', get_val('name'));
	$xtpl->form_add_input(_("Class name").':', 'text', '40', 'class_name', get_val('class_name'));
	$xtpl->form_add_input(_("Object id").':', 'text', '40', 'row_id', get_val('row_id'));

	$xtpl->form_out(_('Show'));

	$params = array(
		'limit' => get_val('limit', 25),
		'offset' => get_val('offset', 0),
		'meta' => array('includes' => 'user')
	);

	if ($_GET['user'])
		$params['user'] = $_GET['user'];
	
	if ($_GET['state'])
		$params['state'] = $_GET['state'];
	
	if ($_GET['name'])
		$params['name'] = $_GET['name'];
	
	if ($_GET['class_name'])
		$params['class_name'] = $_GET['class_name'];
	
	if ($_GET['row_id'])
		$params['row_id'] = $_GET['row_id'];

	$chains = $api->transaction_chain->list($params);
	
	$xtpl->table_add_category('#');
	$xtpl->table_add_category(_('Date'));
	
	if ($_SESSION['is_admin'])
		$xtpl->table_add_category(_('User'));
	
	$xtpl->table_add_category(_('Label'));
	$xtpl->table_add_category(_('Object'));
	$xtpl->table_add_category(_('State'));
	$xtpl->table_add_category(_('Size'));
	$xtpl->table_add_category(_('Progress'));

	foreach ($chains as $chain) {
		$xtpl->table_td('<a href="?page=transactions&chain='.$chain->id.'">'.$chain->id.'</a>');
		$xtpl->table_td($chain->created_at);
		
		if ($_SESSION['is_admin']) {
			if ($chain->user_id)
				$xtpl->table_td('<a href="?page=adminm&action=edit&id='.$chain->user_id.'">'.$chain->user->login.'</a>');
			else
				$xtpl->table_td('---');
		}
		
		$xtpl->table_td($chain->label);
		$xtpl->table_td(transaction_chain_concerns($chain));
		$xtpl->table_td($chain->state);
		$xtpl->table_td($chain->size);
		$xtpl->table_td($chain->progress .' ('.round($chain->progress / $chain->size * 100, 0).' %)');
		$xtpl->table_tr(false, chain_class($chain));
	}

	$xtpl->table_out();
}

function transaction_class($t) {
	if ($t->done == 'done' && $t->success == 1)
		return 'ok';
		
	elseif ($t->done == 'done' && $t->success == 0)
		return 'error';
	
	elseif ($t->done == 'done' && $t->success == 2)
		return 'warning';
	
	elseif ($t->done == 'waiting' && $t->success == 0)
		return 'pending';
	
	return '';
}

function chain_transactions($chain_id) {
	global $xtpl, $api;
	
	try {
		$chain = $api->transaction_chain->find($chain_id);
		
	} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
		$xtpl->perex_format_errors(_('Chain not found'), $e->getResponse());
		return;
	}
	
	$xtpl->table_title(_('Transaction chain').' #'.$chain->id.' '.$chain->label);
	$xtpl->table_add_category(_('Chain info'));
	$xtpl->table_add_category('');
	
	$xtpl->table_td(_('Name'));
	$xtpl->table_td($chain->name);
	$xtpl->table_tr();
	
	$xtpl->table_td(_('Concerns'));
	$xtpl->table_td(transaction_chain_concerns($chain));
	$xtpl->table_tr();
	
	$xtpl->table_td(_('State'));
	$xtpl->table_td($chain->state);
	$xtpl->table_tr();
	
	$xtpl->table_td(_('Size'));
	$xtpl->table_td($chain->size);
	$xtpl->table_tr();
	
	$xtpl->table_td(_('Progress'));
	$xtpl->table_td($chain->progress .' ('.round($chain->progress / $chain->size * 100, 0).' %)');
	$xtpl->table_tr();
	
	$xtpl->table_td(_('User'));
	$xtpl->table_td($chain->user_id ? ('<a href="?page=adminm&action=edit&id='.$chain->user_id.'">'.$chain->user->login.'</a>') : '---');
	$xtpl->table_tr();
	
	$xtpl->table_td(_('Created at'));
	$xtpl->table_td(tolocaltz($chain->created_at));
	$xtpl->table_tr();
	
	$xtpl->table_out();
	
	$xtpl->table_title(_('Filters'));
	$xtpl->form_create('', 'get', 'transaction-filter', false);
	
	$xtpl->table_td(_("Limit").':'.
		'<input type="hidden" name="page" value="transactions">'.
		'<input type="hidden" name="chain" value="'.$chain->id.'">'
	);
	$xtpl->form_add_input_pure('text', '40', 'limit', get_val('limit', '100'));
	$xtpl->table_tr();
	
	$xtpl->form_add_input(_("Offset").':', 'text', '40', 'offset', get_val('offset', '0'));
	$xtpl->form_add_input(_("Exact ID").':', 'text', '40', 'transaction', get_val('transaction'));
	$xtpl->form_add_select(_("Node").':', 'node', 
		resource_list_to_options($api->node->list(), 'id', 'name'), get_val('node'));
	$xtpl->form_add_input(_("Type").':', 'text', '40', 'type', get_val('type'));
	$xtpl->form_add_input(_("Done").':', 'text', '40', 'done', get_val('done'));
	$xtpl->form_add_input(_("Success").':', 'text', '40', 'success', get_val('success'));
	$xtpl->form_add_checkbox(_("Detailed mode").':', 'details', '1', get_val('details'));
	
	$xtpl->form_out(_('Show'));
	
	$meta = array('includes' => 'user,node');
	
	if ($_GET['transaction']) {
		$transactions = array();
		$transactions[] = $chain->transaction->find($_GET['transaction'], array('meta' => $meta));
		
	} else {
		$params = array(
			'limit' => get_val('limit', '100'),
			'offset' => get_val('offset', '0'),
			'meta' => $meta
		);
		
		if ($_GET['node'])
			$params['node'] = $_GET['node'];
		
		if ($_GET['type'])
			$params['type'] = $_GET['type'];
		
		if ($_GET['done'])
			$params['done'] = $_GET['done'];
		
		if ($_GET['success'])
			$params['success'] = $_GET['success'];
		
		$transactions = $chain->transaction->list($params);
	}
	
	$xtpl->table_title(_('Chained transactions'));
	$xtpl->table_add_category("ID");
	$xtpl->table_add_category("QUEUED");
	$xtpl->table_add_category("TIME");
	$xtpl->table_add_category("REAL");
	$xtpl->table_add_category("USER");
	$xtpl->table_add_category("NODE");
	$xtpl->table_add_category("TYPE");
	$xtpl->table_add_category("PRIO");
	$xtpl->table_add_category("DONE?");
	$xtpl->table_add_category("OK?");
	
	foreach ($transactions as $t) {
		$created_at = strtotime($t->created_at);
		$started_at = strtotime($t->started_at);
		$finished_at = strtotime($t->finished_at);
		
		$xtpl->table_td('<a href="?page=transactions&chain='.$chain->id.'&transaction='.$t->id.'&details=1">'.$t->id.'</a>');
		$xtpl->table_td(tolocaltz($t->created_at));
		$xtpl->table_td(format_duration(($finished_at ? $finished_at - $created_at : 0)));
		$xtpl->table_td(format_duration($finished_at - $started_at));
		$xtpl->table_td($t->user_id ? ('<a href="?page=adminm&action=edit&id='.$t->user_id.'">'.$t->user->login.'</a>') : '---');
		$xtpl->table_td($t->node->name);
		$xtpl->table_td($t->name.' ('.$t->type.')');
		$xtpl->table_td(($t->urgent ? '<img src="template/icons/warning.png" alt="'._('Urgent').'" title="'._('Urgent').'"> ' : '') . $t->priority);
		$xtpl->table_td($t->done);
		$xtpl->table_td($t->success);
		$xtpl->table_tr(false, transaction_class($t));
		
		if ($_GET['details']) {
			$xtpl->table_td(nl2br(
				"<strong>"._('Input')."</strong>\n".
				"<pre><code>".htmlspecialchars(print_r(json_decode($t->input, true), true))."</pre></code>".
				"\n<strong>"._('Output')."</strong>\n".
				"<pre><code>".htmlspecialchars(print_r(json_decode($t->output, true), true))."</pre></code>"
			), false, false, 10);
			$xtpl->table_tr();
		}
	}
	
	$xtpl->table_out();
}

if ($_SESSION["logged_in"]) {

if ($_GET['chain']) {
	chain_transactions($_GET['chain']);

} else {
	list_chains();
}

} else $xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
