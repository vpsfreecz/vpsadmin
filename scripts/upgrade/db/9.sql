DROP TABLE `servers_status`;

CREATE TABLE `servers_status` (
  `server_id` int(10) unsigned NOT NULL,
  `timestamp` int(10) unsigned NOT NULL,
  `ram_free_mb` int(10) unsigned DEFAULT NULL,
  `disk_vz_free_gb` float unsigned DEFAULT NULL,
  `cpu_load` float unsigned DEFAULT NULL,
  `daemon` tinyint(1) NOT NULL,
  `vpsadmin_version` varchar(63) DEFAULT NULL,
  PRIMARY KEY (`server_id`)
) ENGINE=MEMORY  DEFAULT CHARSET=utf8 ;
