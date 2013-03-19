CREATE TABLE IF NOT EXISTS `storage_root` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `node_id` int(11) NOT NULL,
  `label` varchar(255) COLLATE utf8_czech_ci NOT NULL,
  `root_dataset` varchar(500) COLLATE utf8_czech_ci NOT NULL,
  `root_path` varchar(500) COLLATE utf8_czech_ci NOT NULL,
  `type` enum('per_member','per_vps') COLLATE utf8_czech_ci NOT NULL,
  `user_export` tinyint(4) NOT NULL DEFAULT '0',
  `user_mount` enum('none','ro','rw') COLLATE utf8_czech_ci NOT NULL DEFAULT 'none',
  `quota` bigint(20) unsigned NOT NULL,
  `used` bigint(20) unsigned NOT NULL,
  `avail` bigint(20) unsigned NOT NULL,
  `share_options` varchar(500) COLLATE utf8_czech_ci NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_czech_ci;

CREATE TABLE IF NOT EXISTS `storage_export` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `member_id` int(11) NOT NULL,
  `root_id` int(11) NOT NULL,
  `dataset` varchar(500) COLLATE utf8_czech_ci NOT NULL,
  `path` varchar(500) COLLATE utf8_czech_ci NOT NULL,
  `quota` bigint(20) unsigned NOT NULL,
  `used` bigint(20) unsigned NOT NULL,
  `avail` bigint(20) unsigned NOT NULL,
  `user_editable` tinyint(4) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 COLLATE=utf8_czech_ci ;

CREATE TABLE IF NOT EXISTS `vps_mount` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `vps_id` int(11) NOT NULL,
  `src` varchar(500) COLLATE utf8_czech_ci NOT NULL,
  `dst` varchar(500) COLLATE utf8_czech_ci NOT NULL,
  `mount_opts` varchar(255) COLLATE utf8_czech_ci NOT NULL,
  `umount_opts` varchar(255) COLLATE utf8_czech_ci NOT NULL,
  `type` enum('bind','nfs') COLLATE utf8_czech_ci NOT NULL,
  `server_id` int(11) DEFAULT NULL,
  `storage_export_id` int(11) DEFAULT NULL,
  `mode` enum('ro','rw') COLLATE utf8_czech_ci NOT NULL,
  `cmd_premount` varchar(500) COLLATE utf8_czech_ci NOT NULL,
  `cmd_postmount` varchar(500) COLLATE utf8_czech_ci NOT NULL,
  `cmd_preumount` varchar(500) COLLATE utf8_czech_ci NOT NULL,
  `cmd_postumount` varchar(500) COLLATE utf8_czech_ci NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 COLLATE=utf8_czech_ci ;

UPDATE `servers` SET `server_type` = 'storage' WHERE `server_type` = 'backuper';
ALTER TABLE  `servers` CHANGE  `server_type`  `server_type` ENUM(  'node',  'storage',  'mailer' ) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL;

ALTER TABLE `vps` DROP `vps_backup_mount`;
