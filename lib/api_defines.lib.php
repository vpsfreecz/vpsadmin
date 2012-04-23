<?php

define('PARAM_SINGLE'						, 0);
define('PARAM_ARRAY'						, 1);

/** RETURN MESSAGES **/

$RET_MSG = array();

define(	'RET_OK'						, 0);
$RET_MSG[RET_OK]						= "ok";

define(	'RET_QUEUED'				, 1);
$RET_MSG[RET_QUEUED]				= "request queued";

define(	'RET_ERROR'					, -1);
$RET_MSG[RET_ERROR]					= "general failure";

define(	'RET_EINVALIDREQ'		, -2);
$RET_MSG[RET_EINVALIDREQ]		= "invalid request";

define(	'RET_EMALFORM'			, -3);
$RET_MSG[RET_EMALFORM]			= "malformed request";

define(	'RET_EPMISSING'			, -4);
$RET_MSG[RET_EPMISSING]			= "missing parameter";

define(	'RET_EPINVALID'			, -5);
$RET_MSG[RET_EPINVALID]			= "invalid parameter";

define(	'RET_ENOAC'					, -6);
$RET_MSG[RET_ENOAC]					= "access denied";

define(	'RET_ENI'						, -1000);
$RET_MSG[RET_ENI]						= "not implemented";

define(	'RET_EDISABLED'			, -1001);
$RET_MSG[RET_EDISABLED]			= "api disabled";
