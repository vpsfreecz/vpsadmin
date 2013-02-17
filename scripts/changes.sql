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
