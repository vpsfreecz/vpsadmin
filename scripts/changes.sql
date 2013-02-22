-- v1.8.0-dev
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

CREATE TABLE IF NOT EXISTS `node_storage` (
  `node_id` int(11) NOT NULL,
  `root_dataset` varchar(500) COLLATE utf8_czech_ci NOT NULL,
  `root_path` varchar(500) COLLATE utf8_czech_ci NOT NULL,
  `type` enum('per_member','per_vps') COLLATE utf8_czech_ci NOT NULL,
  `user_export` tinyint(4) NOT NULL DEFAULT '0',
  `user_mount` enum('none','ro','rw') COLLATE utf8_czech_ci NOT NULL DEFAULT 'none',
  PRIMARY KEY (`node_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_czech_ci;

UPDATE `servers` SET `server_type` = 'storage' WHERE `server_type` = 'backuper';
ALTER TABLE  `servers` CHANGE  `server_type`  `server_type` ENUM(  'node',  'storage',  'mailer' ) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL;
