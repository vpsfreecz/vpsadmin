# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20170325151018) do

  create_table "api_tokens", force: :cascade do |t|
    t.integer  "user_id",    limit: 4,               null: false
    t.string   "token",      limit: 100,             null: false
    t.datetime "valid_to"
    t.string   "label",      limit: 255
    t.integer  "use_count",  limit: 4,   default: 0, null: false
    t.integer  "lifetime",   limit: 4,               null: false
    t.integer  "interval",   limit: 4
    t.datetime "created_at"
  end

  create_table "branches", force: :cascade do |t|
    t.integer  "dataset_tree_id", limit: 4,                   null: false
    t.string   "name",            limit: 255,                 null: false
    t.integer  "index",           limit: 4,   default: 0,     null: false
    t.boolean  "head",            limit: 1,   default: false, null: false
    t.integer  "confirmed",       limit: 4,   default: 0,     null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "branches", ["dataset_tree_id"], name: "index_branches_on_dataset_tree_id", using: :btree

  create_table "cluster_resource_uses", force: :cascade do |t|
    t.integer "user_cluster_resource_id", limit: 4,                  null: false
    t.string  "class_name",               limit: 255,                null: false
    t.string  "table_name",               limit: 255,                null: false
    t.integer "row_id",                   limit: 4,                  null: false
    t.integer "value",                    limit: 4,                  null: false
    t.integer "confirmed",                limit: 4,   default: 0,    null: false
    t.integer "admin_lock_type",          limit: 4,   default: 0,    null: false
    t.integer "admin_limit",              limit: 4
    t.boolean "enabled",                  limit: 1,   default: true, null: false
  end

  add_index "cluster_resource_uses", ["class_name", "table_name", "row_id"], name: "cluster_resouce_use_name_search", using: :btree
  add_index "cluster_resource_uses", ["user_cluster_resource_id"], name: "index_cluster_resource_uses_on_user_cluster_resource_id", using: :btree

  create_table "cluster_resources", force: :cascade do |t|
    t.string  "name",           limit: 100, null: false
    t.string  "label",          limit: 100, null: false
    t.integer "min",            limit: 4,   null: false
    t.integer "max",            limit: 4,   null: false
    t.integer "stepsize",       limit: 4,   null: false
    t.integer "resource_type",  limit: 4,   null: false
    t.string  "allocate_chain", limit: 255
    t.string  "free_chain",     limit: 255
  end

  add_index "cluster_resources", ["name"], name: "index_cluster_resources_on_name", unique: true, using: :btree

  create_table "dataset_actions", force: :cascade do |t|
    t.integer "pool_id",                 limit: 4
    t.integer "src_dataset_in_pool_id",  limit: 4
    t.integer "dst_dataset_in_pool_id",  limit: 4
    t.integer "snapshot_id",             limit: 4
    t.boolean "recursive",               limit: 1, default: false, null: false
    t.integer "dataset_plan_id",         limit: 4
    t.integer "dataset_in_pool_plan_id", limit: 4
    t.integer "action",                  limit: 4,                 null: false
  end

  create_table "dataset_in_pool_plans", force: :cascade do |t|
    t.integer "environment_dataset_plan_id", limit: 4, null: false
    t.integer "dataset_in_pool_id",          limit: 4, null: false
  end

  add_index "dataset_in_pool_plans", ["environment_dataset_plan_id", "dataset_in_pool_id"], name: "dataset_in_pool_plans_unique", unique: true, using: :btree

  create_table "dataset_in_pools", force: :cascade do |t|
    t.integer "dataset_id",       limit: 4,                     null: false
    t.integer "pool_id",          limit: 4,                     null: false
    t.string  "label",            limit: 100
    t.integer "used",             limit: 4,   default: 0,       null: false
    t.integer "avail",            limit: 4,   default: 0,       null: false
    t.integer "min_snapshots",    limit: 4,   default: 14,      null: false
    t.integer "max_snapshots",    limit: 4,   default: 20,      null: false
    t.integer "snapshot_max_age", limit: 4,   default: 1209600, null: false
    t.string  "mountpoint",       limit: 500
    t.integer "confirmed",        limit: 4,   default: 0,       null: false
  end

  add_index "dataset_in_pools", ["dataset_id", "pool_id"], name: "index_dataset_in_pools_on_dataset_id_and_pool_id", unique: true, using: :btree
  add_index "dataset_in_pools", ["dataset_id"], name: "index_dataset_in_pools_on_dataset_id", using: :btree

  create_table "dataset_plans", force: :cascade do |t|
    t.string "name", limit: 255, null: false
  end

  create_table "dataset_properties", force: :cascade do |t|
    t.integer  "pool_id",            limit: 4
    t.integer  "dataset_id",         limit: 4
    t.integer  "dataset_in_pool_id", limit: 4
    t.string   "ancestry",           limit: 255
    t.integer  "ancestry_depth",     limit: 4,   default: 0,    null: false
    t.string   "name",               limit: 30,                 null: false
    t.string   "value",              limit: 255
    t.boolean  "inherited",          limit: 1,   default: true, null: false
    t.integer  "confirmed",          limit: 4,   default: 0,    null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "dataset_properties", ["dataset_id"], name: "index_dataset_properties_on_dataset_id", using: :btree
  add_index "dataset_properties", ["dataset_in_pool_id", "name"], name: "index_dataset_properties_on_dataset_in_pool_id_and_name", using: :btree
  add_index "dataset_properties", ["dataset_in_pool_id"], name: "index_dataset_properties_on_dataset_in_pool_id", using: :btree
  add_index "dataset_properties", ["pool_id"], name: "index_dataset_properties_on_pool_id", using: :btree

  create_table "dataset_property_histories", force: :cascade do |t|
    t.integer  "dataset_property_id", limit: 4, null: false
    t.integer  "value",               limit: 4, null: false
    t.datetime "created_at",                    null: false
  end

  add_index "dataset_property_histories", ["dataset_property_id"], name: "index_dataset_property_histories_on_dataset_property_id", using: :btree

  create_table "dataset_trees", force: :cascade do |t|
    t.integer  "dataset_in_pool_id", limit: 4,                 null: false
    t.integer  "index",              limit: 4, default: 0,     null: false
    t.boolean  "head",               limit: 1, default: false, null: false
    t.integer  "confirmed",          limit: 4, default: 0,     null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "dataset_trees", ["dataset_in_pool_id"], name: "index_dataset_trees_on_dataset_in_pool_id", using: :btree

  create_table "datasets", force: :cascade do |t|
    t.string   "name",               limit: 255,              null: false
    t.string   "full_name",          limit: 1000,             null: false
    t.integer  "user_id",            limit: 4
    t.boolean  "user_editable",      limit: 1,                null: false
    t.boolean  "user_create",        limit: 1,                null: false
    t.boolean  "user_destroy",       limit: 1,                null: false
    t.string   "ancestry",           limit: 255
    t.integer  "ancestry_depth",     limit: 4,    default: 0, null: false
    t.datetime "expiration"
    t.integer  "confirmed",          limit: 4,    default: 0, null: false
    t.integer  "object_state",       limit: 4,                null: false
    t.datetime "expiration_date"
    t.integer  "current_history_id", limit: 4,    default: 0, null: false
  end

  add_index "datasets", ["ancestry"], name: "index_datasets_on_ancestry", using: :btree
  add_index "datasets", ["user_id"], name: "index_datasets_on_user_id", using: :btree

  create_table "default_lifetime_values", force: :cascade do |t|
    t.integer "environment_id", limit: 4
    t.string  "class_name",     limit: 50,  null: false
    t.integer "direction",      limit: 4,   null: false
    t.integer "state",          limit: 4,   null: false
    t.integer "add_expiration", limit: 4
    t.string  "reason",         limit: 255, null: false
  end

  create_table "default_object_cluster_resources", force: :cascade do |t|
    t.integer "environment_id",      limit: 4,   null: false
    t.integer "cluster_resource_id", limit: 4,   null: false
    t.string  "class_name",          limit: 255, null: false
    t.integer "value",               limit: 4,   null: false
  end

  create_table "dns_resolvers", force: :cascade do |t|
    t.string  "addrs",        limit: 63,                 null: false
    t.string  "label",        limit: 63,                 null: false
    t.boolean "is_universal", limit: 1,  default: false
    t.integer "location_id",  limit: 4,                               unsigned: true
    t.integer "ip_version",   limit: 4,  default: 4
  end

  create_table "environment_config_chains", force: :cascade do |t|
    t.integer "environment_id", limit: 4, null: false
    t.integer "vps_config_id",  limit: 4, null: false
    t.integer "cfg_order",      limit: 4, null: false
  end

  add_index "environment_config_chains", ["environment_id", "vps_config_id"], name: "environment_config_chains_unique", unique: true, using: :btree

  create_table "environment_dataset_plans", force: :cascade do |t|
    t.integer "environment_id",  limit: 4, null: false
    t.integer "dataset_plan_id", limit: 4, null: false
    t.boolean "user_add",        limit: 1, null: false
    t.boolean "user_remove",     limit: 1, null: false
  end

  create_table "environment_user_configs", force: :cascade do |t|
    t.integer "environment_id",  limit: 4,                 null: false
    t.integer "user_id",         limit: 4,                 null: false
    t.boolean "can_create_vps",  limit: 1, default: false, null: false
    t.boolean "can_destroy_vps", limit: 1, default: false, null: false
    t.integer "vps_lifetime",    limit: 4, default: 0,     null: false
    t.integer "max_vps_count",   limit: 4, default: 1,     null: false
    t.boolean "default",         limit: 1, default: true,  null: false
  end

  add_index "environment_user_configs", ["environment_id", "user_id"], name: "environment_user_configs_unique", unique: true, using: :btree

  create_table "environments", force: :cascade do |t|
    t.string   "label",                   limit: 100,                 null: false
    t.string   "domain",                  limit: 100,                 null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "maintenance_lock",        limit: 4,   default: 0,     null: false
    t.string   "maintenance_lock_reason", limit: 255
    t.boolean  "can_create_vps",          limit: 1,   default: false, null: false
    t.boolean  "can_destroy_vps",         limit: 1,   default: false, null: false
    t.integer  "vps_lifetime",            limit: 4,   default: 0,     null: false
    t.integer  "max_vps_count",           limit: 4,   default: 1,     null: false
    t.boolean  "user_ip_ownership",       limit: 1,                   null: false
  end

  create_table "group_snapshots", force: :cascade do |t|
    t.integer "dataset_action_id",  limit: 4
    t.integer "dataset_in_pool_id", limit: 4
  end

  add_index "group_snapshots", ["dataset_action_id", "dataset_in_pool_id"], name: "group_snapshots_unique", unique: true, using: :btree

  create_table "integrity_checks", force: :cascade do |t|
    t.integer  "user_id",          limit: 4
    t.integer  "status",           limit: 4, default: 0, null: false
    t.integer  "checked_objects",  limit: 4, default: 0, null: false
    t.integer  "integral_objects", limit: 4, default: 0, null: false
    t.integer  "broken_objects",   limit: 4, default: 0, null: false
    t.integer  "checked_facts",    limit: 4, default: 0, null: false
    t.integer  "true_facts",       limit: 4, default: 0, null: false
    t.integer  "false_facts",      limit: 4, default: 0, null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.datetime "finished_at"
  end

  create_table "integrity_facts", force: :cascade do |t|
    t.integer  "integrity_object_id", limit: 4,                null: false
    t.string   "name",                limit: 30,               null: false
    t.string   "expected_value",      limit: 255,              null: false
    t.string   "actual_value",        limit: 255,              null: false
    t.integer  "status",              limit: 4,    default: 0, null: false
    t.integer  "severity",            limit: 4,    default: 1, null: false
    t.string   "message",             limit: 1000
    t.datetime "created_at"
  end

  create_table "integrity_objects", force: :cascade do |t|
    t.integer  "integrity_check_id", limit: 4,               null: false
    t.integer  "node_id",            limit: 4,               null: false
    t.string   "class_name",         limit: 100,             null: false
    t.integer  "row_id",             limit: 4
    t.string   "ancestry",           limit: 255
    t.integer  "ancestry_depth",     limit: 4,   default: 0, null: false
    t.integer  "status",             limit: 4,   default: 0, null: false
    t.integer  "checked_facts",      limit: 4,   default: 0, null: false
    t.integer  "true_facts",         limit: 4,   default: 0, null: false
    t.integer  "false_facts",        limit: 4,   default: 0, null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "ip_addresses", force: :cascade do |t|
    t.integer "vps_id",     limit: 4,                                  unsigned: true
    t.string  "ip_addr",    limit: 40,                    null: false
    t.integer "max_tx",     limit: 8,  default: 39321600, null: false, unsigned: true
    t.integer "max_rx",     limit: 8,  default: 39321600, null: false, unsigned: true
    t.integer "class_id",   limit: 4,                     null: false
    t.integer "user_id",    limit: 4
    t.integer "network_id", limit: 4,                     null: false
    t.integer "order",      limit: 4
  end

  add_index "ip_addresses", ["class_id"], name: "index_ip_addresses_on_class_id", unique: true, using: :btree
  add_index "ip_addresses", ["network_id"], name: "index_ip_addresses_on_network_id", using: :btree
  add_index "ip_addresses", ["user_id"], name: "index_ip_addresses_on_user_id", using: :btree
  add_index "ip_addresses", ["vps_id"], name: "index_ip_addresses_on_vps_id", using: :btree
  add_index "ip_addresses", ["vps_id"], name: "vps_id", using: :btree

  create_table "ip_recent_traffics", force: :cascade do |t|
    t.integer  "ip_address_id", limit: 4,             null: false
    t.integer  "user_id",       limit: 4
    t.integer  "protocol",      limit: 4,             null: false
    t.integer  "packets_in",    limit: 8, default: 0, null: false, unsigned: true
    t.integer  "packets_out",   limit: 8, default: 0, null: false, unsigned: true
    t.integer  "bytes_in",      limit: 8, default: 0, null: false, unsigned: true
    t.integer  "bytes_out",     limit: 8, default: 0, null: false, unsigned: true
    t.datetime "created_at",                          null: false
    t.integer  "role",          limit: 4, default: 0, null: false
  end

  add_index "ip_recent_traffics", ["ip_address_id", "user_id", "protocol", "role", "created_at"], name: "transfers_unique", unique: true, using: :btree
  add_index "ip_recent_traffics", ["ip_address_id"], name: "index_ip_recent_traffics_on_ip_address_id", using: :btree
  add_index "ip_recent_traffics", ["user_id"], name: "index_ip_recent_traffics_on_user_id", using: :btree

  create_table "ip_traffic_live_monitors", force: :cascade do |t|
    t.integer  "ip_address_id",             limit: 4,             null: false
    t.integer  "packets",                   limit: 8, default: 0, null: false, unsigned: true
    t.integer  "packets_in",                limit: 8, default: 0, null: false, unsigned: true
    t.integer  "packets_out",               limit: 8, default: 0, null: false, unsigned: true
    t.integer  "bytes",                     limit: 8, default: 0, null: false, unsigned: true
    t.integer  "bytes_in",                  limit: 8, default: 0, null: false, unsigned: true
    t.integer  "bytes_out",                 limit: 8, default: 0, null: false, unsigned: true
    t.integer  "public_packets",            limit: 8, default: 0, null: false, unsigned: true
    t.integer  "public_packets_in",         limit: 8, default: 0, null: false, unsigned: true
    t.integer  "public_packets_out",        limit: 8, default: 0, null: false, unsigned: true
    t.integer  "public_bytes",              limit: 8, default: 0, null: false, unsigned: true
    t.integer  "public_bytes_in",           limit: 8, default: 0, null: false, unsigned: true
    t.integer  "public_bytes_out",          limit: 8, default: 0, null: false, unsigned: true
    t.integer  "public_tcp_packets",        limit: 8, default: 0, null: false, unsigned: true
    t.integer  "public_tcp_packets_in",     limit: 8, default: 0, null: false, unsigned: true
    t.integer  "public_tcp_packets_out",    limit: 8, default: 0, null: false, unsigned: true
    t.integer  "public_tcp_bytes",          limit: 8, default: 0, null: false, unsigned: true
    t.integer  "public_tcp_bytes_in",       limit: 8, default: 0, null: false, unsigned: true
    t.integer  "public_tcp_bytes_out",      limit: 8, default: 0, null: false, unsigned: true
    t.integer  "public_udp_packets",        limit: 8, default: 0, null: false, unsigned: true
    t.integer  "public_udp_packets_in",     limit: 8, default: 0, null: false, unsigned: true
    t.integer  "public_udp_packets_out",    limit: 8, default: 0, null: false, unsigned: true
    t.integer  "public_udp_bytes",          limit: 8, default: 0, null: false, unsigned: true
    t.integer  "public_udp_bytes_in",       limit: 8, default: 0, null: false, unsigned: true
    t.integer  "public_udp_bytes_out",      limit: 8, default: 0, null: false, unsigned: true
    t.integer  "public_other_packets",      limit: 8, default: 0, null: false, unsigned: true
    t.integer  "public_other_packets_in",   limit: 8, default: 0, null: false, unsigned: true
    t.integer  "public_other_packets_out",  limit: 8, default: 0, null: false, unsigned: true
    t.integer  "public_other_bytes",        limit: 8, default: 0, null: false, unsigned: true
    t.integer  "public_other_bytes_in",     limit: 8, default: 0, null: false, unsigned: true
    t.integer  "public_other_bytes_out",    limit: 8, default: 0, null: false, unsigned: true
    t.integer  "private_packets",           limit: 8, default: 0, null: false, unsigned: true
    t.integer  "private_packets_in",        limit: 8, default: 0, null: false, unsigned: true
    t.integer  "private_packets_out",       limit: 8, default: 0, null: false, unsigned: true
    t.integer  "private_bytes",             limit: 8, default: 0, null: false, unsigned: true
    t.integer  "private_bytes_in",          limit: 8, default: 0, null: false, unsigned: true
    t.integer  "private_bytes_out",         limit: 8, default: 0, null: false, unsigned: true
    t.integer  "private_tcp_packets",       limit: 8, default: 0, null: false, unsigned: true
    t.integer  "private_tcp_packets_in",    limit: 8, default: 0, null: false, unsigned: true
    t.integer  "private_tcp_packets_out",   limit: 8, default: 0, null: false, unsigned: true
    t.integer  "private_tcp_bytes",         limit: 8, default: 0, null: false, unsigned: true
    t.integer  "private_tcp_bytes_in",      limit: 8, default: 0, null: false, unsigned: true
    t.integer  "private_tcp_bytes_out",     limit: 8, default: 0, null: false, unsigned: true
    t.integer  "private_udp_packets",       limit: 8, default: 0, null: false, unsigned: true
    t.integer  "private_udp_packets_in",    limit: 8, default: 0, null: false, unsigned: true
    t.integer  "private_udp_packets_out",   limit: 8, default: 0, null: false, unsigned: true
    t.integer  "private_udp_bytes",         limit: 8, default: 0, null: false, unsigned: true
    t.integer  "private_udp_bytes_in",      limit: 8, default: 0, null: false, unsigned: true
    t.integer  "private_udp_bytes_out",     limit: 8, default: 0, null: false, unsigned: true
    t.integer  "private_other_packets",     limit: 8, default: 0, null: false, unsigned: true
    t.integer  "private_other_packets_in",  limit: 8, default: 0, null: false, unsigned: true
    t.integer  "private_other_packets_out", limit: 8, default: 0, null: false, unsigned: true
    t.integer  "private_other_bytes",       limit: 8, default: 0, null: false, unsigned: true
    t.integer  "private_other_bytes_in",    limit: 8, default: 0, null: false, unsigned: true
    t.integer  "private_other_bytes_out",   limit: 8, default: 0, null: false, unsigned: true
    t.datetime "updated_at",                                      null: false
    t.integer  "delta",                     limit: 4
  end

  add_index "ip_traffic_live_monitors", ["ip_address_id"], name: "index_ip_traffic_live_monitors_on_ip_address_id", unique: true, using: :btree

  create_table "ip_traffic_monthly_summaries", force: :cascade do |t|
    t.integer  "ip_address_id", limit: 4,             null: false
    t.integer  "user_id",       limit: 4
    t.integer  "protocol",      limit: 4,             null: false
    t.integer  "role",          limit: 4,             null: false
    t.integer  "packets_in",    limit: 8, default: 0, null: false, unsigned: true
    t.integer  "packets_out",   limit: 8, default: 0, null: false, unsigned: true
    t.integer  "bytes_in",      limit: 8, default: 0, null: false, unsigned: true
    t.integer  "bytes_out",     limit: 8, default: 0, null: false, unsigned: true
    t.datetime "created_at",                          null: false
    t.integer  "year",          limit: 4,             null: false
    t.integer  "month",         limit: 4,             null: false
  end

  add_index "ip_traffic_monthly_summaries", ["ip_address_id", "user_id", "protocol", "role", "created_at"], name: "ip_traffic_monthly_summaries_unique", unique: true, using: :btree
  add_index "ip_traffic_monthly_summaries", ["ip_address_id", "year", "month"], name: "ip_traffic_monthly_summaries_ip_year_month", using: :btree
  add_index "ip_traffic_monthly_summaries", ["ip_address_id"], name: "index_ip_traffic_monthly_summaries_on_ip_address_id", using: :btree
  add_index "ip_traffic_monthly_summaries", ["month"], name: "index_ip_traffic_monthly_summaries_on_month", using: :btree
  add_index "ip_traffic_monthly_summaries", ["protocol"], name: "index_ip_traffic_monthly_summaries_on_protocol", using: :btree
  add_index "ip_traffic_monthly_summaries", ["user_id"], name: "index_ip_traffic_monthly_summaries_on_user_id", using: :btree
  add_index "ip_traffic_monthly_summaries", ["year", "month"], name: "index_ip_traffic_monthly_summaries_on_year_and_month", using: :btree
  add_index "ip_traffic_monthly_summaries", ["year"], name: "index_ip_traffic_monthly_summaries_on_year", using: :btree

  create_table "ip_traffics", force: :cascade do |t|
    t.integer  "ip_address_id", limit: 4,             null: false
    t.integer  "user_id",       limit: 4
    t.integer  "protocol",      limit: 4,             null: false
    t.integer  "packets_in",    limit: 8, default: 0, null: false, unsigned: true
    t.integer  "packets_out",   limit: 8, default: 0, null: false, unsigned: true
    t.integer  "bytes_in",      limit: 8, default: 0, null: false, unsigned: true
    t.integer  "bytes_out",     limit: 8, default: 0, null: false, unsigned: true
    t.datetime "created_at",                          null: false
    t.integer  "role",          limit: 4, default: 0, null: false
  end

  add_index "ip_traffics", ["ip_address_id", "user_id", "protocol", "role", "created_at"], name: "transfers_unique", unique: true, using: :btree
  add_index "ip_traffics", ["ip_address_id"], name: "index_ip_traffics_on_ip_address_id", using: :btree
  add_index "ip_traffics", ["user_id"], name: "index_ip_traffics_on_user_id", using: :btree

  create_table "languages", force: :cascade do |t|
    t.string "code",  limit: 2,   null: false
    t.string "label", limit: 100, null: false
  end

  add_index "languages", ["code"], name: "index_languages_on_code", unique: true, using: :btree

  create_table "locations", force: :cascade do |t|
    t.string   "label",                   limit: 63,                 null: false
    t.boolean  "has_ipv6",                limit: 1,                  null: false
    t.boolean  "vps_onboot",              limit: 1,   default: true, null: false
    t.string   "remote_console_server",   limit: 255,                null: false
    t.string   "domain",                  limit: 100,                null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "maintenance_lock",        limit: 4,   default: 0,    null: false
    t.string   "maintenance_lock_reason", limit: 255
    t.integer  "environment_id",          limit: 4,                  null: false
  end

  create_table "mail_logs", force: :cascade do |t|
    t.integer  "user_id",          limit: 4
    t.string   "to",               limit: 500,        null: false
    t.string   "cc",               limit: 500,        null: false
    t.string   "bcc",              limit: 500,        null: false
    t.string   "from",             limit: 255,        null: false
    t.string   "reply_to",         limit: 255
    t.string   "return_path",      limit: 255
    t.string   "message_id",       limit: 255
    t.string   "in_reply_to",      limit: 255
    t.string   "references",       limit: 255
    t.string   "subject",          limit: 255,        null: false
    t.text     "text_plain",       limit: 4294967295
    t.text     "text_html",        limit: 4294967295
    t.integer  "mail_template_id", limit: 4
    t.integer  "transaction_id",   limit: 4
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "mail_logs", ["user_id"], name: "index_mail_logs_on_user_id", using: :btree

  create_table "mail_recipients", force: :cascade do |t|
    t.string "label", limit: 100, null: false
    t.string "to",    limit: 500
    t.string "cc",    limit: 500
    t.string "bcc",   limit: 500
  end

  create_table "mail_template_recipients", force: :cascade do |t|
    t.integer "mail_template_id",  limit: 4, null: false
    t.integer "mail_recipient_id", limit: 4, null: false
  end

  add_index "mail_template_recipients", ["mail_template_id", "mail_recipient_id"], name: "mail_template_recipients_unique", unique: true, using: :btree

  create_table "mail_template_translations", force: :cascade do |t|
    t.integer  "mail_template_id", limit: 4,     null: false
    t.integer  "language_id",      limit: 4,     null: false
    t.string   "from",             limit: 255,   null: false
    t.string   "reply_to",         limit: 255
    t.string   "return_path",      limit: 255
    t.string   "subject",          limit: 255,   null: false
    t.text     "text_plain",       limit: 65535
    t.text     "text_html",        limit: 65535
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "mail_template_translations", ["mail_template_id", "language_id"], name: "mail_template_translation_unique", unique: true, using: :btree

  create_table "mail_templates", force: :cascade do |t|
    t.string   "name",            limit: 100,             null: false
    t.string   "label",           limit: 100,             null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "template_id",     limit: 100,             null: false
    t.integer  "user_visibility", limit: 4,   default: 0, null: false
  end

  add_index "mail_templates", ["name"], name: "index_mail_templates_on_name", unique: true, using: :btree

  create_table "maintenance_locks", force: :cascade do |t|
    t.string   "class_name", limit: 100,                null: false
    t.integer  "row_id",     limit: 4
    t.integer  "user_id",    limit: 4
    t.string   "reason",     limit: 255,                null: false
    t.boolean  "active",     limit: 1,   default: true, null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "maintenance_locks", ["class_name", "row_id"], name: "index_maintenance_locks_on_class_name_and_row_id", using: :btree

  create_table "migration_plans", force: :cascade do |t|
    t.integer  "state",         limit: 4,   default: 0,    null: false
    t.boolean  "stop_on_error", limit: 1,   default: true, null: false
    t.boolean  "send_mail",     limit: 1,   default: true, null: false
    t.integer  "user_id",       limit: 4
    t.integer  "node_id",       limit: 4
    t.integer  "concurrency",   limit: 4,                  null: false
    t.string   "reason",        limit: 255
    t.datetime "created_at"
    t.datetime "finished_at"
  end

  create_table "mirrors", force: :cascade do |t|
    t.integer "src_pool_id",            limit: 4
    t.integer "dst_pool_id",            limit: 4
    t.integer "src_dataset_in_pool_id", limit: 4
    t.integer "dst_dataset_in_pool_id", limit: 4
    t.boolean "recursive",              limit: 1, default: false, null: false
    t.integer "interval",               limit: 4, default: 60,    null: false
  end

  create_table "mounts", force: :cascade do |t|
    t.integer  "vps_id",              limit: 4,                  null: false
    t.string   "src",                 limit: 500
    t.string   "dst",                 limit: 500,                null: false
    t.string   "mount_opts",          limit: 255,                null: false
    t.string   "umount_opts",         limit: 255,                null: false
    t.string   "mount_type",          limit: 10,                 null: false
    t.boolean  "user_editable",       limit: 1,   default: true, null: false
    t.integer  "dataset_in_pool_id",  limit: 4
    t.integer  "snapshot_in_pool_id", limit: 4
    t.string   "mode",                limit: 2,                  null: false
    t.integer  "confirmed",           limit: 4,   default: 0,    null: false
    t.integer  "object_state",        limit: 4,                  null: false
    t.datetime "expiration_date"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "on_start_fail",       limit: 4,   default: 1,    null: false
    t.boolean  "enabled",             limit: 1,   default: true, null: false
    t.boolean  "master_enabled",      limit: 1,   default: true, null: false
    t.integer  "current_state",       limit: 4,   default: 0,    null: false
  end

  add_index "mounts", ["vps_id"], name: "index_mounts_on_vps_id", using: :btree

  create_table "networks", force: :cascade do |t|
    t.string  "label",          limit: 255
    t.integer "location_id",    limit: 4,                       null: false
    t.integer "ip_version",     limit: 4,                       null: false
    t.string  "address",        limit: 255,                     null: false
    t.integer "prefix",         limit: 4,                       null: false
    t.integer "role",           limit: 4,                       null: false
    t.boolean "managed",        limit: 1,                       null: false
    t.string  "type",           limit: 255, default: "Network", null: false
    t.string  "ancestry",       limit: 255
    t.integer "ancestry_depth", limit: 4,   default: 0,         null: false
    t.integer "split_access",   limit: 4,   default: 0,         null: false
    t.integer "split_prefix",   limit: 4
    t.integer "user_id",        limit: 4
  end

  add_index "networks", ["location_id", "address", "prefix"], name: "index_networks_on_location_id_and_address_and_prefix", unique: true, using: :btree

  create_table "node_current_statuses", force: :cascade do |t|
    t.integer  "node_id",            limit: 4,  null: false
    t.integer  "uptime",             limit: 4
    t.integer  "cpus",               limit: 4
    t.integer  "total_memory",       limit: 4
    t.integer  "total_swap",         limit: 4
    t.string   "vpsadmind_version",  limit: 25, null: false
    t.string   "kernel",             limit: 30, null: false
    t.integer  "update_count",       limit: 4,  null: false
    t.integer  "process_count",      limit: 4
    t.float    "cpu_user",           limit: 24
    t.float    "cpu_nice",           limit: 24
    t.float    "cpu_system",         limit: 24
    t.float    "cpu_idle",           limit: 24
    t.float    "cpu_iowait",         limit: 24
    t.float    "cpu_irq",            limit: 24
    t.float    "cpu_softirq",        limit: 24
    t.float    "cpu_guest",          limit: 24
    t.float    "loadavg",            limit: 24
    t.integer  "used_memory",        limit: 4
    t.integer  "used_swap",          limit: 4
    t.integer  "arc_c_max",          limit: 4
    t.integer  "arc_c",              limit: 4
    t.integer  "arc_size",           limit: 4
    t.float    "arc_hitpercent",     limit: 24
    t.integer  "sum_process_count",  limit: 4
    t.float    "sum_cpu_user",       limit: 24
    t.float    "sum_cpu_nice",       limit: 24
    t.float    "sum_cpu_system",     limit: 24
    t.float    "sum_cpu_idle",       limit: 24
    t.float    "sum_cpu_iowait",     limit: 24
    t.float    "sum_cpu_irq",        limit: 24
    t.float    "sum_cpu_softirq",    limit: 24
    t.float    "sum_cpu_guest",      limit: 24
    t.float    "sum_loadavg",        limit: 24
    t.integer  "sum_used_memory",    limit: 4
    t.integer  "sum_used_swap",      limit: 4
    t.integer  "sum_arc_c_max",      limit: 4
    t.integer  "sum_arc_c",          limit: 4
    t.integer  "sum_arc_size",       limit: 4
    t.float    "sum_arc_hitpercent", limit: 24
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "node_current_statuses", ["node_id"], name: "index_node_current_statuses_on_node_id", unique: true, using: :btree

  create_table "node_pubkeys", id: false, force: :cascade do |t|
    t.integer "node_id",  limit: 4,     null: false
    t.string  "key_type", limit: 3,     null: false
    t.text    "key",      limit: 65535, null: false
  end

  add_index "node_pubkeys", ["node_id"], name: "index_node_pubkeys_on_node_id", using: :btree

  create_table "node_statuses", force: :cascade do |t|
    t.integer  "node_id",           limit: 4,  null: false
    t.integer  "uptime",            limit: 4,  null: false
    t.integer  "process_count",     limit: 4
    t.integer  "cpus",              limit: 4
    t.float    "cpu_user",          limit: 24
    t.float    "cpu_nice",          limit: 24
    t.float    "cpu_system",        limit: 24
    t.float    "cpu_idle",          limit: 24
    t.float    "cpu_iowait",        limit: 24
    t.float    "cpu_irq",           limit: 24
    t.float    "cpu_softirq",       limit: 24
    t.float    "cpu_guest",         limit: 24
    t.integer  "total_memory",      limit: 4
    t.integer  "used_memory",       limit: 4
    t.integer  "total_swap",        limit: 4
    t.integer  "used_swap",         limit: 4
    t.integer  "arc_c_max",         limit: 4
    t.integer  "arc_c",             limit: 4
    t.integer  "arc_size",          limit: 4
    t.float    "arc_hitpercent",    limit: 24
    t.float    "loadavg",           limit: 24, null: false
    t.string   "vpsadmind_version", limit: 25, null: false
    t.string   "kernel",            limit: 30, null: false
    t.datetime "created_at"
  end

  add_index "node_statuses", ["node_id"], name: "index_node_statuses_on_node_id", using: :btree

  create_table "nodes", force: :cascade do |t|
    t.string  "name",                    limit: 64,                                          null: false
    t.integer "location_id",             limit: 4,                                           null: false, unsigned: true
    t.string  "ip_addr",                 limit: 127,                                         null: false
    t.integer "max_vps",                 limit: 4
    t.string  "ve_private",              limit: 255, default: "/vz/private/%{veid}/private"
    t.string  "net_interface",           limit: 50
    t.integer "max_tx",                  limit: 8,   default: 235929600,                     null: false, unsigned: true
    t.integer "max_rx",                  limit: 8,   default: 235929600,                     null: false, unsigned: true
    t.integer "maintenance_lock",        limit: 4,   default: 0,                             null: false
    t.string  "maintenance_lock_reason", limit: 255
    t.integer "cpus",                    limit: 4,                                           null: false
    t.integer "total_memory",            limit: 4,                                           null: false
    t.integer "total_swap",              limit: 4,                                           null: false
    t.integer "role",                    limit: 4,                                           null: false
  end

  add_index "nodes", ["location_id"], name: "location_id", using: :btree

  create_table "object_histories", force: :cascade do |t|
    t.integer  "user_id",             limit: 4
    t.integer  "user_session_id",     limit: 4
    t.integer  "tracked_object_id",   limit: 4,     null: false
    t.string   "tracked_object_type", limit: 255,   null: false
    t.string   "event_type",          limit: 255,   null: false
    t.text     "event_data",          limit: 65535
    t.datetime "created_at",                        null: false
  end

  add_index "object_histories", ["tracked_object_id", "tracked_object_type"], name: "object_histories_tracked_object", using: :btree
  add_index "object_histories", ["user_id"], name: "index_object_histories_on_user_id", using: :btree
  add_index "object_histories", ["user_session_id"], name: "index_object_histories_on_user_session_id", using: :btree

  create_table "object_states", force: :cascade do |t|
    t.string   "class_name",      limit: 255, null: false
    t.integer  "row_id",          limit: 4,   null: false
    t.integer  "state",           limit: 4,   null: false
    t.integer  "user_id",         limit: 4
    t.string   "reason",          limit: 255
    t.datetime "expiration_date"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "object_states", ["class_name", "row_id"], name: "index_object_states_on_class_name_and_row_id", using: :btree

  create_table "os_templates", force: :cascade do |t|
    t.string  "name",      limit: 64,                null: false
    t.string  "label",     limit: 64,                null: false
    t.text    "info",      limit: 65535
    t.integer "enabled",   limit: 1,     default: 1, null: false
    t.integer "supported", limit: 1,     default: 1, null: false
    t.integer "order",     limit: 1,     default: 1, null: false
  end

  create_table "pools", force: :cascade do |t|
    t.integer "node_id",                 limit: 4,                   null: false
    t.string  "label",                   limit: 500,                 null: false
    t.string  "filesystem",              limit: 500,                 null: false
    t.integer "role",                    limit: 4,                   null: false
    t.boolean "refquota_check",          limit: 1,   default: false, null: false
    t.integer "maintenance_lock",        limit: 4,   default: 0,     null: false
    t.string  "maintenance_lock_reason", limit: 255
  end

  create_table "port_reservations", force: :cascade do |t|
    t.integer "node_id",              limit: 4,   null: false
    t.string  "addr",                 limit: 100
    t.integer "port",                 limit: 4,   null: false
    t.integer "transaction_chain_id", limit: 4
  end

  add_index "port_reservations", ["node_id", "port"], name: "port_reservation_uniqueness", unique: true, using: :btree
  add_index "port_reservations", ["node_id"], name: "index_port_reservations_on_node_id", using: :btree
  add_index "port_reservations", ["transaction_chain_id"], name: "index_port_reservations_on_transaction_chain_id", using: :btree

  create_table "repeatable_tasks", force: :cascade do |t|
    t.string  "label",        limit: 100
    t.string  "class_name",   limit: 255, null: false
    t.string  "table_name",   limit: 255, null: false
    t.integer "row_id",       limit: 4,   null: false
    t.string  "minute",       limit: 255, null: false
    t.string  "hour",         limit: 255, null: false
    t.string  "day_of_month", limit: 255, null: false
    t.string  "month",        limit: 255, null: false
    t.string  "day_of_week",  limit: 255, null: false
  end

  create_table "resource_locks", force: :cascade do |t|
    t.string   "resource",       limit: 100, null: false
    t.integer  "row_id",         limit: 4,   null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "locked_by_id",   limit: 4
    t.string   "locked_by_type", limit: 255
  end

  add_index "resource_locks", ["locked_by_id", "locked_by_type"], name: "index_resource_locks_on_locked_by_id_and_locked_by_type", using: :btree
  add_index "resource_locks", ["resource", "row_id"], name: "index_resource_locks_on_resource_and_row_id", unique: true, using: :btree

  create_table "snapshot_downloads", force: :cascade do |t|
    t.integer  "user_id",          limit: 4,               null: false
    t.integer  "snapshot_id",      limit: 4
    t.integer  "pool_id",          limit: 4,               null: false
    t.string   "secret_key",       limit: 100,             null: false
    t.string   "file_name",        limit: 255,             null: false
    t.integer  "confirmed",        limit: 4,   default: 0, null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "object_state",     limit: 4,               null: false
    t.datetime "expiration_date"
    t.integer  "size",             limit: 4
    t.integer  "format",           limit: 4,   default: 0, null: false
    t.integer  "from_snapshot_id", limit: 4
    t.string   "sha256sum",        limit: 64
  end

  add_index "snapshot_downloads", ["secret_key"], name: "index_snapshot_downloads_on_secret_key", unique: true, using: :btree

  create_table "snapshot_in_pool_in_branches", force: :cascade do |t|
    t.integer "snapshot_in_pool_id",           limit: 4,             null: false
    t.integer "snapshot_in_pool_in_branch_id", limit: 4
    t.integer "branch_id",                     limit: 4,             null: false
    t.integer "confirmed",                     limit: 4, default: 0, null: false
  end

  add_index "snapshot_in_pool_in_branches", ["snapshot_in_pool_id", "branch_id"], name: "unique_snapshot_in_pool_in_branches", unique: true, using: :btree
  add_index "snapshot_in_pool_in_branches", ["snapshot_in_pool_id"], name: "index_snapshot_in_pool_in_branches_on_snapshot_in_pool_id", using: :btree

  create_table "snapshot_in_pools", force: :cascade do |t|
    t.integer "snapshot_id",        limit: 4,             null: false
    t.integer "dataset_in_pool_id", limit: 4,             null: false
    t.integer "reference_count",    limit: 4, default: 0, null: false
    t.integer "mount_id",           limit: 4
    t.integer "confirmed",          limit: 4, default: 0, null: false
  end

  add_index "snapshot_in_pools", ["dataset_in_pool_id"], name: "index_snapshot_in_pools_on_dataset_in_pool_id", using: :btree
  add_index "snapshot_in_pools", ["snapshot_id", "dataset_in_pool_id"], name: "index_snapshot_in_pools_on_snapshot_id_and_dataset_in_pool_id", unique: true, using: :btree
  add_index "snapshot_in_pools", ["snapshot_id"], name: "index_snapshot_in_pools_on_snapshot_id", using: :btree

  create_table "snapshots", force: :cascade do |t|
    t.string   "name",                 limit: 255,             null: false
    t.integer  "dataset_id",           limit: 4,               null: false
    t.integer  "confirmed",            limit: 4,   default: 0, null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "snapshot_download_id", limit: 4
    t.integer  "history_id",           limit: 4,   default: 0, null: false
    t.string   "label",                limit: 255
  end

  add_index "snapshots", ["dataset_id"], name: "index_snapshots_on_dataset_id", using: :btree

  create_table "sysconfig", force: :cascade do |t|
    t.string   "category",       limit: 75,                     null: false
    t.string   "name",           limit: 75,                     null: false
    t.string   "data_type",      limit: 255,   default: "Text", null: false
    t.text     "value",          limit: 65535
    t.string   "label",          limit: 255
    t.text     "description",    limit: 65535
    t.integer  "min_user_level", limit: 4
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "sysconfig", ["category", "name"], name: "index_sysconfig_on_category_and_name", unique: true, using: :btree
  add_index "sysconfig", ["category"], name: "index_sysconfig_on_category", using: :btree

  create_table "transaction_chain_concerns", force: :cascade do |t|
    t.integer "transaction_chain_id", limit: 4,   null: false
    t.string  "class_name",           limit: 255, null: false
    t.integer "row_id",               limit: 4,   null: false
  end

  add_index "transaction_chain_concerns", ["transaction_chain_id"], name: "index_transaction_chain_concerns_on_transaction_chain_id", using: :btree

  create_table "transaction_chains", force: :cascade do |t|
    t.string   "name",            limit: 30,              null: false
    t.string   "type",            limit: 100,             null: false
    t.integer  "state",           limit: 4,               null: false
    t.integer  "size",            limit: 4,               null: false
    t.integer  "progress",        limit: 4,   default: 0, null: false
    t.integer  "user_id",         limit: 4
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "urgent_rollback", limit: 4,   default: 0, null: false
    t.integer  "concern_type",    limit: 4,   default: 0, null: false
    t.integer  "user_session_id", limit: 4
  end

  add_index "transaction_chains", ["state"], name: "index_transaction_chains_on_state", using: :btree
  add_index "transaction_chains", ["user_id"], name: "index_transaction_chains_on_user_id", using: :btree
  add_index "transaction_chains", ["user_session_id"], name: "index_transaction_chains_on_user_session_id", using: :btree

  create_table "transaction_confirmations", force: :cascade do |t|
    t.integer  "transaction_id", limit: 4,                 null: false
    t.string   "class_name",     limit: 255,               null: false
    t.string   "table_name",     limit: 255,               null: false
    t.string   "row_pks",        limit: 255,               null: false
    t.text     "attr_changes",   limit: 65535
    t.integer  "confirm_type",   limit: 4,                 null: false
    t.integer  "done",           limit: 4,     default: 0, null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "transaction_confirmations", ["transaction_id"], name: "index_transaction_confirmations_on_transaction_id", using: :btree

  create_table "transactions", force: :cascade do |t|
    t.integer  "user_id",              limit: 4,                                           unsigned: true
    t.integer  "node_id",              limit: 4,                                           unsigned: true
    t.integer  "vps_id",               limit: 4,                                           unsigned: true
    t.integer  "handle",               limit: 4,                              null: false, unsigned: true
    t.integer  "depends_on_id",        limit: 4
    t.boolean  "urgent",               limit: 1,          default: false,     null: false
    t.integer  "priority",             limit: 4,          default: 0,         null: false
    t.integer  "status",               limit: 4,                              null: false, unsigned: true
    t.integer  "done",                 limit: 4,          default: 0,         null: false
    t.text     "input",                limit: 4294967295
    t.text     "output",               limit: 65535
    t.integer  "transaction_chain_id", limit: 4,                              null: false
    t.integer  "reversible",           limit: 4,          default: 1,         null: false
    t.datetime "created_at"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.string   "queue",                limit: 30,         default: "general", null: false
  end

  add_index "transactions", ["depends_on_id"], name: "index_transactions_on_depends_on_id", using: :btree
  add_index "transactions", ["done"], name: "index_transactions_on_done", using: :btree
  add_index "transactions", ["node_id"], name: "index_transactions_on_node_id", using: :btree
  add_index "transactions", ["status"], name: "index_transactions_on_status", using: :btree
  add_index "transactions", ["transaction_chain_id"], name: "index_transactions_on_transaction_chain_id", using: :btree
  add_index "transactions", ["user_id"], name: "index_transactions_on_user_id", using: :btree

  create_table "user_cluster_resources", force: :cascade do |t|
    t.integer "user_id",             limit: 4
    t.integer "environment_id",      limit: 4, null: false
    t.integer "cluster_resource_id", limit: 4, null: false
    t.integer "value",               limit: 4, null: false
  end

  add_index "user_cluster_resources", ["cluster_resource_id"], name: "index_user_cluster_resources_on_cluster_resource_id", using: :btree
  add_index "user_cluster_resources", ["environment_id"], name: "index_user_cluster_resources_on_environment_id", using: :btree
  add_index "user_cluster_resources", ["user_id", "environment_id", "cluster_resource_id"], name: "user_cluster_resource_unique", unique: true, using: :btree
  add_index "user_cluster_resources", ["user_id"], name: "index_user_cluster_resources_on_user_id", using: :btree

  create_table "user_mail_role_recipients", force: :cascade do |t|
    t.integer "user_id", limit: 4,   null: false
    t.string  "role",    limit: 100, null: false
    t.string  "to",      limit: 500
  end

  add_index "user_mail_role_recipients", ["user_id", "role"], name: "index_user_mail_role_recipients_on_user_id_and_role", unique: true, using: :btree
  add_index "user_mail_role_recipients", ["user_id"], name: "index_user_mail_role_recipients_on_user_id", using: :btree

  create_table "user_mail_template_recipients", force: :cascade do |t|
    t.integer "user_id",          limit: 4,   null: false
    t.integer "mail_template_id", limit: 4,   null: false
    t.string  "to",               limit: 500, null: false
  end

  add_index "user_mail_template_recipients", ["user_id", "mail_template_id"], name: "user_id_mail_template_id", unique: true, using: :btree
  add_index "user_mail_template_recipients", ["user_id"], name: "index_user_mail_template_recipients_on_user_id", using: :btree

  create_table "user_public_keys", force: :cascade do |t|
    t.integer  "user_id",     limit: 4,                     null: false
    t.string   "label",       limit: 255,                   null: false
    t.text     "key",         limit: 65535,                 null: false
    t.boolean  "auto_add",    limit: 1,     default: false, null: false
    t.string   "fingerprint", limit: 50,                    null: false
    t.string   "comment",     limit: 255,                   null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "user_public_keys", ["user_id"], name: "index_user_public_keys_on_user_id", using: :btree

  create_table "user_session_agents", force: :cascade do |t|
    t.text     "agent",      limit: 65535, null: false
    t.string   "agent_hash", limit: 40,    null: false
    t.datetime "created_at",               null: false
  end

  add_index "user_session_agents", ["agent_hash"], name: "user_session_agents_hash", unique: true, using: :btree

  create_table "user_sessions", force: :cascade do |t|
    t.integer  "user_id",               limit: 4,   null: false
    t.string   "auth_type",             limit: 30,  null: false
    t.string   "api_ip_addr",           limit: 46,  null: false
    t.integer  "user_session_agent_id", limit: 4
    t.string   "client_version",        limit: 255, null: false
    t.integer  "api_token_id",          limit: 4
    t.string   "api_token_str",         limit: 100
    t.datetime "created_at",                        null: false
    t.datetime "last_request_at"
    t.datetime "closed_at"
    t.integer  "admin_id",              limit: 4
    t.string   "api_ip_ptr",            limit: 255
    t.string   "client_ip_addr",        limit: 46
    t.string   "client_ip_ptr",         limit: 255
  end

  add_index "user_sessions", ["user_id"], name: "index_user_sessions_on_user_id", using: :btree

  create_table "users", force: :cascade do |t|
    t.text     "info",               limit: 65535
    t.integer  "level",              limit: 4,                    null: false, unsigned: true
    t.string   "login",              limit: 63
    t.string   "full_name",          limit: 255
    t.string   "password",           limit: 255,                  null: false
    t.string   "email",              limit: 127
    t.text     "address",            limit: 65535
    t.boolean  "mailer_enabled",     limit: 1,     default: true, null: false
    t.integer  "login_count",        limit: 4,     default: 0,    null: false
    t.integer  "failed_login_count", limit: 4,     default: 0,    null: false
    t.datetime "last_request_at"
    t.datetime "current_login_at"
    t.datetime "last_login_at"
    t.string   "current_login_ip",   limit: 255
    t.string   "last_login_ip",      limit: 255
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "object_state",       limit: 4,                    null: false
    t.datetime "expiration_date"
    t.integer  "password_version",   limit: 4,     default: 1,    null: false
    t.datetime "last_activity_at"
    t.integer  "language_id",        limit: 4,     default: 1
    t.string   "orig_login",         limit: 63
  end

  add_index "users", ["login"], name: "index_users_on_login", unique: true, using: :btree
  add_index "users", ["object_state"], name: "index_users_on_object_state", using: :btree

  create_table "versions", force: :cascade do |t|
    t.string   "item_type",  limit: 255,   null: false
    t.integer  "item_id",    limit: 4,     null: false
    t.string   "event",      limit: 255,   null: false
    t.string   "whodunnit",  limit: 255
    t.text     "object",     limit: 65535
    t.datetime "created_at"
  end

  add_index "versions", ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id", using: :btree

  create_table "vps_configs", force: :cascade do |t|
    t.string "name",   limit: 50,    null: false
    t.string "label",  limit: 50,    null: false
    t.text   "config", limit: 65535, null: false
  end

  create_table "vps_consoles", force: :cascade do |t|
    t.integer  "vps_id",     limit: 4,   null: false
    t.string   "token",      limit: 100
    t.datetime "expiration",             null: false
    t.integer  "user_id",    limit: 4
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "vps_consoles", ["token"], name: "index_vps_consoles_on_token", unique: true, using: :btree

  create_table "vps_current_statuses", force: :cascade do |t|
    t.integer  "vps_id",            limit: 4,  null: false
    t.boolean  "status",            limit: 1,  null: false
    t.boolean  "is_running",        limit: 1,  null: false
    t.integer  "uptime",            limit: 4
    t.integer  "cpus",              limit: 4
    t.integer  "total_memory",      limit: 4
    t.integer  "total_swap",        limit: 4
    t.integer  "update_count",      limit: 4,  null: false
    t.integer  "process_count",     limit: 4
    t.float    "cpu_user",          limit: 24
    t.float    "cpu_nice",          limit: 24
    t.float    "cpu_system",        limit: 24
    t.float    "cpu_idle",          limit: 24
    t.float    "cpu_iowait",        limit: 24
    t.float    "cpu_irq",           limit: 24
    t.float    "cpu_softirq",       limit: 24
    t.float    "loadavg",           limit: 24
    t.integer  "used_memory",       limit: 4
    t.integer  "used_swap",         limit: 4
    t.integer  "sum_process_count", limit: 4
    t.float    "sum_cpu_user",      limit: 24
    t.float    "sum_cpu_nice",      limit: 24
    t.float    "sum_cpu_system",    limit: 24
    t.float    "sum_cpu_idle",      limit: 24
    t.float    "sum_cpu_iowait",    limit: 24
    t.float    "sum_cpu_irq",       limit: 24
    t.float    "sum_cpu_softirq",   limit: 24
    t.float    "sum_loadavg",       limit: 24
    t.integer  "sum_used_memory",   limit: 4
    t.integer  "sum_used_swap",     limit: 4
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "vps_current_statuses", ["vps_id"], name: "index_vps_current_statuses_on_vps_id", unique: true, using: :btree

  create_table "vps_features", force: :cascade do |t|
    t.integer  "vps_id",     limit: 4,   null: false
    t.string   "name",       limit: 255, null: false
    t.boolean  "enabled",    limit: 1,   null: false
    t.datetime "updated_at"
  end

  add_index "vps_features", ["vps_id", "name"], name: "index_vps_features_on_vps_id_and_name", unique: true, using: :btree
  add_index "vps_features", ["vps_id"], name: "index_vps_features_on_vps_id", using: :btree

  create_table "vps_has_configs", force: :cascade do |t|
    t.integer "vps_id",        limit: 4, null: false
    t.integer "vps_config_id", limit: 4, null: false
    t.integer "order",         limit: 4, null: false
    t.integer "confirmed",     limit: 4, null: false
  end

  add_index "vps_has_configs", ["vps_id", "vps_config_id", "confirmed"], name: "index_vps_has_configs_on_vps_id_and_vps_config_id_and_confirmed", unique: true, using: :btree
  add_index "vps_has_configs", ["vps_id"], name: "index_vps_has_configs_on_vps_id", using: :btree

  create_table "vps_migrations", force: :cascade do |t|
    t.integer  "vps_id",               limit: 4,                null: false
    t.integer  "migration_plan_id",    limit: 4,                null: false
    t.integer  "state",                limit: 4, default: 0,    null: false
    t.boolean  "outage_window",        limit: 1, default: true, null: false
    t.integer  "transaction_chain_id", limit: 4
    t.integer  "src_node_id",          limit: 4,                null: false
    t.integer  "dst_node_id",          limit: 4,                null: false
    t.datetime "created_at"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.boolean  "cleanup_data",         limit: 1, default: true
  end

  add_index "vps_migrations", ["migration_plan_id", "vps_id"], name: "vps_migrations_unique", unique: true, using: :btree

  create_table "vps_outage_windows", force: :cascade do |t|
    t.integer "vps_id",    limit: 4, null: false
    t.integer "weekday",   limit: 4, null: false
    t.boolean "is_open",   limit: 1, null: false
    t.integer "opens_at",  limit: 4
    t.integer "closes_at", limit: 4
  end

  add_index "vps_outage_windows", ["vps_id", "weekday"], name: "index_vps_outage_windows_on_vps_id_and_weekday", unique: true, using: :btree

  create_table "vps_statuses", force: :cascade do |t|
    t.integer  "vps_id",        limit: 4,  null: false
    t.boolean  "status",        limit: 1,  null: false
    t.boolean  "is_running",    limit: 1,  null: false
    t.integer  "uptime",        limit: 4
    t.integer  "process_count", limit: 4
    t.integer  "cpus",          limit: 4
    t.float    "cpu_user",      limit: 24
    t.float    "cpu_nice",      limit: 24
    t.float    "cpu_system",    limit: 24
    t.float    "cpu_idle",      limit: 24
    t.float    "cpu_iowait",    limit: 24
    t.float    "cpu_irq",       limit: 24
    t.float    "cpu_softirq",   limit: 24
    t.float    "loadavg",       limit: 24
    t.integer  "total_memory",  limit: 4
    t.integer  "used_memory",   limit: 4
    t.integer  "total_swap",    limit: 4
    t.integer  "used_swap",     limit: 4
    t.datetime "created_at"
  end

  add_index "vps_statuses", ["vps_id"], name: "index_vps_statuses_on_vps_id", using: :btree

  create_table "vpses", force: :cascade do |t|
    t.integer  "user_id",                 limit: 4,                        null: false, unsigned: true
    t.string   "hostname",                limit: 255,      default: "vps"
    t.integer  "os_template_id",          limit: 4,        default: 1,     null: false, unsigned: true
    t.text     "info",                    limit: 16777215
    t.integer  "dns_resolver_id",         limit: 4
    t.integer  "node_id",                 limit: 4,                        null: false, unsigned: true
    t.boolean  "onboot",                  limit: 1,        default: true,  null: false
    t.boolean  "onstartall",              limit: 1,        default: true,  null: false
    t.text     "config",                  limit: 65535,                    null: false
    t.integer  "confirmed",               limit: 4,        default: 0,     null: false
    t.integer  "dataset_in_pool_id",      limit: 4
    t.integer  "maintenance_lock",        limit: 4,        default: 0,     null: false
    t.string   "maintenance_lock_reason", limit: 255
    t.integer  "object_state",            limit: 4,                        null: false
    t.datetime "expiration_date"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.boolean  "manage_hostname",         limit: 1,        default: true,  null: false
  end

  add_index "vpses", ["dataset_in_pool_id"], name: "index_vpses_on_dataset_in_pool_id", using: :btree
  add_index "vpses", ["dns_resolver_id"], name: "index_vpses_on_dns_resolver_id", using: :btree
  add_index "vpses", ["node_id"], name: "index_vpses_on_node_id", using: :btree
  add_index "vpses", ["object_state"], name: "index_vpses_on_object_state", using: :btree
  add_index "vpses", ["os_template_id"], name: "index_vpses_on_os_template_id", using: :btree
  add_index "vpses", ["user_id"], name: "index_vpses_on_user_id", using: :btree

end
