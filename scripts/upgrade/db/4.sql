CREATE TABLE IF NOT EXISTS `node_node` (
  `node_id` int(11) NOT NULL,
  `max_vps` int(11) NOT NULL,
  `ve_private` varchar(255) COLLATE utf8_czech_ci NOT NULL DEFAULT '/vz/private/%{veid}',
  `fstype` ENUM('ext4',  'zfs') NOT NULL DEFAULT 'ext4',
  PRIMARY KEY (`node_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

INSERT INTO `node_node` SELECT server_id, server_maxvps, '/vz/private/%{veid}' FROM servers WHERE server_type = 'node';

ALTER TABLE `servers` DROP server_maxvps, server_path_vz;
