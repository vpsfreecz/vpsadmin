<?php

class CsrfTokenInvalid extends \Exception {};

function csrf_init($user, $passwd) {
	$_SESSION['csrf_base'] = hash('sha256', $user . $passwd . microtime());
	$_SESSION['csrf_tokens'] = array();
}

function csrf_token($name = 'common', $count = 1000) {
	if (isset($_SESSION['csrf_tokens'][$name]) && $_SESSION['csrf_tokens'][$name]['count'] > 0)
		return $_SESSION['csrf_tokens'][$name]['token'];
	
	$t = hash('sha1', $_SESSION['csrf_base'] . $name . microtime());
	
	$_SESSION['csrf_tokens'][$name] = array(
		'token' => $t,
		'count' => $count
	);
	
	return $t;
}

function csrf_check($name = 'common', $t = null) {
	if (!$t) {
		if (isset($_POST['csrf_token']))
			$t = $_POST['csrf_token'];
		
		elseif (isset($_GET['t']))
			$t = $_GET['t'];
		
		else
			throw new CsrfTokenInvalid();
	}
	
	if (
		   !isset($_SESSION['csrf_tokens'][$name])
		|| $_SESSION['csrf_tokens'][$name]['token'] != $t
		|| $_SESSION['csrf_tokens'][$name]['count']-- < 0
	)
		throw new CsrfTokenInvalid();
	
	if ($_SESSION['csrf_tokens'][$name]['count'] == 0)
		unset($_SESSION['csrf_tokens'][$name]);
	
	return true;
}
