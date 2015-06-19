<?php
/*
    ./lib/transact.lib.php

    vpsAdmin
    Web-admin interface for OpenVZ (see http://openvz.org)
    Copyright (C) 2008-2011 Pavel Snajdr, snajpa@snajpa.net
*/

function list_transaction_chains() {
	global $api, $xtpl;
	
	$chains = $api->transaction_chain->list(array('limit' => 10));
	
	foreach($chains as $chain) {
		$xtpl->transaction_chain($chain);
	}
	
	$xtpl->transaction_chains_out();
}
