# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2025_10_03_074953) do
  create_table "auth_tokens", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "token_id", null: false
    t.integer "user_id", null: false
    t.string "opts"
    t.datetime "created_at", precision: nil, null: false
    t.string "api_ip_addr", limit: 46
    t.string "api_ip_ptr"
    t.string "client_ip_addr", limit: 46
    t.string "client_ip_ptr"
    t.integer "user_agent_id"
    t.string "client_version"
    t.integer "purpose", default: 0, null: false
    t.boolean "fulfilled", default: false, null: false
  end

  create_table "branches", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "dataset_tree_id", null: false
    t.string "name", null: false
    t.integer "index", default: 0, null: false
    t.boolean "head", default: false, null: false
    t.integer "confirmed", default: 0, null: false
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["dataset_tree_id"], name: "index_branches_on_dataset_tree_id"
  end

  create_table "cluster_resource_package_items", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "cluster_resource_package_id", null: false
    t.integer "cluster_resource_id", null: false
    t.decimal "value", precision: 40, null: false
    t.index ["cluster_resource_id"], name: "cluster_resource_id"
    t.index ["cluster_resource_package_id", "cluster_resource_id"], name: "cluster_resource_package_items_unique", unique: true
    t.index ["cluster_resource_package_id"], name: "cluster_resource_package_id"
  end

  create_table "cluster_resource_packages", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.string "label", null: false
    t.integer "environment_id"
    t.integer "user_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["environment_id", "user_id"], name: "cluster_resource_packages_unique", unique: true
    t.index ["environment_id"], name: "index_cluster_resource_packages_on_environment_id"
    t.index ["user_id"], name: "index_cluster_resource_packages_on_user_id"
  end

  create_table "cluster_resource_uses", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "user_cluster_resource_id", null: false
    t.string "class_name", null: false
    t.string "table_name", null: false
    t.integer "row_id", null: false
    t.decimal "value", precision: 40, null: false
    t.integer "confirmed", default: 0, null: false
    t.integer "admin_lock_type", default: 0, null: false
    t.integer "admin_limit"
    t.boolean "enabled", default: true, null: false
    t.index ["class_name", "table_name", "row_id"], name: "cluster_resouce_use_name_search"
    t.index ["user_cluster_resource_id"], name: "index_cluster_resource_uses_on_user_cluster_resource_id"
  end

  create_table "cluster_resources", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.string "name", limit: 100, null: false
    t.string "label", limit: 100, null: false
    t.decimal "min", precision: 40, null: false
    t.decimal "max", precision: 40, null: false
    t.integer "stepsize", null: false
    t.integer "resource_type", null: false
    t.string "allocate_chain"
    t.string "free_chain"
    t.index ["name"], name: "index_cluster_resources_on_name", unique: true
  end

  create_table "components", charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.string "name", limit: 30, null: false
    t.string "label", limit: 100, null: false
    t.text "description", default: "", null: false
    t.index ["name"], name: "index_components_on_name", unique: true
  end

  create_table "dataset_actions", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "pool_id"
    t.integer "src_dataset_in_pool_id"
    t.integer "dst_dataset_in_pool_id"
    t.integer "snapshot_id"
    t.boolean "recursive", default: false, null: false
    t.integer "dataset_plan_id"
    t.integer "dataset_in_pool_plan_id"
    t.integer "action", null: false
  end

  create_table "dataset_expansion_events", charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.bigint "dataset_id", null: false
    t.integer "original_refquota", null: false
    t.integer "new_refquota", null: false
    t.integer "added_space", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["dataset_id"], name: "index_dataset_expansion_events_on_dataset_id"
  end

  create_table "dataset_expansion_histories", charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.bigint "dataset_expansion_id", null: false
    t.integer "original_refquota", null: false
    t.integer "new_refquota", null: false
    t.integer "added_space", null: false
    t.bigint "admin_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_id"], name: "index_dataset_expansion_histories_on_admin_id"
    t.index ["dataset_expansion_id"], name: "index_dataset_expansion_histories_on_dataset_expansion_id"
  end

  create_table "dataset_expansions", charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.bigint "vps_id", null: false
    t.bigint "dataset_id", null: false
    t.integer "state", default: 0, null: false
    t.integer "original_refquota", null: false
    t.integer "added_space", null: false
    t.boolean "enable_notifications", default: true, null: false
    t.boolean "enable_shrink", default: true, null: false
    t.boolean "stop_vps", default: true, null: false
    t.datetime "last_shrink"
    t.datetime "last_vps_stop"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "over_refquota_seconds", default: 0, null: false
    t.integer "max_over_refquota_seconds", null: false
    t.datetime "last_over_refquota_check"
    t.index ["dataset_id"], name: "index_dataset_expansions_on_dataset_id"
    t.index ["vps_id"], name: "index_dataset_expansions_on_vps_id"
  end

  create_table "dataset_in_pool_plans", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "environment_dataset_plan_id", null: false
    t.integer "dataset_in_pool_id", null: false
    t.index ["environment_dataset_plan_id", "dataset_in_pool_id"], name: "dataset_in_pool_plans_unique", unique: true
  end

  create_table "dataset_in_pools", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "dataset_id", null: false
    t.integer "pool_id", null: false
    t.string "label", limit: 100
    t.integer "used", default: 0, null: false
    t.integer "avail", default: 0, null: false
    t.integer "min_snapshots", default: 14, null: false
    t.integer "max_snapshots", default: 20, null: false
    t.integer "snapshot_max_age", default: 1209600, null: false
    t.string "mountpoint", limit: 500
    t.integer "confirmed", default: 0, null: false
    t.index ["dataset_id", "pool_id"], name: "index_dataset_in_pools_on_dataset_id_and_pool_id", unique: true
    t.index ["dataset_id"], name: "index_dataset_in_pools_on_dataset_id"
  end

  create_table "dataset_plans", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.string "name", null: false
  end

  create_table "dataset_properties", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "pool_id"
    t.integer "dataset_id"
    t.integer "dataset_in_pool_id"
    t.string "ancestry"
    t.integer "ancestry_depth", default: 0, null: false
    t.string "name", limit: 30, null: false
    t.string "value"
    t.boolean "inherited", default: true, null: false
    t.integer "confirmed", default: 0, null: false
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["dataset_id"], name: "index_dataset_properties_on_dataset_id"
    t.index ["dataset_in_pool_id", "name"], name: "index_dataset_properties_on_dataset_in_pool_id_and_name"
    t.index ["dataset_in_pool_id"], name: "index_dataset_properties_on_dataset_in_pool_id"
    t.index ["pool_id"], name: "index_dataset_properties_on_pool_id"
  end

  create_table "dataset_property_histories", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "dataset_property_id", null: false
    t.integer "value", null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["dataset_property_id"], name: "index_dataset_property_histories_on_dataset_property_id"
  end

  create_table "dataset_trees", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "dataset_in_pool_id", null: false
    t.integer "index", default: 0, null: false
    t.boolean "head", default: false, null: false
    t.integer "confirmed", default: 0, null: false
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["dataset_in_pool_id"], name: "index_dataset_trees_on_dataset_in_pool_id"
  end

  create_table "datasets", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.string "name", null: false
    t.string "full_name", limit: 1000, null: false
    t.integer "user_id"
    t.boolean "user_editable", null: false
    t.boolean "user_create", null: false
    t.boolean "user_destroy", null: false
    t.string "ancestry"
    t.integer "ancestry_depth", default: 0, null: false
    t.datetime "expiration", precision: nil
    t.integer "confirmed", default: 0, null: false
    t.integer "object_state", null: false
    t.datetime "expiration_date", precision: nil
    t.integer "current_history_id", default: 0, null: false
    t.datetime "remind_after_date", precision: nil
    t.integer "dataset_expansion_id"
    t.bigint "vps_id"
    t.index ["ancestry"], name: "index_datasets_on_ancestry"
    t.index ["dataset_expansion_id"], name: "index_datasets_on_dataset_expansion_id", unique: true
    t.index ["user_id"], name: "index_datasets_on_user_id"
    t.index ["vps_id"], name: "index_datasets_on_vps_id"
  end

  create_table "default_lifetime_values", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "environment_id"
    t.string "class_name", limit: 50, null: false
    t.integer "direction", null: false
    t.integer "state", null: false
    t.integer "add_expiration"
    t.string "reason", null: false
  end

  create_table "default_object_cluster_resources", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "environment_id", null: false
    t.integer "cluster_resource_id", null: false
    t.string "class_name", null: false
    t.decimal "value", precision: 40, null: false
  end

  create_table "default_user_cluster_resource_packages", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "environment_id", null: false
    t.integer "cluster_resource_package_id", null: false
    t.index ["environment_id", "cluster_resource_package_id"], name: "default_user_cluster_resource_packages_unique", unique: true
  end

  create_table "dns_record_logs", charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.bigint "dns_zone_id"
    t.integer "change_type", null: false
    t.string "name", null: false
    t.string "record_type", limit: 10, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "attr_changes", size: :medium, null: false
    t.bigint "user_id"
    t.string "dns_zone_name", limit: 500, null: false
    t.bigint "transaction_chain_id"
    t.index ["dns_zone_id"], name: "index_dns_record_logs_on_dns_zone_id"
    t.index ["user_id"], name: "index_dns_record_logs_on_user_id"
  end

  create_table "dns_records", charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.bigint "dns_zone_id", null: false
    t.string "name", null: false
    t.string "record_type", limit: 10, null: false
    t.text "content", null: false
    t.integer "ttl"
    t.integer "priority"
    t.boolean "enabled", default: true, null: false
    t.bigint "host_ip_address_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "confirmed", default: 0, null: false
    t.string "comment", default: "", null: false
    t.bigint "update_token_id"
    t.boolean "managed", default: false, null: false
    t.integer "user_id"
    t.boolean "original_enabled", default: true, null: false
    t.index ["dns_zone_id"], name: "index_dns_records_on_dns_zone_id"
    t.index ["host_ip_address_id"], name: "index_dns_records_on_host_ip_address_id", unique: true
    t.index ["update_token_id"], name: "index_dns_records_on_update_token_id"
    t.index ["user_id"], name: "index_dns_records_on_user_id"
  end

  create_table "dns_resolvers", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.string "addrs", limit: 63, null: false
    t.string "label", limit: 63, null: false
    t.boolean "is_universal", default: false
    t.integer "location_id", unsigned: true
    t.integer "ip_version", default: 4
  end

  create_table "dns_server_zones", charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.bigint "dns_server_id", null: false
    t.bigint "dns_zone_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "serial", unsigned: true
    t.datetime "loaded_at"
    t.datetime "expires_at"
    t.datetime "refresh_at"
    t.datetime "last_check_at"
    t.integer "confirmed", default: 0, null: false
    t.integer "zone_type", default: 0, null: false
    t.index ["dns_server_id", "dns_zone_id"], name: "index_dns_server_zones_on_dns_server_id_and_dns_zone_id", unique: true
    t.index ["dns_server_id"], name: "index_dns_server_zones_on_dns_server_id"
    t.index ["dns_zone_id"], name: "index_dns_server_zones_on_dns_zone_id"
  end

  create_table "dns_servers", charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.bigint "node_id", null: false
    t.string "name", null: false
    t.string "ipv4_addr", limit: 46
    t.string "ipv6_addr", limit: 46
    t.boolean "enable_user_dns_zones", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "hidden", default: false, null: false
    t.integer "user_dns_zone_type", default: 0, null: false
    t.index ["name"], name: "index_dns_servers_on_name", unique: true
    t.index ["node_id"], name: "index_dns_servers_on_node_id"
  end

  create_table "dns_tsig_keys", charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.bigint "user_id"
    t.string "name", null: false
    t.string "algorithm", limit: 20, null: false
    t.string "secret", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_dns_tsig_keys_on_name", unique: true
    t.index ["user_id"], name: "index_dns_tsig_keys_on_user_id"
  end

  create_table "dns_zone_transfers", charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.bigint "dns_zone_id", null: false
    t.bigint "host_ip_address_id", null: false
    t.integer "peer_type", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "dns_tsig_key_id"
    t.integer "confirmed", default: 0, null: false
    t.index ["dns_tsig_key_id"], name: "index_dns_zone_transfers_on_dns_tsig_key_id"
    t.index ["dns_zone_id", "host_ip_address_id"], name: "index_dns_zone_transfers_on_dns_zone_id_and_host_ip_address_id", unique: true
    t.index ["dns_zone_id"], name: "index_dns_zone_transfers_on_dns_zone_id"
    t.index ["host_ip_address_id"], name: "index_dns_zone_transfers_on_host_ip_address_id"
  end

  create_table "dns_zones", charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.bigint "user_id"
    t.string "name", limit: 500, null: false
    t.string "reverse_network_address", limit: 46
    t.integer "reverse_network_prefix"
    t.string "label", limit: 500, default: "", null: false
    t.integer "zone_role", default: 0, null: false
    t.integer "zone_source", default: 0, null: false
    t.integer "default_ttl", default: 3600
    t.string "email"
    t.integer "serial", default: 1, unsigned: true
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "confirmed", default: 0, null: false
    t.boolean "dnssec_enabled", default: false, null: false
    t.boolean "original_enabled", default: true, null: false
    t.index ["name"], name: "index_dns_zones_on_name", unique: true
    t.index ["user_id"], name: "index_dns_zones_on_user_id"
    t.index ["zone_source"], name: "index_dns_zones_on_zone_source"
  end

  create_table "dnssec_records", charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.bigint "dns_zone_id", null: false
    t.integer "keyid", null: false
    t.integer "dnskey_algorithm", null: false
    t.string "dnskey_pubkey", limit: 1000, null: false
    t.integer "ds_algorithm", null: false
    t.integer "ds_digest_type", null: false
    t.string "ds_digest", limit: 1000, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["dns_zone_id"], name: "index_dnssec_records_on_dns_zone_id"
  end

  create_table "environment_dataset_plans", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "environment_id", null: false
    t.integer "dataset_plan_id", null: false
    t.boolean "user_add", null: false
    t.boolean "user_remove", null: false
  end

  create_table "environment_user_configs", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "environment_id", null: false
    t.integer "user_id", null: false
    t.boolean "can_create_vps", default: false, null: false
    t.boolean "can_destroy_vps", default: false, null: false
    t.integer "vps_lifetime", default: 0, null: false
    t.integer "max_vps_count", default: 1, null: false
    t.boolean "default", default: true, null: false
    t.index ["environment_id", "user_id"], name: "environment_user_configs_unique", unique: true
  end

  create_table "environments", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.string "label", limit: 100, null: false
    t.string "domain", limit: 100, null: false
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.integer "maintenance_lock", default: 0, null: false
    t.string "maintenance_lock_reason"
    t.boolean "can_create_vps", default: false, null: false
    t.boolean "can_destroy_vps", default: false, null: false
    t.integer "vps_lifetime", default: 0, null: false
    t.integer "max_vps_count", default: 1, null: false
    t.boolean "user_ip_ownership", null: false
    t.text "description"
  end

  create_table "export_hosts", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "export_id", null: false
    t.integer "ip_address_id", null: false
    t.boolean "rw", null: false
    t.boolean "sync", null: false
    t.boolean "subtree_check", null: false
    t.boolean "root_squash", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["export_id", "ip_address_id"], name: "index_export_hosts_on_export_id_and_ip_address_id", unique: true
  end

  create_table "export_mounts", charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.bigint "export_id", null: false
    t.bigint "vps_id", null: false
    t.string "mountpoint", limit: 500, null: false
    t.string "nfs_version", limit: 10, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["export_id"], name: "index_export_mounts_on_export_id"
    t.index ["vps_id"], name: "index_export_mounts_on_vps_id"
  end

  create_table "exports", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "dataset_in_pool_id", null: false
    t.integer "snapshot_in_pool_clone_id"
    t.integer "user_id", null: false
    t.boolean "all_vps", default: true, null: false
    t.string "path", null: false
    t.boolean "rw", default: true, null: false
    t.boolean "sync", default: true, null: false
    t.boolean "subtree_check", default: false, null: false
    t.boolean "root_squash", default: false, null: false
    t.integer "threads", default: 8, null: false
    t.boolean "enabled", default: true, null: false
    t.integer "object_state", null: false
    t.datetime "expiration_date", precision: nil
    t.integer "confirmed", default: 0, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "snapshot_in_pool_clone_n", default: 0, null: false
    t.datetime "remind_after_date", precision: nil
    t.boolean "original_enabled", default: true, null: false
    t.bigint "uuid_id", null: false
    t.index ["dataset_in_pool_id", "snapshot_in_pool_clone_n"], name: "exports_unique", unique: true
    t.index ["user_id"], name: "index_exports_on_user_id"
    t.index ["uuid_id"], name: "index_exports_on_uuid_id", unique: true
  end

  create_table "group_snapshots", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "dataset_action_id"
    t.integer "dataset_in_pool_id"
    t.index ["dataset_action_id", "dataset_in_pool_id"], name: "group_snapshots_unique", unique: true
  end

  create_table "host_ip_addresses", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "ip_address_id", null: false
    t.string "ip_addr", limit: 40, null: false
    t.integer "order"
    t.boolean "auto_add", default: true, null: false
    t.boolean "user_created", default: false, null: false
    t.bigint "reverse_dns_record_id"
    t.index ["auto_add"], name: "index_host_ip_addresses_on_auto_add"
    t.index ["ip_address_id", "ip_addr"], name: "index_host_ip_addresses_on_ip_address_id_and_ip_addr", unique: true
    t.index ["ip_address_id"], name: "index_host_ip_addresses_on_ip_address_id"
    t.index ["reverse_dns_record_id"], name: "index_host_ip_addresses_on_reverse_dns_record_id", unique: true
  end

  create_table "incident_reports", charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "vps_id", null: false
    t.bigint "ip_address_assignment_id"
    t.bigint "filed_by_id"
    t.bigint "mailbox_id"
    t.string "subject", null: false
    t.text "text", null: false
    t.string "codename", limit: 100
    t.datetime "detected_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "reported_at"
    t.integer "cpu_limit"
    t.integer "vps_action", default: 0, null: false
    t.index ["cpu_limit"], name: "index_incident_reports_on_cpu_limit"
    t.index ["created_at"], name: "index_incident_reports_on_created_at"
    t.index ["detected_at"], name: "index_incident_reports_on_detected_at"
    t.index ["filed_by_id"], name: "index_incident_reports_on_filed_by_id"
    t.index ["ip_address_assignment_id"], name: "index_incident_reports_on_ip_address_assignment_id"
    t.index ["mailbox_id"], name: "index_incident_reports_on_mailbox_id"
    t.index ["reported_at"], name: "index_incident_reports_on_reported_at"
    t.index ["user_id"], name: "index_incident_reports_on_user_id"
    t.index ["vps_id"], name: "index_incident_reports_on_vps_id"
  end

  create_table "ip_address_assignments", charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.bigint "ip_address_id", null: false
    t.string "ip_addr", limit: 40, null: false
    t.integer "ip_prefix", null: false
    t.bigint "user_id", null: false
    t.bigint "vps_id", null: false
    t.datetime "from_date", null: false
    t.datetime "to_date"
    t.bigint "assigned_by_chain_id"
    t.bigint "unassigned_by_chain_id"
    t.boolean "reconstructed", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["assigned_by_chain_id"], name: "index_ip_address_assignments_on_assigned_by_chain_id"
    t.index ["from_date"], name: "index_ip_address_assignments_on_from_date"
    t.index ["ip_addr"], name: "index_ip_address_assignments_on_ip_addr"
    t.index ["ip_address_id"], name: "index_ip_address_assignments_on_ip_address_id"
    t.index ["ip_prefix"], name: "index_ip_address_assignments_on_ip_prefix"
    t.index ["to_date"], name: "index_ip_address_assignments_on_to_date"
    t.index ["unassigned_by_chain_id"], name: "index_ip_address_assignments_on_unassigned_by_chain_id"
    t.index ["user_id"], name: "index_ip_address_assignments_on_user_id"
    t.index ["vps_id"], name: "index_ip_address_assignments_on_vps_id"
  end

  create_table "ip_addresses", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.string "ip_addr", limit: 40, null: false
    t.integer "user_id"
    t.integer "network_id", null: false
    t.integer "order"
    t.integer "prefix", null: false
    t.decimal "size", precision: 40, null: false
    t.integer "network_interface_id"
    t.integer "route_via_id"
    t.integer "charged_environment_id"
    t.bigint "reverse_dns_zone_id"
    t.index ["charged_environment_id"], name: "index_ip_addresses_on_charged_environment_id"
    t.index ["network_id"], name: "index_ip_addresses_on_network_id"
    t.index ["network_interface_id"], name: "index_ip_addresses_on_network_interface_id"
    t.index ["reverse_dns_zone_id"], name: "index_ip_addresses_on_reverse_dns_zone_id"
    t.index ["route_via_id"], name: "index_ip_addresses_on_route_via_id"
    t.index ["user_id"], name: "index_ip_addresses_on_user_id"
  end

  create_table "ip_traffic_monthly_summaries", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "ip_address_id", null: false
    t.integer "user_id"
    t.integer "protocol", null: false
    t.integer "role", null: false
    t.bigint "packets_in", default: 0, null: false, unsigned: true
    t.bigint "packets_out", default: 0, null: false, unsigned: true
    t.bigint "bytes_in", default: 0, null: false, unsigned: true
    t.bigint "bytes_out", default: 0, null: false, unsigned: true
    t.datetime "created_at", precision: nil, null: false
    t.integer "year", null: false
    t.integer "month", null: false
    t.index ["ip_address_id", "user_id", "protocol", "role", "created_at"], name: "ip_traffic_monthly_summaries_unique", unique: true
    t.index ["ip_address_id", "year", "month"], name: "ip_traffic_monthly_summaries_ip_year_month"
    t.index ["ip_address_id"], name: "index_ip_traffic_monthly_summaries_on_ip_address_id"
    t.index ["month"], name: "index_ip_traffic_monthly_summaries_on_month"
    t.index ["protocol"], name: "index_ip_traffic_monthly_summaries_on_protocol"
    t.index ["user_id"], name: "index_ip_traffic_monthly_summaries_on_user_id"
    t.index ["year", "month"], name: "index_ip_traffic_monthly_summaries_on_year_and_month"
    t.index ["year"], name: "index_ip_traffic_monthly_summaries_on_year"
  end

  create_table "languages", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.string "code", limit: 2, null: false
    t.string "label", limit: 100, null: false
    t.index ["code"], name: "index_languages_on_code", unique: true
  end

  create_table "location_networks", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "location_id", null: false
    t.integer "network_id", null: false
    t.integer "priority", default: 10, null: false
    t.boolean "autopick", default: true, null: false
    t.boolean "userpick", default: true, null: false
    t.boolean "primary"
    t.index ["location_id", "network_id"], name: "index_location_networks_on_location_id_and_network_id", unique: true
    t.index ["network_id", "primary"], name: "location_networks_primary", unique: true
  end

  create_table "locations", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.string "label", limit: 63, null: false
    t.boolean "has_ipv6", null: false
    t.string "remote_console_server", null: false
    t.string "domain", limit: 100, null: false
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.integer "maintenance_lock", default: 0, null: false
    t.string "maintenance_lock_reason"
    t.integer "environment_id", null: false
    t.text "description"
  end

  create_table "mail_logs", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "user_id"
    t.string "to", limit: 500, null: false
    t.string "cc", limit: 500, null: false
    t.string "bcc", limit: 500, null: false
    t.string "from", null: false
    t.string "reply_to"
    t.string "return_path"
    t.string "message_id"
    t.string "in_reply_to"
    t.string "references"
    t.string "subject", null: false
    t.text "text_plain", size: :long
    t.text "text_html", size: :long
    t.integer "mail_template_id"
    t.integer "transaction_id"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["user_id"], name: "index_mail_logs_on_user_id"
  end

  create_table "mail_recipients", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.string "label", limit: 100, null: false
    t.string "to", limit: 500
    t.string "cc", limit: 500
    t.string "bcc", limit: 500
  end

  create_table "mail_template_recipients", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "mail_template_id", null: false
    t.integer "mail_recipient_id", null: false
    t.index ["mail_template_id", "mail_recipient_id"], name: "mail_template_recipients_unique", unique: true
  end

  create_table "mail_template_translations", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "mail_template_id", null: false
    t.integer "language_id", null: false
    t.string "from", null: false
    t.string "reply_to"
    t.string "return_path"
    t.string "subject", null: false
    t.text "text_plain"
    t.text "text_html"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["mail_template_id", "language_id"], name: "mail_template_translation_unique", unique: true
  end

  create_table "mail_templates", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.string "name", limit: 100, null: false
    t.string "label", limit: 100, null: false
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.string "template_id", limit: 100, null: false
    t.integer "user_visibility", default: 0, null: false
    t.index ["name"], name: "index_mail_templates_on_name", unique: true
  end

  create_table "mailbox_handlers", charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.bigint "mailbox_id", null: false
    t.string "class_name", null: false
    t.integer "order", default: 1, null: false
    t.boolean "continue", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["mailbox_id"], name: "index_mailbox_handlers_on_mailbox_id"
  end

  create_table "mailboxes", charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.string "label", null: false
    t.string "server", null: false
    t.integer "port", default: 993, null: false
    t.string "user", null: false
    t.string "password", null: false
    t.boolean "enable_ssl", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "maintenance_locks", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.string "class_name", limit: 100, null: false
    t.integer "row_id"
    t.integer "user_id"
    t.string "reason", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["class_name", "row_id"], name: "index_maintenance_locks_on_class_name_and_row_id"
  end

  create_table "metrics_access_tokens", charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.bigint "token_id", null: false
    t.bigint "user_id", null: false
    t.string "metric_prefix", limit: 30, default: "vpsadmin_", null: false
    t.integer "use_count", default: 0, null: false
    t.datetime "last_use"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token_id"], name: "index_metrics_access_tokens_on_token_id"
    t.index ["user_id"], name: "index_metrics_access_tokens_on_user_id"
  end

  create_table "migration_plans", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "state", default: 0, null: false
    t.boolean "stop_on_error", default: true, null: false
    t.boolean "send_mail", default: true, null: false
    t.integer "user_id"
    t.integer "node_id"
    t.integer "concurrency", null: false
    t.string "reason"
    t.datetime "created_at", precision: nil
    t.datetime "finished_at", precision: nil
  end

  create_table "mirrors", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "src_pool_id"
    t.integer "dst_pool_id"
    t.integer "src_dataset_in_pool_id"
    t.integer "dst_dataset_in_pool_id"
    t.boolean "recursive", default: false, null: false
    t.integer "interval", default: 60, null: false
  end

  create_table "mounts", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "vps_id", null: false
    t.string "src", limit: 500
    t.string "dst", limit: 500, null: false
    t.string "mount_opts", null: false
    t.string "umount_opts", null: false
    t.string "mount_type", limit: 10, null: false
    t.boolean "user_editable", default: true, null: false
    t.integer "dataset_in_pool_id"
    t.integer "snapshot_in_pool_id"
    t.string "mode", limit: 2, null: false
    t.integer "confirmed", default: 0, null: false
    t.integer "object_state", null: false
    t.datetime "expiration_date", precision: nil
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.integer "on_start_fail", default: 1, null: false
    t.boolean "enabled", default: true, null: false
    t.boolean "master_enabled", default: true, null: false
    t.integer "current_state", default: 0, null: false
    t.integer "snapshot_in_pool_clone_id"
    t.datetime "remind_after_date", precision: nil
    t.index ["snapshot_in_pool_clone_id"], name: "index_mounts_on_snapshot_in_pool_clone_id"
    t.index ["vps_id"], name: "index_mounts_on_vps_id"
  end

  create_table "network_interface_daily_accountings", primary_key: ["network_interface_id", "user_id", "year", "month", "day"], charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.bigint "network_interface_id", null: false
    t.bigint "user_id", null: false
    t.bigint "packets_in", null: false, unsigned: true
    t.bigint "packets_out", null: false, unsigned: true
    t.bigint "bytes_in", null: false, unsigned: true
    t.bigint "bytes_out", null: false, unsigned: true
    t.integer "year", null: false
    t.integer "month", null: false
    t.integer "day", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["day"], name: "index_network_interface_daily_accountings_on_day"
    t.index ["month"], name: "index_network_interface_daily_accountings_on_month"
    t.index ["network_interface_id"], name: "index_network_interface_daily_accountings_on_netif"
    t.index ["user_id"], name: "index_network_interface_daily_accountings_on_user_id"
    t.index ["year"], name: "index_network_interface_daily_accountings_on_year"
  end

  create_table "network_interface_monitors", primary_key: "network_interface_id", id: :bigint, default: nil, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.bigint "packets", null: false, unsigned: true
    t.bigint "packets_in", null: false, unsigned: true
    t.bigint "packets_out", null: false, unsigned: true
    t.bigint "bytes", null: false, unsigned: true
    t.bigint "bytes_in", null: false, unsigned: true
    t.bigint "bytes_out", null: false, unsigned: true
    t.integer "delta", null: false
    t.bigint "packets_in_readout", null: false, unsigned: true
    t.bigint "packets_out_readout", null: false, unsigned: true
    t.bigint "bytes_in_readout", null: false, unsigned: true
    t.bigint "bytes_out_readout", null: false, unsigned: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "network_interface_monthly_accountings", primary_key: ["network_interface_id", "user_id", "year", "month"], charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.bigint "network_interface_id", null: false
    t.bigint "user_id", null: false
    t.bigint "packets_in", null: false, unsigned: true
    t.bigint "packets_out", null: false, unsigned: true
    t.bigint "bytes_in", null: false, unsigned: true
    t.bigint "bytes_out", null: false, unsigned: true
    t.integer "year", null: false
    t.integer "month", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["month"], name: "index_network_interface_monthly_accountings_on_month"
    t.index ["network_interface_id"], name: "index_network_interface_monthly_accountings_on_netif"
    t.index ["user_id"], name: "index_network_interface_monthly_accountings_on_user_id"
    t.index ["year"], name: "index_network_interface_monthly_accountings_on_year"
  end

  create_table "network_interface_yearly_accountings", primary_key: ["network_interface_id", "user_id", "year"], charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.bigint "network_interface_id", null: false
    t.bigint "user_id", null: false
    t.bigint "packets_in", null: false, unsigned: true
    t.bigint "packets_out", null: false, unsigned: true
    t.bigint "bytes_in", null: false, unsigned: true
    t.bigint "bytes_out", null: false, unsigned: true
    t.integer "year", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["network_interface_id"], name: "index_network_interface_yearly_accountings_on_netif"
    t.index ["user_id"], name: "index_network_interface_yearly_accountings_on_user_id"
    t.index ["year"], name: "index_network_interface_yearly_accountings_on_year"
  end

  create_table "network_interfaces", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "vps_id"
    t.string "name", limit: 30, null: false
    t.integer "kind", null: false
    t.string "mac", limit: 17
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.integer "export_id"
    t.bigint "max_tx", default: 0, null: false, unsigned: true
    t.bigint "max_rx", default: 0, null: false, unsigned: true
    t.boolean "enable", default: true, null: false
    t.index ["export_id", "name"], name: "index_network_interfaces_on_export_id_and_name", unique: true
    t.index ["kind"], name: "index_network_interfaces_on_kind"
    t.index ["mac"], name: "index_network_interfaces_on_mac", unique: true
    t.index ["vps_id", "name"], name: "index_network_interfaces_on_vps_id_and_name", unique: true
    t.index ["vps_id"], name: "index_network_interfaces_on_vps_id"
  end

  create_table "networks", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.string "label"
    t.integer "ip_version", null: false
    t.string "address", null: false
    t.integer "prefix", null: false
    t.integer "role", null: false
    t.boolean "managed", null: false
    t.integer "split_access", default: 0, null: false
    t.integer "split_prefix", null: false
    t.integer "purpose", default: 0, null: false
    t.integer "primary_location_id"
    t.index ["address", "prefix"], name: "index_networks_on_address_and_prefix", unique: true
    t.index ["purpose"], name: "index_networks_on_purpose"
  end

  create_table "node_current_statuses", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "node_id", null: false
    t.integer "uptime"
    t.integer "cpus"
    t.integer "total_memory"
    t.integer "total_swap"
    t.string "vpsadmin_version", limit: 25, null: false
    t.string "kernel", limit: 30, null: false
    t.integer "update_count", null: false
    t.integer "process_count"
    t.float "cpu_user"
    t.float "cpu_nice"
    t.float "cpu_system"
    t.float "cpu_idle"
    t.float "cpu_iowait"
    t.float "cpu_irq"
    t.float "cpu_softirq"
    t.float "cpu_guest"
    t.float "loadavg"
    t.integer "used_memory"
    t.integer "used_swap"
    t.integer "arc_c_max"
    t.integer "arc_c"
    t.integer "arc_size"
    t.float "arc_hitpercent"
    t.integer "sum_process_count"
    t.float "sum_cpu_user"
    t.float "sum_cpu_nice"
    t.float "sum_cpu_system"
    t.float "sum_cpu_idle"
    t.float "sum_cpu_iowait"
    t.float "sum_cpu_irq"
    t.float "sum_cpu_softirq"
    t.float "sum_cpu_guest"
    t.float "sum_loadavg"
    t.integer "sum_used_memory"
    t.integer "sum_used_swap"
    t.integer "sum_arc_c_max"
    t.integer "sum_arc_c"
    t.integer "sum_arc_size"
    t.float "sum_arc_hitpercent"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.integer "pool_state", default: 0, null: false
    t.integer "pool_scan", default: 0, null: false
    t.datetime "pool_checked_at", precision: nil
    t.float "pool_scan_percent"
    t.integer "cgroup_version", default: 1, null: false
    t.datetime "last_log_at"
    t.float "loadavg1", default: 0.0, null: false
    t.float "loadavg5", default: 0.0, null: false
    t.float "loadavg15", default: 0.0, null: false
    t.float "sum_loadavg1", default: 0.0, null: false
    t.float "sum_loadavg5", default: 0.0, null: false
    t.float "sum_loadavg15", default: 0.0, null: false
    t.index ["node_id"], name: "index_node_current_statuses_on_node_id", unique: true
  end

  create_table "node_statuses", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "node_id", null: false
    t.integer "uptime", null: false
    t.integer "process_count"
    t.integer "cpus"
    t.float "cpu_user"
    t.float "cpu_nice"
    t.float "cpu_system"
    t.float "cpu_idle"
    t.float "cpu_iowait"
    t.float "cpu_irq"
    t.float "cpu_softirq"
    t.float "cpu_guest"
    t.integer "total_memory"
    t.integer "used_memory"
    t.integer "total_swap"
    t.integer "used_swap"
    t.integer "arc_c_max"
    t.integer "arc_c"
    t.integer "arc_size"
    t.float "arc_hitpercent"
    t.float "loadavg"
    t.string "vpsadmin_version", limit: 25, null: false
    t.string "kernel", limit: 30, null: false
    t.datetime "created_at", precision: nil
    t.integer "cgroup_version", default: 1, null: false
    t.float "loadavg1", default: 0.0, null: false
    t.float "loadavg5", default: 0.0, null: false
    t.float "loadavg15", default: 0.0, null: false
    t.index ["node_id"], name: "index_node_statuses_on_node_id"
  end

  create_table "nodes", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.string "name", limit: 64, null: false
    t.integer "location_id", null: false, unsigned: true
    t.string "ip_addr", limit: 127, null: false
    t.integer "max_vps"
    t.bigint "max_tx", default: 235929600, null: false, unsigned: true
    t.bigint "max_rx", default: 235929600, null: false, unsigned: true
    t.integer "maintenance_lock", default: 0, null: false
    t.string "maintenance_lock_reason"
    t.integer "cpus", null: false
    t.integer "total_memory", null: false
    t.integer "total_swap", null: false
    t.integer "role", null: false
    t.integer "hypervisor_type"
    t.boolean "active", default: true, null: false
    t.index ["active"], name: "index_nodes_on_active"
    t.index ["hypervisor_type"], name: "index_nodes_on_hypervisor_type"
    t.index ["location_id"], name: "location_id"
  end

  create_table "oauth2_authorizations", charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.bigint "oauth2_client_id", null: false
    t.bigint "user_id", null: false
    t.text "scope", null: false
    t.bigint "code_id"
    t.bigint "user_session_id"
    t.bigint "refresh_token_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "code_challenge"
    t.string "code_challenge_method", limit: 20
    t.integer "single_sign_on_id"
    t.string "client_ip_addr", limit: 46
    t.string "client_ip_ptr"
    t.bigint "user_device_id"
    t.bigint "user_agent_id"
    t.index ["code_id"], name: "index_oauth2_authorizations_on_code_id"
    t.index ["oauth2_client_id"], name: "index_oauth2_authorizations_on_oauth2_client_id"
    t.index ["refresh_token_id"], name: "index_oauth2_authorizations_on_refresh_token_id"
    t.index ["single_sign_on_id"], name: "index_oauth2_authorizations_on_single_sign_on_id"
    t.index ["user_device_id"], name: "index_oauth2_authorizations_on_user_device_id"
    t.index ["user_id"], name: "index_oauth2_authorizations_on_user_id"
    t.index ["user_session_id"], name: "index_oauth2_authorizations_on_user_session_id"
  end

  create_table "oauth2_clients", charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.string "name", null: false
    t.string "client_id", null: false
    t.string "client_secret_hash", null: false
    t.string "redirect_uri", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "access_token_lifetime", default: 0, null: false
    t.integer "access_token_seconds", default: 900, null: false
    t.integer "refresh_token_seconds", default: 3600, null: false
    t.boolean "issue_refresh_token", default: false, null: false
    t.boolean "allow_single_sign_on", default: true, null: false
    t.index ["client_id"], name: "index_oauth2_clients_on_client_id", unique: true
  end

  create_table "object_histories", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "user_id"
    t.integer "user_session_id"
    t.integer "tracked_object_id", null: false
    t.string "tracked_object_type", null: false
    t.string "event_type", null: false
    t.text "event_data"
    t.datetime "created_at", precision: nil, null: false
    t.index ["tracked_object_id", "tracked_object_type"], name: "object_histories_tracked_object"
    t.index ["user_id"], name: "index_object_histories_on_user_id"
    t.index ["user_session_id"], name: "index_object_histories_on_user_session_id"
  end

  create_table "object_states", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.string "class_name", null: false
    t.integer "row_id", null: false
    t.integer "state", null: false
    t.integer "user_id"
    t.string "reason"
    t.datetime "expiration_date", precision: nil
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.datetime "remind_after_date", precision: nil
    t.index ["class_name", "row_id"], name: "index_object_states_on_class_name_and_row_id"
  end

  create_table "oom_preventions", charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.bigint "vps_id", null: false
    t.integer "action", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_oom_preventions_on_action"
    t.index ["vps_id"], name: "index_oom_preventions_on_vps_id"
  end

  create_table "oom_report_counters", charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.bigint "vps_id", null: false
    t.string "cgroup", default: "/", null: false
    t.bigint "counter", default: 0, null: false
    t.index ["vps_id", "cgroup"], name: "index_oom_report_counters_on_vps_id_and_cgroup", unique: true
    t.index ["vps_id"], name: "index_oom_report_counters_on_vps_id"
  end

  create_table "oom_report_rules", charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.bigint "vps_id", null: false
    t.integer "action", null: false
    t.string "cgroup_pattern", null: false
    t.bigint "hit_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["vps_id"], name: "index_oom_report_rules_on_vps_id"
  end

  create_table "oom_report_stats", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "oom_report_id", null: false
    t.string "parameter", limit: 30, null: false
    t.decimal "value", precision: 40, null: false
    t.index ["oom_report_id"], name: "index_oom_report_stats_on_oom_report_id"
  end

  create_table "oom_report_tasks", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "oom_report_id", null: false
    t.string "name", limit: 50, null: false
    t.integer "host_pid", null: false
    t.integer "vps_pid"
    t.integer "host_uid", null: false
    t.integer "vps_uid"
    t.integer "tgid", null: false
    t.integer "total_vm", null: false
    t.integer "rss", null: false
    t.integer "pgtables_bytes", null: false
    t.integer "swapents", null: false
    t.integer "oom_score_adj", null: false
    t.integer "rss_anon"
    t.integer "rss_file"
    t.integer "rss_shmem"
    t.index ["oom_report_id"], name: "index_oom_report_tasks_on_oom_report_id"
  end

  create_table "oom_report_usages", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "oom_report_id", null: false
    t.string "memtype", limit: 20, null: false
    t.decimal "usage", precision: 40, null: false
    t.decimal "limit", precision: 40, null: false
    t.decimal "failcnt", precision: 40, null: false
    t.index ["oom_report_id"], name: "index_oom_report_usages_on_oom_report_id"
  end

  create_table "oom_reports", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "vps_id", null: false
    t.integer "invoked_by_pid", null: false
    t.string "invoked_by_name", limit: 50, null: false
    t.integer "killed_pid"
    t.string "killed_name", limit: 50
    t.boolean "processed", default: false, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "reported_at", precision: nil
    t.integer "count", default: 1, null: false
    t.string "cgroup", default: "/", null: false
    t.boolean "ignored", default: false, null: false
    t.bigint "oom_report_rule_id"
    t.index ["created_at"], name: "index_oom_reports_on_created_at"
    t.index ["processed"], name: "index_oom_reports_on_processed"
    t.index ["reported_at"], name: "index_oom_reports_on_reported_at"
    t.index ["vps_id"], name: "index_oom_reports_on_vps_id"
  end

  create_table "os_families", charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.string "label", null: false
    t.text "description", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "os_templates", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.string "name", limit: 64, null: false
    t.string "label", limit: 64, null: false
    t.text "info"
    t.boolean "enabled", default: true, null: false
    t.boolean "supported", default: true, null: false
    t.integer "order", limit: 1, default: 1, null: false
    t.integer "hypervisor_type", default: 0, null: false
    t.string "vendor"
    t.string "variant"
    t.string "arch"
    t.string "distribution"
    t.string "version"
    t.integer "cgroup_version", default: 0, null: false
    t.text "config", default: "", null: false
    t.bigint "os_family_id", null: false
    t.boolean "manage_hostname", default: true, null: false
    t.boolean "manage_dns_resolver", default: true, null: false
    t.boolean "enable_script", default: true, null: false
    t.boolean "enable_cloud_init", default: true, null: false
    t.index ["cgroup_version"], name: "index_os_templates_on_cgroup_version"
    t.index ["enable_cloud_init"], name: "index_os_templates_on_enable_cloud_init"
    t.index ["enable_script"], name: "index_os_templates_on_enable_script"
    t.index ["os_family_id"], name: "index_os_templates_on_os_family_id"
  end

  create_table "pools", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "node_id", null: false
    t.string "label", limit: 500, null: false
    t.string "filesystem", limit: 500, null: false
    t.integer "role", null: false
    t.boolean "refquota_check", default: false, null: false
    t.integer "maintenance_lock", default: 0, null: false
    t.string "maintenance_lock_reason"
    t.string "export_root", limit: 100, default: "/export", null: false
    t.text "migration_public_key"
    t.integer "max_datasets", default: 0, null: false
    t.integer "state", default: 0, null: false
    t.integer "scan", default: 0, null: false
    t.datetime "checked_at", precision: nil
    t.float "scan_percent"
    t.integer "is_open", default: 1, null: false
    t.index ["is_open"], name: "index_pools_on_is_open"
  end

  create_table "port_reservations", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "node_id", null: false
    t.string "addr", limit: 100
    t.integer "port", null: false
    t.integer "transaction_chain_id"
    t.index ["node_id", "port"], name: "port_reservation_uniqueness", unique: true
    t.index ["node_id"], name: "index_port_reservations_on_node_id"
    t.index ["transaction_chain_id"], name: "index_port_reservations_on_transaction_chain_id"
  end

  create_table "repeatable_tasks", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.string "label", limit: 100
    t.string "class_name", null: false
    t.string "table_name", null: false
    t.integer "row_id", null: false
    t.string "minute", null: false
    t.string "hour", null: false
    t.string "day_of_month", null: false
    t.string "month", null: false
    t.string "day_of_week", null: false
  end

  create_table "resource_locks", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.string "resource", limit: 100, null: false
    t.integer "row_id", null: false
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.integer "locked_by_id"
    t.string "locked_by_type"
    t.index ["locked_by_id", "locked_by_type"], name: "index_resource_locks_on_locked_by_id_and_locked_by_type"
    t.index ["resource", "row_id"], name: "index_resource_locks_on_resource_and_row_id", unique: true
  end

  create_table "single_sign_ons", charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "token_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token_id"], name: "index_single_sign_ons_on_token_id"
    t.index ["user_id"], name: "index_single_sign_ons_on_user_id"
  end

  create_table "snapshot_downloads", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "snapshot_id"
    t.integer "pool_id", null: false
    t.string "secret_key", limit: 100, null: false
    t.string "file_name", null: false
    t.integer "confirmed", default: 0, null: false
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.integer "object_state", null: false
    t.datetime "expiration_date", precision: nil
    t.integer "size"
    t.integer "format", default: 0, null: false
    t.integer "from_snapshot_id"
    t.string "sha256sum", limit: 64
    t.datetime "remind_after_date", precision: nil
    t.index ["secret_key"], name: "index_snapshot_downloads_on_secret_key", unique: true
  end

  create_table "snapshot_in_pool_clones", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "snapshot_in_pool_id", null: false
    t.integer "state", default: 0, null: false
    t.string "name", limit: 50, null: false
    t.integer "user_namespace_map_id"
    t.integer "confirmed", default: 0, null: false
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["snapshot_in_pool_id", "user_namespace_map_id"], name: "snapshot_in_pool_clones_unique", unique: true
    t.index ["snapshot_in_pool_id"], name: "index_snapshot_in_pool_clones_on_snapshot_in_pool_id"
  end

  create_table "snapshot_in_pool_in_branches", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "snapshot_in_pool_id", null: false
    t.integer "snapshot_in_pool_in_branch_id"
    t.integer "branch_id", null: false
    t.integer "confirmed", default: 0, null: false
    t.index ["snapshot_in_pool_id", "branch_id"], name: "unique_snapshot_in_pool_in_branches", unique: true
    t.index ["snapshot_in_pool_id"], name: "index_snapshot_in_pool_in_branches_on_snapshot_in_pool_id"
  end

  create_table "snapshot_in_pools", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "snapshot_id", null: false
    t.integer "dataset_in_pool_id", null: false
    t.integer "reference_count", default: 0, null: false
    t.integer "mount_id"
    t.integer "confirmed", default: 0, null: false
    t.index ["dataset_in_pool_id"], name: "index_snapshot_in_pools_on_dataset_in_pool_id"
    t.index ["snapshot_id", "dataset_in_pool_id"], name: "index_snapshot_in_pools_on_snapshot_id_and_dataset_in_pool_id", unique: true
    t.index ["snapshot_id"], name: "index_snapshot_in_pools_on_snapshot_id"
  end

  create_table "snapshots", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.string "name", null: false
    t.integer "dataset_id", null: false
    t.integer "confirmed", default: 0, null: false
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.integer "snapshot_download_id"
    t.integer "history_id", default: 0, null: false
    t.string "label"
    t.index ["dataset_id"], name: "index_snapshots_on_dataset_id"
  end

  create_table "sysconfig", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.string "category", limit: 75, null: false
    t.string "name", limit: 75, null: false
    t.string "data_type", default: "Text", null: false
    t.text "value"
    t.string "label"
    t.text "description"
    t.integer "min_user_level"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["category", "name"], name: "index_sysconfig_on_category_and_name", unique: true
    t.index ["category"], name: "index_sysconfig_on_category"
  end

  create_table "tokens", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.string "token", limit: 100, null: false
    t.datetime "valid_to", precision: nil
    t.integer "owner_id"
    t.string "owner_type"
    t.datetime "created_at", precision: nil, null: false
    t.index ["owner_type", "owner_id"], name: "index_tokens_on_owner_type_and_owner_id"
    t.index ["token"], name: "index_tokens_on_token", unique: true
  end

  create_table "transaction_chain_concerns", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "transaction_chain_id", null: false
    t.string "class_name", null: false
    t.integer "row_id", null: false
    t.index ["class_name", "row_id"], name: "index_transaction_chain_concerns_on_class_name_and_row_id"
    t.index ["class_name"], name: "index_transaction_chain_concerns_on_class_name"
    t.index ["row_id"], name: "index_transaction_chain_concerns_on_row_id"
    t.index ["transaction_chain_id"], name: "index_transaction_chain_concerns_on_transaction_chain_id"
  end

  create_table "transaction_chains", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.string "name", limit: 30, null: false
    t.string "type", limit: 100, null: false
    t.integer "state", null: false
    t.integer "size", null: false
    t.integer "progress", default: 0, null: false
    t.integer "user_id"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.integer "urgent_rollback", default: 0, null: false
    t.integer "concern_type", default: 0, null: false
    t.integer "user_session_id"
    t.index ["created_at"], name: "index_transaction_chains_on_created_at"
    t.index ["state"], name: "index_transaction_chains_on_state"
    t.index ["type", "state"], name: "index_transaction_chains_on_type_and_state"
    t.index ["user_id"], name: "index_transaction_chains_on_user_id"
    t.index ["user_session_id"], name: "index_transaction_chains_on_user_session_id"
  end

  create_table "transaction_confirmations", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "transaction_id", null: false
    t.string "class_name", null: false
    t.string "table_name", null: false
    t.string "row_pks", null: false
    t.text "attr_changes"
    t.integer "confirm_type", null: false
    t.integer "done", default: 0, null: false
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["transaction_id"], name: "index_transaction_confirmations_on_transaction_id"
  end

  create_table "transactions", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "user_id", unsigned: true
    t.integer "node_id", unsigned: true
    t.integer "vps_id", unsigned: true
    t.integer "handle", null: false, unsigned: true
    t.integer "depends_on_id"
    t.boolean "urgent", default: false, null: false
    t.integer "priority", default: 0, null: false
    t.integer "status", null: false, unsigned: true
    t.integer "done", default: 0, null: false
    t.text "input", size: :long
    t.text "output"
    t.integer "transaction_chain_id", null: false
    t.integer "reversible", default: 1, null: false
    t.datetime "created_at", precision: nil
    t.datetime "started_at", precision: nil
    t.datetime "finished_at", precision: nil
    t.string "queue", limit: 30, default: "general", null: false
    t.text "signature"
    t.index ["depends_on_id"], name: "index_transactions_on_depends_on_id"
    t.index ["done"], name: "index_transactions_on_done"
    t.index ["node_id"], name: "index_transactions_on_node_id"
    t.index ["status"], name: "index_transactions_on_status"
    t.index ["transaction_chain_id"], name: "index_transactions_on_transaction_chain_id"
    t.index ["user_id"], name: "index_transactions_on_user_id"
  end

  create_table "user_agents", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.text "agent", null: false
    t.string "agent_hash", limit: 40, null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["agent_hash"], name: "user_session_agents_hash", unique: true
  end

  create_table "user_cluster_resource_packages", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "environment_id"
    t.integer "user_id", null: false
    t.integer "cluster_resource_package_id", null: false
    t.integer "added_by_id"
    t.string "comment", default: "", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["added_by_id"], name: "added_by_id"
    t.index ["cluster_resource_package_id"], name: "cluster_resource_package_id"
    t.index ["environment_id"], name: "environment_id"
    t.index ["user_id"], name: "user_id"
  end

  create_table "user_cluster_resources", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "user_id"
    t.integer "environment_id", null: false
    t.integer "cluster_resource_id", null: false
    t.decimal "value", precision: 40, null: false
    t.index ["cluster_resource_id"], name: "index_user_cluster_resources_on_cluster_resource_id"
    t.index ["environment_id"], name: "index_user_cluster_resources_on_environment_id"
    t.index ["user_id", "environment_id", "cluster_resource_id"], name: "user_cluster_resource_unique", unique: true
    t.index ["user_id"], name: "index_user_cluster_resources_on_user_id"
  end

  create_table "user_devices", charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "token_id"
    t.string "client_ip_addr", limit: 46, null: false
    t.string "client_ip_ptr", null: false
    t.bigint "user_agent_id", null: false
    t.boolean "known", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "last_seen_at", null: false
    t.datetime "skip_multi_factor_auth_until"
    t.string "last_next_multi_factor_auth", limit: 30, default: "", null: false
    t.index ["token_id"], name: "index_user_devices_on_token_id"
    t.index ["user_agent_id"], name: "index_user_devices_on_user_agent_id"
    t.index ["user_id"], name: "index_user_devices_on_user_id"
  end

  create_table "user_failed_logins", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "auth_type", limit: 30, null: false
    t.string "reason", null: false
    t.string "api_ip_addr", limit: 46, null: false
    t.string "api_ip_ptr"
    t.string "client_ip_addr", limit: 46
    t.string "client_ip_ptr"
    t.integer "user_agent_id"
    t.string "client_version", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "reported_at"
    t.index ["auth_type"], name: "index_user_failed_logins_on_auth_type"
    t.index ["user_agent_id"], name: "index_user_failed_logins_on_user_agent_id"
    t.index ["user_id"], name: "index_user_failed_logins_on_user_id"
  end

  create_table "user_mail_role_recipients", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "role", limit: 100, null: false
    t.string "to", limit: 500
    t.index ["user_id", "role"], name: "index_user_mail_role_recipients_on_user_id_and_role", unique: true
    t.index ["user_id"], name: "index_user_mail_role_recipients_on_user_id"
  end

  create_table "user_mail_template_recipients", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "mail_template_id", null: false
    t.string "to", limit: 500, null: false
    t.index ["user_id", "mail_template_id"], name: "user_id_mail_template_id", unique: true
    t.index ["user_id"], name: "index_user_mail_template_recipients_on_user_id"
  end

  create_table "user_namespace_blocks", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "user_namespace_id"
    t.integer "index", null: false
    t.integer "offset", null: false, unsigned: true
    t.integer "size", null: false
    t.index ["index"], name: "index_user_namespace_blocks_on_index", unique: true
    t.index ["offset"], name: "index_user_namespace_blocks_on_offset"
    t.index ["user_namespace_id"], name: "index_user_namespace_blocks_on_user_namespace_id"
  end

  create_table "user_namespace_map_entries", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "user_namespace_map_id", null: false
    t.integer "kind", null: false
    t.integer "vps_id", null: false, unsigned: true
    t.integer "ns_id", null: false, unsigned: true
    t.integer "count", null: false, unsigned: true
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["user_namespace_map_id"], name: "index_user_namespace_map_entries_on_user_namespace_map_id"
  end

  create_table "user_namespace_maps", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "user_namespace_id", null: false
    t.string "label", null: false
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["user_namespace_id"], name: "index_user_namespace_maps_on_user_namespace_id"
  end

  create_table "user_namespaces", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "block_count", null: false
    t.integer "offset", null: false, unsigned: true
    t.integer "size", null: false
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["block_count"], name: "index_user_namespaces_on_block_count"
    t.index ["offset"], name: "index_user_namespaces_on_offset"
    t.index ["size"], name: "index_user_namespaces_on_size"
    t.index ["user_id"], name: "index_user_namespaces_on_user_id"
  end

  create_table "user_public_keys", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "label", null: false
    t.text "key", null: false
    t.boolean "auto_add", default: false, null: false
    t.string "fingerprint", limit: 50, null: false
    t.string "comment", null: false
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["user_id"], name: "index_user_public_keys_on_user_id"
  end

  create_table "user_sessions", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "auth_type", limit: 30, null: false
    t.string "api_ip_addr", limit: 46, null: false
    t.integer "user_agent_id"
    t.string "client_version", null: false
    t.string "token_str", limit: 100
    t.datetime "created_at", precision: nil, null: false
    t.datetime "last_request_at", precision: nil
    t.datetime "closed_at", precision: nil
    t.integer "admin_id"
    t.string "api_ip_ptr"
    t.string "client_ip_addr", limit: 46
    t.string "client_ip_ptr"
    t.text "scope", default: "[\"all\"]", null: false
    t.string "label", default: "", null: false
    t.integer "request_count", default: 0, null: false
    t.integer "token_id"
    t.integer "token_lifetime", default: 0, null: false
    t.integer "token_interval"
    t.index ["token_id"], name: "index_user_sessions_on_token_id"
    t.index ["user_id"], name: "index_user_sessions_on_user_id"
  end

  create_table "user_totp_devices", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "label", limit: 100, null: false
    t.boolean "confirmed", default: false, null: false
    t.boolean "enabled", default: false, null: false
    t.string "secret", limit: 32
    t.string "recovery_code"
    t.integer "last_verification_at"
    t.integer "use_count", default: 0, null: false, unsigned: true
    t.datetime "last_use_at", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["enabled"], name: "index_user_totp_devices_on_enabled"
    t.index ["secret"], name: "index_user_totp_devices_on_secret", unique: true
    t.index ["user_id"], name: "index_user_totp_devices_on_user_id"
  end

  create_table "users", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.text "info"
    t.integer "level", null: false, unsigned: true
    t.string "login", limit: 63
    t.string "full_name"
    t.string "password", null: false
    t.string "email", limit: 127
    t.text "address"
    t.boolean "mailer_enabled", default: true, null: false
    t.integer "login_count", default: 0, null: false
    t.integer "failed_login_count", default: 0, null: false
    t.datetime "last_request_at", precision: nil
    t.datetime "current_login_at", precision: nil
    t.datetime "last_login_at", precision: nil
    t.string "current_login_ip"
    t.string "last_login_ip"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.integer "object_state", null: false
    t.datetime "expiration_date", precision: nil
    t.integer "password_version", default: 1, null: false
    t.datetime "last_activity_at", precision: nil
    t.integer "language_id", default: 1
    t.string "orig_login", limit: 63
    t.boolean "password_reset", default: false, null: false
    t.boolean "lockout", default: false, null: false
    t.datetime "remind_after_date", precision: nil
    t.integer "preferred_session_length", default: 1200, null: false
    t.boolean "preferred_logout_all", default: false, null: false
    t.boolean "enable_single_sign_on", default: true
    t.boolean "enable_basic_auth", default: false, null: false
    t.boolean "enable_token_auth", default: true, null: false
    t.boolean "enable_oauth2_auth", default: true, null: false
    t.boolean "enable_new_login_notification", default: true, null: false
    t.string "webauthn_id"
    t.boolean "enable_multi_factor_auth", default: false, null: false
    t.index ["login"], name: "index_users_on_login", unique: true
    t.index ["object_state"], name: "index_users_on_object_state"
  end

  create_table "uuids", charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.string "uuid", limit: 36, null: false
    t.string "owner_type"
    t.bigint "owner_id"
    t.datetime "created_at", null: false
    t.index ["owner_type", "owner_id"], name: "index_uuids_on_owner"
    t.index ["uuid"], name: "index_uuids_on_uuid", unique: true
  end

  create_table "versions", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.string "item_type", null: false
    t.integer "item_id", null: false
    t.string "event", null: false
    t.string "whodunnit"
    t.text "object"
    t.datetime "created_at", precision: nil
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  create_table "vps_consoles", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "vps_id", null: false
    t.string "token", limit: 100
    t.datetime "expiration", precision: nil, null: false
    t.integer "user_id"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["token"], name: "index_vps_consoles_on_token", unique: true
  end

  create_table "vps_current_statuses", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "vps_id", null: false
    t.boolean "status", null: false
    t.boolean "is_running", null: false
    t.integer "uptime"
    t.integer "cpus"
    t.integer "total_memory"
    t.integer "total_swap"
    t.integer "update_count", null: false
    t.integer "process_count"
    t.float "cpu_user"
    t.float "cpu_nice"
    t.float "cpu_system"
    t.float "cpu_idle"
    t.float "cpu_iowait"
    t.float "cpu_irq"
    t.float "cpu_softirq"
    t.float "loadavg5"
    t.integer "used_memory"
    t.integer "used_swap"
    t.integer "sum_process_count"
    t.float "sum_cpu_user"
    t.float "sum_cpu_nice"
    t.float "sum_cpu_system"
    t.float "sum_cpu_idle"
    t.float "sum_cpu_iowait"
    t.float "sum_cpu_irq"
    t.float "sum_cpu_softirq"
    t.float "sum_loadavg5"
    t.integer "sum_used_memory"
    t.integer "sum_used_swap"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.boolean "in_rescue_mode", default: false
    t.datetime "last_log_at"
    t.float "loadavg1"
    t.float "loadavg15"
    t.float "sum_loadavg1"
    t.float "sum_loadavg15"
    t.integer "total_diskspace"
    t.integer "used_diskspace"
    t.integer "sum_used_diskspace"
    t.boolean "halted", default: false, null: false
    t.index ["vps_id"], name: "index_vps_current_statuses_on_vps_id", unique: true
  end

  create_table "vps_features", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "vps_id", null: false
    t.string "name", null: false
    t.boolean "enabled", null: false
    t.datetime "updated_at", precision: nil
    t.index ["vps_id", "name"], name: "index_vps_features_on_vps_id_and_name", unique: true
    t.index ["vps_id"], name: "index_vps_features_on_vps_id"
  end

  create_table "vps_maintenance_windows", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "vps_id", null: false
    t.integer "weekday", null: false
    t.boolean "is_open", null: false
    t.integer "opens_at"
    t.integer "closes_at"
    t.index ["vps_id", "weekday"], name: "index_vps_maintenance_windows_on_vps_id_and_weekday", unique: true
  end

  create_table "vps_migrations", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "vps_id", null: false
    t.integer "migration_plan_id", null: false
    t.integer "state", default: 0, null: false
    t.boolean "outage_window", default: true, null: false
    t.integer "transaction_chain_id"
    t.integer "src_node_id", null: false
    t.integer "dst_node_id", null: false
    t.datetime "created_at", precision: nil
    t.datetime "started_at", precision: nil
    t.datetime "finished_at", precision: nil
    t.boolean "cleanup_data", default: true
    t.index ["migration_plan_id", "vps_id"], name: "vps_migrations_unique", unique: true
  end

  create_table "vps_os_processes", primary_key: ["vps_id", "state"], charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.bigint "vps_id", null: false
    t.string "state", limit: 5, null: false
    t.integer "count", null: false, unsigned: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["state"], name: "index_vps_os_processes_on_state"
    t.index ["vps_id"], name: "index_vps_os_processes_on_vps_id"
  end

  create_table "vps_ssh_host_keys", charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.bigint "vps_id", null: false
    t.integer "bits", null: false, unsigned: true
    t.string "algorithm", limit: 30, null: false
    t.string "fingerprint", limit: 100, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["vps_id", "algorithm"], name: "index_vps_ssh_host_keys_on_vps_id_and_algorithm", unique: true
    t.index ["vps_id"], name: "index_vps_ssh_host_keys_on_vps_id"
  end

  create_table "vps_statuses", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "vps_id", null: false
    t.boolean "status", null: false
    t.boolean "is_running", null: false
    t.integer "uptime"
    t.integer "process_count"
    t.integer "cpus"
    t.float "cpu_user"
    t.float "cpu_nice"
    t.float "cpu_system"
    t.float "cpu_idle"
    t.float "cpu_iowait"
    t.float "cpu_irq"
    t.float "cpu_softirq"
    t.float "loadavg5"
    t.integer "total_memory"
    t.integer "used_memory"
    t.integer "total_swap"
    t.integer "used_swap"
    t.datetime "created_at", precision: nil
    t.boolean "in_rescue_mode", default: false
    t.float "loadavg1"
    t.float "loadavg15"
    t.integer "total_diskspace"
    t.integer "used_diskspace"
    t.index ["vps_id"], name: "index_vps_statuses_on_vps_id"
  end

  create_table "vps_user_data", charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "label", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "format", limit: 30, default: "script", null: false
    t.index ["format"], name: "index_vps_user_data_on_format"
    t.index ["user_id"], name: "index_vps_user_data_on_user_id"
  end

  create_table "vpses", id: { type: :integer, unsigned: true }, charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.integer "user_id", null: false, unsigned: true
    t.string "hostname", default: "vps"
    t.integer "os_template_id", default: 1, null: false, unsigned: true
    t.text "info", size: :medium
    t.integer "dns_resolver_id"
    t.integer "node_id", null: false, unsigned: true
    t.boolean "onstartall", default: true, null: false
    t.integer "confirmed", default: 0, null: false
    t.integer "dataset_in_pool_id"
    t.integer "maintenance_lock", default: 0, null: false
    t.string "maintenance_lock_reason"
    t.integer "object_state", null: false
    t.datetime "expiration_date", precision: nil
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.boolean "manage_hostname", default: true, null: false
    t.integer "cpu_limit"
    t.integer "start_menu_timeout", default: 5
    t.datetime "remind_after_date", precision: nil
    t.boolean "autostart_enable", default: false, null: false
    t.integer "autostart_priority", default: 1000, null: false
    t.integer "cgroup_version", default: 0, null: false
    t.boolean "allow_admin_modifications", default: true, null: false
    t.integer "user_namespace_map_id"
    t.boolean "enable_os_template_auto_update", default: true, null: false
    t.bigint "implicit_oom_report_rule_hit_count", default: 0, null: false
    t.boolean "enable_network", default: true, null: false
    t.integer "map_mode", default: 0, null: false
    t.index ["allow_admin_modifications"], name: "index_vpses_on_allow_admin_modifications"
    t.index ["cgroup_version"], name: "index_vpses_on_cgroup_version"
    t.index ["dataset_in_pool_id"], name: "index_vpses_on_dataset_in_pool_id"
    t.index ["dns_resolver_id"], name: "index_vpses_on_dns_resolver_id"
    t.index ["map_mode"], name: "index_vpses_on_map_mode"
    t.index ["node_id"], name: "index_vpses_on_node_id"
    t.index ["object_state"], name: "index_vpses_on_object_state"
    t.index ["os_template_id"], name: "index_vpses_on_os_template_id"
    t.index ["user_id"], name: "index_vpses_on_user_id"
    t.index ["user_namespace_map_id"], name: "index_vpses_on_user_namespace_map_id"
  end

  create_table "webauthn_challenges", charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "token_id", null: false
    t.integer "challenge_type", null: false
    t.string "challenge", null: false
    t.string "api_ip_addr", limit: 46, null: false
    t.string "api_ip_ptr", null: false
    t.string "client_ip_addr", limit: 46, null: false
    t.string "client_ip_ptr", null: false
    t.integer "user_agent_id", null: false
    t.string "client_version", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token_id"], name: "index_webauthn_challenges_on_token_id"
    t.index ["user_id"], name: "index_webauthn_challenges_on_user_id"
  end

  create_table "webauthn_credentials", charset: "utf8mb3", collation: "utf8mb3_czech_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "label", null: false
    t.string "external_id", null: false
    t.string "public_key", null: false
    t.bigint "sign_count", default: 0, null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "last_use_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "use_count", default: 0, null: false
    t.index ["external_id"], name: "index_webauthn_credentials_on_external_id", unique: true
    t.index ["user_id"], name: "index_webauthn_credentials_on_user_id"
  end
end
