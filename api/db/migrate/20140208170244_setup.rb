class Setup < ActiveRecord::Migration
  def change
    create_table :members, primary_key: 'm_id' do |t|
      # compatibility columns for vpsadmin1
      t.text      :m_info,              null: true
      t.integer   :m_created,           null: true
      t.integer   :m_deleted,           null: true
      t.integer   :m_level,             null: false
      t.string    :m_nick,              null: false, limit: 63
      t.string    :m_name,              null: true,  limit: 255
      t.string    :m_pass,              null: false, limit: 255
      t.string    :m_mail,              null: true,  limit: 127
      t.text      :m_address,           null: true
      t.string    :m_lang,              null: true,  limit: 16
      t.string    :m_paid_until,        null: true,  limit: 32
      t.integer   :m_last_activity,     null: true
      t.integer   :m_monthly_payment,   null: false,             default: 300
      t.boolean   :m_mailer_enable,     null: false,             default: 1
      t.boolean   :m_playground_enable, null: false,             default: 1
      t.string    :m_state,             null: false, limit: 10,  default: 'active'
      t.string    :m_suspend_reason,    null: true,  limit: 100

      t.integer   :login_count,         null: false,             default: 0
      t.integer   :failed_login_count,  null: false,             default: 0
      t.datetime  :last_request_at
      t.datetime  :current_login_at
      t.datetime  :last_login_at
      t.string    :current_login_ip
      t.string    :last_login_ip

      t.timestamps
    end

    # in addition to vpsadmin1
    create_table :environments do |t|
      t.string    :label,                 limit: 100, null: false
      t.string    :domain,                limit: 100, null: false
      t.timestamps
    end

    create_table :locations, primary_key: 'location_id' do |t|
      # compatibility columns
      t.string     :location_label,       limit: 100, null: false
      t.string     :location_type,        limit: 100, null: false
      t.boolean    :location_has_ipv6,                null: false
      t.boolean    :location_vps_onboot,              null: false, default: 1
      t.string     :location_remote_console_server, limit: 255, null: false

      # additional columns
      t.belongs_to :environment
      t.string     :domain, limit: 100, null: false
      t.timestamps

      # Dropped support of following columns:
      #   location_has_ospf
      #   location_has_rdiff_backup
      #   location_rdiff_target
      #   location_rdiff_history
      #   location_rdiff_mount_sshfs
      #   location_rdiff_mount_archfs
      #   location_rdiff_target_path
      #   location_tpl_sync_path
      #   location_backup_server_id
    end

    create_table :servers, primary_key: 'server_id' do |t|
      t.string     :server_name,         limit: 50,  null: false
      t.string     :server_type,         limit: 10,  null: false
      t.integer    :server_location,                 null: false, index: true
      t.text       :server_availstat,                null: true
      t.string     :server_ip4, limit: 127, null: false
      t.boolean    :server_maintenance,              null: false,  default: 0
      t.integer    :max_vps,                         null: false,  default: 0
      t.string     :ve_private,          limit: 255, null: false,  default: '/vz/private/%{veid}'
      t.string     :fstype,              limit: 15,  null: false,  default: 'zfs'
      t.timestamps
    end

    # create_table :environment_os_templates do |t|
    #  t.boolean     :enabled,                 null: false
    #  t.boolean     :supported,               null: false
    #  t.integer     :order,                   null: false
    #  t.belongs_to  :environment
    #  t.belongs_to  :os_template
    # end

    create_table :cfg_templates, primary_key: 'templ_id' do |t|
      t.string      :templ_name,        limit: 64, null: false
      t.string      :templ_label,       limit: 64, null: false
      t.text        :templ_info,                   null: true
      t.boolean     :templ_enabled,                null: false, default: 1
      t.boolean     :templ_supported,              null: false, default: 1
      t.integer     :templ_order,                  null: false, default: 1

      # Dropped column 'special'
    end

    create_table :vps, primary_key: 'vps_id' do |t|
      t.integer     :vps_created,                      null: true
      t.integer     :vps_expiration,                   null: true
      t.integer     :vps_deleted,                      null: true
      t.integer     :m_id,                             null: false, index: true
      t.string      :vps_hostname, limit: 255, null: true
      t.integer     :vps_template,                     null: false
      t.text        :vps_info,                         null: true
      t.belongs_to  :dns_resolver,                     null: true
      t.integer     :vps_server,                       null: false, index: true
      t.boolean     :vps_onboot,                       null: false, default: 1
      t.boolean     :vps_onstartall,                   null: false, default: 1
      t.boolean     :vps_backup_enabled,               null: false, default: 1
      t.boolean     :vps_features_enabled, limit: 255, null: false, default: 0
      t.integer     :vps_backup_export,                null: true
      t.boolean     :vps_backup_lock,                  null: false, default: 0
      t.text        :vps_backup_exclude,               null: false
      t.text        :vps_config,                       null: false

      t.timestamps

      # Dropped columns vps_specials_installed, vps_nameserver
      # New column dns_resolver_id
    end

    create_table :vps_ip, primary_key: 'ip_id' do |t|
      t.integer     :vps_id,                  null: true
      t.integer     :ip_v,                    null: false, default: 4
      t.integer     :ip_location,             null: false
      t.string      :ip_addr, limit: 40, null: false
    end

    create_table :transactions, primary_key: 't_id' do |t|
      t.integer     :t_group,                 null: true
      t.integer     :t_time,                  null: true
      t.integer     :t_real_start,            null: true
      t.integer     :t_end,                   null: true
      t.integer     :t_m_id,                  null: true
      t.integer     :t_server,                null: true
      t.integer     :t_vps,                   null: true
      t.integer     :t_type,                  null: false
      t.integer     :t_depends_on,            null: true
      t.text        :t_fallback,              null: true
      t.boolean     :t_urgent,                null: false, default: false
      t.integer     :t_priority,              null: false, default: 0
      t.integer     :t_success,               null: false
      t.boolean     :t_done,                  null: false
      t.text        :t_param,                 null: true
      t.text        :t_output,                null: true
    end

    create_table :cfg_dns, primary_key: 'dns_id' do |t|
      t.string      :dns_ip,     limit: 63,   null: false
      t.string      :dns_label,  limit: 63,   null: false
      t.boolean     :dns_is_universal,        null: true,  default: false
      t.integer     :dns_location,            null: true,  default: nil
    end

    create_table :config do |t|
      t.string      :name,       limit: 50,   null: false
      t.string      :label,      limit: 50,   null: false
      t.text        :config,                  null: false
    end

    create_table :vps_has_config, id: false do |t|
      t.integer     :vps_id,                  null: false
      t.integer     :config_id,               null: false
      t.integer     :order,                   null: false
    end

    create_table :sysconfig, id: false do |t|
      t.string      :cfg_name,                null: false
      t.text        :cfg_value,               null: true, default: nil
    end

    create_table :storage_root do |t|
      t.belongs_to  :node_id,                    null: false
      t.string      :label,          limit: 255, null: false
      t.string      :root_dataset,   limit: 500, null: false
      t.string      :root_path,      limit: 500, null: false
      t.string      :storage_layout, limit: 10,  null: false
      t.boolean     :user_export,                null: false
      t.string      :user_mount, limit: 10, null: false
      t.integer     :quota,                      null: false
      t.integer     :used,                       null: false, default: 0
      t.integer     :avail,                      null: false, default: 0
      t.string      :share_options, limit: 500, null: false

      # Rename type to storage_layout.
    end

    change_column :storage_root, :quota, 'bigint unsigned'
    change_column :storage_root, :used, 'bigint unsigned'
    change_column :storage_root, :avail, 'bigint unsigned'

    create_table :storage_export do |t|
      t.integer     :member_id,                  null: false
      t.integer     :root_id,                    null: false
      t.string      :dataset,        limit: 500, null: false
      t.string      :path,           limit: 500, null: false
      t.integer     :quota,                      null: false
      t.integer     :used,                       null: false, default: 0
      t.integer     :avail,                      null: false, default: 0
      t.boolean     :user_editable,              null: false, default: false
      t.string      :default,        limit: 10,  null: false, default: 'no'
      t.string      :data_type,      limit: 10,  null: false

      # Rename type to data_type.
    end

    change_column :storage_export, :quota, 'bigint unsigned'
    change_column :storage_export, :used, 'bigint unsigned'
    change_column :storage_export, :avail, 'bigint unsigned'
  end

  create_table :vps_mount do |t|
    t.integer       :vps_id,                     null: false
    t.string        :src,            limit: 500, null: false
    t.string        :dst,            limit: 500, null: false
    t.string        :mount_opts,     limit: 255, null: false
    t.string        :umount_opts,    limit: 255, null: false
    t.string        :mount_type,     limit: 10,  null: false
    t.integer       :server_id,                  null: true
    t.integer       :storage_export_id,          null: true
    t.string        :mode,           limit: 2,   null: false
    t.string        :cmd_premount,   limit: 500, null: false
    t.string        :cmd_postmount,  limit: 500, null: false
    t.string        :cmd_preumount,  limit: 500, null: false
    t.string        :cmd_postumount, limit: 500, null: false
    t.boolean       :default,                    null: false, default: false
  end
end
