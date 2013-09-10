ALTER TABLE  `node_node` CHANGE  `fstype`  `fstype` ENUM(  'ext4',  'zfs',  'zfs_compat' ) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL DEFAULT  'ext4';
