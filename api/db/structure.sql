
/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;
DROP TABLE IF EXISTS `ar_internal_metadata`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `ar_internal_metadata` (
  `key` varchar(255) NOT NULL,
  `value` varchar(255) DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `auth_tokens`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `auth_tokens` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `token_id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `opts` varchar(255) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `api_ip_addr` varchar(46) DEFAULT NULL,
  `api_ip_ptr` varchar(255) DEFAULT NULL,
  `client_ip_addr` varchar(46) DEFAULT NULL,
  `client_ip_ptr` varchar(255) DEFAULT NULL,
  `user_agent_id` int(11) DEFAULT NULL,
  `client_version` varchar(255) DEFAULT NULL,
  `purpose` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `branches`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `branches` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `dataset_tree_id` int(11) NOT NULL,
  `name` varchar(255) NOT NULL,
  `index` int(11) NOT NULL DEFAULT 0,
  `head` tinyint(1) NOT NULL DEFAULT 0,
  `confirmed` int(11) NOT NULL DEFAULT 0,
  `created_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  `updated_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_branches_on_dataset_tree_id` (`dataset_tree_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `cluster_resource_package_items`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `cluster_resource_package_items` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `cluster_resource_package_id` int(11) NOT NULL,
  `cluster_resource_id` int(11) NOT NULL,
  `value` decimal(40,0) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `cluster_resource_package_items_unique` (`cluster_resource_package_id`,`cluster_resource_id`),
  KEY `cluster_resource_package_id` (`cluster_resource_package_id`),
  KEY `cluster_resource_id` (`cluster_resource_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `cluster_resource_packages`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `cluster_resource_packages` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `label` varchar(255) NOT NULL,
  `environment_id` int(11) DEFAULT NULL,
  `user_id` int(11) DEFAULT NULL,
  `created_at` datetime /* mariadb-5.3 */ NOT NULL,
  `updated_at` datetime /* mariadb-5.3 */ NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `cluster_resource_packages_unique` (`environment_id`,`user_id`),
  KEY `index_cluster_resource_packages_on_environment_id` (`environment_id`),
  KEY `index_cluster_resource_packages_on_user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `cluster_resource_uses`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `cluster_resource_uses` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `user_cluster_resource_id` int(11) NOT NULL,
  `class_name` varchar(255) NOT NULL,
  `table_name` varchar(255) NOT NULL,
  `row_id` int(11) NOT NULL,
  `value` decimal(40,0) NOT NULL,
  `confirmed` int(11) NOT NULL DEFAULT 0,
  `admin_lock_type` int(11) NOT NULL DEFAULT 0,
  `admin_limit` int(11) DEFAULT NULL,
  `enabled` tinyint(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  KEY `cluster_resouce_use_name_search` (`class_name`,`table_name`,`row_id`) USING BTREE,
  KEY `index_cluster_resource_uses_on_user_cluster_resource_id` (`user_cluster_resource_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `cluster_resources`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `cluster_resources` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL,
  `label` varchar(100) NOT NULL,
  `min` decimal(40,0) NOT NULL,
  `max` decimal(40,0) NOT NULL,
  `stepsize` int(11) NOT NULL,
  `resource_type` int(11) NOT NULL,
  `allocate_chain` varchar(255) DEFAULT NULL,
  `free_chain` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_cluster_resources_on_name` (`name`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `components`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `components` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `name` varchar(30) NOT NULL,
  `label` varchar(100) NOT NULL,
  `description` text NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_components_on_name` (`name`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `dataset_actions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `dataset_actions` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `pool_id` int(11) DEFAULT NULL,
  `src_dataset_in_pool_id` int(11) DEFAULT NULL,
  `dst_dataset_in_pool_id` int(11) DEFAULT NULL,
  `snapshot_id` int(11) DEFAULT NULL,
  `recursive` tinyint(1) NOT NULL DEFAULT 0,
  `dataset_plan_id` int(11) DEFAULT NULL,
  `dataset_in_pool_plan_id` int(11) DEFAULT NULL,
  `action` int(11) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `dataset_expansion_events`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `dataset_expansion_events` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `dataset_id` bigint(20) NOT NULL,
  `original_refquota` int(11) NOT NULL,
  `new_refquota` int(11) NOT NULL,
  `added_space` int(11) NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_dataset_expansion_events_on_dataset_id` (`dataset_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `dataset_expansion_histories`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `dataset_expansion_histories` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `dataset_expansion_id` bigint(20) NOT NULL,
  `original_refquota` int(11) NOT NULL,
  `new_refquota` int(11) NOT NULL,
  `added_space` int(11) NOT NULL,
  `admin_id` bigint(20) DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_dataset_expansion_histories_on_dataset_expansion_id` (`dataset_expansion_id`),
  KEY `index_dataset_expansion_histories_on_admin_id` (`admin_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `dataset_expansions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `dataset_expansions` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `vps_id` bigint(20) NOT NULL,
  `dataset_id` bigint(20) NOT NULL,
  `state` int(11) NOT NULL DEFAULT 0,
  `original_refquota` int(11) NOT NULL,
  `added_space` int(11) NOT NULL,
  `enable_notifications` tinyint(1) NOT NULL DEFAULT 1,
  `enable_shrink` tinyint(1) NOT NULL DEFAULT 1,
  `stop_vps` tinyint(1) NOT NULL DEFAULT 1,
  `last_shrink` datetime(6) DEFAULT NULL,
  `last_vps_stop` datetime(6) DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `over_refquota_seconds` int(11) NOT NULL DEFAULT 0,
  `max_over_refquota_seconds` int(11) NOT NULL,
  `last_over_refquota_check` datetime(6) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_dataset_expansions_on_vps_id` (`vps_id`),
  KEY `index_dataset_expansions_on_dataset_id` (`dataset_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `dataset_in_pool_plans`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `dataset_in_pool_plans` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `environment_dataset_plan_id` int(11) NOT NULL,
  `dataset_in_pool_id` int(11) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `dataset_in_pool_plans_unique` (`environment_dataset_plan_id`,`dataset_in_pool_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `dataset_in_pools`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `dataset_in_pools` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `dataset_id` int(11) NOT NULL,
  `pool_id` int(11) NOT NULL,
  `label` varchar(100) DEFAULT NULL,
  `used` int(11) NOT NULL DEFAULT 0,
  `avail` int(11) NOT NULL DEFAULT 0,
  `min_snapshots` int(11) NOT NULL DEFAULT 14,
  `max_snapshots` int(11) NOT NULL DEFAULT 20,
  `snapshot_max_age` int(11) NOT NULL DEFAULT 1209600,
  `mountpoint` varchar(500) DEFAULT NULL,
  `confirmed` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_dataset_in_pools_on_dataset_id_and_pool_id` (`dataset_id`,`pool_id`) USING BTREE,
  KEY `index_dataset_in_pools_on_dataset_id` (`dataset_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `dataset_plans`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `dataset_plans` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `dataset_properties`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `dataset_properties` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `pool_id` int(11) DEFAULT NULL,
  `dataset_id` int(11) DEFAULT NULL,
  `dataset_in_pool_id` int(11) DEFAULT NULL,
  `ancestry` varchar(255) DEFAULT NULL,
  `ancestry_depth` int(11) NOT NULL DEFAULT 0,
  `name` varchar(30) NOT NULL,
  `value` varchar(255) DEFAULT NULL,
  `inherited` tinyint(1) NOT NULL DEFAULT 1,
  `confirmed` int(11) NOT NULL DEFAULT 0,
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_dataset_properties_on_dataset_id` (`dataset_id`) USING BTREE,
  KEY `index_dataset_properties_on_dataset_in_pool_id_and_name` (`dataset_in_pool_id`,`name`) USING BTREE,
  KEY `index_dataset_properties_on_dataset_in_pool_id` (`dataset_in_pool_id`) USING BTREE,
  KEY `index_dataset_properties_on_pool_id` (`pool_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `dataset_property_histories`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `dataset_property_histories` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `dataset_property_id` int(11) NOT NULL,
  `value` int(11) NOT NULL,
  `created_at` datetime /* mariadb-5.3 */ NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_dataset_property_histories_on_dataset_property_id` (`dataset_property_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `dataset_trees`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `dataset_trees` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `dataset_in_pool_id` int(11) NOT NULL,
  `index` int(11) NOT NULL DEFAULT 0,
  `head` tinyint(1) NOT NULL DEFAULT 0,
  `confirmed` int(11) NOT NULL DEFAULT 0,
  `created_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  `updated_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_dataset_trees_on_dataset_in_pool_id` (`dataset_in_pool_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `datasets`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `datasets` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `full_name` varchar(1000) NOT NULL,
  `user_id` int(11) DEFAULT NULL,
  `user_editable` tinyint(1) NOT NULL,
  `user_create` tinyint(1) NOT NULL,
  `user_destroy` tinyint(1) NOT NULL,
  `ancestry` varchar(255) DEFAULT NULL,
  `ancestry_depth` int(11) NOT NULL DEFAULT 0,
  `expiration` datetime DEFAULT NULL,
  `confirmed` int(11) NOT NULL DEFAULT 0,
  `object_state` int(11) NOT NULL,
  `expiration_date` datetime DEFAULT NULL,
  `current_history_id` int(11) NOT NULL DEFAULT 0,
  `remind_after_date` datetime DEFAULT NULL,
  `dataset_expansion_id` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_datasets_on_dataset_expansion_id` (`dataset_expansion_id`),
  KEY `index_datasets_on_ancestry` (`ancestry`) USING BTREE,
  KEY `index_datasets_on_user_id` (`user_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `default_lifetime_values`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `default_lifetime_values` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `environment_id` int(11) DEFAULT NULL,
  `class_name` varchar(50) NOT NULL,
  `direction` int(11) NOT NULL,
  `state` int(11) NOT NULL,
  `add_expiration` int(11) DEFAULT NULL,
  `reason` varchar(255) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `default_object_cluster_resources`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `default_object_cluster_resources` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `environment_id` int(11) NOT NULL,
  `cluster_resource_id` int(11) NOT NULL,
  `class_name` varchar(255) NOT NULL,
  `value` decimal(40,0) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `default_user_cluster_resource_packages`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `default_user_cluster_resource_packages` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `environment_id` int(11) NOT NULL,
  `cluster_resource_package_id` int(11) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `default_user_cluster_resource_packages_unique` (`environment_id`,`cluster_resource_package_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `dns_record_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `dns_record_logs` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `dns_zone_id` bigint(20) NOT NULL,
  `change_type` int(11) NOT NULL,
  `name` varchar(255) NOT NULL,
  `record_type` varchar(10) NOT NULL,
  `content` text NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_dns_record_logs_on_dns_zone_id` (`dns_zone_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `dns_records`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `dns_records` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `dns_zone_id` bigint(20) NOT NULL,
  `name` varchar(255) NOT NULL,
  `record_type` varchar(10) NOT NULL,
  `content` text NOT NULL,
  `ttl` int(11) DEFAULT NULL,
  `priority` int(11) DEFAULT NULL,
  `enabled` tinyint(1) NOT NULL DEFAULT 1,
  `host_ip_address_id` bigint(20) DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_dns_records_on_host_ip_address_id` (`host_ip_address_id`),
  KEY `index_dns_records_on_dns_zone_id` (`dns_zone_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `dns_resolvers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `dns_resolvers` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `addrs` varchar(63) NOT NULL,
  `label` varchar(63) NOT NULL,
  `is_universal` tinyint(1) DEFAULT 0,
  `location_id` int(10) unsigned DEFAULT NULL,
  `ip_version` int(11) DEFAULT 4,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `dns_server_zones`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `dns_server_zones` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `dns_server_id` bigint(20) NOT NULL,
  `dns_zone_id` bigint(20) NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_dns_server_zones_on_dns_server_id_and_dns_zone_id` (`dns_server_id`,`dns_zone_id`),
  KEY `index_dns_server_zones_on_dns_server_id` (`dns_server_id`),
  KEY `index_dns_server_zones_on_dns_zone_id` (`dns_zone_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `dns_servers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `dns_servers` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `node_id` bigint(20) NOT NULL,
  `name` varchar(255) NOT NULL,
  `ipv4_addr` varchar(46) DEFAULT NULL,
  `ipv6_addr` varchar(46) DEFAULT NULL,
  `enable_user_dns_zones` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_dns_servers_on_name` (`name`),
  KEY `index_dns_servers_on_node_id` (`node_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `dns_zone_transfers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `dns_zone_transfers` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `dns_zone_id` bigint(20) NOT NULL,
  `host_ip_address_id` bigint(20) NOT NULL,
  `peer_type` int(11) NOT NULL DEFAULT 0,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_dns_zone_transfers_on_dns_zone_id_and_host_ip_address_id` (`dns_zone_id`,`host_ip_address_id`),
  KEY `index_dns_zone_transfers_on_dns_zone_id` (`dns_zone_id`),
  KEY `index_dns_zone_transfers_on_host_ip_address_id` (`host_ip_address_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `dns_zones`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `dns_zones` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `user_id` bigint(20) DEFAULT NULL,
  `name` varchar(500) NOT NULL,
  `reverse_network_address` varchar(46) DEFAULT NULL,
  `reverse_network_prefix` int(11) DEFAULT NULL,
  `label` varchar(500) NOT NULL DEFAULT '',
  `zone_role` int(11) NOT NULL DEFAULT 0,
  `zone_source` int(11) NOT NULL DEFAULT 0,
  `default_ttl` int(11) DEFAULT 3600,
  `email` varchar(255) DEFAULT NULL,
  `serial` int(10) unsigned DEFAULT 1,
  `tsig_algorithm` varchar(20) NOT NULL DEFAULT 'none',
  `tsig_key` varchar(255) NOT NULL DEFAULT '',
  `enabled` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_dns_zones_on_name` (`name`),
  KEY `index_dns_zones_on_user_id` (`user_id`),
  KEY `index_dns_zones_on_zone_source` (`zone_source`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `environment_dataset_plans`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `environment_dataset_plans` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `environment_id` int(11) NOT NULL,
  `dataset_plan_id` int(11) NOT NULL,
  `user_add` tinyint(1) NOT NULL,
  `user_remove` tinyint(1) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `environment_user_configs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `environment_user_configs` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `environment_id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `can_create_vps` tinyint(1) NOT NULL DEFAULT 0,
  `can_destroy_vps` tinyint(1) NOT NULL DEFAULT 0,
  `vps_lifetime` int(11) NOT NULL DEFAULT 0,
  `max_vps_count` int(11) NOT NULL DEFAULT 1,
  `default` tinyint(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  UNIQUE KEY `environment_user_configs_unique` (`environment_id`,`user_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `environments`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `environments` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `label` varchar(100) NOT NULL,
  `domain` varchar(100) NOT NULL,
  `created_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  `updated_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  `maintenance_lock` int(11) NOT NULL DEFAULT 0,
  `maintenance_lock_reason` varchar(255) DEFAULT NULL,
  `can_create_vps` tinyint(1) NOT NULL DEFAULT 0,
  `can_destroy_vps` tinyint(1) NOT NULL DEFAULT 0,
  `vps_lifetime` int(11) NOT NULL DEFAULT 0,
  `max_vps_count` int(11) NOT NULL DEFAULT 1,
  `user_ip_ownership` tinyint(1) NOT NULL,
  `description` text DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `export_hosts`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `export_hosts` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `export_id` int(11) NOT NULL,
  `ip_address_id` int(11) NOT NULL,
  `rw` tinyint(1) NOT NULL,
  `sync` tinyint(1) NOT NULL,
  `subtree_check` tinyint(1) NOT NULL,
  `root_squash` tinyint(1) NOT NULL,
  `created_at` datetime /* mariadb-5.3 */ NOT NULL,
  `updated_at` datetime /* mariadb-5.3 */ NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_export_hosts_on_export_id_and_ip_address_id` (`export_id`,`ip_address_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `exports`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `exports` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `dataset_in_pool_id` int(11) NOT NULL,
  `snapshot_in_pool_clone_id` int(11) DEFAULT NULL,
  `user_id` int(11) NOT NULL,
  `all_vps` tinyint(1) NOT NULL DEFAULT 1,
  `path` varchar(255) NOT NULL,
  `rw` tinyint(1) NOT NULL DEFAULT 1,
  `sync` tinyint(1) NOT NULL DEFAULT 1,
  `subtree_check` tinyint(1) NOT NULL DEFAULT 0,
  `root_squash` tinyint(1) NOT NULL DEFAULT 0,
  `threads` int(11) NOT NULL DEFAULT 8,
  `enabled` tinyint(1) NOT NULL DEFAULT 1,
  `object_state` int(11) NOT NULL,
  `expiration_date` datetime DEFAULT NULL,
  `confirmed` int(11) NOT NULL DEFAULT 0,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `snapshot_in_pool_clone_n` int(11) NOT NULL DEFAULT 0,
  `remind_after_date` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `exports_unique` (`dataset_in_pool_id`,`snapshot_in_pool_clone_n`),
  KEY `index_exports_on_user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `group_snapshots`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `group_snapshots` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `dataset_action_id` int(11) DEFAULT NULL,
  `dataset_in_pool_id` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `group_snapshots_unique` (`dataset_action_id`,`dataset_in_pool_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `host_ip_addresses`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `host_ip_addresses` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `ip_address_id` int(11) NOT NULL,
  `ip_addr` varchar(40) NOT NULL,
  `order` int(11) DEFAULT NULL,
  `auto_add` tinyint(1) NOT NULL DEFAULT 1,
  `user_created` tinyint(1) NOT NULL DEFAULT 0,
  `reverse_dns_record_id` bigint(20) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_host_ip_addresses_on_ip_address_id_and_ip_addr` (`ip_address_id`,`ip_addr`),
  UNIQUE KEY `index_host_ip_addresses_on_reverse_dns_record_id` (`reverse_dns_record_id`),
  KEY `index_host_ip_addresses_on_ip_address_id` (`ip_address_id`),
  KEY `index_host_ip_addresses_on_auto_add` (`auto_add`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `incident_reports`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `incident_reports` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `user_id` bigint(20) NOT NULL,
  `vps_id` bigint(20) NOT NULL,
  `ip_address_assignment_id` bigint(20) DEFAULT NULL,
  `filed_by_id` bigint(20) DEFAULT NULL,
  `mailbox_id` bigint(20) DEFAULT NULL,
  `subject` varchar(255) NOT NULL,
  `text` text NOT NULL,
  `codename` varchar(100) DEFAULT NULL,
  `detected_at` datetime(6) NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `reported_at` datetime(6) DEFAULT NULL,
  `cpu_limit` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_incident_reports_on_user_id` (`user_id`),
  KEY `index_incident_reports_on_vps_id` (`vps_id`),
  KEY `index_incident_reports_on_ip_address_assignment_id` (`ip_address_assignment_id`),
  KEY `index_incident_reports_on_filed_by_id` (`filed_by_id`),
  KEY `index_incident_reports_on_mailbox_id` (`mailbox_id`),
  KEY `index_incident_reports_on_created_at` (`created_at`),
  KEY `index_incident_reports_on_detected_at` (`detected_at`),
  KEY `index_incident_reports_on_reported_at` (`reported_at`),
  KEY `index_incident_reports_on_cpu_limit` (`cpu_limit`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `ip_address_assignments`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `ip_address_assignments` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `ip_address_id` bigint(20) NOT NULL,
  `ip_addr` varchar(40) NOT NULL,
  `ip_prefix` int(11) NOT NULL,
  `user_id` bigint(20) NOT NULL,
  `vps_id` bigint(20) NOT NULL,
  `from_date` datetime(6) NOT NULL,
  `to_date` datetime(6) DEFAULT NULL,
  `assigned_by_chain_id` bigint(20) DEFAULT NULL,
  `unassigned_by_chain_id` bigint(20) DEFAULT NULL,
  `reconstructed` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_ip_address_assignments_on_ip_address_id` (`ip_address_id`),
  KEY `index_ip_address_assignments_on_user_id` (`user_id`),
  KEY `index_ip_address_assignments_on_vps_id` (`vps_id`),
  KEY `index_ip_address_assignments_on_assigned_by_chain_id` (`assigned_by_chain_id`),
  KEY `index_ip_address_assignments_on_unassigned_by_chain_id` (`unassigned_by_chain_id`),
  KEY `index_ip_address_assignments_on_ip_addr` (`ip_addr`),
  KEY `index_ip_address_assignments_on_ip_prefix` (`ip_prefix`),
  KEY `index_ip_address_assignments_on_from_date` (`from_date`),
  KEY `index_ip_address_assignments_on_to_date` (`to_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `ip_addresses`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `ip_addresses` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `ip_addr` varchar(40) NOT NULL,
  `user_id` int(11) DEFAULT NULL,
  `network_id` int(11) NOT NULL,
  `order` int(11) DEFAULT NULL,
  `prefix` int(11) NOT NULL,
  `size` decimal(40,0) NOT NULL,
  `network_interface_id` int(11) DEFAULT NULL,
  `route_via_id` int(11) DEFAULT NULL,
  `charged_environment_id` int(11) DEFAULT NULL,
  `reverse_dns_zone_id` bigint(20) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_ip_addresses_on_network_id` (`network_id`) USING BTREE,
  KEY `index_ip_addresses_on_user_id` (`user_id`) USING BTREE,
  KEY `index_ip_addresses_on_network_interface_id` (`network_interface_id`),
  KEY `index_ip_addresses_on_route_via_id` (`route_via_id`),
  KEY `index_ip_addresses_on_charged_environment_id` (`charged_environment_id`),
  KEY `index_ip_addresses_on_reverse_dns_zone_id` (`reverse_dns_zone_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `ip_traffic_monthly_summaries`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `ip_traffic_monthly_summaries` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `ip_address_id` int(11) NOT NULL,
  `user_id` int(11) DEFAULT NULL,
  `protocol` int(11) NOT NULL,
  `role` int(11) NOT NULL,
  `packets_in` bigint(20) unsigned NOT NULL DEFAULT 0,
  `packets_out` bigint(20) unsigned NOT NULL DEFAULT 0,
  `bytes_in` bigint(20) unsigned NOT NULL DEFAULT 0,
  `bytes_out` bigint(20) unsigned NOT NULL DEFAULT 0,
  `created_at` datetime /* mariadb-5.3 */ NOT NULL,
  `year` int(11) NOT NULL,
  `month` int(11) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `ip_traffic_monthly_summaries_unique` (`ip_address_id`,`user_id`,`protocol`,`role`,`created_at`) USING BTREE,
  KEY `ip_traffic_monthly_summaries_ip_year_month` (`ip_address_id`,`year`,`month`) USING BTREE,
  KEY `index_ip_traffic_monthly_summaries_on_ip_address_id` (`ip_address_id`) USING BTREE,
  KEY `index_ip_traffic_monthly_summaries_on_month` (`month`) USING BTREE,
  KEY `index_ip_traffic_monthly_summaries_on_protocol` (`protocol`) USING BTREE,
  KEY `index_ip_traffic_monthly_summaries_on_user_id` (`user_id`) USING BTREE,
  KEY `index_ip_traffic_monthly_summaries_on_year_and_month` (`year`,`month`) USING BTREE,
  KEY `index_ip_traffic_monthly_summaries_on_year` (`year`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `languages`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `languages` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `code` varchar(2) NOT NULL,
  `label` varchar(100) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_languages_on_code` (`code`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `location_networks`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `location_networks` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `location_id` int(11) NOT NULL,
  `network_id` int(11) NOT NULL,
  `priority` int(11) NOT NULL DEFAULT 10,
  `autopick` tinyint(1) NOT NULL DEFAULT 1,
  `userpick` tinyint(1) NOT NULL DEFAULT 1,
  `primary` tinyint(1) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_location_networks_on_location_id_and_network_id` (`location_id`,`network_id`),
  UNIQUE KEY `location_networks_primary` (`network_id`,`primary`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `locations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `locations` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `label` varchar(63) NOT NULL,
  `has_ipv6` tinyint(1) NOT NULL,
  `remote_console_server` varchar(255) NOT NULL,
  `domain` varchar(100) NOT NULL,
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL,
  `maintenance_lock` int(11) NOT NULL DEFAULT 0,
  `maintenance_lock_reason` varchar(255) DEFAULT NULL,
  `environment_id` int(11) NOT NULL,
  `description` text DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `mail_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `mail_logs` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(11) DEFAULT NULL,
  `to` varchar(500) NOT NULL,
  `cc` varchar(500) NOT NULL,
  `bcc` varchar(500) NOT NULL,
  `from` varchar(255) NOT NULL,
  `reply_to` varchar(255) DEFAULT NULL,
  `return_path` varchar(255) DEFAULT NULL,
  `message_id` varchar(255) DEFAULT NULL,
  `in_reply_to` varchar(255) DEFAULT NULL,
  `references` varchar(255) DEFAULT NULL,
  `subject` varchar(255) NOT NULL,
  `text_plain` longtext DEFAULT NULL,
  `text_html` longtext DEFAULT NULL,
  `mail_template_id` int(11) DEFAULT NULL,
  `transaction_id` int(11) DEFAULT NULL,
  `created_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  `updated_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_mail_logs_on_user_id` (`user_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `mail_recipients`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `mail_recipients` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `label` varchar(100) NOT NULL,
  `to` varchar(500) DEFAULT NULL,
  `cc` varchar(500) DEFAULT NULL,
  `bcc` varchar(500) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `mail_template_recipients`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `mail_template_recipients` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `mail_template_id` int(11) NOT NULL,
  `mail_recipient_id` int(11) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `mail_template_recipients_unique` (`mail_template_id`,`mail_recipient_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `mail_template_translations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `mail_template_translations` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `mail_template_id` int(11) NOT NULL,
  `language_id` int(11) NOT NULL,
  `from` varchar(255) NOT NULL,
  `reply_to` varchar(255) DEFAULT NULL,
  `return_path` varchar(255) DEFAULT NULL,
  `subject` varchar(255) NOT NULL,
  `text_plain` text DEFAULT NULL,
  `text_html` text DEFAULT NULL,
  `created_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  `updated_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `mail_template_translation_unique` (`mail_template_id`,`language_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `mail_templates`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `mail_templates` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL,
  `label` varchar(100) NOT NULL,
  `created_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  `updated_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  `template_id` varchar(100) NOT NULL,
  `user_visibility` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_mail_templates_on_name` (`name`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `mailbox_handlers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `mailbox_handlers` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `mailbox_id` bigint(20) NOT NULL,
  `class_name` varchar(255) NOT NULL,
  `order` int(11) NOT NULL DEFAULT 1,
  `continue` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_mailbox_handlers_on_mailbox_id` (`mailbox_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `mailboxes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `mailboxes` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `label` varchar(255) NOT NULL,
  `server` varchar(255) NOT NULL,
  `port` int(11) NOT NULL DEFAULT 993,
  `user` varchar(255) NOT NULL,
  `password` varchar(255) NOT NULL,
  `enable_ssl` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `maintenance_locks`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `maintenance_locks` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `class_name` varchar(100) NOT NULL,
  `row_id` int(11) DEFAULT NULL,
  `user_id` int(11) DEFAULT NULL,
  `reason` varchar(255) NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  `updated_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_maintenance_locks_on_class_name_and_row_id` (`class_name`,`row_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `metrics_access_tokens`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `metrics_access_tokens` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `token_id` bigint(20) NOT NULL,
  `user_id` bigint(20) NOT NULL,
  `metric_prefix` varchar(30) NOT NULL DEFAULT 'vpsadmin_',
  `use_count` int(11) NOT NULL DEFAULT 0,
  `last_use` datetime(6) DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_metrics_access_tokens_on_token_id` (`token_id`),
  KEY `index_metrics_access_tokens_on_user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `migration_plans`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `migration_plans` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `state` int(11) NOT NULL DEFAULT 0,
  `stop_on_error` tinyint(1) NOT NULL DEFAULT 1,
  `send_mail` tinyint(1) NOT NULL DEFAULT 1,
  `user_id` int(11) DEFAULT NULL,
  `node_id` int(11) DEFAULT NULL,
  `concurrency` int(11) NOT NULL,
  `reason` varchar(255) DEFAULT NULL,
  `created_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  `finished_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `mirrors`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `mirrors` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `src_pool_id` int(11) DEFAULT NULL,
  `dst_pool_id` int(11) DEFAULT NULL,
  `src_dataset_in_pool_id` int(11) DEFAULT NULL,
  `dst_dataset_in_pool_id` int(11) DEFAULT NULL,
  `recursive` tinyint(1) NOT NULL DEFAULT 0,
  `interval` int(11) NOT NULL DEFAULT 60,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `mounts`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `mounts` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `vps_id` int(11) NOT NULL,
  `src` varchar(500) DEFAULT NULL,
  `dst` varchar(500) NOT NULL,
  `mount_opts` varchar(255) NOT NULL,
  `umount_opts` varchar(255) NOT NULL,
  `mount_type` varchar(10) NOT NULL,
  `user_editable` tinyint(1) NOT NULL DEFAULT 1,
  `dataset_in_pool_id` int(11) DEFAULT NULL,
  `snapshot_in_pool_id` int(11) DEFAULT NULL,
  `mode` varchar(2) NOT NULL,
  `confirmed` int(11) NOT NULL DEFAULT 0,
  `object_state` int(11) NOT NULL,
  `expiration_date` datetime DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL,
  `on_start_fail` int(11) NOT NULL DEFAULT 1,
  `enabled` tinyint(1) NOT NULL DEFAULT 1,
  `master_enabled` tinyint(1) NOT NULL DEFAULT 1,
  `current_state` int(11) NOT NULL DEFAULT 0,
  `snapshot_in_pool_clone_id` int(11) DEFAULT NULL,
  `remind_after_date` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_mounts_on_vps_id` (`vps_id`) USING BTREE,
  KEY `index_mounts_on_snapshot_in_pool_clone_id` (`snapshot_in_pool_clone_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `network_interface_daily_accountings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `network_interface_daily_accountings` (
  `network_interface_id` bigint(20) NOT NULL,
  `user_id` bigint(20) NOT NULL,
  `packets_in` bigint(20) unsigned NOT NULL,
  `packets_out` bigint(20) unsigned NOT NULL,
  `bytes_in` bigint(20) unsigned NOT NULL,
  `bytes_out` bigint(20) unsigned NOT NULL,
  `year` int(11) NOT NULL,
  `month` int(11) NOT NULL,
  `day` int(11) NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`network_interface_id`,`user_id`,`year`,`month`,`day`),
  KEY `index_network_interface_daily_accountings_on_netif` (`network_interface_id`),
  KEY `index_network_interface_daily_accountings_on_user_id` (`user_id`),
  KEY `index_network_interface_daily_accountings_on_year` (`year`),
  KEY `index_network_interface_daily_accountings_on_month` (`month`),
  KEY `index_network_interface_daily_accountings_on_day` (`day`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `network_interface_monitors`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `network_interface_monitors` (
  `network_interface_id` bigint(20) NOT NULL,
  `packets` bigint(20) unsigned NOT NULL,
  `packets_in` bigint(20) unsigned NOT NULL,
  `packets_out` bigint(20) unsigned NOT NULL,
  `bytes` bigint(20) unsigned NOT NULL,
  `bytes_in` bigint(20) unsigned NOT NULL,
  `bytes_out` bigint(20) unsigned NOT NULL,
  `delta` int(11) NOT NULL,
  `packets_in_readout` bigint(20) unsigned NOT NULL,
  `packets_out_readout` bigint(20) unsigned NOT NULL,
  `bytes_in_readout` bigint(20) unsigned NOT NULL,
  `bytes_out_readout` bigint(20) unsigned NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`network_interface_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `network_interface_monthly_accountings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `network_interface_monthly_accountings` (
  `network_interface_id` bigint(20) NOT NULL,
  `user_id` bigint(20) NOT NULL,
  `packets_in` bigint(20) unsigned NOT NULL,
  `packets_out` bigint(20) unsigned NOT NULL,
  `bytes_in` bigint(20) unsigned NOT NULL,
  `bytes_out` bigint(20) unsigned NOT NULL,
  `year` int(11) NOT NULL,
  `month` int(11) NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`network_interface_id`,`user_id`,`year`,`month`),
  KEY `index_network_interface_monthly_accountings_on_netif` (`network_interface_id`),
  KEY `index_network_interface_monthly_accountings_on_user_id` (`user_id`),
  KEY `index_network_interface_monthly_accountings_on_year` (`year`),
  KEY `index_network_interface_monthly_accountings_on_month` (`month`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `network_interface_yearly_accountings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `network_interface_yearly_accountings` (
  `network_interface_id` bigint(20) NOT NULL,
  `user_id` bigint(20) NOT NULL,
  `packets_in` bigint(20) unsigned NOT NULL,
  `packets_out` bigint(20) unsigned NOT NULL,
  `bytes_in` bigint(20) unsigned NOT NULL,
  `bytes_out` bigint(20) unsigned NOT NULL,
  `year` int(11) NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`network_interface_id`,`user_id`,`year`),
  KEY `index_network_interface_yearly_accountings_on_netif` (`network_interface_id`),
  KEY `index_network_interface_yearly_accountings_on_user_id` (`user_id`),
  KEY `index_network_interface_yearly_accountings_on_year` (`year`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `network_interfaces`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `network_interfaces` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `vps_id` int(11) DEFAULT NULL,
  `name` varchar(30) NOT NULL,
  `kind` int(11) NOT NULL,
  `mac` varchar(17) DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL,
  `export_id` int(11) DEFAULT NULL,
  `max_tx` bigint(20) unsigned NOT NULL DEFAULT 0,
  `max_rx` bigint(20) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_network_interfaces_on_vps_id_and_name` (`vps_id`,`name`),
  UNIQUE KEY `index_network_interfaces_on_mac` (`mac`),
  UNIQUE KEY `index_network_interfaces_on_export_id_and_name` (`export_id`,`name`),
  KEY `index_network_interfaces_on_vps_id` (`vps_id`),
  KEY `index_network_interfaces_on_kind` (`kind`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `networks`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `networks` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `label` varchar(255) DEFAULT NULL,
  `ip_version` int(11) NOT NULL,
  `address` varchar(255) NOT NULL,
  `prefix` int(11) NOT NULL,
  `role` int(11) NOT NULL,
  `managed` tinyint(1) NOT NULL,
  `split_access` int(11) NOT NULL DEFAULT 0,
  `split_prefix` int(11) NOT NULL,
  `purpose` int(11) NOT NULL DEFAULT 0,
  `primary_location_id` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_networks_on_address_and_prefix` (`address`,`prefix`),
  KEY `index_networks_on_purpose` (`purpose`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `node_current_statuses`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `node_current_statuses` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `node_id` int(11) NOT NULL,
  `uptime` int(11) DEFAULT NULL,
  `cpus` int(11) DEFAULT NULL,
  `total_memory` int(11) DEFAULT NULL,
  `total_swap` int(11) DEFAULT NULL,
  `vpsadmin_version` varchar(25) NOT NULL,
  `kernel` varchar(30) NOT NULL,
  `update_count` int(11) NOT NULL,
  `process_count` int(11) DEFAULT NULL,
  `cpu_user` float DEFAULT NULL,
  `cpu_nice` float DEFAULT NULL,
  `cpu_system` float DEFAULT NULL,
  `cpu_idle` float DEFAULT NULL,
  `cpu_iowait` float DEFAULT NULL,
  `cpu_irq` float DEFAULT NULL,
  `cpu_softirq` float DEFAULT NULL,
  `cpu_guest` float DEFAULT NULL,
  `loadavg` float DEFAULT NULL,
  `used_memory` int(11) DEFAULT NULL,
  `used_swap` int(11) DEFAULT NULL,
  `arc_c_max` int(11) DEFAULT NULL,
  `arc_c` int(11) DEFAULT NULL,
  `arc_size` int(11) DEFAULT NULL,
  `arc_hitpercent` float DEFAULT NULL,
  `sum_process_count` int(11) DEFAULT NULL,
  `sum_cpu_user` float DEFAULT NULL,
  `sum_cpu_nice` float DEFAULT NULL,
  `sum_cpu_system` float DEFAULT NULL,
  `sum_cpu_idle` float DEFAULT NULL,
  `sum_cpu_iowait` float DEFAULT NULL,
  `sum_cpu_irq` float DEFAULT NULL,
  `sum_cpu_softirq` float DEFAULT NULL,
  `sum_cpu_guest` float DEFAULT NULL,
  `sum_loadavg` float DEFAULT NULL,
  `sum_used_memory` int(11) DEFAULT NULL,
  `sum_used_swap` int(11) DEFAULT NULL,
  `sum_arc_c_max` int(11) DEFAULT NULL,
  `sum_arc_c` int(11) DEFAULT NULL,
  `sum_arc_size` int(11) DEFAULT NULL,
  `sum_arc_hitpercent` float DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL,
  `pool_state` int(11) NOT NULL DEFAULT 0,
  `pool_scan` int(11) NOT NULL DEFAULT 0,
  `pool_checked_at` datetime DEFAULT NULL,
  `pool_scan_percent` float DEFAULT NULL,
  `cgroup_version` int(11) NOT NULL DEFAULT 1,
  `last_log_at` datetime(6) DEFAULT NULL,
  `loadavg1` float NOT NULL DEFAULT 0,
  `loadavg5` float NOT NULL DEFAULT 0,
  `loadavg15` float NOT NULL DEFAULT 0,
  `sum_loadavg1` float NOT NULL DEFAULT 0,
  `sum_loadavg5` float NOT NULL DEFAULT 0,
  `sum_loadavg15` float NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_node_current_statuses_on_node_id` (`node_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `node_statuses`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `node_statuses` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `node_id` int(11) NOT NULL,
  `uptime` int(11) NOT NULL,
  `process_count` int(11) DEFAULT NULL,
  `cpus` int(11) DEFAULT NULL,
  `cpu_user` float DEFAULT NULL,
  `cpu_nice` float DEFAULT NULL,
  `cpu_system` float DEFAULT NULL,
  `cpu_idle` float DEFAULT NULL,
  `cpu_iowait` float DEFAULT NULL,
  `cpu_irq` float DEFAULT NULL,
  `cpu_softirq` float DEFAULT NULL,
  `cpu_guest` float DEFAULT NULL,
  `total_memory` int(11) DEFAULT NULL,
  `used_memory` int(11) DEFAULT NULL,
  `total_swap` int(11) DEFAULT NULL,
  `used_swap` int(11) DEFAULT NULL,
  `arc_c_max` int(11) DEFAULT NULL,
  `arc_c` int(11) DEFAULT NULL,
  `arc_size` int(11) DEFAULT NULL,
  `arc_hitpercent` float DEFAULT NULL,
  `loadavg` float DEFAULT NULL,
  `vpsadmin_version` varchar(25) NOT NULL,
  `kernel` varchar(30) NOT NULL,
  `created_at` datetime DEFAULT NULL,
  `cgroup_version` int(11) NOT NULL DEFAULT 1,
  `loadavg1` float NOT NULL DEFAULT 0,
  `loadavg5` float NOT NULL DEFAULT 0,
  `loadavg15` float NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `index_node_statuses_on_node_id` (`node_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `nodes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `nodes` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(64) NOT NULL,
  `location_id` int(10) unsigned NOT NULL,
  `ip_addr` varchar(127) NOT NULL,
  `max_vps` int(11) DEFAULT NULL,
  `max_tx` bigint(20) unsigned NOT NULL DEFAULT 235929600,
  `max_rx` bigint(20) unsigned NOT NULL DEFAULT 235929600,
  `maintenance_lock` int(11) NOT NULL DEFAULT 0,
  `maintenance_lock_reason` varchar(255) DEFAULT NULL,
  `cpus` int(11) NOT NULL,
  `total_memory` int(11) NOT NULL,
  `total_swap` int(11) NOT NULL,
  `role` int(11) NOT NULL,
  `hypervisor_type` int(11) DEFAULT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  KEY `location_id` (`location_id`) USING BTREE,
  KEY `index_nodes_on_hypervisor_type` (`hypervisor_type`),
  KEY `index_nodes_on_active` (`active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `oauth2_authorizations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `oauth2_authorizations` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `oauth2_client_id` bigint(20) NOT NULL,
  `user_id` bigint(20) NOT NULL,
  `scope` text NOT NULL,
  `code_id` bigint(20) DEFAULT NULL,
  `user_session_id` bigint(20) DEFAULT NULL,
  `refresh_token_id` bigint(20) DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `code_challenge` varchar(255) DEFAULT NULL,
  `code_challenge_method` varchar(20) DEFAULT NULL,
  `single_sign_on_id` int(11) DEFAULT NULL,
  `client_ip_addr` varchar(46) DEFAULT NULL,
  `client_ip_ptr` varchar(255) DEFAULT NULL,
  `user_device_id` bigint(20) DEFAULT NULL,
  `user_agent_id` bigint(20) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_oauth2_authorizations_on_oauth2_client_id` (`oauth2_client_id`),
  KEY `index_oauth2_authorizations_on_user_id` (`user_id`),
  KEY `index_oauth2_authorizations_on_code_id` (`code_id`),
  KEY `index_oauth2_authorizations_on_user_session_id` (`user_session_id`),
  KEY `index_oauth2_authorizations_on_refresh_token_id` (`refresh_token_id`),
  KEY `index_oauth2_authorizations_on_single_sign_on_id` (`single_sign_on_id`),
  KEY `index_oauth2_authorizations_on_user_device_id` (`user_device_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `oauth2_clients`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `oauth2_clients` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `client_id` varchar(255) NOT NULL,
  `client_secret_hash` varchar(255) NOT NULL,
  `redirect_uri` varchar(255) NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `access_token_lifetime` int(11) NOT NULL DEFAULT 0,
  `access_token_seconds` int(11) NOT NULL DEFAULT 900,
  `refresh_token_seconds` int(11) NOT NULL DEFAULT 3600,
  `issue_refresh_token` tinyint(1) NOT NULL DEFAULT 0,
  `allow_single_sign_on` tinyint(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_oauth2_clients_on_client_id` (`client_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `object_histories`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `object_histories` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(11) DEFAULT NULL,
  `user_session_id` int(11) DEFAULT NULL,
  `tracked_object_id` int(11) NOT NULL,
  `tracked_object_type` varchar(255) NOT NULL,
  `event_type` varchar(255) NOT NULL,
  `event_data` text DEFAULT NULL,
  `created_at` datetime /* mariadb-5.3 */ NOT NULL,
  PRIMARY KEY (`id`),
  KEY `object_histories_tracked_object` (`tracked_object_id`,`tracked_object_type`) USING BTREE,
  KEY `index_object_histories_on_user_id` (`user_id`) USING BTREE,
  KEY `index_object_histories_on_user_session_id` (`user_session_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `object_states`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `object_states` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `class_name` varchar(255) NOT NULL,
  `row_id` int(11) NOT NULL,
  `state` int(11) NOT NULL,
  `user_id` int(11) DEFAULT NULL,
  `reason` varchar(255) DEFAULT NULL,
  `expiration_date` datetime DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL,
  `remind_after_date` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_object_states_on_class_name_and_row_id` (`class_name`,`row_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `oom_preventions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `oom_preventions` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `vps_id` bigint(20) NOT NULL,
  `action` int(11) NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_oom_preventions_on_vps_id` (`vps_id`),
  KEY `index_oom_preventions_on_action` (`action`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `oom_report_counters`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `oom_report_counters` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `vps_id` bigint(20) NOT NULL,
  `cgroup` varchar(255) NOT NULL DEFAULT '/',
  `counter` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_oom_report_counters_on_vps_id_and_cgroup` (`vps_id`,`cgroup`),
  KEY `index_oom_report_counters_on_vps_id` (`vps_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `oom_report_stats`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `oom_report_stats` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `oom_report_id` int(11) NOT NULL,
  `parameter` varchar(30) NOT NULL,
  `value` decimal(40,0) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_oom_report_stats_on_oom_report_id` (`oom_report_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `oom_report_tasks`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `oom_report_tasks` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `oom_report_id` int(11) NOT NULL,
  `name` varchar(50) NOT NULL,
  `host_pid` int(11) NOT NULL,
  `vps_pid` int(11) DEFAULT NULL,
  `host_uid` int(11) NOT NULL,
  `vps_uid` int(11) DEFAULT NULL,
  `tgid` int(11) NOT NULL,
  `total_vm` int(11) NOT NULL,
  `rss` int(11) NOT NULL,
  `pgtables_bytes` int(11) NOT NULL,
  `swapents` int(11) NOT NULL,
  `oom_score_adj` int(11) NOT NULL,
  `rss_anon` int(11) DEFAULT NULL,
  `rss_file` int(11) DEFAULT NULL,
  `rss_shmem` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_oom_report_tasks_on_oom_report_id` (`oom_report_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `oom_report_usages`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `oom_report_usages` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `oom_report_id` int(11) NOT NULL,
  `memtype` varchar(20) NOT NULL,
  `usage` decimal(40,0) NOT NULL,
  `limit` decimal(40,0) NOT NULL,
  `failcnt` decimal(40,0) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_oom_report_usages_on_oom_report_id` (`oom_report_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `oom_reports`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `oom_reports` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `vps_id` int(11) NOT NULL,
  `invoked_by_pid` int(11) NOT NULL,
  `invoked_by_name` varchar(50) NOT NULL,
  `killed_pid` int(11) DEFAULT NULL,
  `killed_name` varchar(50) DEFAULT NULL,
  `processed` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` datetime NOT NULL,
  `reported_at` datetime DEFAULT NULL,
  `count` int(11) NOT NULL DEFAULT 1,
  `cgroup` varchar(255) NOT NULL DEFAULT '/',
  PRIMARY KEY (`id`),
  KEY `index_oom_reports_on_vps_id` (`vps_id`),
  KEY `index_oom_reports_on_processed` (`processed`),
  KEY `index_oom_reports_on_reported_at` (`reported_at`),
  KEY `index_oom_reports_on_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `os_templates`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `os_templates` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(64) NOT NULL,
  `label` varchar(64) NOT NULL,
  `info` text DEFAULT NULL,
  `enabled` tinyint(1) NOT NULL DEFAULT 1,
  `supported` tinyint(1) NOT NULL DEFAULT 1,
  `order` tinyint(4) NOT NULL DEFAULT 1,
  `hypervisor_type` int(11) NOT NULL DEFAULT 0,
  `vendor` varchar(255) DEFAULT NULL,
  `variant` varchar(255) DEFAULT NULL,
  `arch` varchar(255) DEFAULT NULL,
  `distribution` varchar(255) DEFAULT NULL,
  `version` varchar(255) DEFAULT NULL,
  `cgroup_version` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `index_os_templates_on_cgroup_version` (`cgroup_version`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `pools`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `pools` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `node_id` int(11) NOT NULL,
  `label` varchar(500) NOT NULL,
  `filesystem` varchar(500) NOT NULL,
  `role` int(11) NOT NULL,
  `refquota_check` tinyint(1) NOT NULL DEFAULT 0,
  `maintenance_lock` int(11) NOT NULL DEFAULT 0,
  `maintenance_lock_reason` varchar(255) DEFAULT NULL,
  `export_root` varchar(100) NOT NULL DEFAULT '/export',
  `migration_public_key` text DEFAULT NULL,
  `max_datasets` int(11) NOT NULL DEFAULT 0,
  `state` int(11) NOT NULL DEFAULT 0,
  `scan` int(11) NOT NULL DEFAULT 0,
  `checked_at` datetime DEFAULT NULL,
  `scan_percent` float DEFAULT NULL,
  `is_open` int(11) NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  KEY `index_pools_on_is_open` (`is_open`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `port_reservations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `port_reservations` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `node_id` int(11) NOT NULL,
  `addr` varchar(100) DEFAULT NULL,
  `port` int(11) NOT NULL,
  `transaction_chain_id` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `port_reservation_uniqueness` (`node_id`,`port`) USING BTREE,
  KEY `index_port_reservations_on_node_id` (`node_id`) USING BTREE,
  KEY `index_port_reservations_on_transaction_chain_id` (`transaction_chain_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `repeatable_tasks`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `repeatable_tasks` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `label` varchar(100) DEFAULT NULL,
  `class_name` varchar(255) NOT NULL,
  `table_name` varchar(255) NOT NULL,
  `row_id` int(11) NOT NULL,
  `minute` varchar(255) NOT NULL,
  `hour` varchar(255) NOT NULL,
  `day_of_month` varchar(255) NOT NULL,
  `month` varchar(255) NOT NULL,
  `day_of_week` varchar(255) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `resource_locks`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `resource_locks` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `resource` varchar(100) NOT NULL,
  `row_id` int(11) NOT NULL,
  `created_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  `updated_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  `locked_by_id` int(11) DEFAULT NULL,
  `locked_by_type` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_resource_locks_on_resource_and_row_id` (`resource`,`row_id`) USING BTREE,
  KEY `index_resource_locks_on_locked_by_id_and_locked_by_type` (`locked_by_id`,`locked_by_type`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `schema_migrations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `schema_migrations` (
  `version` varchar(255) NOT NULL,
  UNIQUE KEY `unique_schema_migrations` (`version`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `single_sign_ons`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `single_sign_ons` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `user_id` bigint(20) NOT NULL,
  `token_id` bigint(20) DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_single_sign_ons_on_user_id` (`user_id`),
  KEY `index_single_sign_ons_on_token_id` (`token_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `snapshot_downloads`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `snapshot_downloads` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `snapshot_id` int(11) DEFAULT NULL,
  `pool_id` int(11) NOT NULL,
  `secret_key` varchar(100) NOT NULL,
  `file_name` varchar(255) NOT NULL,
  `confirmed` int(11) NOT NULL DEFAULT 0,
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL,
  `object_state` int(11) NOT NULL,
  `expiration_date` datetime DEFAULT NULL,
  `size` int(11) DEFAULT NULL,
  `format` int(11) NOT NULL DEFAULT 0,
  `from_snapshot_id` int(11) DEFAULT NULL,
  `sha256sum` varchar(64) DEFAULT NULL,
  `remind_after_date` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_snapshot_downloads_on_secret_key` (`secret_key`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `snapshot_in_pool_clones`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `snapshot_in_pool_clones` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `snapshot_in_pool_id` int(11) NOT NULL,
  `state` int(11) NOT NULL DEFAULT 0,
  `name` varchar(50) NOT NULL,
  `user_namespace_map_id` int(11) DEFAULT NULL,
  `confirmed` int(11) NOT NULL DEFAULT 0,
  `created_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  `updated_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `snapshot_in_pool_clones_unique` (`snapshot_in_pool_id`,`user_namespace_map_id`),
  KEY `index_snapshot_in_pool_clones_on_snapshot_in_pool_id` (`snapshot_in_pool_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `snapshot_in_pool_in_branches`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `snapshot_in_pool_in_branches` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `snapshot_in_pool_id` int(11) NOT NULL,
  `snapshot_in_pool_in_branch_id` int(11) DEFAULT NULL,
  `branch_id` int(11) NOT NULL,
  `confirmed` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_snapshot_in_pool_in_branches` (`snapshot_in_pool_id`,`branch_id`) USING BTREE,
  KEY `index_snapshot_in_pool_in_branches_on_snapshot_in_pool_id` (`snapshot_in_pool_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `snapshot_in_pools`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `snapshot_in_pools` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `snapshot_id` int(11) NOT NULL,
  `dataset_in_pool_id` int(11) NOT NULL,
  `reference_count` int(11) NOT NULL DEFAULT 0,
  `mount_id` int(11) DEFAULT NULL,
  `confirmed` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_snapshot_in_pools_on_snapshot_id_and_dataset_in_pool_id` (`snapshot_id`,`dataset_in_pool_id`) USING BTREE,
  KEY `index_snapshot_in_pools_on_dataset_in_pool_id` (`dataset_in_pool_id`) USING BTREE,
  KEY `index_snapshot_in_pools_on_snapshot_id` (`snapshot_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `snapshots`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `snapshots` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `dataset_id` int(11) NOT NULL,
  `confirmed` int(11) NOT NULL DEFAULT 0,
  `created_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  `updated_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  `snapshot_download_id` int(11) DEFAULT NULL,
  `history_id` int(11) NOT NULL DEFAULT 0,
  `label` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_snapshots_on_dataset_id` (`dataset_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `sysconfig`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `sysconfig` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `category` varchar(75) NOT NULL,
  `name` varchar(75) NOT NULL,
  `data_type` varchar(255) NOT NULL DEFAULT 'Text',
  `value` text DEFAULT NULL,
  `label` varchar(255) DEFAULT NULL,
  `description` text DEFAULT NULL,
  `min_user_level` int(11) DEFAULT NULL,
  `created_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  `updated_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_sysconfig_on_category_and_name` (`category`,`name`) USING BTREE,
  KEY `index_sysconfig_on_category` (`category`) USING BTREE
) ENGINE=InnoDB AUTO_INCREMENT=35 DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `tokens`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `tokens` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `token` varchar(100) NOT NULL,
  `valid_to` datetime /* mariadb-5.3 */ DEFAULT NULL,
  `owner_id` int(11) DEFAULT NULL,
  `owner_type` varchar(255) DEFAULT NULL,
  `created_at` datetime /* mariadb-5.3 */ NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_tokens_on_token` (`token`),
  KEY `index_tokens_on_owner_type_and_owner_id` (`owner_type`,`owner_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `transaction_chain_concerns`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `transaction_chain_concerns` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `transaction_chain_id` int(11) NOT NULL,
  `class_name` varchar(255) NOT NULL,
  `row_id` int(11) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_transaction_chain_concerns_on_transaction_chain_id` (`transaction_chain_id`) USING BTREE,
  KEY `index_transaction_chain_concerns_on_class_name` (`class_name`),
  KEY `index_transaction_chain_concerns_on_row_id` (`row_id`),
  KEY `index_transaction_chain_concerns_on_class_name_and_row_id` (`class_name`,`row_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `transaction_chains`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `transaction_chains` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(30) NOT NULL,
  `type` varchar(100) NOT NULL,
  `state` int(11) NOT NULL,
  `size` int(11) NOT NULL,
  `progress` int(11) NOT NULL DEFAULT 0,
  `user_id` int(11) DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL,
  `urgent_rollback` int(11) NOT NULL DEFAULT 0,
  `concern_type` int(11) NOT NULL DEFAULT 0,
  `user_session_id` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_transaction_chains_on_state` (`state`) USING BTREE,
  KEY `index_transaction_chains_on_user_id` (`user_id`) USING BTREE,
  KEY `index_transaction_chains_on_user_session_id` (`user_session_id`) USING BTREE,
  KEY `index_transaction_chains_on_created_at` (`created_at`),
  KEY `index_transaction_chains_on_type_and_state` (`type`,`state`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `transaction_confirmations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `transaction_confirmations` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `transaction_id` int(11) NOT NULL,
  `class_name` varchar(255) NOT NULL,
  `table_name` varchar(255) NOT NULL,
  `row_pks` varchar(255) NOT NULL,
  `attr_changes` text DEFAULT NULL,
  `confirm_type` int(11) NOT NULL,
  `done` int(11) NOT NULL DEFAULT 0,
  `created_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  `updated_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_transaction_confirmations_on_transaction_id` (`transaction_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `transactions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `transactions` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(10) unsigned DEFAULT NULL,
  `node_id` int(10) unsigned DEFAULT NULL,
  `vps_id` int(10) unsigned DEFAULT NULL,
  `handle` int(10) unsigned NOT NULL,
  `depends_on_id` int(11) DEFAULT NULL,
  `urgent` tinyint(1) NOT NULL DEFAULT 0,
  `priority` int(11) NOT NULL DEFAULT 0,
  `status` int(10) unsigned NOT NULL,
  `done` int(11) NOT NULL DEFAULT 0,
  `input` longtext DEFAULT NULL,
  `output` text DEFAULT NULL,
  `transaction_chain_id` int(11) NOT NULL,
  `reversible` int(11) NOT NULL DEFAULT 1,
  `created_at` datetime DEFAULT NULL,
  `started_at` datetime DEFAULT NULL,
  `finished_at` datetime DEFAULT NULL,
  `queue` varchar(30) NOT NULL DEFAULT 'general',
  `signature` text DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_transactions_on_depends_on_id` (`depends_on_id`) USING BTREE,
  KEY `index_transactions_on_done` (`done`) USING BTREE,
  KEY `index_transactions_on_node_id` (`node_id`) USING BTREE,
  KEY `index_transactions_on_status` (`status`) USING BTREE,
  KEY `index_transactions_on_transaction_chain_id` (`transaction_chain_id`) USING BTREE,
  KEY `index_transactions_on_user_id` (`user_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `user_agents`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `user_agents` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `agent` text NOT NULL,
  `agent_hash` varchar(40) NOT NULL,
  `created_at` datetime /* mariadb-5.3 */ NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `user_session_agents_hash` (`agent_hash`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `user_cluster_resource_packages`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `user_cluster_resource_packages` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `environment_id` int(11) DEFAULT NULL,
  `user_id` int(11) NOT NULL,
  `cluster_resource_package_id` int(11) NOT NULL,
  `added_by_id` int(11) DEFAULT NULL,
  `comment` varchar(255) NOT NULL DEFAULT '',
  `created_at` datetime /* mariadb-5.3 */ NOT NULL,
  `updated_at` datetime /* mariadb-5.3 */ NOT NULL,
  PRIMARY KEY (`id`),
  KEY `environment_id` (`environment_id`),
  KEY `user_id` (`user_id`),
  KEY `cluster_resource_package_id` (`cluster_resource_package_id`),
  KEY `added_by_id` (`added_by_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `user_cluster_resources`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `user_cluster_resources` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(11) DEFAULT NULL,
  `environment_id` int(11) NOT NULL,
  `cluster_resource_id` int(11) NOT NULL,
  `value` decimal(40,0) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `user_cluster_resource_unique` (`user_id`,`environment_id`,`cluster_resource_id`) USING BTREE,
  KEY `index_user_cluster_resources_on_cluster_resource_id` (`cluster_resource_id`) USING BTREE,
  KEY `index_user_cluster_resources_on_environment_id` (`environment_id`) USING BTREE,
  KEY `index_user_cluster_resources_on_user_id` (`user_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `user_devices`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `user_devices` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `user_id` bigint(20) NOT NULL,
  `token_id` bigint(20) DEFAULT NULL,
  `client_ip_addr` varchar(46) NOT NULL,
  `client_ip_ptr` varchar(255) NOT NULL,
  `user_agent_id` bigint(20) NOT NULL,
  `known` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `last_seen_at` datetime(6) NOT NULL,
  `skip_multi_factor_auth_until` datetime(6) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_user_devices_on_user_id` (`user_id`),
  KEY `index_user_devices_on_token_id` (`token_id`),
  KEY `index_user_devices_on_user_agent_id` (`user_agent_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `user_failed_logins`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `user_failed_logins` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `auth_type` varchar(30) NOT NULL,
  `reason` varchar(255) NOT NULL,
  `api_ip_addr` varchar(46) NOT NULL,
  `api_ip_ptr` varchar(255) DEFAULT NULL,
  `client_ip_addr` varchar(46) DEFAULT NULL,
  `client_ip_ptr` varchar(255) DEFAULT NULL,
  `user_agent_id` int(11) DEFAULT NULL,
  `client_version` varchar(255) NOT NULL,
  `created_at` datetime NOT NULL,
  `reported_at` datetime(6) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_user_failed_logins_on_user_id` (`user_id`),
  KEY `index_user_failed_logins_on_auth_type` (`auth_type`),
  KEY `index_user_failed_logins_on_user_agent_id` (`user_agent_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `user_mail_role_recipients`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `user_mail_role_recipients` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `role` varchar(100) NOT NULL,
  `to` varchar(500) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_user_mail_role_recipients_on_user_id_and_role` (`user_id`,`role`),
  KEY `index_user_mail_role_recipients_on_user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `user_mail_template_recipients`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `user_mail_template_recipients` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `mail_template_id` int(11) NOT NULL,
  `to` varchar(500) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `user_id_mail_template_id` (`user_id`,`mail_template_id`),
  KEY `index_user_mail_template_recipients_on_user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `user_namespace_blocks`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `user_namespace_blocks` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `user_namespace_id` int(11) DEFAULT NULL,
  `index` int(11) NOT NULL,
  `offset` int(10) unsigned NOT NULL,
  `size` int(11) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_user_namespace_blocks_on_index` (`index`),
  KEY `index_user_namespace_blocks_on_user_namespace_id` (`user_namespace_id`),
  KEY `index_user_namespace_blocks_on_offset` (`offset`)
) ENGINE=InnoDB AUTO_INCREMENT=65535 DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `user_namespace_map_entries`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `user_namespace_map_entries` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `user_namespace_map_id` int(11) NOT NULL,
  `kind` int(11) NOT NULL,
  `vps_id` int(10) unsigned NOT NULL,
  `ns_id` int(10) unsigned NOT NULL,
  `count` int(10) unsigned NOT NULL,
  `created_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  `updated_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_user_namespace_map_entries_on_user_namespace_map_id` (`user_namespace_map_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `user_namespace_maps`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `user_namespace_maps` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `user_namespace_id` int(11) NOT NULL,
  `label` varchar(255) NOT NULL,
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_user_namespace_maps_on_user_namespace_id` (`user_namespace_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `user_namespaces`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `user_namespaces` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `block_count` int(11) NOT NULL,
  `offset` int(10) unsigned NOT NULL,
  `size` int(11) NOT NULL,
  `created_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  `updated_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_user_namespaces_on_user_id` (`user_id`),
  KEY `index_user_namespaces_on_block_count` (`block_count`),
  KEY `index_user_namespaces_on_offset` (`offset`),
  KEY `index_user_namespaces_on_size` (`size`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `user_public_keys`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `user_public_keys` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `label` varchar(255) NOT NULL,
  `key` text NOT NULL,
  `auto_add` tinyint(1) NOT NULL DEFAULT 0,
  `fingerprint` varchar(50) NOT NULL,
  `comment` varchar(255) NOT NULL,
  `created_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  `updated_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_user_public_keys_on_user_id` (`user_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `user_sessions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `user_sessions` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `auth_type` varchar(30) NOT NULL,
  `api_ip_addr` varchar(46) NOT NULL,
  `user_agent_id` int(11) DEFAULT NULL,
  `client_version` varchar(255) NOT NULL,
  `token_str` varchar(100) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `last_request_at` datetime DEFAULT NULL,
  `closed_at` datetime DEFAULT NULL,
  `admin_id` int(11) DEFAULT NULL,
  `api_ip_ptr` varchar(255) DEFAULT NULL,
  `client_ip_addr` varchar(46) DEFAULT NULL,
  `client_ip_ptr` varchar(255) DEFAULT NULL,
  `scope` text NOT NULL DEFAULT '["all"]',
  `label` varchar(255) NOT NULL DEFAULT '',
  `request_count` int(11) NOT NULL DEFAULT 0,
  `token_id` int(11) DEFAULT NULL,
  `token_lifetime` int(11) NOT NULL DEFAULT 0,
  `token_interval` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_user_sessions_on_user_id` (`user_id`) USING BTREE,
  KEY `index_user_sessions_on_token_id` (`token_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `user_totp_devices`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `user_totp_devices` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `label` varchar(100) NOT NULL,
  `confirmed` tinyint(1) NOT NULL DEFAULT 0,
  `enabled` tinyint(1) NOT NULL DEFAULT 0,
  `secret` varchar(32) DEFAULT NULL,
  `recovery_code` varchar(255) DEFAULT NULL,
  `last_verification_at` int(11) DEFAULT NULL,
  `use_count` int(10) unsigned NOT NULL DEFAULT 0,
  `last_use_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  `created_at` datetime /* mariadb-5.3 */ NOT NULL,
  `updated_at` datetime /* mariadb-5.3 */ NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_user_totp_devices_on_secret` (`secret`),
  KEY `index_user_totp_devices_on_user_id` (`user_id`),
  KEY `index_user_totp_devices_on_enabled` (`enabled`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `users`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `users` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `info` text DEFAULT NULL,
  `level` int(10) unsigned NOT NULL,
  `login` varchar(63) DEFAULT NULL,
  `full_name` varchar(255) DEFAULT NULL,
  `password` varchar(255) NOT NULL,
  `email` varchar(127) DEFAULT NULL,
  `address` text DEFAULT NULL,
  `mailer_enabled` tinyint(1) NOT NULL DEFAULT 1,
  `login_count` int(11) NOT NULL DEFAULT 0,
  `failed_login_count` int(11) NOT NULL DEFAULT 0,
  `last_request_at` datetime DEFAULT NULL,
  `current_login_at` datetime DEFAULT NULL,
  `last_login_at` datetime DEFAULT NULL,
  `current_login_ip` varchar(255) DEFAULT NULL,
  `last_login_ip` varchar(255) DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL,
  `object_state` int(11) NOT NULL,
  `expiration_date` datetime DEFAULT NULL,
  `password_version` int(11) NOT NULL DEFAULT 1,
  `last_activity_at` datetime DEFAULT NULL,
  `language_id` int(11) DEFAULT 1,
  `orig_login` varchar(63) DEFAULT NULL,
  `password_reset` tinyint(1) NOT NULL DEFAULT 0,
  `lockout` tinyint(1) NOT NULL DEFAULT 0,
  `remind_after_date` datetime DEFAULT NULL,
  `preferred_session_length` int(11) NOT NULL DEFAULT 1200,
  `preferred_logout_all` tinyint(1) NOT NULL DEFAULT 0,
  `enable_single_sign_on` tinyint(1) DEFAULT 1,
  `enable_basic_auth` tinyint(1) NOT NULL DEFAULT 0,
  `enable_token_auth` tinyint(1) NOT NULL DEFAULT 1,
  `enable_oauth2_auth` tinyint(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_users_on_login` (`login`) USING BTREE,
  KEY `index_users_on_object_state` (`object_state`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `versions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `versions` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `item_type` varchar(255) NOT NULL,
  `item_id` int(11) NOT NULL,
  `event` varchar(255) NOT NULL,
  `whodunnit` varchar(255) DEFAULT NULL,
  `object` text DEFAULT NULL,
  `created_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_versions_on_item_type_and_item_id` (`item_type`,`item_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `vps_consoles`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `vps_consoles` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `vps_id` int(11) NOT NULL,
  `token` varchar(100) DEFAULT NULL,
  `expiration` datetime /* mariadb-5.3 */ NOT NULL,
  `user_id` int(11) DEFAULT NULL,
  `created_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  `updated_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_vps_consoles_on_token` (`token`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `vps_current_statuses`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `vps_current_statuses` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `vps_id` int(11) NOT NULL,
  `status` tinyint(1) NOT NULL,
  `is_running` tinyint(1) NOT NULL,
  `uptime` int(11) DEFAULT NULL,
  `cpus` int(11) DEFAULT NULL,
  `total_memory` int(11) DEFAULT NULL,
  `total_swap` int(11) DEFAULT NULL,
  `update_count` int(11) NOT NULL,
  `process_count` int(11) DEFAULT NULL,
  `cpu_user` float DEFAULT NULL,
  `cpu_nice` float DEFAULT NULL,
  `cpu_system` float DEFAULT NULL,
  `cpu_idle` float DEFAULT NULL,
  `cpu_iowait` float DEFAULT NULL,
  `cpu_irq` float DEFAULT NULL,
  `cpu_softirq` float DEFAULT NULL,
  `loadavg5` float DEFAULT NULL,
  `used_memory` int(11) DEFAULT NULL,
  `used_swap` int(11) DEFAULT NULL,
  `sum_process_count` int(11) DEFAULT NULL,
  `sum_cpu_user` float DEFAULT NULL,
  `sum_cpu_nice` float DEFAULT NULL,
  `sum_cpu_system` float DEFAULT NULL,
  `sum_cpu_idle` float DEFAULT NULL,
  `sum_cpu_iowait` float DEFAULT NULL,
  `sum_cpu_irq` float DEFAULT NULL,
  `sum_cpu_softirq` float DEFAULT NULL,
  `sum_loadavg5` float DEFAULT NULL,
  `sum_used_memory` int(11) DEFAULT NULL,
  `sum_used_swap` int(11) DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL,
  `in_rescue_mode` tinyint(1) DEFAULT 0,
  `last_log_at` datetime(6) DEFAULT NULL,
  `loadavg1` float DEFAULT NULL,
  `loadavg15` float DEFAULT NULL,
  `sum_loadavg1` float DEFAULT NULL,
  `sum_loadavg15` float DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_vps_current_statuses_on_vps_id` (`vps_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `vps_features`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `vps_features` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `vps_id` int(11) NOT NULL,
  `name` varchar(255) NOT NULL,
  `enabled` tinyint(1) NOT NULL,
  `updated_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_vps_features_on_vps_id_and_name` (`vps_id`,`name`) USING BTREE,
  KEY `index_vps_features_on_vps_id` (`vps_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `vps_maintenance_windows`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `vps_maintenance_windows` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `vps_id` int(11) NOT NULL,
  `weekday` int(11) NOT NULL,
  `is_open` tinyint(1) NOT NULL,
  `opens_at` int(11) DEFAULT NULL,
  `closes_at` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_vps_maintenance_windows_on_vps_id_and_weekday` (`vps_id`,`weekday`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `vps_migrations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `vps_migrations` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `vps_id` int(11) NOT NULL,
  `migration_plan_id` int(11) NOT NULL,
  `state` int(11) NOT NULL DEFAULT 0,
  `outage_window` tinyint(1) NOT NULL DEFAULT 1,
  `transaction_chain_id` int(11) DEFAULT NULL,
  `src_node_id` int(11) NOT NULL,
  `dst_node_id` int(11) NOT NULL,
  `created_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  `started_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  `finished_at` datetime /* mariadb-5.3 */ DEFAULT NULL,
  `cleanup_data` tinyint(1) DEFAULT 1,
  PRIMARY KEY (`id`),
  UNIQUE KEY `vps_migrations_unique` (`migration_plan_id`,`vps_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `vps_os_processes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `vps_os_processes` (
  `vps_id` bigint(20) NOT NULL,
  `state` varchar(5) NOT NULL,
  `count` int(10) unsigned NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`vps_id`,`state`),
  KEY `index_vps_os_processes_on_vps_id` (`vps_id`),
  KEY `index_vps_os_processes_on_state` (`state`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `vps_ssh_host_keys`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `vps_ssh_host_keys` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `vps_id` bigint(20) NOT NULL,
  `bits` int(10) unsigned NOT NULL,
  `algorithm` varchar(30) NOT NULL,
  `fingerprint` varchar(100) NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_vps_ssh_host_keys_on_vps_id_and_algorithm` (`vps_id`,`algorithm`),
  KEY `index_vps_ssh_host_keys_on_vps_id` (`vps_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `vps_statuses`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `vps_statuses` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `vps_id` int(11) NOT NULL,
  `status` tinyint(1) NOT NULL,
  `is_running` tinyint(1) NOT NULL,
  `uptime` int(11) DEFAULT NULL,
  `process_count` int(11) DEFAULT NULL,
  `cpus` int(11) DEFAULT NULL,
  `cpu_user` float DEFAULT NULL,
  `cpu_nice` float DEFAULT NULL,
  `cpu_system` float DEFAULT NULL,
  `cpu_idle` float DEFAULT NULL,
  `cpu_iowait` float DEFAULT NULL,
  `cpu_irq` float DEFAULT NULL,
  `cpu_softirq` float DEFAULT NULL,
  `loadavg5` float DEFAULT NULL,
  `total_memory` int(11) DEFAULT NULL,
  `used_memory` int(11) DEFAULT NULL,
  `total_swap` int(11) DEFAULT NULL,
  `used_swap` int(11) DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  `in_rescue_mode` tinyint(1) DEFAULT 0,
  `loadavg1` float DEFAULT NULL,
  `loadavg15` float DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_vps_statuses_on_vps_id` (`vps_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `vpses`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `vpses` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(10) unsigned NOT NULL,
  `hostname` varchar(255) DEFAULT 'vps',
  `os_template_id` int(10) unsigned NOT NULL DEFAULT 1,
  `info` mediumtext DEFAULT NULL,
  `dns_resolver_id` int(11) DEFAULT NULL,
  `node_id` int(10) unsigned NOT NULL,
  `onstartall` tinyint(1) NOT NULL DEFAULT 1,
  `confirmed` int(11) NOT NULL DEFAULT 0,
  `dataset_in_pool_id` int(11) DEFAULT NULL,
  `maintenance_lock` int(11) NOT NULL DEFAULT 0,
  `maintenance_lock_reason` varchar(255) DEFAULT NULL,
  `object_state` int(11) NOT NULL,
  `expiration_date` datetime DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL,
  `manage_hostname` tinyint(1) NOT NULL DEFAULT 1,
  `cpu_limit` int(11) DEFAULT NULL,
  `start_menu_timeout` int(11) DEFAULT 5,
  `remind_after_date` datetime DEFAULT NULL,
  `autostart_enable` tinyint(1) NOT NULL DEFAULT 0,
  `autostart_priority` int(11) NOT NULL DEFAULT 1000,
  `cgroup_version` int(11) NOT NULL DEFAULT 0,
  `allow_admin_modifications` tinyint(1) NOT NULL DEFAULT 1,
  `user_namespace_map_id` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_vpses_on_dataset_in_pool_id` (`dataset_in_pool_id`) USING BTREE,
  KEY `index_vpses_on_dns_resolver_id` (`dns_resolver_id`) USING BTREE,
  KEY `index_vpses_on_node_id` (`node_id`) USING BTREE,
  KEY `index_vpses_on_object_state` (`object_state`) USING BTREE,
  KEY `index_vpses_on_os_template_id` (`os_template_id`) USING BTREE,
  KEY `index_vpses_on_user_id` (`user_id`) USING BTREE,
  KEY `index_vpses_on_cgroup_version` (`cgroup_version`),
  KEY `index_vpses_on_allow_admin_modifications` (`allow_admin_modifications`),
  KEY `index_vpses_on_user_namespace_map_id` (`user_namespace_map_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_czech_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

INSERT INTO `schema_migrations` (version) VALUES
('20240618092416'),
('20240615123252'),
('20240615093116'),
('20240614150907'),
('20240614140313'),
('20240612165217'),
('20240612140437'),
('20240612125623'),
('20240610150646'),
('20240602092635'),
('20240601131223'),
('20240527153145'),
('20240513130256'),
('20240418082651'),
('20240308152841'),
('20240229135345'),
('20240126165609'),
('20240125124755'),
('20240113193809'),
('20240113131046'),
('20231229175415'),
('20231220124552'),
('20231220100636'),
('20231219143126'),
('20231218085935'),
('20231216155818'),
('20231216135851'),
('20231214083846'),
('20231213163402'),
('20231207174132'),
('20231203074758'),
('20231201191543'),
('20231116085008'),
('20231031085006'),
('20231028151738'),
('20231028145905'),
('20231027164147'),
('20231016100700'),
('20230909064402'),
('20230904121318'),
('20230821123710'),
('20230810143840'),
('20230806151956'),
('20230803123312'),
('20230703161003'),
('20230623142135'),
('20230615150518'),
('20230615143920'),
('20230614112319'),
('20230421182709'),
('20230421171841'),
('20230415154230'),
('20230225142050'),
('20230225073544'),
('20230224164856'),
('20230218165608'),
('20230214080054'),
('20230214074616'),
('20230213092308'),
('20230213084545'),
('20230213083054'),
('20230213082735'),
('20230213081826'),
('20230122214018'),
('20221112155629'),
('20220920120951'),
('20220913114040'),
('20220913065326'),
('20220912070451'),
('20220908161330'),
('20220908140908'),
('20220831193118'),
('20220820133941'),
('20220714144902'),
('20220504184116'),
('20220202111859'),
('20220123194603'),
('20210529125923'),
('20210215160434'),
('20210126204326'),
('20200927121503'),
('20200924180219'),
('20200922070226'),
('20200803135923'),
('20200803134524'),
('20200309160016'),
('20200308161901'),
('20200307143441'),
('20191104081056'),
('20191021125132'),
('20190920153359'),
('20190912160159'),
('20190519074913'),
('20190513075510'),
('20190513064725'),
('20190513064011'),
('20190508070536'),
('20190507122654'),
('20190507121309'),
('20190503142157'),
('20190501185918'),
('20190314114331'),
('20190211124513'),
('20181121153314'),
('20181119183704'),
('20180929203314'),
('20180928161725'),
('20180604115723'),
('20180525100900'),
('20180524103629'),
('20180524085512'),
('20180518140011'),
('20180518104840'),
('20180516061203'),
('20180503073718'),
('20180501145934'),
('20180501071844'),
('20180416111102'),
('20180412063632'),
('20171106154702'),
('20170610084155'),
('20170325151018'),
('20170204092606'),
('20170203122106'),
('20170130154206'),
('20170130112048'),
('20170125153139'),
('20170120080846'),
('20170118160101'),
('20170118094034'),
('20170117181427'),
('20170117132633'),
('20170116135908'),
('20170115162128'),
('20170115153933'),
('20170115104106'),
('20170115092224'),
('20170114153715'),
('20170114091907'),
('20161115174257'),
('20160907135218'),
('20160906090554'),
('20160904191844'),
('20160902154617'),
('20160831111818'),
('20160826150804'),
('20160819100816'),
('20160819084000'),
('20160805144125'),
('20160629150716'),
('20160628064205'),
('20160627085407'),
('20160624185945'),
('20160614112222'),
('20160308154537'),
('20160229081009'),
('20160224195110'),
('20160222135554'),
('20160214135501'),
('20160214135014'),
('20160208123742'),
('20160204152946'),
('20160203074916'),
('20160203074500'),
('20160201072025'),
('20160130185329'),
('20160120075845'),
('20160109160611'),
('20151213173722'),
('20151124085559'),
('20151124085214'),
('20151029160857'),
('20151029155746'),
('20151017155120'),
('20151017130111'),
('20151015085656'),
('20151004115901'),
('20151002090440'),
('20150904152438'),
('20150904081403'),
('20150903120108'),
('20150903081103'),
('20150820174810'),
('20150811075054'),
('20150807152819'),
('20150804201125'),
('20150802162711'),
('20150801211753'),
('20150801090150'),
('20150730152316'),
('20150730133630'),
('20150728160553'),
('20150717065916'),
('20150715150147'),
('20150630072821'),
('20150625145437'),
('20150618124817'),
('20150614074218'),
('20150528111113'),
('20150528110508'),
('20150312171845'),
('20150309175827'),
('20150307174728'),
('20150218142131'),
('20150206154652'),
('20150205145349'),
('20150131162852'),
('20150126080724'),
('20141212180955'),
('20141112075438'),
('20141105175157'),
('20141105130158'),
('20140927161700'),
('20140927161625'),
('20140913164605'),
('20140815161745'),
('20140615185520'),
('20140227150154'),
('20140208170244');

