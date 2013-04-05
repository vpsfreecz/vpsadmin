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
  `type` ENUM(  'data',  'backup' ) NOT NULL,
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
ALTER TABLE `vps`
  DROP `vps_privvmpages`,
  DROP `vps_cpulimit`,
  DROP `vps_cpuprio`,
  DROP `vps_diskspace`;

ALTER TABLE  `vps` ADD  `vps_deleted` INT( 11 ) NULL AFTER  `vps_created`;
ALTER TABLE  `vps` ADD  `vps_backup_export` INT NOT NULL AFTER  `vps_features_enabled`;

ALTER TABLE  `members` ADD  `m_state` ENUM(  'active',  'suspended',  'deleted' ) NOT NULL DEFAULT  'active' AFTER `m_active`;
UPDATE members SET m_state = 'suspended' WHERE m_active = 0;
ALTER TABLE members DROP `m_active`;
ALTER TABLE  `members` ADD  `m_deleted` INT NULL AFTER  `m_created`;

-- Fix traffic accounting - replace NULLs with 0
UPDATE `transfered` SET tr_in = 0 WHERE tr_in IS NULL;
UPDATE `transfered` SET tr_out = 0 WHERE tr_out IS NULL;

ALTER TABLE  `transfered` CHANGE  `tr_in`  `tr_in` BIGINT( 63 ) UNSIGNED NOT NULL DEFAULT  '0',
CHANGE  `tr_out`  `tr_out` BIGINT( 63 ) UNSIGNED NOT NULL DEFAULT  '0';

-- Fix IPv6 traffic
UPDATE `transfered` SET tr_ip = REPLACE( tr_ip,  '/128',  '' ) WHERE tr_ip LIKE  '%/128';
