CREATE TABLE IF NOT EXISTS `members_changes` (
  `m_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `m_created` int(11) NOT NULL,
  `m_type` ENUM('add', 'change') NOT NULL,
  `m_state` ENUM('awaiting','approved','denied','invalid','ignored') NOT NULL,
  `m_applicant` int (11) NULL,
  `m_changed_by` int(11) NULL,
  `m_changed_at` int(11) NULL,
  `m_nick` varchar(63) NULL,
  `m_name` varchar(255) NULL,
  `m_mail` varchar(127) NULL,
  `m_address` text NULL,
  `m_year` int(11) NULL,
  `m_jabber` varchar(255) NULL,
  `m_how` varchar(500) NULL,
  `m_note` varchar(500) NULL,
  `m_distribution` int(11) NULL,
  `m_location` int(11) NULL,
  `m_currency` varchar(10) NULL,
  `m_addr` varchar(127) NOT NULL,
  `m_addr_reverse` varchar(255) NOT NULL,
  `m_reason` varchar(500) NOT NULL,
  `m_admin_response` varchar(500) NULL,
  `m_last_mail_id` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`m_id`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 ;

ALTER TABLE cfg_templates ADD `templ_supported` tinyint(4) NOT NULL DEFAULT '1' AFTER templ_enabled;
