class Setup < ActiveRecord::Migration
  def change
    create_table :members, :primary_key => 'm_id' do |t|
      # compatibility columns for vpsadmin1
      t.text      :m_info,              null: true
      t.integer   :m_created,           null: true
      t.integer   :m_deleted,           null: true
      t.integer   :m_level,             null: false
      t.string    :m_nick,              null: false, limit: 63
      t.string    :m_name,              null: false, limit: 255
      t.string    :m_pass,              null: false, limit: 255
      t.string    :m_mail,              null: false, limit: 127
      t.text      :m_address,           null: false
      t.string    :m_lang,              null: true,  limit: 16
      t.string    :m_paid_until,        null: true,  limit: 32
      t.integer   :m_last_activity,     null: true
      t.integer   :m_monthly_payment,   null: false,             default: 300
      t.boolean   :m_mailer_enable,     null: false,             default: 1
      t.boolean   :m_playground_enable, null: false,             default: 1
      t.string    :m_state,             null: false, limit: 10,  default: 'active'
      t.string    :m_suspend_reason,    null: false, limit: 100

      # required authlogic columns
      t.string    :persistence_token,   null: false

      # the rest is optional, it will work without them
      t.string    :single_access_token, null: false
      t.string    :perishable_token,    null: false

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

    create_table :locations, :primary_key => 'location_id' do |t|
      # compatibility columns
      t.string     :location_label,       limit: 100, null: false
      t.string     :location_type,        limit: 100, null: false
      t.boolean    :location_has_ipv6,                null: false
      t.boolean    :location_vps_onboot,              null: false, default: 1
      t.string     :location_remote_console_server, limit: 255, null: false

      # additional columns
      t.belongs_to :environment
      t.string     :domain,               limit: 100, null: false
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

    create_table :servers, :primary_key => 'server_id' do |t|
      t.string     :server_name,         limit: 50,  null: false
      t.string     :server_type,         limit: 10,  null: false
      t.integer    :server_location,                 null: false,      index: true
      t.text       :server_availstat,                null: true
      t.string     :server_ip4,          limit: 127, null: false
      t.boolean    :server_maintenance,              null: false,  default: 0
      t.timestamps
    end

    #create_table :environment_os_templates do |t|
    #  t.boolean     :enabled,                 null: false
    #  t.boolean     :supported,               null: false
    #  t.integer     :order,                   null: false
    #  t.belongs_to  :environment
    #  t.belongs_to  :os_template
    #end

    create_table :cfg_templates, :primary_key => 'templ_id' do |t|
      t.string      :templ_name,        limit: 64, null: false
      t.string      :templ_label,       limit: 64, null: false
      t.text        :templ_info,                   null: true
      t.boolean     :templ_enabled,                null: false, default: 1
      t.boolean     :templ_supported,              null: false, default: 1
      t.integer     :templ_order,                  null: false, default: 1

      # Dropped column 'special'
    end

    create_table :vps, :primary_key => 'vps_id' do |t|
      t.integer     :vps_created,                      null: true
      t.integer     :vps_expiration,                   null: true
      t.integer     :vps_deleted,                      null: true
      t.integer     :m_id,                             null: false, index: true
      t.string      :vps_hostname,   limit: 255,       null: true
      t.integer     :vps_template,                     null: false
      t.text        :vps_info,                         null: true
      t.string      :vps_nameserver, limit: 255,       null: false
      t.integer     :vps_server,                       null: false, index: true
      t.boolean     :vps_onboot,                       null: false, default: 1
      t.boolean     :vps_onstartall,                   null: false, default: 1
      t.boolean     :vps_backup_enabled,               null: false, default: 1
      t.boolean     :vps_features_enabled, limit: 255, null: false, default: 0
      t.integer     :vps_backup_export,                null: false
      t.boolean     :vps_backup_lock,                  null: false, default: 0
      t.text        :vps_backup_exclude,               null: false
      t.text        :vps_config,                       null: false

      t.timestamps

      # Dropped column vps_specials_installed
    end

    create_table :vps_ip, :primary_key => 'ip_id' do |t|
      t.integer     :vps_id,                  null: true
      t.integer     :ip_v,                    null: false, default: 4
      t.integer     :ip_location,             null: false
      t.string      :ip_addr,     limit: 40,  null: false
    end

    create_table :transactions, :primary_key => 't_id' do |t|
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
  end
end
