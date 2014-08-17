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

ActiveRecord::Schema.define(version: 20140815161745) do

  create_table "api_tokens", force: true do |t|
    t.integer  "user_id",                           null: false
    t.string   "token",     limit: 100,             null: false
    t.datetime "valid_to"
    t.string   "label"
    t.integer  "use_count",             default: 0, null: false
  end

  create_table "cfg_dns", primary_key: "dns_id", force: true do |t|
    t.string  "dns_ip",           limit: 63,                 null: false
    t.string  "dns_label",        limit: 63,                 null: false
    t.boolean "dns_is_universal",            default: false
    t.integer "dns_location"
  end

  create_table "cfg_templates", primary_key: "templ_id", force: true do |t|
    t.string  "templ_name",      limit: 64,             null: false
    t.string  "templ_label",     limit: 64,             null: false
    t.text    "templ_info"
    t.integer "templ_enabled",   limit: 1,  default: 1, null: false
    t.integer "templ_supported", limit: 1,  default: 1, null: false
    t.integer "templ_order",     limit: 1,  default: 1, null: false
  end

  create_table "config", force: true do |t|
    t.string "name",   limit: 50, null: false
    t.string "label",  limit: 50, null: false
    t.text   "config",            null: false
  end

  create_table "environments", force: true do |t|
    t.string   "label",      limit: 100, null: false
    t.string   "domain",     limit: 100, null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "helpbox", force: true do |t|
    t.string "page",    limit: 50, null: false
    t.string "action",  limit: 50, null: false
    t.text   "content",            null: false
  end

  create_table "locations", primary_key: "location_id", force: true do |t|
    t.string   "location_label",                 limit: 63,                         null: false
    t.string   "location_type",                  limit: 10,  default: "production", null: false
    t.boolean  "location_has_ipv6",                                                 null: false
    t.boolean  "location_vps_onboot",                        default: true,         null: false
    t.string   "location_remote_console_server",                                    null: false
    t.integer  "environment_id"
    t.string   "domain",                         limit: 100,                        null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "log", force: true do |t|
    t.integer "timestamp", null: false
    t.text    "msg",       null: false
  end

  create_table "mailer", force: true do |t|
    t.integer "sentTime",  null: false
    t.integer "member_id"
    t.string  "type",      null: false
    t.text    "details",   null: false
  end

  add_index "mailer", ["member_id"], name: "member_id", using: :btree

  create_table "members", primary_key: "m_id", force: true do |t|
    t.text     "m_info"
    t.integer  "m_created"
    t.integer  "m_deleted"
    t.integer  "m_level",                                            null: false
    t.string   "m_nick",              limit: 63,                     null: false
    t.string   "m_name"
    t.string   "m_pass",                                             null: false
    t.string   "m_mail",              limit: 127
    t.text     "m_address"
    t.string   "m_lang",              limit: 16
    t.string   "m_paid_until",        limit: 32
    t.integer  "m_last_activity"
    t.integer  "m_monthly_payment",               default: 300,      null: false
    t.boolean  "m_mailer_enable",                 default: true,     null: false
    t.boolean  "m_playground_enable",             default: true,     null: false
    t.string   "m_state",             limit: 9,   default: "active", null: false
    t.string   "m_suspend_reason",    limit: 100
    t.integer  "login_count",                     default: 0,        null: false
    t.integer  "failed_login_count",              default: 0,        null: false
    t.datetime "last_request_at"
    t.datetime "current_login_at"
    t.datetime "last_login_at"
    t.string   "current_login_ip"
    t.string   "last_login_ip"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "members_changes", primary_key: "m_id", force: true do |t|
    t.integer "m_created",                                null: false
    t.string  "m_type",           limit: 6,               null: false
    t.string  "m_state",          limit: 8,               null: false
    t.integer "m_applicant"
    t.integer "m_changed_by"
    t.integer "m_changed_at"
    t.string  "m_nick",           limit: 63
    t.string  "m_name"
    t.string  "m_mail",           limit: 127
    t.text    "m_address"
    t.integer "m_year"
    t.string  "m_jabber"
    t.string  "m_how",            limit: 500
    t.string  "m_note",           limit: 500
    t.integer "m_distribution"
    t.integer "m_location"
    t.string  "m_currency",       limit: 10
    t.string  "m_addr",           limit: 127,             null: false
    t.string  "m_addr_reverse",                           null: false
    t.string  "m_reason",         limit: 500,             null: false
    t.integer "m_last_mail_id",               default: 0, null: false
    t.string  "m_admin_response", limit: 500
  end

  create_table "members_payments", force: true do |t|
    t.integer "m_id",                  null: false
    t.integer "acct_m_id",             null: false
    t.integer "timestamp",   limit: 8, null: false
    t.integer "change_from", limit: 8, null: false
    t.integer "change_to",   limit: 8, null: false
  end

  create_table "node_pubkey", id: false, force: true do |t|
    t.integer "node_id",           null: false
    t.string  "type",    limit: 3, null: false
    t.text    "key",               null: false
  end

  create_table "servers", primary_key: "server_id", force: true do |t|
    t.string  "server_name",        limit: 64,                                 null: false
    t.string  "server_type",        limit: 7,                                  null: false
    t.integer "server_location",                                               null: false
    t.text    "server_availstat"
    t.string  "server_ip4",         limit: 127,                                null: false
    t.boolean "server_maintenance",             default: false,                null: false
    t.integer "max_vps",                                                       null: false
    t.string  "ve_private",                     default: "/vz/private/%veid%", null: false
    t.string  "fstype",             limit: 10,  default: "zfs",                null: false
    t.string  "net_interface",      limit: 50
    t.integer "max_tx",             limit: 8,   default: 235929600,            null: false
    t.integer "max_rx",             limit: 8,   default: 235929600,            null: false
  end

  add_index "servers", ["server_location"], name: "server_location", using: :btree

  create_table "servers_status", primary_key: "server_id", force: true do |t|
    t.integer "timestamp",                   null: false
    t.integer "ram_free_mb"
    t.float   "disk_vz_free_gb"
    t.float   "cpu_load"
    t.boolean "daemon",                      null: false
    t.string  "vpsadmin_version", limit: 63
    t.string  "kernel",           limit: 50, null: false
  end

  create_table "storage_export", force: true do |t|
    t.integer "member_id",                                null: false
    t.integer "root_id",                                  null: false
    t.string  "dataset",       limit: 500,                null: false
    t.string  "path",          limit: 500,                null: false
    t.integer "quota",         limit: 8,                  null: false
    t.integer "used",          limit: 8,   default: 0,    null: false
    t.integer "avail",         limit: 8,   default: 0,    null: false
    t.integer "user_editable", limit: 1,   default: 0,    null: false
    t.string  "default",       limit: 6,   default: "no", null: false
    t.string  "data_type",     limit: 6,                  null: false
  end

  create_table "storage_root", force: true do |t|
    t.integer "node_id",                                     null: false
    t.string  "label",                                       null: false
    t.string  "root_dataset",   limit: 500,                  null: false
    t.string  "root_path",      limit: 500,                  null: false
    t.string  "storage_layout", limit: 10,                   null: false
    t.integer "user_export",    limit: 1,   default: 0,      null: false
    t.string  "user_mount",     limit: 4,   default: "none", null: false
    t.integer "quota",          limit: 8,                    null: false
    t.integer "used",           limit: 8,   default: 0,      null: false
    t.integer "avail",          limit: 8,   default: 0,      null: false
    t.string  "share_options",  limit: 500,                  null: false
  end

  create_table "sysconfig", primary_key: "cfg_name", force: true do |t|
    t.text "cfg_value"
  end

  create_table "tmp_sysconfig", primary_key: "cfg_name", force: true do |t|
    t.text "cfg_value"
  end

  create_table "transaction_groups", force: true do |t|
    t.boolean "is_clusterwide",  default: false
    t.boolean "is_locationwide", default: false
    t.integer "location_id",     default: 0
  end

  create_table "transactions", primary_key: "t_id", force: true do |t|
    t.integer "t_group"
    t.integer "t_time"
    t.integer "t_real_start"
    t.integer "t_end"
    t.integer "t_m_id"
    t.integer "t_server"
    t.integer "t_vps"
    t.integer "t_type",                       null: false
    t.integer "t_depends_on"
    t.text    "t_fallback"
    t.boolean "t_urgent",     default: false, null: false
    t.integer "t_priority",   default: 0,     null: false
    t.integer "t_success",                    null: false
    t.boolean "t_done",                       null: false
    t.text    "t_param"
    t.text    "t_output"
  end

  add_index "transactions", ["t_server"], name: "t_server", using: :btree

  create_table "transfered", id: false, force: true do |t|
    t.string   "tr_ip",          limit: 127,             null: false
    t.string   "tr_proto",       limit: 4,               null: false
    t.integer  "tr_packets_in",  limit: 8,   default: 0, null: false
    t.integer  "tr_packets_out", limit: 8,   default: 0, null: false
    t.integer  "tr_bytes_in",    limit: 8,   default: 0, null: false
    t.integer  "tr_bytes_out",   limit: 8,   default: 0, null: false
    t.datetime "tr_date",                                null: false
  end

  create_table "transfered_recent", id: false, force: true do |t|
    t.string   "tr_ip",          limit: 127,             null: false
    t.string   "tr_proto",       limit: 5,               null: false
    t.integer  "tr_packets_in",  limit: 8,   default: 0, null: false
    t.integer  "tr_packets_out", limit: 8,   default: 0, null: false
    t.integer  "tr_bytes_in",    limit: 8,   default: 0, null: false
    t.integer  "tr_bytes_out",   limit: 8,   default: 0, null: false
    t.datetime "tr_date",                                null: false
  end

  create_table "versions", force: true do |t|
    t.string   "item_type",  null: false
    t.integer  "item_id",    null: false
    t.string   "event",      null: false
    t.string   "whodunnit"
    t.text     "object"
    t.datetime "created_at"
  end

  add_index "versions", ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id", using: :btree

  create_table "vps", primary_key: "vps_id", force: true do |t|
    t.integer "vps_created"
    t.integer "vps_expiration"
    t.integer "vps_deleted"
    t.integer "m_id",                                                  null: false
    t.string  "vps_hostname",                          default: "vps"
    t.integer "vps_template",                          default: 1,     null: false
    t.text    "vps_info",             limit: 16777215
    t.integer "dns_resolver_id"
    t.integer "vps_server",                                            null: false
    t.boolean "vps_onboot",                            default: true,  null: false
    t.boolean "vps_onstartall",                        default: true,  null: false
    t.boolean "vps_backup_enabled",                    default: true,  null: false
    t.boolean "vps_features_enabled",                  default: false, null: false
    t.integer "vps_backup_export",                                     null: false
    t.integer "vps_backup_lock",      limit: 1,        default: 0,     null: false
    t.text    "vps_backup_exclude",                                    null: false
    t.text    "vps_config",                                            null: false
  end

  add_index "vps", ["m_id"], name: "m_id", using: :btree

  create_table "vps_backups", id: false, force: true do |t|
    t.integer "vps_id",              null: false
    t.integer "timestamp",           null: false
    t.integer "size",      limit: 8, null: false
  end

  add_index "vps_backups", ["vps_id"], name: "vps_id", using: :btree

  create_table "vps_console", force: true do |t|
    t.integer  "vps_id",                null: false
    t.string   "key",        limit: 64, null: false
    t.datetime "expiration",            null: false
  end

  create_table "vps_has_config", id: false, force: true do |t|
    t.integer "vps_id",    null: false
    t.integer "config_id", null: false
    t.integer "order",     null: false
  end

  create_table "vps_ip", primary_key: "ip_id", force: true do |t|
    t.integer "vps_id"
    t.integer "ip_v",                   default: 4,        null: false
    t.integer "ip_location",                               null: false
    t.string  "ip_addr",     limit: 40,                    null: false
    t.integer "max_tx",      limit: 8,  default: 39321600, null: false
    t.integer "max_rx",      limit: 8,  default: 39321600, null: false
    t.integer "class_id",                                  null: false
  end

  add_index "vps_ip", ["vps_id"], name: "vps_id", using: :btree

  create_table "vps_mount", force: true do |t|
    t.integer "vps_id",                                    null: false
    t.string  "src",               limit: 500,             null: false
    t.string  "dst",               limit: 500,             null: false
    t.string  "mount_opts",                                null: false
    t.string  "umount_opts",                               null: false
    t.string  "mount_type",        limit: 4,               null: false
    t.integer "server_id"
    t.integer "storage_export_id"
    t.string  "mode",              limit: 2,               null: false
    t.string  "cmd_premount",      limit: 500,             null: false
    t.string  "cmd_postmount",     limit: 500,             null: false
    t.string  "cmd_preumount",     limit: 500,             null: false
    t.string  "cmd_postumount",    limit: 500,             null: false
    t.integer "default",           limit: 1,   default: 0, null: false
  end

  create_table "vps_status", force: true do |t|
    t.integer "vps_id",                                          null: false
    t.integer "timestamp",                                       null: false
    t.boolean "vps_up"
    t.integer "vps_nproc"
    t.integer "vps_vm_used_mb"
    t.integer "vps_disk_used_mb"
    t.string  "vps_admin_ver",    limit: 63, default: "not set"
  end

  add_index "vps_status", ["vps_id"], name: "vps_id", using: :btree
  add_index "vps_status", ["vps_id"], name: "vps_id_2", unique: true, using: :btree

end
