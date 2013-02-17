CREATE TABLE IF NOT EXISTS `cfg_dns` (
  `dns_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `dns_ip` varchar(63) NOT NULL,
  `dns_label` varchar(63) NOT NULL,
  `dns_is_universal` tinyint(1) unsigned DEFAULT '0',
  `dns_location` int(10) unsigned DEFAULT NULL,
  PRIMARY KEY (`dns_id`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 ;

CREATE TABLE IF NOT EXISTS `cfg_templates` (
  `templ_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `templ_name` varchar(64) NOT NULL,
  `templ_label` varchar(64) NOT NULL,
  `templ_info` text,
  `special` varchar(255) DEFAULT NULL,
  `templ_enabled` tinyint(4) NOT NULL DEFAULT '1',
  PRIMARY KEY (`templ_id`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 ;

CREATE TABLE IF NOT EXISTS `config` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(50) CHARACTER SET utf8 COLLATE utf8_czech_ci NOT NULL,
  `label` varchar(50) NOT NULL,
  `config` text NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 ;

CREATE TABLE IF NOT EXISTS `helpbox` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `page` varchar(50) NOT NULL,
  `action` varchar(50) NOT NULL,
  `content` text NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 ;

CREATE TABLE IF NOT EXISTS `locations` (
  `location_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `location_label` varchar(63) NOT NULL,
  `location_type` enum('production','playground') NOT NULL DEFAULT 'production',
  `location_has_ipv6` tinyint(1) NOT NULL,
  `location_vps_onboot` tinyint(1) unsigned NOT NULL DEFAULT '1',
  `location_has_ospf` tinyint(1) unsigned NOT NULL DEFAULT '0',
  `location_has_rdiff_backup` tinyint(1) unsigned NOT NULL DEFAULT '0',
  `location_rdiff_target` varchar(64) DEFAULT NULL,
  `location_rdiff_history` int(11) DEFAULT NULL,
  `location_rdiff_mount_sshfs` varchar(255) DEFAULT NULL,
  `location_rdiff_mount_archfs` varchar(255) DEFAULT NULL,
  `location_rdiff_target_path` varchar(255) DEFAULT NULL,
  `location_tpl_sync_path` varchar(255) NOT NULL,
  `location_backup_server_id` int(11) DEFAULT NULL,
  `location_remote_console_server` varchar(255) NOT NULL,
  PRIMARY KEY (`location_id`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 ;

CREATE TABLE IF NOT EXISTS `log` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `timestamp` int(11) NOT NULL,
  `msg` text NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 ;

CREATE TABLE IF NOT EXISTS `mailer` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `sentTime` int(11) unsigned NOT NULL,
  `member_id` int(10) unsigned DEFAULT NULL,
  `type` varchar(255) NOT NULL,
  `details` text NOT NULL,
  PRIMARY KEY (`id`),
  KEY `member_id` (`member_id`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 ;

CREATE TABLE IF NOT EXISTS `members` (
  `m_info` text,
  `m_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `m_created` int(11) unsigned DEFAULT NULL,
  `m_level` int(10) unsigned NOT NULL,
  `m_nick` varchar(63) NOT NULL,
  `m_name` varchar(255) NOT NULL,
  `m_pass` varchar(255) NOT NULL,
  `m_mail` varchar(127) NOT NULL,
  `m_address` text NOT NULL,
  `m_lang` varchar(16) DEFAULT NULL,
  `m_paid_until` varchar(32) DEFAULT NULL,
  `m_last_activity` int(10) unsigned DEFAULT NULL,
  `m_monthly_payment` int(10) unsigned NOT NULL DEFAULT '300',
  `m_mailer_enable` tinyint(1) unsigned NOT NULL DEFAULT '1',
  `m_playground_enable` tinyint(1) NOT NULL DEFAULT '1',
  `m_active` tinyint(4) NOT NULL DEFAULT '1',
  `m_suspend_reason` varchar(100) NOT NULL,
  PRIMARY KEY (`m_id`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 ;

CREATE TABLE IF NOT EXISTS `members_payments` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `m_id` int(11) NOT NULL,
  `acct_m_id` int(11) NOT NULL,
  `timestamp` bigint(20) NOT NULL,
  `change_from` bigint(20) NOT NULL,
  `change_to` bigint(20) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 ;

CREATE TABLE IF NOT EXISTS `servers` (
  `server_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `server_name` varchar(64) NOT NULL,
  `server_type` enum('node','backuper','storage','mailer') NOT NULL,
  `server_location` int(10) unsigned NOT NULL,
  `server_availstat` text,
  `server_ip4` varchar(127) NOT NULL,
  `server_maxvps` int(10) unsigned DEFAULT NULL,
  `server_path_vz` varchar(63) NOT NULL DEFAULT '/var/lib/vz',
  PRIMARY KEY (`server_id`),
  KEY `server_location` (`server_location`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 ;

CREATE TABLE IF NOT EXISTS `servers_status` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `server_id` int(10) unsigned NOT NULL,
  `timestamp` int(10) unsigned NOT NULL,
  `ram_free_mb` int(10) unsigned DEFAULT NULL,
  `disk_vz_free_gb` float unsigned DEFAULT NULL,
  `cpu_load` float unsigned DEFAULT NULL,
  `daemon` tinyint(1) NOT NULL,
  `vpsadmin_version` varchar(63) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `server_id` (`server_id`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 ;

CREATE TABLE IF NOT EXISTS `sysconfig` (
  `cfg_name` varchar(127) NOT NULL,
  `cfg_value` text,
  PRIMARY KEY (`cfg_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `transactions` (
  `t_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `t_group` int(10) unsigned DEFAULT NULL,
  `t_time` int(10) unsigned DEFAULT NULL,
  `t_real_start` int(11) DEFAULT NULL,
  `t_end` int(11) DEFAULT NULL,
  `t_m_id` int(10) unsigned DEFAULT NULL,
  `t_server` int(10) unsigned DEFAULT NULL,
  `t_vps` int(10) unsigned DEFAULT NULL,
  `t_type` int(10) unsigned NOT NULL,
  `t_depends_on` int(11) DEFAULT NULL,
  `t_priority` int(11) NOT NULL DEFAULT '0',
  `t_success` int(10) unsigned NOT NULL,
  `t_done` tinyint(1) unsigned NOT NULL,
  `t_param` text,
  `t_output` text,
  PRIMARY KEY (`t_id`),
  KEY `t_server` (`t_server`)
) ENGINE=MyISAM  DEFAULT CHARSET=utf8 ;

CREATE TABLE IF NOT EXISTS `transaction_groups` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `is_clusterwide` tinyint(1) unsigned DEFAULT '0',
  `is_locationwide` tinyint(1) unsigned DEFAULT '0',
  `location_id` int(10) unsigned DEFAULT '0',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 ;

CREATE TABLE IF NOT EXISTS `transfered` (
  `tr_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `tr_ip` varchar(127) NOT NULL,
  `tr_in` bigint(63) unsigned DEFAULT '0',
  `tr_out` bigint(63) unsigned DEFAULT '0',
  `tr_time` int(10) unsigned NOT NULL,
  PRIMARY KEY (`tr_id`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 ;

CREATE TABLE IF NOT EXISTS `vps` (
  `vps_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `vps_created` int(11) unsigned DEFAULT NULL,
  `m_id` int(63) unsigned NOT NULL,
  `vps_hostname` varchar(64) DEFAULT 'darkstar',
  `vps_template` int(10) unsigned NOT NULL DEFAULT '1',
  `vps_info` mediumtext,
  `vps_nameserver` varchar(255) NOT NULL DEFAULT '4.2.2.2',
  `vps_privvmpages` int(10) unsigned NOT NULL DEFAULT '1',
  `vps_cpulimit` int(11) DEFAULT NULL,
  `vps_cpuprio` varchar(255) DEFAULT NULL,
  `vps_diskspace` bigint(10) unsigned NOT NULL DEFAULT '0',
  `vps_server` int(11) unsigned NOT NULL,
  `vps_onboot` tinyint(1) unsigned NOT NULL DEFAULT '1',
  `vps_onstartall` tinyint(1) unsigned NOT NULL DEFAULT '1',
  `vps_backup_enabled` tinyint(1) unsigned NOT NULL DEFAULT '1',
  `vps_backup_mount` tinyint(1) unsigned NOT NULL DEFAULT '0',
  `vps_specials_installed` varchar(255) DEFAULT NULL,
  `vps_features_enabled` tinyint(1) NOT NULL DEFAULT '0',
  `vps_backup_lock` tinyint(4) NOT NULL DEFAULT '0',
  `vps_backup_exclude` text NOT NULL,
  `vps_config` text CHARACTER SET utf8 COLLATE utf8_czech_ci NOT NULL,
  PRIMARY KEY (`vps_id`),
  KEY `m_id` (`m_id`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 ;

CREATE TABLE IF NOT EXISTS `vps_backups` (
  `vps_id` int(10) unsigned NOT NULL,
  `timestamp` int(10) unsigned NOT NULL,
  KEY `vps_id` (`vps_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `vps_console` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `vps_id` int(11) NOT NULL,
  `key` varchar(64) NOT NULL,
  `expiration` datetime NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 ;

CREATE TABLE IF NOT EXISTS `vps_has_config` (
  `vps_id` int(11) NOT NULL,
  `config_id` int(11) NOT NULL,
  `order` int(11) NOT NULL,
  PRIMARY KEY (`vps_id`,`config_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `vps_ip` (
  `ip_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `vps_id` int(10) unsigned NOT NULL,
  `ip_v` int(10) unsigned NOT NULL DEFAULT '4',
  `ip_location` int(10) unsigned NOT NULL,
  `ip_addr` varchar(40) NOT NULL,
  PRIMARY KEY (`ip_id`),
  KEY `vps_id` (`vps_id`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 ;

CREATE TABLE IF NOT EXISTS `vps_status` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `vps_id` int(10) unsigned NOT NULL,
  `timestamp` int(10) unsigned NOT NULL,
  `vps_up` tinyint(1) unsigned DEFAULT NULL,
  `vps_nproc` int(10) unsigned DEFAULT NULL,
  `vps_vm_used_mb` int(10) unsigned DEFAULT NULL,
  `vps_disk_used_mb` int(10) unsigned DEFAULT NULL,
  `vps_admin_ver` varchar(63) DEFAULT 'not set',
  PRIMARY KEY (`id`),
  UNIQUE KEY `vps_id_2` (`vps_id`),
  KEY `vps_id` (`vps_id`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 ;

CREATE TABLE IF NOT EXISTS `vps_mount` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `vps_id` int(11) NOT NULL,
  `src` varchar(500) COLLATE utf8_czech_ci NOT NULL,
  `dst` varchar(500) COLLATE utf8_czech_ci NOT NULL,
  `options` varchar(255) COLLATE utf8_czech_ci NOT NULL,
  `mode` enum('bind','nfs') COLLATE utf8_czech_ci NOT NULL,
  `server_id` int(11) DEFAULT NULL,
  `type` enum('backup','nas','custom') COLLATE utf8_czech_ci NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 COLLATE=utf8_czech_ci ;
