<?php

$vps = $api->vps->find($_GET["veid"], array('meta' => array('includes' => 'user')));

if ($vps->object_state != 'active' || $vps->user->object_state != 'active')
	exit;

switch ($_GET["action"]) {
	default:
		break;
}
