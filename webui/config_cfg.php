<?php

$cfg_privlevel[PRIV_USER] = 'User';

$cfg_privlevel[PRIV_POWERUSER] = 'Power User';
$cfg_privlevel[PRIV_ADMIN] = 'Admin';
$cfg_privlevel[PRIV_SUPERADMIN] = 'Super Admin';
$cfg_privlevel[PRIV_GOD] = 'Master Admin';

$cfg_transactions['per_page'] = 25;
$cfg_transactions['max_offset_listing'] = 6;

/********************************************************
    change this, if you want to have table header for:
     'server' - each server
     '' - only one heading on vpsmanagement page
********************************************************/
$cfg_adminvps['table_heading'] = '';

$langs = [
    "en_US.utf8" => [
        "code" => "en_US.utf8",
        "api_code" => "en",
        "html" => "en",
        "icon" => "us",
        "lang" => "English",
        "aliases" => ["en", "en-US"],
    ],
    "cs_CZ.utf8" => [
        "code" => "cs_CZ.utf8",
        "api_code" => "cs",
        "html" => "cs",
        "icon" => "cz",
        "lang" => "Česky",
        "aliases" => ["cs", "cs-CZ"],
    ],
];
