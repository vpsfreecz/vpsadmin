-- API requirements
-- ----------------

-- Members
ALTER TABLE `members` ADD `login_count` int(11) NOT NULL DEFAULT '0' AFTER `m_suspend_reason`;
ALTER TABLE `members` ADD `failed_login_count` int(11) NOT NULL DEFAULT '0' AFTER `login_count`;
ALTER TABLE `members` ADD `last_request_at` datetime DEFAULT NULL AFTER `failed_login_count`;
ALTER TABLE `members` ADD `current_login_at` datetime DEFAULT NULL AFTER `last_request_at`;
ALTER TABLE `members` ADD `last_login_at` datetime DEFAULT NULL AFTER `current_login_at`;
ALTER TABLE `members` ADD `current_login_ip` varchar(255) COLLATE utf8_unicode_ci DEFAULT NULL AFTER `last_login_at`;
ALTER TABLE `members` ADD `last_login_ip` varchar(255) COLLATE utf8_unicode_ci DEFAULT NULL AFTER `current_login_ip`;
ALTER TABLE `members` ADD `created_at` datetime DEFAULT NULL AFTER `last_login_ip`;
ALTER TABLE `members` ADD `updated_at` datetime DEFAULT NULL AFTER `created_at`;

-- Environments
CREATE TABLE IF NOT EXISTS `environments` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `label` varchar(100) COLLATE utf8_unicode_ci NOT NULL,
  `domain` varchar(100) COLLATE utf8_unicode_ci NOT NULL,
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 ;

-- Locations
ALTER TABLE `locations` DROP `location_has_ospf`;
ALTER TABLE `locations` DROP `location_has_rdiff_backup`;
ALTER TABLE `locations` DROP `location_rdiff_target`;
ALTER TABLE `locations` DROP `location_rdiff_history`;
ALTER TABLE `locations` DROP `location_rdiff_mount_sshfs`;
ALTER TABLE `locations` DROP `location_rdiff_mount_archfs`;
ALTER TABLE `locations` DROP `location_rdiff_target_path`;
ALTER TABLE `locations` DROP `location_tpl_sync_path`;
ALTER TABLE `locations` DROP `location_backup_server_id`;

ALTER TABLE `locations` ADD `environment_id` int(11) DEFAULT NULL AFTER `location_remote_console_server`;
ALTER TABLE `locations` ADD `domain` varchar(100) COLLATE utf8_unicode_ci NOT NULL AFTER `environment_id`;
ALTER TABLE `locations` ADD `created_at` datetime DEFAULT NULL AFTER `domain`;
ALTER TABLE `locations` ADD `updated_at` datetime DEFAULT NULL AFTER `created_at`;

-- Servers - put everything to one table
ALTER TABLE `servers` ADD `max_vps` int(11) NOT NULL;
ALTER TABLE `servers` ADD `ve_private` varchar(255) CHARACTER SET utf8 COLLATE utf8_czech_ci NOT NULL DEFAULT '/vz/private/%veid%';
ALTER TABLE `servers` ADD `fstype` enum('ext4','zfs','zfs_compat') NOT NULL DEFAULT 'zfs';

UPDATE `servers` s INNER JOIN `node_node` n ON s.server_id = n.node_id
SET s.max_vps = n.max_vps, s.ve_private = n.ve_private, s.fstype = n.fstype;

    
DROP TABLE `node_node`;
DROP TABLE IF EXISTS `node_storage`;

-- Storage root
ALTER TABLE `storage_root` CHANGE `type` `storage_layout` enum('per_member', 'per_vps') NOT NULL;
ALTER TABLE `storage_root` MODIFY `used` bigint(20) NOT NULL DEFAULT '0';
ALTER TABLE `storage_root` MODIFY `avail` bigint(20) NOT NULL DEFAULT '0';

-- Storage export
ALTER TABLE `storage_export` CHANGE `type` `data_type` enum('data', 'backup') NOT NULL;
ALTER TABLE `storage_export` MODIFY `used` bigint(20) NOT NULL DEFAULT '0';
ALTER TABLE `storage_export` MODIFY `avail` bigint(20) NOT NULL DEFAULT '0';

-- Templates
ALTER TABLE `cfg_templates` DROP `special`;

-- Vpses
ALTER TABLE `vps` DROP `vps_specials_installed`;
ALTER TABLE `vps` ADD `dns_resolver_id` int DEFAULT NULL AFTER `vps_nameserver`;

UPDATE `vps`
INNER JOIN servers s ON vps_server = s.server_id
LEFT JOIN cfg_dns dns ON vps_nameserver = dns.dns_ip AND (dns_location = server_location OR dns_is_universal)
SET dns_resolver_id = dns.dns_id;

ALTER TABLE `vps` DROP `vps_nameserver`;

-- IP addresses
ALTER TABLE  `vps_ip` CHANGE  `vps_id`  `vps_id` INT( 10 ) UNSIGNED NULL;

-- PaperTrail
CREATE TABLE IF NOT EXISTS `versions` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `item_type` varchar(255) COLLATE utf8_unicode_ci NOT NULL,
  `item_id` int(11) NOT NULL,
  `event` varchar(255) COLLATE utf8_unicode_ci NOT NULL,
  `whodunnit` varchar(255) COLLATE utf8_unicode_ci DEFAULT NULL,
  `object` text COLLATE utf8_unicode_ci,
  `created_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_versions_on_item_type_and_item_id` (`item_type`,`item_id`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 ;
