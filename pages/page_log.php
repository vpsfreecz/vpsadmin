<?php

$xtpl->title(_("Log"));

$xtpl->table_add_category(_("Date and time"));
$xtpl->table_add_category(_("Message"));

foreach ($api->news_log->list() as $news) {
	$xtpl->table_td('['.tolocaltz($news->published_at, "Y-m-d H:i").']');
	$xtpl->table_td($news->message);
	$xtpl->table_tr();
}
$xtpl->table_out("notice_board");
