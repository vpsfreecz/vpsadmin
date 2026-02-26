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

    $params = [
        'view' => true,
        'limit' => 1000,
    ];

    if ($pageProvided) {
        $params['page'] = $page;
    }

    if ($actionProvided) {
        $params['action'] = $action;
    }

    $boxes = $api->help_box->list($params);

    $ret = '';

    foreach ($boxes as $box) {
        $ret .= $box->content . '<br>';
    }

    return $ret;
}
