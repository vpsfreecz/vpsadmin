CREATE TABLE IF NOT EXISTS `transfered_tmp` (
  `tr_ip` varchar(127) NOT NULL,
  `tr_proto` varchar(4) NOT NULL,
  `tr_packets_in` bigint(63) unsigned NOT NULL DEFAULT '0',
  `tr_packets_out` bigint(63) unsigned NOT NULL DEFAULT '0',
  `tr_bytes_in` bigint(63) unsigned NOT NULL DEFAULT '0',
  `tr_bytes_out` bigint(63) unsigned NOT NULL DEFAULT '0',
  `tr_date` datetime NOT NULL,
  PRIMARY KEY (`tr_ip`, `tr_proto`, `tr_date`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 ;

INSERT INTO `transfered_tmp` (tr_ip, tr_proto, tr_packets_in, tr_packets_out, tr_bytes_in, tr_bytes_out, tr_date)
SELECT tr_ip, 'all', 0, 0, SUM(tr_in), SUM(tr_out), FROM_UNIXTIME(tr_time) FROM `transfered`
GROUP BY tr_ip, tr_time;

DROP TABLE `transfered`;
RENAME TABLE `transfered_tmp` TO `transfered`;

CREATE TABLE IF NOT EXISTS `transfered_recent` (
  `tr_ip` varchar(127) NOT NULL,
  `tr_proto` varchar(5) NOT NULL,
  `tr_packets_in` bigint(63) unsigned NOT NULL DEFAULT '0',
  `tr_packets_out` bigint(63) unsigned NOT NULL DEFAULT '0',
  `tr_bytes_in` bigint(63) unsigned NOT NULL DEFAULT '0',
  `tr_bytes_out` bigint(63) unsigned NOT NULL DEFAULT '0',
  `tr_date` datetime NOT NULL,
  PRIMARY KEY (`tr_ip`, `tr_proto`, `tr_date`)
) ENGINE=MEMORY DEFAULT CHARSET=utf8;
