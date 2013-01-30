<?php

$xtpl->title(_("Log"));

$xtpl->table_add_category(_("Date and time"));
$xtpl->table_add_category(_("Message"));

while($log = $db->find("log", NULL, "timestamp DESC")) {
	$xtpl->table_td('['.strftime("%Y-%m-%d %H:%M", $log["timestamp"]).']');
	$xtpl->table_td($log["msg"]);
	$xtpl->table_tr();
}
$xtpl->table_out("notice_board");
