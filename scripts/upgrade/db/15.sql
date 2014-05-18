ALTER TABLE  `members`
  CHANGE  `m_name`  `m_name` VARCHAR( 255 ) CHARACTER SET utf8 COLLATE utf8_general_ci NULL ,
  CHANGE  `m_mail`  `m_mail` VARCHAR( 127 ) CHARACTER SET utf8 COLLATE utf8_general_ci NULL ,
  CHANGE  `m_address`  `m_address` TEXT CHARACTER SET utf8 COLLATE utf8_general_ci NULL,
  CHANGE `m_suspend_reason`  `m_suspend_reason` VARCHAR( 100 ) CHARACTER SET utf8 COLLATE utf8_general_ci NULL;

CREATE TABLE IF NOT EXISTS `schema_migrations` (
  `version` varchar(255) COLLATE utf8_unicode_ci NOT NULL,
  UNIQUE KEY `unique_schema_migrations` (`version`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

INSERT INTO `schema_migrations` (`version`) VALUES ('20140227150154');
