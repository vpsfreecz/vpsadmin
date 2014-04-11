ALTER TABLE `transactions` ADD `t_urgent` tinyint(1) NOT NULL DEFAULT '0' AFTER `t_fallback`;
