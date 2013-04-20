ALTER TABLE  `vps_backups` ADD  `size` bigint(20) unsigned NOT NULL;

ALTER TABLE `storage_export` DROP `add_member_prefix`;
