<?php

function get_helpbox($page = null, $action = null)
{
    global $api;

    if (!$api->help_box) {
        return '';
    }

    $pageProvided = $page !== null;
    $actionProvided = $action !== null;

    if (!$pageProvided && array_key_exists('page', $_GET)) {
        $page = $_GET['page'];
        $pageProvided = true;
    }

    if (!$actionProvided && array_key_exists('action', $_GET)) {
        $action = $_GET['action'];
        $actionProvided = true;
    }

    if ($pageProvided && $page === false) {
        $page = '';
    }

    if ($actionProvided && $action === false) {
        $action = '';
    }

    $boxes = $api->help_box->list([
        'view' => true,
        'page' => $pageProvided ? $page : null,
        'action' => $actionProvided ? $action : null,
        'limit' => 1000,
    ]);

    $ret = '';

    foreach ($boxes as $box) {
        $ret .= $box->content . '<br>';
    }

    return $ret;
}
