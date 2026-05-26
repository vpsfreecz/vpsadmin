<?php

/**
 * This script is used to maintain PHP session to avoid it being garbage-collected
 * on session.gc_maxlifetime. Since the JavaScript code communicates directly
 * with the API, the PHP session would expire even when the API access token
 * is still valid.
 */

include '/etc/vpsadmin/config.php';
session_start();
exit;
